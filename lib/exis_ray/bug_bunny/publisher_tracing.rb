# frozen_string_literal: true

module ExisRay
  module BugBunny
    # Middleware de publicación para BugBunny::Client.
    #
    # Inyecta el header de trazabilidad de ExisRay en cada mensaje publicado,
    # permitiendo la propagación del trace context a los servicios consumidores.
    # Esto hace posible correlacionar un request HTTP original con todos los mensajes
    # y logs que genera en el ecosistema de microservicios.
    #
    # @example Configuración en el cliente
    #   client = BugBunny::Client.new(pool: pool) do |stack|
    #     stack.use ExisRay::BugBunny::PublisherTracing
    #   end
    #
    # @example Configuración en un BugBunny::Resource
    #   class UserResource < BugBunny::Resource
    #     middleware do |stack|
    #       stack.use ExisRay::BugBunny::PublisherTracing
    #     end
    #   end
    class PublisherTracing < ::BugBunny::Middleware::Base
      # Header AMQP personalizado para propagar el trace context entre servicios.
      TRACE_HEADER = 'x-trace-id'

      # Inyecta el header de traza antes de publicar el mensaje.
      # Solo actúa si hay un trace context activo (root_id presente).
      #
      # @param env [BugBunny::Request] El objeto request del mensaje saliente.
      # @return [void]
      def on_request(env)
        return unless ExisRay::Tracer.root_id.present?

        env.headers[TRACE_HEADER] = ExisRay::Tracer.generate_trace_header
      rescue StandardError
        # La propagación de tracing nunca debe interrumpir la publicación de mensajes.
      end
    end
  end
end
