require 'faraday'

module ExisRay
  # Middleware para Faraday que inyecta el header de trazabilidad saliente.
  class FaradayMiddleware < Faraday::Middleware
    def call(env)
      if ExisRay::Tracer.root_id.present?
        # Generamos el valor de traza
        header_value = ExisRay::Tracer.generate_trace_header
        # Obtenemos la key configurada para propagación
        header_key = ExisRay.configuration.propagation_trace_header

        env.request_headers[header_key] = header_value
      end
      @app.call(env)
    end
  end
end

