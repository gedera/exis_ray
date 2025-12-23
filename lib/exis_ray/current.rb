require 'active_support/current_attributes'

module ExisRay
  # Clase base para la gestión del contexto de negocio (User, ISP, Correlation).
  #
  # @example Uso en la aplicación host:
  #   # app/models/current.rb
  #   class Current < ExisRay::Current
  #     attribute :custom_field
  #   end
  class Current < ActiveSupport::CurrentAttributes
    attribute :user_id, :isp_id, :correlation_id

    # Callback nativo de Rails: Se ejecuta automáticamente al llamar a Current.reset
    # (Rails lo hace al final de cada request o job).
    resets do
      # Limpiamos variables memoizadas
      @user = nil
      @isp  = nil

      # Limpiamos contextos externos
      if defined?(PaperTrail)
        PaperTrail.request.whodunnit = nil
        PaperTrail.request.controller_info = {}
      end

      if defined?(ActiveResource::Base)
        ActiveResource::Base.headers.delete('UserId')
        ActiveResource::Base.headers.delete('IspId')
        ActiveResource::Base.headers.delete('CorrelationId')
      end
    end

    # --- Setters con Efectos Secundarios (Hooks) ---

    def user_id=(id)
      super
      if defined?(ActiveResource::Base)
        ActiveResource::Base.headers['UserId'] = id.to_s
      end
      if defined?(PaperTrail)
        PaperTrail.request.whodunnit = id
      end
    end

    def isp_id=(id)
      super
      @isp = nil # Invalida cache

      if defined?(ActiveResource::Base)
        ActiveResource::Base.headers['IspId'] = id.to_s
      end
    end

    def correlation_id=(id)
      super

      if defined?(::Session)
        ::Session.request_id = id # DEPRECATED
      end

      if defined?(ActiveResource::Base)
        ActiveResource::Base.headers['CorrelationId'] = id.to_s
      end

      if defined?(PaperTrail)
        PaperTrail.request.controller_info = { correlation_id: id }
      end

      # Integración con Choto (si existe)
      if defined?(ExisRay.configuration.reporter_class) && ExisRay.configuration.reporter_class.respond_to?(:add_tags)
        ExisRay.configuration.reporter_class.add_tags(correlation_id: id)
      end
    end

    # --- Helpers de Objetos (Lazy Loading Defensivo) ---

    def user=(object)
      @user = object
      self.user_id = object&.id
    end

    def user
      return @user if defined?(@user) && @user

      # Buscamos solo si hay ID y la clase User existe en la app
      if user_id && defined?(::User) && ::User.respond_to?(:find_by)
        @user = ::User.find_by(id: user_id)
      else
        nil
      end
    end

    def isp=(object)
      @isp = object
      self.isp_id = object&.id
    end

    def isp
      return @isp if defined?(@isp) && @isp

      if isp_id && defined?(::Isp) && ::Isp.respond_to?(:find_by)
        @isp = ::Isp.find_by(id: isp_id)
      else
        nil
      end
    end

    def user?
      user_id.present?
    end

    def isp?
      isp_id.present?
    end

    def correlation_id?
      correlation_id.present?
    end
  end
end
