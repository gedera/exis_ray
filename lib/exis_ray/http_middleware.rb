module ExisRay
  # Middleware de Rack encargado de interceptar todas las peticiones HTTP entrantes.
  # Su responsabilidad es inicializar el contexto de trazabilidad ({ExisRay::Tracer})
  # antes de que la petición llegue al controlador o lógica de la aplicación.
  #
  # Funcionalidades principales:
  # 1. Detectar dinámicamente el Trace ID basándose en la configuración de headers ({ExisRay::Configuration}).
  # 2. Inicializar el Tracer con tiempos, IDs y nombres de servicio.
  # 3. Sincronizar el Correlation ID con la clase `Current` de la aplicación (si existe) para logs y auditoría.
  class HttpMiddleware
    # Inicializa el middleware.
    # Determina el nombre base del servicio una sola vez al arrancar para optimizar rendimiento.
    #
    # @param app [Object] La siguiente aplicación o middleware en la cadena de Rack.
    def initialize(app)
      @app = app
      # Fallback seguro: Si Rails no está definido (ej: Sinatra/Rack puro), usamos 'App'.
      @base_service_name = defined?(Rails) ? Rails.application.class.module_parent_name : 'App'
    end

    # Ejecuta la lógica de intercepción para cada petición HTTP.
    #
    # @param env [Hash] El entorno de Rack que contiene headers, parámetros y variables del servidor.
    # @return [Array] La respuesta estándar de Rack [status, headers, body].
    def call(env)
      # 1. Hidratar Infraestructura (Tracer)
      # Marcamos el tiempo de inicio y definimos el contexto (HTTP)
      ExisRay::Tracer.created_at   = Time.now.utc.to_f
      ExisRay::Tracer.service_name = "#{@base_service_name}-HTTP"

      # Buscamos el Trace ID en los headers configurados (ej: HTTP_X_AMZN_TRACE_ID).
      # Usamos .find para detenernos en el primer header que contenga valor.
      trace_header_key = ExisRay.configuration.trace_header

      # Asignamos el valor encontrado (o nil si no vino ninguno)
      ExisRay::Tracer.trace_id     = env[trace_header_key]
      ExisRay::Tracer.request_id   = env['action_dispatch.request_id']

      # Procesamos el string para descomponer Root, Parent, etc.
      ExisRay::Tracer.parse_trace_id

      # 2. Hidratar Negocio (Puente con la App)
      # Si la aplicación define un modelo `Current` con `correlation_id`, se lo inyectamos.
      # Esto permite que los logs y herramientas de negocio (como PaperTrail) tengan contexto.
      if defined?(::Current) && ::Current.respond_to?(:correlation_id=) && ExisRay::Tracer.root_id.present?
        ::Current.correlation_id = ExisRay::Tracer.correlation_id
      end

      # 3. Continuar con la cadena de ejecución
      @app.call(env)
    end
  end
end
