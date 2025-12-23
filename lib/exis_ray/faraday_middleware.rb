require 'faraday'

module ExisRay
  # Middleware para Faraday que inyecta automáticamente el header de trazabilidad
  # en todas las peticiones salientes.
  #
  # Esto asegura que si el Servicio A llama al Servicio B, la traza continúe
  # y no se rompa la cadena de observabilidad.
  #
  # @example Uso
  #   conn = Faraday.new(url: 'https://api.wispro.co') do |f|
  #     f.use ExisRay::FaradayMiddleware
  #     f.adapter Faraday.default_adapter
  #   end
  class FaradayMiddleware < Faraday::Middleware
    # Intercepta la llamada saliente.
    #
    # @param env [Faraday::Env] El entorno de la petición saliente.
    def call(env)
      # Solo inyectamos el header si tenemos un Trace ID activo en el contexto actual.
      if ExisRay::Tracer.trace_id.present?
        # Generamos el string propagable (Root=...;Self=...; etc)
        header_value = ExisRay::Tracer.generate_trace_header

        # Usamos el header de propagation
        header_key = ExisRay.configuration.propagation_trace_header

        # Inyectamos el header
        env.request_headers[header_key] = header_value
      end

      # Continuamos con la llamada HTTP real
      @app.call(env)
    end
  end
end
