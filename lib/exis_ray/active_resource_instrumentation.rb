# frozen_string_literal: true

module ExisRay
  # Módulo diseñado para interceptar e instrumentar las peticiones HTTP salientes realizadas con ActiveResource.
  # Utiliza el patrón `prepend` para envolver el método `headers` original sin romper la cadena de herencia.
  #
  # Su función principal es inyectar automáticamente el header de trazabilidad (Trace ID)
  # en todas las peticiones salientes para mantener la traza distribuida entre microservicios.
  module ActiveResourceInstrumentation
    # Sobrescribe el método `headers` de ActiveResource para inyectar el Trace ID actual.
    #
    # Lógica de inyección:
    # 1. Obtiene los headers definidos originalmente por el modelo o la request.
    # 2. Verifica si existe un contexto de traza activo (Root ID).
    # 3. Si existe, genera el header formateado (AWS/Wispro) y lo fusiona con los headers originales.
    #
    # @return [Hash] Un hash de headers HTTP que incluye el header de trazabilidad si corresponde.
    def headers
      original_headers = super
      return original_headers unless ExisRay::Tracer.root_id.present?

      inject_trace_header(original_headers)
    rescue StandardError
      original_headers
    end

    private

    def inject_trace_header(original_headers)
      trace_header_value = ExisRay::Tracer.generate_trace_header
      trace_header_key = ExisRay.configuration.propagation_trace_header
      original_headers.merge(trace_header_key => trace_header_value)
    rescue StandardError
      original_headers
    end
  end
end
