# frozen_string_literal: true

module ExisRay
  module Sidekiq
    # Middleware de cliente que inyecta trace context y contexto de negocio en el payload del job.
    class ClientMiddleware
      # Intercepta el push del trabajo a Redis.
      #
      # @param _worker_class [String, Class] La clase del worker (no utilizado).
      # @param job [Hash] El payload del trabajo (aquí inyectamos datos).
      # @param _queue [String] Nombre de la cola (no utilizado).
      # @param _redis_pool [Object] Pool de conexión legacy Sidekiq v6 (no utilizado).
      def call(_worker_class, job, _queue, _redis_pool = nil)
        inject_trace_context(job)
        yield
      end

      private

      def inject_trace_context(job)
        return unless ExisRay::Tracer.root_id.present?

        job["exis_ray_trace"] = ExisRay::Tracer.generate_trace_header
        inject_business_context(job)
      rescue StandardError
      end

      def inject_business_context(job)
        return unless (curr = ExisRay.current_class).present?

        context = {}
        context[:user_id]        = curr.user_id        if curr.respond_to?(:user_id) && !curr.user_id.nil?
        context[:isp_id]         = curr.isp_id         if curr.respond_to?(:isp_id) && !curr.isp_id.nil?
        context[:correlation_id] = curr.correlation_id if curr.respond_to?(:correlation_id)

        job["exis_ray_context"] = context
      rescue StandardError
      end
    end
  end
end
