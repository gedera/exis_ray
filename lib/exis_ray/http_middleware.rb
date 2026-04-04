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
      ExisRay::Tracer.request_id = env["action_dispatch.request_id"]
      ExisRay.sync_correlation_id

      @app.call(env)
    rescue StandardError
      @app.call(env)
    end
  end
end
