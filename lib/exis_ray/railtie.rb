require 'rails/railtie'

module ExisRay
  # Integración automática con el ciclo de vida de Rails.
  # Esta clase se encarga de inyectar los middlewares, configurar los logs y aplicar parches
  # necesarios cuando la gema se carga dentro de una aplicación Rails.
  class Railtie < ::Rails::Railtie
    # 1. Configuración del Middleware HTTP
    # Inserta el middleware de ExisRay inmediatamente después de `RequestId`.
    # Esto asegura que el Trace ID esté disponible lo antes posible en la cadena de procesamiento,
    # antes de que se ejecuten otros middlewares de log o autenticación.
    initializer "exis_ray.configure_middleware" do |app|
      require 'exis_ray/http_middleware'
      app.middleware.insert_after ActionDispatch::RequestId, ExisRay::HttpMiddleware
    end

    # 2. Configuración de Tags en Logs
    # Añade dinámicamente el ID de traza al inicio de cada línea de log de Rails.
    #
    # Estrategia de Tagging:
    # - Si es una petición Web: Muestra el `trace_id` completo (Header raw) si existe.
    # - Si es un Cron/Task: Muestra `Root=...` usando el `root_id` generado internamente.
    #
    # @example Salida en logs
    #   [Root=1-653a...f9] Started GET "/users" ...
    initializer "exis_ray.configure_log_tags" do |app|
      # Inicializamos el array si no existe (defensivo)
      app.config.log_tags ||= []

      app.config.log_tags << proc {
        # Preferencia: Header original completo (tiene más contexto: Parent, Sampled, etc.)
        if ExisRay::Tracer.trace_id.present?
          ExisRay::Tracer.trace_id
        # Fallback: Si estamos en un Cron (TaskMonitor), no hay header, pero sí hay Root ID.
        elsif ExisRay::Tracer.root_id.present?
          "Root=#{ExisRay::Tracer.root_id}"
        else
          nil
        end
      }
    end

    # 3. Instrumentación de ActiveResource
    # Se ejecuta después de la inicialización completa para asegurar que ActiveResource
    # ya ha sido cargado por Rails o por otras gemas.
    #
    # Aplica el módulo `ActiveResourceInstrumentation` usando `prepend` para
    # inyectar los headers de traza en las peticiones salientes.
    config.after_initialize do
      if defined?(ActiveResource::Base)
        require 'exis_ray/active_resource_instrumentation'

        # Inyectamos el módulo. Usamos send(:prepend) porque en versiones viejas de Ruby/Rails
        # prepend podría ser privado o protegido en ciertos contextos.
        ActiveResource::Base.send(:prepend, ExisRay::ActiveResourceInstrumentation)

        Rails.logger.info "[ExisRay] ActiveResource instrumentado correctamente."
      end
    end
  end
end
