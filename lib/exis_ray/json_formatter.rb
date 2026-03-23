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

    # Procesa un mensaje de log y lo formatea como una cadena estructurada en JSON.
    #
    # @param severity [String] El nivel de severidad del log (ej. "INFO", "ERROR", "DEBUG").
    # @param timestamp [Time] La marca de tiempo en la que se generó el log.
    # @param _progname [String, nil] El nombre del programa o aplicación (ignorado aquí).
    # @param msg [String, Hash, Object] El mensaje a registrar. Puede ser un Hash (inyectado por Lograge) o un String.
    # @return [String] Una cadena en formato JSON terminada con un salto de línea (\n).
    def call(severity, timestamp, _progname, msg)
      payload = {
        time: timestamp.utc.iso8601,
        level: severity,
        service: ExisRay::Tracer.service_name
      }

      inject_tracer_context(payload)
      inject_business_context(payload)
      inject_current_tags(payload)
      process_message(payload, msg)

      # Compactamos para eliminar claves con valores nulos (nil) y generamos el JSON
      "#{payload.compact.to_json}\n"
    end

    private

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

      payload[:user_id] = curr.user_id if curr.respond_to?(:user_id) && curr.user_id
      payload[:isp_id]  = curr.isp_id  if curr.respond_to?(:isp_id)  && curr.isp_id

      if curr.respond_to?(:correlation_id) && curr.correlation_id
        payload[:correlation_id] = curr.correlation_id
      end
    end

    # Inyecta cualquier etiqueta nativa (tags) de Rails que esté presente en el hilo actual.
    #
    # @param payload [Hash] El diccionario base del log.
    # @return [void]
    def inject_current_tags(payload)
      if respond_to?(:current_tags) && current_tags.any?
        payload[:tags] = current_tags
      end
    end

    # Procesa el cuerpo del mensaje recibido y lo fusiona con el payload.
    #
    # Si el mensaje es un `Hash` (como el que nos pasará Lograge para peticiones HTTP),
    # se hace un merge directo. Si es un String con formato key=value (ej: "event=foo bar=baz"),
    # se parsea y los campos se elevan al nivel raíz del JSON. Valores con espacios deben estar
    # entre comillas (ej: message="algo salió mal"). Si el String no sigue ese formato, se asigna
    # a la clave `:message`.
    #
    # @param payload [Hash] El diccionario base del log.
    # @param msg [String, Hash, Object] El mensaje original recibido por el logger.
    # @return [void]
    def process_message(payload, msg)
      if msg.is_a?(Hash)
        payload.merge!(msg)
      elsif msg.is_a?(String) && kv_string?(msg)
        payload.merge!(parse_kv_string(msg))
      else
        payload[:message] = msg.to_s
      end
    end

    # Determina si un string tiene formato key=value.
    # Considera que hay formato kv si el string comienza con `word=`.
    #
    # @param str [String]
    # @return [Boolean]
    def kv_string?(str)
      str.match?(/\A\w+=/)
    end

    # Parsea un string con formato key=value y retorna un Hash.
    # Soporta valores con espacios si están entre comillas dobles (ej: message="algo salió mal").
    #
    # @param str [String]
    # @return [Hash]
    def parse_kv_string(str)
      result = {}
      str.scan(/(\w+)=("(?:[^"\\]|\\.)*"|\S+)/) do |key, value|
        result[key.to_sym] = value.start_with?('"') ? value[1..-2].gsub('\\"', '"') : value
      end
      result
    end
  end
end
