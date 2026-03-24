# frozen_string_literal: true

require "active_support/log_subscriber"

module ExisRay
  # Reemplaza Lograge para el logging estructurado de requests HTTP en Rails 6, 7 y 8.
  #
  # Se suscribe a `process_action.action_controller` y emite un Hash al logger,
  # que JsonFormatter convierte a JSON. Suprime los log subscribers por defecto
  # de Rails (ActionController, ActionView, Rails::Rack::Logger) para evitar
  # líneas de log duplicadas o en formato texto.
  #
  # Para inyectar campos extra en cada log de request, heredá esta clase y
  # sobreescribí `extra_fields`:
  #
  #   class MyLogSubscriber < ExisRay::LogSubscriber
  #     def self.extra_fields(event)
  #       { user_agent: event.payload[:headers]["HTTP_USER_AGENT"] }
  #     end
  #   end
  #
  # Luego configurá la subclase:
  #
  #   ExisRay.configure do |config|
  #     config.log_subscriber_class = "MyLogSubscriber"
  #   end
  #
  class LogSubscriber < ActiveSupport::LogSubscriber
    # Procesa el evento de finalización de un request HTTP y lo emite como Hash estructurado.
    #
    # @param event [ActiveSupport::Notifications::Event]
    # @return [void]
    def process_action(event)
      payload = build_payload(event)
      # Usamos el nivel ERROR si el status es 5xx, cumpliendo el estándar de Gabriel.
      if payload[:status] && payload[:status] >= 500
        logger.error(payload)
      else
        logger.info(payload)
      end
    rescue StandardError
      # El logger nunca debe interrumpir el flujo del request.
    end

    # Hook para que las subclases inyecten campos extra en cada log de request.
    # Por defecto retorna un Hash vacío.
    #
    # @param event [ActiveSupport::Notifications::Event]
    # @return [Hash]
    def self.extra_fields(_event)
      {}
    end

    # --- Instalación y supresión de subscribers ---

    # Activa el subscriber correcto (subclase configurada o ExisRay::LogSubscriber por defecto)
    # y suprime los log subscribers por defecto de Rails.
    #
    # @return [void]
    def self.install!
      suppress_default_log_subscribers!
      suppress_rack_logger!
      subscriber_class.attach_to(:action_controller)
    end

    private

    def build_payload(event)
      payload = event.payload
      status  = payload[:status] || exception_status(payload[:exception])

      # Convertimos milisegundos (Rails default) a segundos (Estandar Wispro)
      duration_s = (event.duration / 1000.0).round(4)
      view_s     = payload[:view_runtime] ? (payload[:view_runtime] / 1000.0).round(4) : nil
      db_s       = payload[:db_runtime] ? (payload[:db_runtime] / 1000.0).round(4) : nil

      data = {
        component:      "exis_ray",
        event:          "http_request",
        method:         payload[:method],
        path:           payload[:path],
        format:         payload[:format],
        controller:     payload[:controller],
        action:         payload[:action],
        status:         status,
        duration_s:     duration_s,
        duration_human: ExisRay::Tracer.format_duration(duration_s),
        view_runtime_s: view_s,
        db_runtime_s:   db_s
      }

      data.merge!(self.class.extra_fields(event))
      data.compact
    end

    # Infiere el status HTTP desde el nombre de la excepción cuando el request
    # terminó con una excepción no rescatada (payload[:status] es nil).
    #
    # @param exception_info [Array(String, String), nil] [nombre_clase, mensaje]
    # @return [Integer]
    def exception_status(exception_info)
      return 500 unless exception_info

      exception_class_name = exception_info.first
      # ActionDispatch::ExceptionWrapper disponible desde Rails 3.2+
      ActionDispatch::ExceptionWrapper.status_code_for_exception(exception_class_name)
    rescue StandardError
      500
    end

    # Resuelve la clase a attachar: subclase configurada o ExisRay::LogSubscriber.
    #
    # @return [Class]
    def self.subscriber_class
      klass_name = ExisRay.configuration.log_subscriber_class
      return self unless klass_name.present?

      klass_name.safe_constantize || self
    end

    # Suprime ActionController::LogSubscriber y ActionView::LogSubscriber
    # para evitar los logs multi-línea por defecto de Rails.
    #
    # Introducido en Rails 3.0. Presente sin cambios en Rails 6, 7 y 8.
    #
    # @return [void]
    def self.suppress_default_log_subscribers!
      require "action_controller/log_subscriber"
      require "action_view/log_subscriber"

      ActiveSupport::LogSubscriber.log_subscribers.each do |subscriber|
        case subscriber
        when ActionController::LogSubscriber
          unsubscribe_subscriber(:action_controller, subscriber)
        when ActionView::LogSubscriber
          unsubscribe_subscriber(:action_view, subscriber)
        end
      end
    end

    # Suprime las líneas "Started GET /..." emitidas por Rails::Rack::Logger.
    #
    # Rails::Rack::Logger introducido en Rails 3.2. La firma de `call_app` recibe
    # (request, env) desde Rails 5.0+. Compatible con Rails 6, 7 y 8.
    #
    # @return [void]
    def self.suppress_rack_logger!
      require "rails/rack/logger"

      ::Rails::Rack::Logger.class_eval do
        def call_app(request, env) # rubocop:disable Lint/UnusedMethodArgument
          status, headers, body = @app.call(env)
          [status, headers, ::Rack::BodyProxy.new(body) {}]
        ensure
          ActiveSupport::LogSubscriber.flush_all!
        end
      end
    end

    # Desuscribe un subscriber de todas las notificaciones de un namespace.
    #
    # API de notificaciones:
    # - Rails 6 / 7.0: `notifier.listeners_for(event_name)`
    # - Rails 7.1+:    `notifier.all_listeners_for(event_name)` (listeners_for fue deprecado)
    # - Rails 8:       solo `all_listeners_for`
    #
    # Si `all_listeners_for` desaparece en futuras versiones, revisar
    # ActiveSupport::Notifications::Fanout para el API vigente.
    #
    # @param namespace [Symbol]
    # @param subscriber [ActiveSupport::LogSubscriber]
    # @return [void]
    def self.unsubscribe_subscriber(namespace, subscriber)
      events   = subscriber.public_methods(false).reject { |m| m.to_s == "call" }
      notifier = ActiveSupport::Notifications.notifier

      events.each do |event|
        event_name = "#{event}.#{namespace}"
        listeners  = if notifier.respond_to?(:all_listeners_for)
                       # Rails 7.1+ (introducido en 7.1.0)
                       notifier.all_listeners_for(event_name)
                     else
                       # Rails 6 / 7.0
                       notifier.listeners_for(event_name)
                     end

        listeners.each do |listener|
          delegate = listener.instance_variable_get(:@delegate)
          ActiveSupport::Notifications.unsubscribe(listener) if delegate == subscriber
        end
      end
    end

    private_class_method :suppress_default_log_subscribers!,
                         :suppress_rack_logger!,
                         :unsubscribe_subscriber,
                         :subscriber_class
  end
end
