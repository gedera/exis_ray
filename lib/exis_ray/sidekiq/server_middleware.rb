# frozen_string_literal: true

module ExisRay
  module Sidekiq
    # Middleware de Servidor para Sidekiq.
    #
    # Se ejecuta envolviendo cada trabajo (job) procesado por un Worker.
    #
    # Responsabilidades:
    # 1. Recuperar el Trace ID y contexto de negocio (User, ISP) inyectados por el cliente.
    # 2. Hidratar el entorno local (Tracer, Current, Reporter).
    # 3. Limpiar absolutamente todo al finalizar para no contaminar el Thread Pool de Sidekiq.
    class ServerMiddleware
      # Intercepta la ejecución del job en el servidor Sidekiq.
      #
      # @param worker [Object] La instancia del worker que procesará el job.
      # @param job [Hash] El payload del trabajo (contiene argumentos y metadatos inyectados).
      # @param _queue [String] El nombre de la cola (ignorado).
      # @yield Ejecuta el bloque que procesa el job real.
      # @return [void]
      def call(worker, job, _queue)
        hydrate_tracer(worker, job)
        hydrate_current(job)
        setup_reporter(worker)

        # Ejecución adaptativa de logs
        if !ExisRay.configuration.json_logs? && Rails.logger.respond_to?(:tagged)
          Rails.logger.tagged(ExisRay::Tracer.root_id) { yield }
        else
          yield
        end
      ensure
        # Limpieza vital en Sidekiq para evitar fugas de contexto entre jobs en el mismo hilo.
        ExisRay::Tracer.reset
        ExisRay.current_class&.reset  if ExisRay.current_class.respond_to?(:reset)
        ExisRay.reporter_class&.reset if ExisRay.reporter_class.respond_to?(:reset)
      end

      private

      # Configura el Tracer con el ID recibido en el payload o genera uno nuevo si no existe.
      #
      # @param worker [Object] Instancia del worker.
      # @param job [Hash] Payload de Sidekiq.
      # @return [void]
      def hydrate_tracer(worker, job)
        ExisRay::Tracer.created_at = Time.now.utc.to_f
        ExisRay::Tracer.sidekiq_job = worker.class.name

        if job["exis_ray_trace"]
          # Continuidad: Usamos la traza propagada desde el cliente (Web/Cron)
          ExisRay::Tracer.trace_id = job["exis_ray_trace"]
          ExisRay::Tracer.parse_trace_id
        else
          # Origen: El job nació directamente aquí sin contexto previo
          ExisRay::Tracer.root_id = ExisRay::Tracer.send(:generate_new_root)
        end
      end

      # Hidrata la clase Current configurada con los datos de negocio del payload.
      #
      # @param job [Hash] Payload de Sidekiq.
      # @return [void]
      def hydrate_current(job)
        klass = ExisRay.current_class
        return unless klass && job["exis_ray_context"]

        ctx = job["exis_ray_context"]

        klass.user_id = ctx["user_id"] if ctx["user_id"] && klass.respond_to?(:user_id=)
        klass.isp_id  = ctx["isp_id"]  if ctx["isp_id"]  && klass.respond_to?(:isp_id=)

        if ctx["correlation_id"] && klass.respond_to?(:correlation_id=)
          klass.correlation_id = ctx["correlation_id"]
        end
      end

      # Configura etiquetas y nombres de transacción en el Reporter (Sentry).
      #
      # @param worker [Object] Instancia del worker.
      # @return [void]
      def setup_reporter(worker)
        klass = ExisRay.reporter_class
        return unless klass

        if klass.respond_to?(:transaction_name=)
          klass.transaction_name = "Sidekiq/#{worker.class.name}"
        end

        return unless klass.respond_to?(:add_tags)

        klass.add_tags(
          sidekiq_queue: worker.class.get_sidekiq_options["queue"],
          retry_count: worker.respond_to?(:retry_count) ? worker.retry_count : 0
        )
      end
    end
  end
end
