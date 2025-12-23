module ExisRay
  # Middleware de Rack para interceptar peticiones HTTP.
  # Inicializa el Tracer y sincroniza el Correlation ID con la clase Current configurada.
  class HttpMiddleware
    def initialize(app)
      @app = app
      @base_service_name = defined?(Rails) ? Rails.application.class.module_parent_name : 'App'
    end

    def call(env)
      # 1. Hidratar Infraestructura
      ExisRay::Tracer.created_at   = Time.now.utc.to_f
      ExisRay::Tracer.service_name = "#{@base_service_name}-HTTP"

      trace_header_key = ExisRay.configuration.trace_header

      ExisRay::Tracer.trace_id     = env[trace_header_key]
      ExisRay::Tracer.request_id   = env['action_dispatch.request_id']
      ExisRay::Tracer.parse_trace_id

      # 2. Hidratar Negocio
      # Usamos el helper centralizado para obtener la clase Current
      if (curr = ExisRay.current_class) && curr.respond_to?(:correlation_id=) && ExisRay::Tracer.root_id.present?
        curr.correlation_id = ExisRay::Tracer.correlation_id
      end

      @app.call(env)
    end
  end
end
