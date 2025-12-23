require 'active_support/current_attributes'

module ExisRay
  # Clase base híbrida para reporte de errores y mensajes.
  # Soporta tanto la integración moderna (SDK unificado, ExisRay::Tracer)
  # como la integración legacy (Old Sentry, Session global).
  #
  # @example Uso
  #   class Choto < ExisRay::Report
  #     # custom logic...
  #   end
  class Reporter < ActiveSupport::CurrentAttributes
    attribute :contexts, :tags, :transaction_name, :fingerprint

    resets do
      self.contexts         = {}
      self.tags             = {}
      self.fingerprint      = []
      self.transaction_name = nil

      clean_legacy_session!
    end

    # --- Métodos Públicos ---

    def self.report(message, context: {}, tags: {}, fingerprint: [], transaction_name: nil)
      prepare_scope(context, tags, fingerprint, transaction_name)

      if report_to_new_sentry?
        report_to_new_sentry(message)
      else
        report_to_old_sentry(message)
      end
    end

    def self.exception(excep, context: {}, tags: {}, fingerprint: [], transaction_name: nil)
      prepare_scope(context, tags, fingerprint, transaction_name)
      add_tags(exception: excep.class.to_s)

      Rails.logger.error(excep) unless Rails.env.production?

      if report_to_new_sentry?
        exception_to_new_sentry(excep)
      else
        exception_to_old_sentry(excep)
      end
    end

    # --- Builders de Datos ---

    def self.add_fingerprint(value)
      current_values = fingerprint || []
      current_values << value
      self.fingerprint = current_values.flatten.compact.uniq
    end

    def self.add_context(attrs)
      return if attrs.blank?

      self.contexts = (contexts || {}).merge(attrs.as_json)
    end

    def self.add_tags(attrs)
      return if attrs.blank?

      self.tags = (tags || {}).merge(attrs.as_json)
    end

    # Hook para subclases
    def self.build_custom_context
      # No-op default
    end

    # --- Lógica Legacy (Session & Old Sentry) ---

    def self.clean_legacy_session!
      return unless defined?(::Session) && ::Session.respond_to?(:clean!)

      ::Session.clean!
    end

    def self.session_tag!
      return unless defined?(::Session)

      ::Session.tags_context ||= {}

      if fingerprint.present?
        str_fingerprint = fingerprint.flatten.join(',')
        ::Session.tags_context.merge!(fingerprint: str_fingerprint)
      end

      if transaction_name.present?
        ::Session.tags_context.merge!(transaction_name: transaction_name)
      end

      ::Session.tags_context.merge!(tags) if tags.present?
    end

    def self.session_context!
      return unless contexts.present?
      return unless defined?(::Session)

      ::Session.extra_context ||= {}
      ::Session.extra_context.merge!(contexts)
    end

    def self.report_to_old_sentry(message)
      session_tag!
      session_context!

      Sentry.send_event(message) if defined?(Sentry)
    end

    def self.exception_to_old_sentry(exception)
      session_tag!
      session_context!

      if defined?(Sentry)
        Sentry.populate_context(contexts) if contexts.present?
        Sentry.notify(exception)
      end
    end

    # --- Lógica Moderna (New Sentry) ---

    def self.report_to_new_sentry?
      defined?(::NEW_SENTRY) && ::NEW_SENTRY
    end

    def self.report_to_new_sentry(message)
      send_to_new_sentry do
        Sentry.capture_message(message, fingerprint: fingerprint)
      end
    end

    def self.exception_to_new_sentry(exception)
      send_to_new_sentry do
        Sentry.capture_exception(exception, level: 'error', fingerprint: fingerprint)
      end
    end

    def self.send_to_new_sentry
      return unless defined?(Sentry)

      Sentry.with_scope do |scope|
        scope.set_transaction_name(transaction_name) if transaction_name.present?

        if contexts.present?
          contexts.each do |key, value|
            val = value.is_a?(Hash) ? value : { value: value }
            scope.set_context(key, val)
          end
        end

        scope.set_tags(tags) if tags.present?
        yield(scope)
      end
    end

    # --- Inicialización de Contexto ---

    private_class_method def self.prepare_scope(context, tags, fingerprint, transaction_name)
      add_context(context)
      add_tags(tags)
      add_fingerprint(fingerprint)
      self.transaction_name = transaction_name if transaction_name.present?

      build_from_tracer
      build_from_current
      build_custom_context
    end

    def self.build_from_tracer
      return unless defined?(ExisRay::Tracer)

      if ExisRay::Tracer.root_id.present?
        add_tags(correlation_id: ExisRay::Tracer.root_id)
        add_context(trace: {
          root_id: ExisRay::Tracer.root_id,
          request_id: ExisRay::Tracer.request_id
        })
      end
    end

    def self.build_from_current
      return unless defined?(::Current)

      add_tags(user_id: ::Current.user_id) if ::Current.respond_to?(:user_id?) && ::Current.user_id?
      add_tags(isp_id:  ::Current.isp_id)  if ::Current.respond_to?(:isp_id?)  && ::Current.isp_id?

      if ::Current.respond_to?(:user) && ::Current.user.present?
        user_json = ::Current.user.respond_to?(:as_json) ? ::Current.user.as_json : { id: ::Current.user_id }
        add_context(user: user_json)
      end

      if ::Current.respond_to?(:isp) && ::Current.isp.present?
        isp_json = ::Current.isp.respond_to?(:as_json) ? ::Current.isp.as_json : { id: ::Current.isp_id }
        add_context(isp: isp_json)
      end
    end

    private_class_method :build_from_current, :build_from_tracer
  end
end
