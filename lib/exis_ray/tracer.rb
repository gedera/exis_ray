require 'active_support/current_attributes'
require 'securerandom'

module ExisRay
  # Gestiona el contexto de trazabilidad distribuida (Distributed Tracing) para la aplicación.
  # Utiliza `ActiveSupport::CurrentAttributes` para mantener el estado de la petición actual
  # de forma segura entre hilos (thread-safe).
  #
  # Esta clase es capaz de parsear headers de AWS X-Ray y generar nuevos headers
  # para propagar la traza a microservicios o sistemas externos.
  #
  # @see https://docs.aws.amazon.com/xray/latest/devguide/xray-concepts.html Documentación de AWS X-Ray
  class Tracer < ActiveSupport::CurrentAttributes
    # @!attribute [rw] trace_id
    #   @return [String, nil] El header crudo recibido (ej: HTTP_X_AMZN_TRACE_ID).
    # @!attribute [rw] request_id
    #   @return [String, nil] El UUID interno generado por Rails (ActionDispatch::RequestId).
    # @!attribute [rw] root_id
    #   @return [String, nil] El ID global de la traza (Trace ID) que persiste en toda la cadena de servicios.
    # @!attribute [rw] self_id
    #   @return [String, nil] El ID del servicio que nos llamó (el "Parent" inmediato).
    # @!attribute [rw] called_from
    #   @return [String, nil] El nombre del servicio o componente que realizó la llamada.
    # @!attribute [rw] total_time_so_far
    #   @return [Integer, nil] Tiempo acumulado en milisegundos hasta llegar a nosotros.
    # @!attribute [rw] created_at
    #   @return [Float, nil] Timestamp (float) del momento exacto en que la petición tocó nuestra app.
    # @!attribute [rw] service_name
    #   @return [String, nil] Nombre del contexto actual (ej: 'Wispro-Web', 'Wispro-Cron').
    attribute :trace_id, :request_id, :root_id, :self_id, :called_from, :total_time_so_far, :created_at, :service_name

    # Devuelve el nombre del servicio actual.
    # Si no se ha definido manualmente (ej: en un Cron), hace fallback al nombre de la aplicación Rails.
    #
    # @return [String] El nombre del servicio (ej: "Wispro", "Wispro-Worker", "App").
    def self.service_name
      super || (defined?(Rails) ? Rails.application.class.module_parent_name : 'App')
    end

    # Genera un ID de correlación compuesto, útil para logs y auditoría.
    # Combina el nombre del servicio actual con el Root ID de la traza.
    #
    # @example
    #   ExisRay::Tracer.correlation_id #=> "Wispro;1-5759...-..."
    #
    # @return [String] Cadena compuesta "ServiceName;RootID".
    def self.correlation_id
      "#{service_name};#{root_id}"
    end

    # Parsea el string de trazabilidad recibido (generalmente de AWS ALB) y popula los atributos individuales.
    # Maneja el formato estándar de AWS: "Root=...;Self=...;CalledFrom=...;TotalTimeSoFar=..."
    #
    # @return [void]
    def self.parse_trace_id
      return unless trace_id.present?

      # Convertimos a Hash para evitar errores si cambia el orden de los parámetros
      data = trace_id.split(';').map { |part| part.split('=', 2) }.to_h

      self.root_id     = data['Root']
      self.self_id     = data['Self']
      self.called_from = data['CalledFrom']

      # Limpiamos el sufijo 'ms' y convertimos a entero de forma segura
      if data['TotalTimeSoFar']
        self.total_time_so_far = data['TotalTimeSoFar'].gsub(/ms$/i, '').to_i
      else
        self.total_time_so_far = 0
      end
    end

    # Calcula el tiempo transcurrido en milisegundos desde que la petición inició en esta instancia
    # hasta el momento actual.
    #
    # @return [Integer] Duración en ms. Devuelve 0 si `created_at` no está seteado.
    def self.current_duration_ms
      return 0 unless created_at
      ((Time.now.utc.to_f - created_at) * 1000).round
    end

    # Construye el header de trazabilidad formateado para ser enviado al siguiente servicio.
    # Propaga el Root ID existente (o crea uno nuevo), genera un nuevo Self ID para este salto,
    # y actualiza el tiempo acumulado.
    #
    # Formato de salida:
    # "Root=...;Self=...;CalledFrom=...;TotalTimeSoFar=...ms"
    #
    # @return [String] Header listo para inyectar en peticiones HTTP salientes.
    def self.generate_trace_header
      # 1. Mantenemos el hilo de la conversación (Root) o iniciamos uno nuevo si no existe.
      safe_root = root_id || generate_new_root

      # 2. Sumamos el tiempo que tardó en llegar aquí + lo que tardamos nosotros.
      total_acc_time = (total_time_so_far || 0) + current_duration_ms

      # 3. Generamos nuestra "firma" para el siguiente servicio.
      # El formato del ID debe ser: Versión(1) - TimestampHex - IdentificadorHex
      my_new_id = "1-#{Time.now.to_i.to_s(16)}-#{clean_request_id}"

      "Root=#{safe_root};Self=#{my_new_id};CalledFrom=#{service_name};TotalTimeSoFar=#{total_acc_time}ms"
    end

    # Genera un nuevo Root ID compatible con el estándar de AWS X-Ray.
    # Útil para iniciar trazas en tareas en segundo plano (Crons, Workers).
    #
    # @api private
    # @param suffix_id [String, Integer, nil] Un identificador opcional (ej: ID del Pod) para agregar al final del hash.
    # @return [String] Un ID con formato: 1-TimestampHex-RandomHex[+SuffixHex]
    def self.generate_new_root(suffix_id = nil)
      # Parte 1: Timestamp actual en Hex (8 chars)
      timestamp_hex = Time.now.to_i.to_s(16)

      # Parte 2: Identificador único (24 chars)
      if suffix_id.present?
        # Convertimos el sufijo a Hex y rellenamos con ceros a la izquierda (8 chars)
        suffix_hex = suffix_id.to_i.to_s(16).rjust(8, '0')
        # 16 chars aleatorios + 8 chars del sufijo = 24 chars
        unique_part = SecureRandom.hex(8) + suffix_hex
      else
        # 24 chars completamente aleatorios
        unique_part = SecureRandom.hex(12)
      end

      "1-#{timestamp_hex}-#{unique_part}"
    end

    # Limpia y formatea el Request ID de Rails para cumplir con el estándar de AWS.
    # AWS requiere estrictamente 24 caracteres hexadecimales.
    #
    # @api private
    # @return [String] String hexadecimal de 24 caracteres.
    def self.clean_request_id
      # request_id puede ser un UUID (36 chars con guiones).
      # Eliminamos guiones y cortamos a 24. Fallback a SecureRandom si es nil.
      (request_id || SecureRandom.hex).delete('-').first(24)
    end

    # Definición explícita de privacidad para métodos de clase
    private_class_method :clean_request_id, :generate_new_root
  end
end
