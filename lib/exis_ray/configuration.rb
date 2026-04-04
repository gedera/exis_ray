# frozen_string_literal: true

module ExisRay
  # Clase de configuración global para la gema.
  # Permite personalizar los headers de trazabilidad y definir las clases de la aplicación host
  # que la gema utilizará para gestionar el contexto (Current) y el reporte de errores (Reporter).
  class Configuration
    # @!attribute [rw] trace_header
    #   @return [String] La key del header HTTP (formato Rack) donde se buscará el Trace ID entrante.
    #   Por defecto es 'HTTP_X_AMZN_TRACE_ID'.
    attr_accessor :trace_header

    # @!attribute [rw] propagation_trace_header
    #   @return [String] La key del header HTTP que se enviará a otros servicios (formato estándar).
    #   Por defecto es 'X-Amzn-Trace-Id'.
    attr_accessor :propagation_trace_header

    # @!attribute [rw] reporter_class
    #   @return [String, Class, nil] El nombre de la clase de la aplicación host que hereda de {ExisRay::Reporter}.
    #   Se recomienda usar un String para evitar problemas de carga (autoloading) durante la inicialización.
    #   @example 'Choto'
    attr_accessor :reporter_class

    # @!attribute [rw] current_class
    #   @return [String, Class, nil] El nombre de la clase de la aplicación host que hereda de {ExisRay::Current}.
    #   Se utiliza para inyectar/leer user_id, isp_id y correlation_id.
    #   @example 'Current'
    attr_accessor :current_class

    # @!attribute [rw] log_format
    #   @return [Symbol] El formato en el que se emitirán los logs de la aplicación.
    #   Puede ser `:text` (comportamiento por defecto de Rails) o `:json` (formato estructurado).
    #   @example :json
    attr_accessor :log_format

    # @!attribute [rw] log_subscriber_class
    #   @return [String, nil] Nombre de la subclase de ExisRay::LogSubscriber de la app host.
    #   Usada para inyectar campos extra en cada log de request HTTP via `extra_fields`.
    #   Si es nil, se usa ExisRay::LogSubscriber directamente (sin campos extra).
    #   @example 'MyLogSubscriber'
    attr_accessor :log_subscriber_class

    # Inicializa la configuración con valores por defecto compatibles con AWS X-Ray.
    def initialize
      @trace_header = "HTTP_X_AMZN_TRACE_ID"
      @propagation_trace_header = "X-Amzn-Trace-Id"
      @reporter_class = "Reporter"
      @current_class = "Current"
      @log_format = :text
      @log_subscriber_class = nil
    end

    # Indica si la aplicación está configurada para emitir logs en formato estructurado (JSON).
    #
    # @return [Boolean] `true` si `log_format` es `:json`, `false` en caso contrario.
    def json_logs?
      @log_format == :json
    end
  end
end
