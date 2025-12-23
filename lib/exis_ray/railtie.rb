require 'rails/railtie'

module ExisRay
  # Integración automática con Rails.
  # Carga middlewares HTTP, tags de logs e integraciones (Sidekiq/ActiveResource).
  class Railtie < ::Rails::Railtie
    # 1. Middleware HTTP
    initializer "exis_ray.configure_middleware" do |app|
      require 'exis_ray/http_middleware'
      app.middleware.insert_after ActionDispatch::RequestId, ExisRay::HttpMiddleware
    end

    # 2. Logs Tags
    initializer "exis_ray.configure_log_tags" do |app|
      app.config.log_tags ||= []
      app.config.log_tags << proc {
        if ExisRay::Tracer.trace_id.present?
          ExisRay::Tracer.trace_id
        elsif ExisRay::Tracer.root_id.present?
          "Root=#{ExisRay::Tracer.root_id}"
        else
          nil
        end
      }
    end

    # 3. Integraciones Post-Boot
    config.after_initialize do
      # ActiveResource
      if defined?(ActiveResource::Base)
        require 'exis_ray/active_resource_instrumentation'
        ActiveResource::Base.send(:prepend, ExisRay::ActiveResourceInstrumentation)
        Rails.logger.info "[ExisRay] ActiveResource instrumentado."
      end

      # Sidekiq
      # Usamos ::Sidekiq para referirnos a la Gema Global y no al módulo local ExisRay::Sidekiq
      if defined?(::Sidekiq)
        require 'exis_ray/sidekiq/client_middleware'
        require 'exis_ray/sidekiq/server_middleware'

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
        Rails.logger.info "[ExisRay] Sidekiq Middleware integrado."
      end
    end
  end
end
