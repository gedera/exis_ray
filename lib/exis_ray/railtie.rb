# frozen_string_literal: true

require "rails/railtie"

module ExisRay
  # Integración automática de la gema con el ecosistema de Ruby on Rails.
  #
  # Se encarga de inyectar middlewares, configurar la estrategia de logging
  # (texto plano o JSON estructurado) e instrumentar dependencias externas
  # como Sidekiq y ActiveResource durante la fase de inicialización (`boot`) de la app.
  class Railtie < ::Rails::Railtie
    # 1. Middleware HTTP
    # Intercepta las peticiones entrantes para hidratar el Tracer.
    initializer "exis_ray.configure_middleware" do |app|
      require "exis_ray/http_middleware"
      app.middleware.insert_after ActionDispatch::RequestId, ExisRay::HttpMiddleware
    end

    # 2. Configuración de Estrategia de Logging (Lograge y Tags)
    # Se ejecuta antes de que la aplicación termine de cargar sus configuraciones.
    initializer "exis_ray.configure_logging" do |app|
      if ExisRay.configuration.json_logs?
        require "lograge"

        # A. YA NO BORRAMOS LOS TAGS.
        # Si el usuario definió config.log_tags = [:uuid], los conservamos.
        # Nuestro JsonFormatter se encargará de agruparlos en un array JSON.

        # B. Activamos Lograge para condensar las múltiples líneas HTTP
        app.config.lograge.enabled = true

        # C. CLAVE: Lograge no debe formatear a JSON, solo debe devolver el Hash crudo.
        app.config.lograge.formatter = Lograge::Formatters::Raw.new
      else
        # Comportamiento legacy: Text Plain Tags
        # Aseguramos que sea un array y AGREGAMOS el nuestro sin pisar los del usuario
        app.config.log_tags ||= []
        app.config.log_tags << proc do
          ExisRay::Tracer.trace_id.presence || ExisRay::Tracer.root_id.presence
        end
      end
    end

    # 3. Integraciones Post-Boot y Forzado de Formateadores
    # Se ejecuta una vez que las gemas y el entorno de Rails están completamente cargados.
    config.after_initialize do
      # Aplicamos el formateador JSON globalmente al logger ya instanciado de Rails
      if ExisRay.configuration.json_logs? && Rails.logger
        Rails.logger.formatter = ExisRay::JsonFormatter.new
        Rails.logger.info({ message: "[ExisRay] JSON Logging unificado activado." })
      end

      # --- Instrumentación de ActiveResource ---
      if defined?(ActiveResource::Base)
        require "exis_ray/active_resource_instrumentation"
        ActiveResource::Base.send(:prepend, ExisRay::ActiveResourceInstrumentation)

        log_message(
          text: "[ExisRay] ActiveResource instrumentado.",
          json: { message: "[ExisRay] ActiveResource instrumentado." }
        )
      end

      # --- Instrumentación de Sidekiq ---
      if defined?(::Sidekiq)
        require "exis_ray/sidekiq/client_middleware"
        require "exis_ray/sidekiq/server_middleware"

        ::Sidekiq.configure_client do |config|
          config.client_middleware do |chain|
            chain.add ExisRay::Sidekiq::ClientMiddleware
          end
        end

        ::Sidekiq.configure_server do |config|
          config.client_middleware do |chain|
            chain.add ExisRay::Sidekiq::ClientMiddleware
          end
          config.server_middleware do |chain|
            chain.prepend ExisRay::Sidekiq::ServerMiddleware
          end
        end

        # Sidekiq maneja su propio logger. Lo forzamos a usar nuestra estructura JSON.
        if ExisRay.configuration.json_logs? && ::Sidekiq.logger
          ::Sidekiq.logger.formatter = ExisRay::JsonFormatter.new
          Rails.logger.info({ message: "[ExisRay] Sidekiq Middleware y JsonFormatter integrados." })
        else
          Rails.logger.info "[ExisRay] Sidekiq Middleware integrado."
        end
      end
    end

    # Helper interno para imprimir logs de inicialización respetando el formato elegido.
    #
    # @param text [String] El mensaje para el formato texto.
    # @param json [Hash] El payload para el formato JSON.
    # @return [void]
    def self.log_message(text:, json:)
      if ExisRay.configuration.json_logs?
        Rails.logger.info(json)
      else
        Rails.logger.info(text)
      end
    end
  end
end
