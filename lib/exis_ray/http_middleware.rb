module ExisRay
  # Middleware de Rack para interceptar peticiones HTTP.
  # Inicializa el Tracer y sincroniza el Correlation ID con la clase Current configurada.
  class HttpMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      # 1. Hidratar Infraestructura
      ExisRay::Tracer.hydrate(
        trace_id: env[ExisRay.configuration.trace_header],
        source:   "http"
      )
      ExisRay::Tracer.request_id = env['action_dispatch.request_id']

      # 2. Hidratar Negocio
      ExisRay.sync_correlation_id

      @app.call(env)
    end
  end
end
