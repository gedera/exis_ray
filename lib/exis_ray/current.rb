require 'active_support/current_attributes'

module ExisRay
  # Clase base para la gestión del contexto de negocio (User, ISP, Correlation).
  # Debe ser heredada por la aplicación host (ej: class Current < ExisRay::Current).
  class Current < ActiveSupport::CurrentAttributes
    attribute :user_id, :isp_id, :correlation_id

    # Sentinel para distinguir "no consultado" de "consultado y no encontrado".
    # Evita re-queries a la DB cuando el objeto no existe.
    NOT_FOUND = Object.new.freeze

    # Callback nativo de Rails: Se ejecuta automáticamente al llamar a Current.reset
    resets do
      @user = NOT_FOUND
      @isp  = NOT_FOUND

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

    # --- Setters con Hooks ---

    def user_id=(id)
      super
      if defined?(ActiveResource::Base)
        ActiveResource::Base.headers['UserId'] = sanitize_header_value(id)
      end
      if defined?(PaperTrail)
        PaperTrail.request.whodunnit = id
      end
    end

    def isp_id=(id)
      super
      @isp = NOT_FOUND # Invalida cache
      if defined?(ActiveResource::Base)
        ActiveResource::Base.headers['IspId'] = sanitize_header_value(id)
      end
    end

    def correlation_id=(id)
      super

      if defined?(::Session)
        ::Session.request_id = id # Deprecated legacy support
      end

      if defined?(ActiveResource::Base)
        ActiveResource::Base.headers['CorrelationId'] = sanitize_header_value(id)
      end

      if defined?(PaperTrail)
        PaperTrail.request.controller_info = { correlation_id: id }
      end

      # Integración con el Reporter configurado
      if (reporter = ExisRay.reporter_class) && reporter.respond_to?(:add_tags)
        reporter.add_tags(correlation_id: id)
      end
    end

    # --- Helpers de Objetos (Lazy Loading) ---
    # Estos métodos asumen que la app host tiene modelos ::User e ::Isp

    def user=(object)
      @user = object || NOT_FOUND
      self.user_id = object&.id
    end

    def user
      @user = NOT_FOUND unless defined?(@user)
      return nil if @user.equal?(NOT_FOUND) && !user_id

      if @user.equal?(NOT_FOUND)
        @user = (defined?(::User) && ::User.respond_to?(:find_by) ? ::User.find_by(id: user_id) : nil) || NOT_FOUND
      end

      @user.equal?(NOT_FOUND) ? nil : @user
    end

    def isp=(object)
      @isp = object || NOT_FOUND
      self.isp_id = object&.id
    end

    def isp
      @isp = NOT_FOUND unless defined?(@isp)
      return nil if @isp.equal?(NOT_FOUND) && !isp_id

      if @isp.equal?(NOT_FOUND)
        @isp = (defined?(::Isp) && ::Isp.respond_to?(:find_by) ? ::Isp.find_by(id: isp_id) : nil) || NOT_FOUND
      end

      @isp.equal?(NOT_FOUND) ? nil : @isp
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

    private

    # Elimina caracteres CRLF para prevenir HTTP header injection.
    # Un valor con "\r\n" en un header de ActiveResource podría inyectar
    # headers arbitrarios en requests hacia otros microservicios.
    def sanitize_header_value(value)
      value.to_s.gsub(/[\r\n]/, '')
    end
  end
end
