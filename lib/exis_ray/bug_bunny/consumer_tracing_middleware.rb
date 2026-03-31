# frozen_string_literal: true

module ExisRay
  module BugBunny
    # Consumer middleware para BugBunny que establece el trace context de ExisRay
    # antes de que la gema empiece a procesar el mensaje.
    #
    # Al correr en el consumer middleware stack (antes de `consumer.message_received`),
    # garantiza que **todos** los logs internos de BugBunny y del controller action
    # incluyan `root_id`, `trace_id` y `source`.
    #
    # Se registra automáticamente al cargar ExisRay con BugBunny presente.
    # El usuario final no necesita configuración adicional.
    #
    # @example Registro automático (ocurre en Railtie#after_initialize)
    #   BugBunny.consumer_middlewares.use ExisRay::BugBunny::ConsumerTracingMiddleware
    class ConsumerTracingMiddleware < ::BugBunny::ConsumerMiddleware::Base
      # Inyecta el trace context antes de delegar al siguiente middleware.
      # Limpia el contexto en `ensure` para no contaminar el próximo mensaje.
      #
      # @param delivery_info [Bunny::DeliveryInfo]
      # @param properties    [Bunny::MessageProperties]
      # @param body          [String]
      def call(delivery_info, properties, body)
        setup_trace_context(properties)
        @app.call(delivery_info, properties, body)
      ensure
        ExisRay::Tracer.reset rescue nil
      end

      private

      # Hidrata el Tracer con el header de traza del mensaje entrante.
      # Si no hay header (mensaje publicado sin trace context), genera un root_id nuevo
      # para que los logs siempre tengan contexto de trazabilidad.
      #
      # @param properties [Bunny::MessageProperties]
      # @return [void]
      def setup_trace_context(properties)
        trace_header = properties.headers&.[](ExisRay.configuration.propagation_trace_header)

        if trace_header.present?
          ExisRay::Tracer.hydrate(trace_id: trace_header, source: 'system')
        else
          ExisRay::Tracer.created_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          ExisRay::Tracer.source     = 'system'
          ExisRay::Tracer.root_id    = ExisRay::Tracer.send(:generate_new_root)
        end

        ExisRay.sync_correlation_id
      rescue StandardError
        # El tracing nunca debe interrumpir el procesamiento del mensaje.
      end
    end
  end
end
