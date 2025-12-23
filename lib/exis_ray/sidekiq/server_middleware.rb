module ExisRay
  module Sidekiq
    # Middleware de Servidor para Sidekiq.
    # Se ejecuta alrededor de cada trabajo (job) procesado por un Worker.
    #
    # Su responsabilidad es:
    # 1. Recuperar el Trace ID y contexto (User, ISP) inyectados por el cliente.
    # 2. Configurar el entorno (Tracer, Current, Reporter).
    # 3. Limpiar todo al finalizar para no contaminar el thread (Thread Pooling).
    class ServerMiddleware
      # Intercepta la ejecución del job.
      #
      # @param worker [Object] La instancia del worker que procesará el job.
      # @param job [Hash] El payload del trabajo (contiene argumentos y metadatos).
      # @param queue [String] El nombre de la cola.
      def call(worker, job, queue)
        # 1. Hidratación de Infraestructura (Tracer)
        hydrate_tracer(worker, job)

        # 2. Hidratación de Negocio (Current Class configurada)
        hydrate_current(job)

        # 3. Configuración de Reporte (Sentry/Reporter Class configurada)
        setup_reporter(worker)

        # 4. Ejecución con Logs Taggeados
        # Inyectamos el Root ID en los logs de Rails para correlacionarlos con Sidekiq.
        tags = [ExisRay::Tracer.root_id]

        if Rails.logger.respond_to?(:tagged)
          Rails.logger.tagged(*tags) { yield }
        else
          yield
        end

      ensure
        # 5. Limpieza Total (Vital en Sidekiq)
        # Sidekiq reutiliza threads. Si no limpiamos, el contexto de un job
        # (ej: usuario actual) podría filtrarse al siguiente job.
        ExisRay::Tracer.reset

        # Limpieza usando los helpers centralizados (sin hardcodear Current)
        ExisRay.current_class&.reset  if ExisRay.current_class.respond_to?(:reset)
        ExisRay.reporter_class&.reset if ExisRay.reporter_class.respond_to?(:reset)
      end

      private

      # Configura el Tracer con el ID recibido o genera uno nuevo.
      def hydrate_tracer(worker, job)
        ExisRay::Tracer.created_at = Time.now.utc.to_f
        ExisRay::Tracer.service_name = "Sidekiq-#{worker.class.name}"

        if job['exis_ray_trace']
          # Continuidad: Usamos la traza que viene del cliente (Web/Cron)
          ExisRay::Tracer.trace_id = job['exis_ray_trace']
          ExisRay::Tracer.parse_trace_id
        else
          # Origen: El job nació aquí (ej: desde consola o trigger externo sin contexto)
          ExisRay::Tracer.root_id = ExisRay::Tracer.send(:generate_new_root)
        end
      end

      # Hidrata la clase Current configurada con los datos del payload.
      def hydrate_current(job)
        # Obtenemos la clase dinámica (ej: Current)
        klass = ExisRay.current_class

        # Salimos si no hay clase configurada o no hay contexto en el job
        return unless klass && job['exis_ray_context']

        ctx = job['exis_ray_context']

        # Asignación segura usando la clase dinámica
        klass.user_id = ctx['user_id'] if ctx['user_id'] && klass.respond_to?(:user_id=)
        klass.isp_id  = ctx['isp_id']  if ctx['isp_id']  && klass.respond_to?(:isp_id=)

        if ctx['correlation_id'] && klass.respond_to?(:correlation_id=)
          klass.correlation_id = ctx['correlation_id']
        end
      end

      # Configura tags y nombres de transacción en el Reporter.
      def setup_reporter(worker)
        klass = ExisRay.reporter_class
        return unless klass

        # Nombre de transacción para Sentry: "Sidekiq/HardWorker"
        if klass.respond_to?(:transaction_name=)
          klass.transaction_name = "Sidekiq/#{worker.class.name}"
        end

        # Tags adicionales de infraestructura Sidekiq
        if klass.respond_to?(:add_tags)
          klass.add_tags(
            sidekiq_queue: worker.class.get_sidekiq_options['queue'],
            retry_count: worker.respond_to?(:retry_count) ? worker.retry_count : 0
          )
        end
      end
    end
  end
end
