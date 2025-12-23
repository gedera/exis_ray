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
      # 1. Obtenemos los headers originales (si los hay)
      original_headers = super

      # 2. Verificación Universal:
      # Usamos `root_id` en lugar de `trace_id`.
      # - trace_id: Solo existe si recibimos una petición Web (viene del header entrante).
      # - root_id: Existe SIEMPRE que haya traza (sea Web o sea un Cron generado por TaskMonitor).
      if ExisRay::Tracer.root_id.present?
        # Generamos el string propagable: "Root=...;Parent=...;Sampled=..."
        trace_header_value = ExisRay::Tracer.generate_trace_header

        # Buscamos la key configurada (ej: 'HTTP_X_AMZN_TRACE_ID' o custom)
        trace_header_key = ExisRay.configuration.trace_header

        # Retornamos un nuevo hash combinado (merge) para no mutar el original por error
        original_headers.merge(trace_header_key => trace_header_value)
      else
        # Si no hay traza activa, devolvemos los headers tal cual
        original_headers
      end
    end
  end
end
