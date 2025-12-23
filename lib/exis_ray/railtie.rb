require 'rails/railtie'

module ExisRay
  # Integración automática con el ciclo de vida de Rails.
  # Esta clase actúa como el "pegamento" que conecta la gema con la aplicación host.
  #
  # Se encarga de:
  # 1. Inyectar el Middleware HTTP para interceptar peticiones web.
  # 2. Configurar los Tags en los logs de Rails para incluir el Trace ID.
  # 3. Detectar e instrumentar librerías externas (ActiveResource, Sidekiq) de forma segura.
  class Railtie < ::Rails::Railtie
    # 1. Configuración del Middleware HTTP
    # Inserta el middleware de ExisRay inmediatamente después de `RequestId`.
    # Esto asegura que el Trace ID esté disponible lo antes posible en la cadena de procesamiento,
    # antes de que se ejecuten otros middlewares de log, autenticación o Sentry.
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
        # Fallback: Si estamos en un Cron (TaskMonitor) o Sidekiq, no hay header HTTP,
        # pero sí hay Root ID generado.
        elsif ExisRay::Tracer.root_id.present?
          "Root=#{ExisRay::Tracer.root_id}"
        else
          nil
        end
      }
    end

    # 3. Integraciones Post-Inicialización (ActiveResource y Sidekiq)
    # Usamos `after_initialize` para garantizar que todas las gemas del Gemfile
    # (como Sidekiq o ActiveResource) ya hayan sido cargadas antes de intentar parchearlas.
    config.after_initialize do
      # --- A. Instrumentación de ActiveResource ---
      if defined?(ActiveResource::Base)
        require 'exis_ray/active_resource_instrumentation'

        # Inyectamos el módulo usando prepend para interceptar las llamadas salientes
        # y agregar los headers de traza.
        ActiveResource::Base.send(:prepend, ExisRay::ActiveResourceInstrumentation)

        Rails.logger.info "[ExisRay] ActiveResource instrumentado correctamente."
      end

      # --- B. Instrumentación de Sidekiq ---
      if defined?(Sidekiq)
        require 'exis_ray/sidekiq/client_middleware'
        require 'exis_ray/sidekiq/server_middleware'

        # Configuración del Cliente:
        # Se ejecuta cuando alguien hace `Worker.perform_async`.
        # Inyecta el Trace ID y el Contexto (User/ISP) en el payload del trabajo.
        Sidekiq.configure_client do |config|
          config.client_middleware do |chain|
            chain.add ExisRay::Sidekiq::ClientMiddleware
          end
        end

        # Configuración del Servidor:
        # Se ejecuta cuando el proceso de Sidekiq arranca para procesar trabajos.
        Sidekiq.configure_server do |config|
          # El servidor también necesita el ClientMiddleware por si un job encola otro job.
          config.client_middleware do |chain|
            chain.add ExisRay::Sidekiq::ClientMiddleware
          end

          # El ServerMiddleware envuelve la ejecución del job.
          # Usamos `prepend` para que sea el PRIMERO en ejecutarse, asegurando que
          # el Tracer esté listo antes de que Sentry o los Logs intenten usarlo.
          config.server_middleware do |chain|
            chain.prepend ExisRay::Sidekiq::ServerMiddleware
          end
        end

        Rails.logger.info "[ExisRay] Sidekiq Middleware integrado correctamente."
      end
    end
  end
end
