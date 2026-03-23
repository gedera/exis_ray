module ExisRay
  module Sidekiq
    class ClientMiddleware
      # Intercepta el push del trabajo a Redis.
      # @param worker_class [String, Class] La clase del worker.
      # @param job [Hash] El payload del trabajo (aquí inyectamos datos).
      # @param queue [String] Nombre de la cola.
      # @param redis_pool [Object] Pool de conexión (Legacy v6).
      def call(worker_class, job, queue, redis_pool = nil)
        # Solo inyectamos si hay una traza activa (viniendo de Web o Cron)
        if ExisRay::Tracer.root_id.present?
          # 1. Inyectamos la traza (usamos generate_trace_header para mantener la cadena)
          job['exis_ray_trace'] = ExisRay::Tracer.generate_trace_header

          # 2. Inyectamos el contexto de negocio (Current)
          # Esto permite saber qué Usuario o ISP disparó el job.
          if (curr = ExisRay.current_class).present?
            context = {}
            context[:user_id]        = curr.user_id        if curr.respond_to?(:user_id)
            context[:isp_id]         = curr.isp_id         if curr.respond_to?(:isp_id)
            context[:correlation_id] = curr.correlation_id if curr.respond_to?(:correlation_id)

            job['exis_ray_context'] = context
          end
        end

        yield
      end
    end
  end
end
