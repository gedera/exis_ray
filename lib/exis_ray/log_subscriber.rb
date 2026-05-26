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
      if payload[:http_status] && payload[:http_status] >= 500
        logger.error(payload)
      else
        logger.info(payload)
      end
    rescue StandardError => e
      begin
        logger.error({
                       component: "exis_ray",
                       event: "log_subscriber_fallback",
                       error: e.message,
                       payload_summary: event.payload.slice(:controller, :action, :method, :path)
                     })
      rescue StandardError
        nil
      end
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
      return if attached?

      suppress_default_log_subscribers!
      suppress_rack_logger!
      subscriber_class.attach_to(:action_controller)
    end

    def self.attached?
      ActiveSupport::LogSubscriber.log_subscribers.any? { |s| s.is_a?(subscriber_class) }
    rescue StandardError
      false
    end

    private

    def build_payload(event)
      payload = event.payload
      status  = payload[:status] || exception_status(payload[:exception])

      # Convertimos milisegundos (Rails default) a segundos (Estandar Wispro)
      duration_s = (event.duration / 1000.0).round(4)
      view_s     = payload[:view_runtime] ? (payload[:view_runtime] / 1000.0).round(4) : nil
      db_s       = payload[:db_runtime] ? (payload[:db_runtime] / 1000.0).round(4) : nil

      headers = payload[:headers] || {}

      exception_data = extract_exception_data(payload)

      data = {
        component: "exis_ray",
        event: "http_request",
        method: payload[:method],
        path: payload[:path],
        http_route: extract_http_route(payload),
        format: payload[:format],
        controller: payload[:controller],
        action: payload[:action],
        http_status: status,
        duration_s: duration_s,
        duration_human: ExisRay::Tracer.format_duration(duration_s),
        view_runtime_s: view_s,
        db_runtime_s: db_s,
        user_agent_original: headers["HTTP_USER_AGENT"],
        server_address: extract_server_address(headers["HTTP_HOST"])
      }

      data.merge!(exception_data)
      data.merge!(self.class.extra_fields(event))
      data.compact
    end

    # Extrae el hostname del valor de HTTP_HOST, descartando el puerto si está presente.
    # OTel `server.address` espera solo hostname; el puerto va en `server.port` por separado.
    #
    # @param http_host [String, nil] Valor del header HTTP_HOST (ej: "api.example.com:3000").
    # @return [String, nil] Hostname sin puerto, o nil si http_host es nil.
    def extract_server_address(http_host)
      return nil unless http_host

      http_host.split(":").first
    end

    # Extrae los datos de excepción para logs OTel.
    # Siempre emite `exception.type`/`exception.message`/`exception.stacktrace` (OTel v1.0).
    # Emite además los campos legacy (`error_class`/`error_message`) cuando
    # `ExisRay.configuration.emit_legacy_exception_keys` es `true` (default durante la
    # ventana de transición). Setear a `false` cuando los consumers hayan migrado.
    #
    # El stacktrace se toma de `payload[:exception_object]` (expuesto por Rails), no
    # de `payload[:exception]` que es solo `[class_name, message]`.
    #
    # @param payload [Hash] Payload completo del notification de Rails.
    # @return [Hash] Campos exception.* (y error_class/error_message si el flag está activo).
    def extract_exception_data(payload)
      exception_info = payload[:exception]
      return {} unless exception_info

      exception_class = exception_info.first
      exception_message = exception_info.last

      data = {
        "exception.type": exception_class,
        "exception.message": exception_message
      }

      if ExisRay.configuration.emit_legacy_exception_keys
        data[:error_class] = exception_class
        data[:error_message] = exception_message
      end

      exception_object = payload[:exception_object]
      if exception_object.respond_to?(:backtrace) && exception_object.backtrace
        data[:"exception.stacktrace"] = exception_object.backtrace.take(20).join("\n")
      end

      data
    rescue StandardError
      {}
    end

    # Extrae la plantilla de ruta (http.route) de una URL concreta.
    # OTel espera la ruta templated (ej: `/users/:id`) en lugar de la URL concreta
    # (ej: `/users/42`), para bajar cardinalidad en dashboards.
    #
    # Estrategia en capas:
    # 1. Rails 7.1+: `payload[:request].route_uri_pattern` si está presente.
    # 2. Fallback: iterar `Rails.application.routes.routes` buscando el match por
    #    `defaults[:controller]` + `defaults[:action]` + verb HTTP, y devolver el
    #    pattern limpio de la primera ruta que matchee.
    #
    # @param payload [Hash] Payload del evento de Rails.
    # @return [String, nil] Ruta plantilla o nil si no se puede resolver.
    def extract_http_route(payload)
      return nil unless defined?(Rails) && Rails.application&.routes

      from_request = extract_from_route_uri_pattern(payload)
      return from_request if from_request

      controller = payload[:controller]
      action = payload[:action]
      method = payload[:method]
      return nil unless controller && action && method

      find_route_template(controller, action, method)
    rescue StandardError
      nil
    end

    # Rails 7.1+ expone `route_uri_pattern` en el request. Algunas versiones de
    # `ActionController::Instrumentation` incluyen el request en el payload; si no,
    # esta rama simplemente retorna nil y el caller cae al fallback.
    #
    # @param payload [Hash]
    # @return [String, nil]
    def extract_from_route_uri_pattern(payload)
      request = payload[:request]
      return nil unless request.respond_to?(:route_uri_pattern)

      pattern = request.route_uri_pattern
      clean_route_pattern(pattern.to_s) if pattern
    rescue StandardError
      nil
    end

    # Busca en la RouteSet de Rails la ruta que matchea controller + action + verb
    # y devuelve su pattern template (ej: `/users/:id`).
    #
    # Rails guarda controller/action en `route.defaults`, no en `route.requirements`.
    # El formato típico es `defaults[:controller] == "users"` (snake_case sin el sufijo
    # `Controller`), mientras que `payload[:controller]` viene como `"UsersController"`.
    #
    # @param controller [String] Class name del controller (ej: "UsersController").
    # @param action [String] Nombre del action (ej: "show").
    # @param method [String] Método HTTP (ej: "GET").
    # @return [String, nil] Pattern template o nil.
    def find_route_template(controller, action, method)
      normalized = controller.to_s.sub(/Controller$/, "").gsub("::", "/")
      normalized = normalized.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
                             .gsub(/([a-z\d])([A-Z])/, '\1_\2')
                             .downcase
      action_s = action.to_s
      method_s = method.to_s.upcase

      Rails.application.routes.routes.each do |route|
        defaults = route.defaults
        next unless defaults[:controller] == normalized
        next unless defaults[:action].to_s == action_s
        next unless route_matches_verb?(route, method_s)

        return clean_route_pattern(route.path.spec.to_s)
      end
      nil
    rescue StandardError
      nil
    end

    # Verifica que el verb HTTP de la ruta matchee con el método del request.
    # `route.verb` en Rails 5+ es un String (ej: "GET"); en versiones antes era un
    # Regexp. Manejamos ambos y además el caso de rutas multi-verb (empty verb).
    #
    # @param route [ActionDispatch::Journey::Route]
    # @param method [String] Método HTTP en mayúsculas.
    # @return [Boolean]
    def route_matches_verb?(route, method)
      verb = route.verb
      return true if verb.nil? || verb.to_s.empty?

      if verb.is_a?(Regexp)
        verb.match?(method)
      else
        verb.to_s.upcase == method
      end
    rescue StandardError
      true
    end

    # Limpia el sufijo `(.:format)` típico de las rutas de Rails, que no es parte
    # del template semántico que queremos emitir en el log.
    #
    # @param pattern [String] Pattern crudo de `route.path.spec.to_s`.
    # @return [String]
    def clean_route_pattern(pattern)
      pattern.to_s.sub(/\(\.:format\)\z/, "")
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
