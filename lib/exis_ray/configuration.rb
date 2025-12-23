module ExisRay
  # Clase de configuración global para la gema.
  # Permite personalizar los headers de trazabilidad y la clase de reporte utilizada por la aplicación host.
  class Configuration
    # @!attribute [rw] trace_header
    #   @return [String] La key del header HTTP (formato Rack) donde se buscará el Trace ID.
    #   Por defecto es 'HTTP_X_AMZN_TRACE_ID'.
    attr_accessor :trace_header

    # @!attribute [rw] propagation_trace_header
    #   @return [String] La key del header HTTP (formato Rack) donde se buscará el Trace ID.
    #   Por defecto es 'HTTP_WISPRO_TRACE_ID'.
    attr_accessor :propagation_trace_header

    # @!attribute [rw] reporter_class
    #   @return [String, Class, nil] El nombre de la clase de la aplicación host que hereda de {ExisRay::Reporter}.
    #   Permite que el TaskMonitor inyecte tags (como el nombre de la tarea) en la clase correcta
    #   para que Sentry los detecte.
    #   @example 'Choto' o 'ErrorReport'
    attr_accessor :reporter_class

    # @!attribute [rw] current_class
    #   @return [String, Class, nil] El nombre de la clase de la aplicación host que hereda de {ExisRay::Current}.
    #   Permite que el se inyecte user, correlation_id e isp
    #   Son modelos genericos que se usan en todos los contextos de los microservicios.
    #   @example 'Current'
    attr_accessor :current_class

    # Inicializa la configuración con valores por defecto.
    def initialize
      # Estándar de AWS X-Ray
      @trace_header = 'HTTP_X_AMZN_TRACE_ID'

      # Por defecto nil. El usuario debe configurarlo en el initializer si usa herencia.
      @reporter_class = nil
    end
  end
end
