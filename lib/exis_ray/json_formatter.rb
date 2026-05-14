# frozen_string_literal: true

require "logger"
require "json"
require "active_support/tagged_logging"

module ExisRay
  # Formateador global que intercepta todos los logs de la aplicación y los emite en formato JSON.
  #
  # Esta clase hereda de `Logger::Formatter` y tiene la responsabilidad unificada
  # de estandarizar la salida para peticiones HTTP (procesadas previamente vía Lograge),
  # trabajos en segundo plano (Sidekiq), tareas programadas (Rake/Cron) y cualquier
  # mensaje arbitrario enviado explícitamente a `Rails.logger`.
  #
  # Automáticamente inyecta el contexto de trazabilidad ({ExisRay::Tracer})
  # y el contexto de negocio ({ExisRay::Current}) en cada línea de log.
  class JsonFormatter < ::Logger::Formatter
    # Solución al NoMethodError: Garantiza que el formateador sea compatible
    # con el wrapper de ActiveSupport::TaggedLogging de Rails.
    include ActiveSupport::TaggedLogging::Formatter if defined?(ActiveSupport::TaggedLogging::Formatter)

    # Detecta si un string comienza con al menos un par key=value.
    KV_DETECT_RE = /\A\w+=/

    # Extrae pares key=value de un string. Soporta valores entre comillas dobles/simples
    # o valores sin comillas que se extienden hasta el próximo token key= o fin de string.
    KV_PARSE_RE  = /(\w+)=("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|(?:(?!\s+\w+=).)+)/

    # Claves sensibles que deben filtrarse automáticamente según el estándar de Gabriel.
    SENSITIVE_KEYS = /password|pass|passwd|secret|token|api_key|auth/i

    # Mapeo de severity_text OTel a SeverityNumber del Log Data Model.
    # https://opentelemetry.io/docs/specs/otel/log/data-model/#field-severitynumber
    SEVERITY_NUMBER = {
      "DEBUG" => 5,
      "INFO" => 9,
      "WARN" => 13,
      "ERROR" => 17,
      "FATAL" => 21
    }.freeze

    # Procesa un mensaje de log y lo formatea como una cadena estructurada en JSON.
    #
    # @param severity [String] El nivel de severidad del log (ej. "INFO", "ERROR", "DEBUG").
    # @param timestamp [Time] La marca de tiempo en la que se generó el log.
    # @param _progname [String, nil] El nombre del programa o aplicación (ignorado aquí).
    # @param msg [String, Hash, Object] El mensaje a registrar. Puede ser un Hash (inyectado por Lograge) o un String.
    # @return [String] Una cadena en formato JSON terminada con un salto de línea (\n).
    def call(severity, timestamp, _progname, msg)
      payload = {
        time: timestamp&.utc&.iso8601 || Time.now.utc.iso8601,
        level: severity,
        severity_number: SEVERITY_NUMBER[severity],
        service: ExisRay::Tracer.service_name,
        service_version: service_version,
        deployment_environment: deployment_environment
      }

      inject_tracer_context(payload)
      inject_business_context(payload)
      inject_current_tags(payload)
      process_message(payload, msg)

      "#{JSON.generate(payload.compact, { ascii_only: false })}\n"
    rescue StandardError
      fallback_message(severity, timestamp, msg)
    end

    private

    # @return [String, nil]
    def service_version
      ExisRay.configuration.service_version
    end

    # @return [String, nil]
    def deployment_environment
      ExisRay.configuration.deployment_environment
    end

    # Genera un JSON de fallback cuando el formateo principal falla.
    # Nunca debe lanzar una excepción.
    #
    # @param severity [String]
    # @param timestamp [Time]
    # @param msg [Object]
    # @return [String]
    def fallback_message(severity, timestamp, msg)
      fallback = {
        time: timestamp&.utc&.iso8601 || Time.now.utc.iso8601,
        level: severity,
        service: ExisRay::Tracer.service_name,
        body: msg.to_s[0..500]
      }
      "#{JSON.generate(fallback)}\n"
    rescue StandardError
      "#{JSON.generate({ time: Time.now.utc.iso8601, level: severity, body: "log_error" })}\n"
    end

    # Inyecta los identificadores de trazabilidad distribuida en el payload.
    #
    # @param payload [Hash] El diccionario del log donde se insertarán los datos.
    # @return [void]
    def inject_tracer_context(payload)
      return unless ExisRay::Tracer.root_id

      payload[:root_id]  = ExisRay::Tracer.root_id
      payload[:trace_id] = ExisRay::Tracer.trace_id if ExisRay::Tracer.trace_id
      payload[:sidekiq_job] = ExisRay::Tracer.sidekiq_job if ExisRay::Tracer.sidekiq_job
      payload[:task] = ExisRay::Tracer.task if ExisRay::Tracer.task
      payload[:source] = ExisRay::Tracer.source if ExisRay::Tracer.source
    end

    # Inyecta el contexto de negocio (ID de usuario, ISP, ID de correlación) en el payload.
    #
    # @param payload [Hash] El diccionario del log donde se insertarán los datos.
    # @return [void]
    def inject_business_context(payload)
      curr = ExisRay.current_class
      return unless curr

      payload[:user_id] = curr.user_id if curr.respond_to?(:user_id) && !curr.user_id.nil?
      payload[:isp_id]  = curr.isp_id  if curr.respond_to?(:isp_id)  && !curr.isp_id.nil?

      if curr.respond_to?(:correlation_id) && curr.correlation_id
        payload[:correlation_id] = curr.correlation_id
      end

      inject_log_fields(payload, curr)
    end

    # Mergea el resultado de `Current.log_fields` al payload, aplicando el mismo
    # filtrado de claves sensibles que el resto del formatter. Si la subclass del
    # host overrideó el hook y revienta, el error se traga: logging nunca debe
    # afectar el flujo principal.
    #
    # @param payload [Hash]
    # @param curr [Class] La clase Current configurada por la app host.
    # @return [void]
    def inject_log_fields(payload, curr)
      return unless curr.respond_to?(:log_fields)

      fields = curr.log_fields
      return if fields.nil? || fields.empty?

      payload.merge!(filter_sensitive_hash(fields))
    rescue StandardError
      nil
    end

    # Inyecta cualquier etiqueta nativa (tags) de Rails que esté presente en el hilo actual.
    #
    # @param payload [Hash] El diccionario base del log.
    # @return [void]
    def inject_current_tags(payload)
      return unless respond_to?(:current_tags) && current_tags.any?

      payload[:tags] = current_tags
    end

    # Procesa el cuerpo del mensaje recibido y lo fusiona con el payload.
    #
    # Si el mensaje es un `Hash` (como el que nos pasará Lograge para peticiones HTTP),
    # se hace un merge directo. Si es un String con formato key=value (ej: "event=foo bar=baz"),
    # se parsea y los campos se elevan al nivel raíz del JSON. Valores con espacios deben estar
    # entre comillas (ej: message="algo salió mal"). Si el String no sigue ese formato, se asigna
    # a la clave `:body` (OpenTelemetry log body).
    #
    # @param payload [Hash] El diccionario base del log.
    # @param msg [String, Hash, Object] El mensaje original recibido por el logger.
    # @return [void]
    def process_message(payload, msg)
      if msg.is_a?(Hash)
        # Filtramos las claves del Hash antes del merge
        payload.merge!(filter_sensitive_hash(msg))
      elsif msg.is_a?(String) && kv_string?(msg)
        parsed = parse_kv_string(msg)
        parsed.empty? ? payload[:body] = msg : payload.merge!(parsed)
      else
        payload[:body] = msg.to_s
      end
    end

    # Determina si un string tiene formato key=value.
    # Considera que hay formato kv si el string comienza con `word=`.
    #
    # @param str [String]
    # @return [Boolean]
    def kv_string?(str)
      str.match?(KV_DETECT_RE)
    end

    # Parsea un string con formato key=value y retorna un Hash.
    # Soporta valores con espacios si están entre comillas dobles o simples.
    # Intenta convertir valores numéricos a Float o Integer automáticamente.
    # Usa strings como claves para evitar memory leaks por symbols.
    #
    # @param str [String]
    # @return [Hash]
    def parse_kv_string(str)
      result = {}
      str.scan(KV_PARSE_RE) do |key, value|
        val = if value.start_with?('"', "'")
                value[1..-2].to_s.gsub("\\#{value[0]}", value[0])
              else
                value.strip
              end

        result[key] = cast_value(key, val)
      end
      result
    end

    # Filtra un valor si la clave se considera sensible.
    # Si no es sensible, intenta castear el valor a número o a objeto JSON si corresponde.
    #
    # @param key [String, Symbol]
    # @param value [Object]
    # @return [Object]
    def cast_value(key, value)
      return "[FILTERED]" if key.to_s.match?(SENSITIVE_KEYS)

      case value
      when /\A\d+\z/ then value.to_i
      when /\A\d+\.\d+\z/ then value.to_f
      else try_parse_json(value)
      end
    end

    # Intenta parsear un string como JSON si parece un objeto o array.
    # Permite que valores como queue_opts={"exclusive":false} se emitan como
    # objetos JSON en lugar de strings escapados.
    #
    # @param value [Object]
    # @return [Object] El objeto parseado o el valor original si no es JSON válido.
    def try_parse_json(value)
      return value unless value.is_a?(String) && (value.start_with?("{") || value.start_with?("["))

      JSON.parse(value)
    rescue JSON::ParserError
      value
    end

    # Filtra recursivamente un Hash que contenga claves sensibles.
    # Maneja valores anidados de tipo Hash o Array.
    # Detecta referencias circulares para evitar stack overflow.
    #
    # @param hash [Hash]
    # @param visited [Set] IDs de objetos ya visitados para detectar ciclos (O(1) lookup).
    # @return [Hash]
    def filter_sensitive_hash(hash, visited = Set.new)
      return {} if hash.nil?
      return {} if visited.include?(hash.object_id)

      visited |= Set.new([hash.object_id])

      hash.each_with_object({}) do |(k, v), result|
        result[k] = case v
                    when Hash  then filter_sensitive_hash(v, visited)
                    when Array then filter_sensitive_array(k, v, visited)
                    else            cast_value(k, v)
                    end
      end
    end

    # Filtra recursivamente los elementos de un Array, propagando la clave padre
    # para que el filtrado de claves sensibles se aplique a hashes anidados.
    # Detecta referencias circulares para evitar stack overflow.
    #
    # @param key [String, Symbol] Clave padre (para filtrado si el array no contiene hashes).
    # @param array [Array]
    # @param visited [Set] IDs de objetos ya visitados para detectar ciclos (O(1) lookup).
    # @return [Array]
    def filter_sensitive_array(key, array, visited = Set.new)
      return [] if array.nil?
      return [] if visited.include?(array.object_id)

      visited |= Set.new([array.object_id])

      array.map do |element|
        case element
        when Hash  then filter_sensitive_hash(element, visited)
        when Array then filter_sensitive_array(key, element, visited)
        else            cast_value(key, element)
        end
      end
    end
  end
end
