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
      def call(worker, job, _queue, &block)
        hydrate_tracer(worker, job)
        hydrate_current(job)
        setup_reporter(worker)

        if !ExisRay.configuration.json_logs? && Rails.logger.respond_to?(:tagged)
          Rails.logger.tagged(ExisRay::Tracer.root_id, &block)
        else
          yield
        end
      ensure
        ExisRay::Tracer.reset
        cleanup_current
        cleanup_reporter
      end

      private

      def cleanup_current
        current = ExisRay.current_class
        return unless current&.respond_to?(:reset)

        current.reset
      rescue StandardError
      end

      def cleanup_reporter
        reporter = ExisRay.reporter_class
        return unless reporter&.respond_to?(:reset)

        reporter.reset
      rescue StandardError
      end

      # Configura el Tracer con el ID recibido en el payload o genera uno nuevo si no existe.
      #
      # @param worker [Object] Instancia del worker.
      # @param job [Hash] Payload de Sidekiq.
      # @return [void]
      def hydrate_tracer(worker, job)
        ExisRay::Tracer.sidekiq_job = worker.class.name

        trace_header = job["exis_ray_trace"]
        if trace_header.present?
          ExisRay::Tracer.hydrate(trace_id: trace_header, source: "sidekiq")
        else
          ExisRay::Tracer.created_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          ExisRay::Tracer.source     = "sidekiq"
          ExisRay::Tracer.root_id    = ExisRay::Tracer.send(:generate_new_root)
        end

        ExisRay.sync_correlation_id
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

        return unless ctx["correlation_id"] && klass.respond_to?(:correlation_id=)

        klass.correlation_id = ctx["correlation_id"]
      end

      # Configura etiquetas y nombres de transacción en el Reporter (Sentry).
      #
      # @param worker [Object] Instancia del worker.
      # @return [void]
      def setup_reporter(worker)
        klass = ExisRay.reporter_class
        return unless klass

        klass.transaction_name = "Sidekiq/#{worker.class.name}" if klass.respond_to?(:transaction_name=)

        return unless klass.respond_to?(:add_tags)

        sidekiq_opts = worker.class.get_sidekiq_options
        sidekiq_queue = sidekiq_opts&.[]("queue")
        retry_count = if worker.respond_to?(:retry_count)
                        worker.retry_count
                      else
                        0
                      end

        tags = { retry_count: retry_count }
        tags[:sidekiq_queue] = sidekiq_queue if sidekiq_queue

        klass.add_tags(tags)
      end
    end
  end
end
