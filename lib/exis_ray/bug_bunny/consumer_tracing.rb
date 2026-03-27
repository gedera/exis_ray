# frozen_string_literal: true

require 'active_support/concern'

module ExisRay
  module BugBunny
    # Concern para BugBunny::Controller que restaura el trace context de ExisRay
    # a partir del header configurado en `ExisRay.configuration.propagation_trace_header`
    # (por defecto `'X-Amzn-Trace-Id'`) inyectado por el publicador.
    #
    # Permite que todos los logs emitidos durante el procesamiento de un mensaje
    # incluyan el mismo root_id y correlation_id que el request HTTP original,
    # logrando trazabilidad distribuida de punta a punta.
    #
    # El contexto se limpia siempre en `ensure`, garantizando que un error en el
    # controller no contamine el procesamiento del siguiente mensaje.
    #
    # @example Incluir en el ApplicationController de BugBunny
    #   class ApplicationController < BugBunny::Controller
    #     include ExisRay::BugBunny::ConsumerTracing
    #   end
    module ConsumerTracing
      extend ActiveSupport::Concern

      # Header AMQP desde el cual se lee el trace context propagado.
      # Debe coincidir con `propagation_trace_header` usado por el publisher.
      def self.trace_header
        ExisRay.configuration.propagation_trace_header
      end

      included do
        around_action :exis_ray_trace_context
      end

      private

      # Restaura el contexto de trazabilidad y lo limpia al finalizar,
      # independientemente de si el controller levantó una excepción.
      #
      # @yieldreturn [void]
      def exis_ray_trace_context
        setup_exis_ray_context
        yield
      ensure
        ExisRay::Tracer.reset rescue nil
      end

      # Hidrata el Tracer con el header de traza recibido en el mensaje.
      # Si el header no está presente (mensaje sin trace context), no hace nada.
      #
      # @return [void]
      def setup_exis_ray_context
        trace_header = headers[self.class.trace_header]
        return unless trace_header.present?

        ExisRay::Tracer.hydrate(trace_id: trace_header, source: 'system')
        ExisRay.sync_correlation_id
      rescue StandardError
        # El tracing nunca debe interrumpir el procesamiento del mensaje.
      end
    end
  end
end
