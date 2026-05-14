# frozen_string_literal: true

require "active_support/current_attributes"

module ExisRay
  # Clase base para la gestión del contexto de negocio (User, ISP, Correlation).
  # Debe ser heredada por la aplicación host (ej: class Current < ExisRay::Current).
  class Current < ActiveSupport::CurrentAttributes
    attribute :user_id, :isp_id, :correlation_id

    # Hook overridable por la subclass de la app host. Retorna un Hash de campos
    # extra a inyectar en cada log line, junto a `user_id`/`isp_id`/`correlation_id`.
    #
    # Pensado para cubrir tanto constantes de proceso (declaradas como `freeze`-d
    # constants en la subclass) como valores dinámicos per-request (leídos de
    # atributos de Current). El JsonFormatter invoca este método en cada log y
    # mergea el resultado al payload — luego de los campos canónicos pero antes
    # de las keys del propio mensaje del developer (que ganan por override).
    #
    # @example Constantes de proceso + valores per-request combinados
    #   class Current < ExisRay::Current
    #     TENANT_ID = ENV.fetch("TENANT_ID").freeze
    #     attribute :region
    #
    #     def self.log_fields
    #       { tenant_id: TENANT_ID, region: region }.compact
    #     end
    #   end
    #
    # @return [Hash] Pares clave/valor a inyectar. Default `{}`.
    def self.log_fields
      {}
    end

    # Callback nativo de Rails: Se ejecuta automáticamente al llamar a Current.reset
    resets do
      @user_object = nil
      @isp_object = nil

      if defined?(PaperTrail)
        PaperTrail.request.whodunnit = nil
        PaperTrail.request.controller_info = {}
      end

      if defined?(ActiveResource::Base)
        ActiveResource::Base.headers.delete("UserId")
        ActiveResource::Base.headers.delete("IspId")
        ActiveResource::Base.headers.delete("CorrelationId")
      end
    end

    # --- Setters con Hooks ---

    def user_id=(id)
      @user_object = nil
      super
      ActiveResource::Base.headers["UserId"] = sanitize_header_value(id) if defined?(ActiveResource::Base)
      return unless defined?(PaperTrail)

      PaperTrail.request.whodunnit = id
    end

    def isp_id=(id)
      @isp_object = nil
      super
      return unless defined?(ActiveResource::Base)

      ActiveResource::Base.headers["IspId"] = sanitize_header_value(id)
    end

    def correlation_id=(id)
      super
      assign_session_request_id(id)
      ActiveResource::Base.headers["CorrelationId"] = sanitize_header_value(id) if defined?(ActiveResource::Base)
      PaperTrail.request.controller_info = { correlation_id: id } if defined?(PaperTrail)
      sync_reporter_correlation_id(id)
    end

    # --- Helpers de Objetos (Lazy Loading con cache por request) ---
    # Estos métodos asumen que la app host tiene modelos ::User e ::Isp.
    # Memoizan el objeto en @user_object/@isp_object, que se limpian en el bloque
    # resets al final de cada request/job, y al asignar un nuevo user_id/isp_id.

    def user=(object)
      self.user_id = object&.id
    end

    def user
      return nil if user_id.nil?
      return nil unless defined?(::User) && ::User.respond_to?(:find_by)

      @user_object ||= ::User.find_by(id: user_id) # rubocop:disable Naming/MemoizedInstanceVariableName
    end

    def isp=(object)
      self.isp_id = object&.id
    end

    def isp
      return nil if isp_id.nil?
      return nil unless defined?(::Isp) && ::Isp.respond_to?(:find_by)

      @isp_object ||= ::Isp.find_by(id: isp_id) # rubocop:disable Naming/MemoizedInstanceVariableName
    end

    def user?
      !user_id.nil?
    end

    def isp?
      !isp_id.nil?
    end

    # Usa present? intencionalmente: un string vacío no es un correlation_id válido,
    # a diferencia de user_id/isp_id donde 0 es un valor legítimo.
    def correlation_id?
      correlation_id.present?
    end

    private

    def assign_session_request_id(id)
      return unless defined?(::Session)

      ::Session.request_id = id
    rescue StandardError
    end

    def sync_reporter_correlation_id(id)
      reporter = ExisRay.reporter_class
      return unless reporter.respond_to?(:add_tags)

      reporter.add_tags(correlation_id: id)
    rescue StandardError
    end

    def sanitize_header_value(value)
      value.to_s.gsub(/[\r\n]/, "")
    end
  end
end
