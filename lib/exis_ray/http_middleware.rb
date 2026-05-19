# frozen_string_literal: true

module ExisRay
  # Rack middleware que hidrata el Tracer con el header de trazabilidad entrante.
  # Se inserta automáticamente después de `ActionDispatch::RequestId` via Railtie.
  class HttpMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      ExisRay::Tracer.hydrate(
        trace_id: env[ExisRay.configuration.trace_header],
        source: "http"
      )
      # Si la request no trae trace header entrante (servicio que es punto de
      # entrada, no eslabón intermedio de un trace distribuido), generamos un
      # root_id fresco igual que el resto de entrypoints
      # (Sidekiq::ServerMiddleware, BugBunny::ConsumerTracingMiddleware,
      # TaskMonitor). Sin esto root_id queda nil y JsonFormatter dropea todo
      # el bloque de tracer, incluido `source` (campo mandatorio). Ver issue #9.
      ExisRay::Tracer.root_id ||= ExisRay::Tracer.send(:generate_new_root)
      ExisRay::Tracer.request_id = env["action_dispatch.request_id"]
      ExisRay.sync_correlation_id

      @app.call(env)
    rescue StandardError
      @app.call(env)
    end
  end
end
