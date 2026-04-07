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
      if app.middleware.respond_to?(:include?) && app.middleware.include?(ActionDispatch::RequestId)
        app.middleware.insert_after ActionDispatch::RequestId, ExisRay::HttpMiddleware
      else
        app.middleware.use ExisRay::HttpMiddleware
      end
    rescue NoMethodError
      app.middleware.use ExisRay::HttpMiddleware
    end

    # 2. Configuración de Estrategia de Logging
    # CLAVE: Usamos `after: :load_config_initializers` para garantizar que la app
    # ya haya leído `config/initializers/exis_ray.rb` antes de tomar esta decisión.
    initializer "exis_ray.configure_logging", after: :load_config_initializers do |app|
      unless ExisRay.configuration.json_logs?
        # Comportamiento legacy: Text Plain Tags
        app.config.log_tags ||= []
        app.config.log_tags << proc do
          ExisRay::Tracer.trace_id.presence || ExisRay::Tracer.root_id.presence
        end
      end
    end

    # 3. Integraciones Post-Boot y Forzado de Formateadores
    # Se ejecuta una vez que las gemas y el entorno de Rails están completamente cargados.
    config.after_initialize do
      # Validación de configuración: verificamos que las clases configuradas
      # hereden de los tipos base. Usamos warn en lugar de raise porque en
      # Rails 8.1+ after_initialize puede correr antes de eager_load!,
      # y safe_constantize puede fallar aún con eager_load=true.
      if (name = ExisRay.configuration.current_class).present?
        klass = name.safe_constantize
        if klass && !klass.<=(ExisRay::Current)
          raise "ExisRay: current_class '#{name}' does not inherit from ExisRay::Current"
        end
      end

      if (name = ExisRay.configuration.reporter_class).present?
        klass = name.safe_constantize
        if klass && !klass.<=(ExisRay::Reporter)
          raise "ExisRay: reporter_class '#{name}' does not inherit from ExisRay::Reporter"
        end
      end

      # Aplicamos el formateador JSON globalmente al logger ya instanciado de Rails
      if ExisRay.configuration.json_logs? && Rails.logger
        Rails.logger.formatter = ExisRay::JsonFormatter.new

        # Activamos nuestro LogSubscriber HTTP y suprimimos los de Rails por defecto.
        # Reemplaza Lograge, compatible con Rails 6, 7 y 8.
        require "exis_ray/log_subscriber"
        ExisRay::LogSubscriber.install!

        log_boot("component=exis_ray event=json_logging_enabled")
      end

      # --- Integración BugBunny ---
      if defined?(::BugBunny)
        require "exis_ray/bug_bunny/publisher_tracing"
        require "exis_ray/bug_bunny/consumer_tracing_middleware"
        ::BugBunny.consumer_middlewares.use ExisRay::BugBunny::ConsumerTracingMiddleware
        ::BugBunny.configuration.rpc_reply_headers = lambda {
          next {} unless ExisRay::Tracer.root_id.present?

          { ExisRay.configuration.propagation_trace_header => ExisRay::Tracer.generate_trace_header }
        }
        ::BugBunny.configuration.on_rpc_reply = lambda { |headers|
          begin
            trace_header = headers&.[](ExisRay.configuration.propagation_trace_header)
            next unless trace_header.present?

            # Solo actualizamos trace_id — no tocamos created_at ni source del publisher.
            ExisRay::Tracer.trace_id = trace_header
            ExisRay::Tracer.parse_trace_id
            ExisRay.sync_correlation_id
          rescue StandardError
          end
        }
        log_boot("component=exis_ray event=bug_bunny_instrumented")
      end

      # --- Instrumentación de ActiveResource ---
      if defined?(ActiveResource::Base)
        require "exis_ray/active_resource_instrumentation"
        unless ActiveResource::Base.ancestors.include?(ExisRay::ActiveResourceInstrumentation)
          ActiveResource::Base.prepend ExisRay::ActiveResourceInstrumentation
          log_boot("component=exis_ray event=active_resource_instrumented")
        end
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

        ::Sidekiq.logger.formatter = ExisRay::JsonFormatter.new if ExisRay.configuration.json_logs? && ::Sidekiq.logger
        log_boot("component=exis_ray event=sidekiq_instrumented")
      end
    end

    # Emite un log de boot en DEBUG con formato key=value.
    # En modo texto es legible directamente. En modo JSON el JsonFormatter
    # lo parsea y eleva cada campo al nivel raíz del JSON automáticamente.
    #
    # @param message [String] String en formato key=value.
    # @return [void]
    def self.log_boot(message)
      Rails.logger.debug { message }
    end
  end
end
