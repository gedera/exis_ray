# frozen_string_literal: true

require "faraday"

module ExisRay
  # Middleware para Faraday que inyecta el header de trazabilidad saliente.
  class FaradayMiddleware < Faraday::Middleware
    def call(env)
      inject_trace_header(env)
      @app.call(env)
    rescue StandardError
      @app.call(env)
    end

    private

    def inject_trace_header(env)
      return unless ExisRay::Tracer.root_id.present?

      header_key = ExisRay.configuration.propagation_trace_header
      header_value = ExisRay::Tracer.generate_trace_header
      env.request_headers[header_key] = header_value
    rescue StandardError
    end
  end
end
