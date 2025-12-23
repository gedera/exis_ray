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

    # Inicializa la configuración con valores por defecto compatibles con AWS X-Ray.
    def initialize
      @trace_header = 'HTTP_X_AMZN_TRACE_ID'
      @propagation_trace_header = 'X-Amzn-Trace-Id'
      @reporter_class = 'Reporter'
      @current_class = 'Current'
    end
  end
end
