require 'active_support/current_attributes'
require 'securerandom'

module ExisRay
  # Gestiona el contexto de trazabilidad distribuida (Distributed Tracing).
  # Utiliza `ActiveSupport::CurrentAttributes` para mantener el estado de la petición actual
  # de forma segura entre hilos (thread-safe).
  #
  # Esta clase parsea headers de AWS X-Ray y genera nuevos headers para la propagación.
  #
  # @see https://docs.aws.amazon.com/xray/latest/devguide/xray-concepts.html Documentación de AWS X-Ray
  class Tracer < ActiveSupport::CurrentAttributes
    attribute :trace_id, :request_id, :root_id, :self_id, :called_from, :total_time_so_far, :created_at, :sidekiq_job, :task, :source

    # Devuelve el nombre de la aplicación en snake_case (ej: "cold_storage_service").
    # Se utiliza como identificador global del servicio en logs y trazabilidad.
    #
    # @return [String]
    def self.service_name
      @service_name ||= (defined?(Rails) ? Rails.application.class.module_parent_name.underscore : "app")
    end

    # Genera un ID de correlación compuesto, útil para logs y auditoría.
    #
    # @example
    #   ExisRay::Tracer.correlation_id #=> "Wispro-HTTP;1-5759...-..."
    #
    # @return [String] Cadena compuesta "ServiceName;RootID".
    def self.correlation_id
      "#{service_name};#{root_id}"
    end

    # Parsea el string de trazabilidad recibido y popula los atributos individuales.
    # Maneja el formato estándar de AWS: "Root=...;Self=...;CalledFrom=...;TotalTimeSoFar=..."
    #
    # @return [void]
    def self.parse_trace_id
      return unless trace_id.present?

      # Fallback para desarrollo: Si el header no trae Root, generamos uno nuevo.
      self.trace_id = generate_new_root(trace_id) if trace_id.exclude?('Root')

      # Parseo a Hash
      data = trace_id.split(';').map { |part| part.split('=', 2) }.to_h

      self.root_id     = data['Root']
      self.self_id     = data['Self']
      self.called_from = data['CalledFrom']

      if data['TotalTimeSoFar']
        self.total_time_so_far = data['TotalTimeSoFar'].gsub(/ms$/i, '').to_i
      else
        self.total_time_so_far = 0
      end
    end

    # Calcula el tiempo transcurrido en milisegundos desde el inicio de la request.
    #
    # @return [Integer] Duración en ms.
    def self.current_duration_ms
      return 0 unless created_at
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - created_at) * 1000).round
    end

    # Construye el header de trazabilidad para enviar al siguiente servicio.
    #
    # @return [String] Header formateado: "Root=...;Self=...;CalledFrom=...;TotalTimeSoFar=...ms"
    def self.generate_trace_header
      safe_root = if root_id.present?
                    root_id.start_with?('Root=') ? root_id : "Root=#{root_id}"
                  else
                    generate_new_root
                  end

      total_acc_time = (total_time_so_far || 0) + current_duration_ms

      # Nuevo ID para el span actual
      my_new_id = "1-#{Time.now.to_i.to_s(16)}-#{clean_request_id}"

      "#{safe_root};Self=#{my_new_id};CalledFrom=#{service_name};TotalTimeSoFar=#{total_acc_time}ms"
    end

    # Genera un nuevo Root ID compatible con AWS X-Ray.
    #
    # @api private
    # @param suffix_id [String, nil] Sufijo opcional (ej: ID del Pod).
    # @return [String] Formato: 1-TimestampHex-RandomHex
    def self.generate_new_root(suffix_id = nil)
      timestamp_hex = Time.now.to_i.to_s(16)

      if suffix_id.present?
        # Codificamos los bytes del string a hex para preservar unicidad
        # independientemente de si el sufijo es numérico o alfanumérico.
        # Ej: "worker01" → "776f726b657230 31", "abc" → "616263"
        suffix_hex = suffix_id.to_s.bytes.map { |b| b.to_s(16).rjust(2, '0') }.join.first(8).rjust(8, '0')
        unique_part = SecureRandom.hex(8) + suffix_hex
      else
        unique_part = SecureRandom.hex(12)
      end

      "Root=1-#{timestamp_hex}-#{unique_part}"
    end

    # Limpia el Request ID para cumplir con los 24 caracteres hex de AWS.
    #
    # @api private
    # @return [String]
    def self.clean_request_id
      (request_id || SecureRandom.hex).delete('-').first(24)
    end

    private_class_method :clean_request_id, :generate_new_root
  end
end
