require "exis_ray/version"

# Dependencias externas
# Necesario para 'safe_constantize', 'present?', 'CurrentAttributes' y 'Duration'
require "active_support"
require "active_support/core_ext/string/inflections" # Para safe_constantize
require "active_support/current_attributes"
require "active_support/duration"
require "active_support/core_ext/numeric/time" # Para .seconds, .minutes, etc.

# Componentes internos del Core
require "exis_ray/configuration"
require "exis_ray/tracer"
require "exis_ray/task_monitor"
require "exis_ray/http_middleware"
require "exis_ray/current"
require "exis_ray/reporter"
require "exis_ray/json_formatter"

# Integraciones Opcionales
# Solo cargamos el middleware de Faraday si la gema está presente en el sistema.
require "exis_ray/faraday_middleware" if defined?(Faraday)

# Solo cargamos la instrumentación si ActiveResource está presente.
require "exis_ray/active_resource_instrumentation" if defined?(ActiveResource::Base)

# Integración automática con Rails
# Solo cargamos el Railtie si la constante Rails está definida.
require "exis_ray/railtie" if defined?(Rails)

# Namespace principal de la gema ExisRay.
# Contiene la configuración global y los helpers de resolución de clases dinámicas.
module ExisRay
  class Error < StandardError; end

  class << self
    # @!attribute [w] configuration
    attr_writer :configuration

    # Accesor para la configuración global de la gema.
    # Inicializa una nueva instancia de {Configuration} si no existe.
    #
    # @return [ExisRay::Configuration] La instancia de configuración actual.
    def configuration
      @configuration ||= Configuration.new
    end

    # Bloque de configuración para inicializar la gema.
    #
    # @example Configurar en un initializer de Rails
    #   ExisRay.configure do |config|
    #     config.trace_header = 'HTTP_X_WP_TRACE_ID'
    #     config.current_class = 'Current'
    #     config.reporter_class = 'Choto'
    #   end
    #
    # @yieldparam config [ExisRay::Configuration] El objeto de configuración.
    def configure
      yield(configuration)
    end

    # --- Helpers Centralizados de Resolución de Clases ---

    # Resuelve y retorna la clase configurada para manejar el contexto de negocio (Current).
    # En producción (cache_classes=true) memoiza el resultado para evitar safe_constantize
    # en cada request. En desarrollo siempre resuelve para soportar el reloading de Zeitwerk.
    #
    # @return [Class, nil] La clase constante (ej: Current) o nil si no se encuentra/configura.
    def current_class
      return nil unless configuration

      klass_name = configuration.current_class
      return nil unless klass_name.present?

      if cache_classes?
        @current_class_cache ||= resolve_class(klass_name)
      else
        resolve_class(klass_name)
      end
    end

    # Resuelve y retorna la clase configurada para el reporte de errores (Reporter).
    # En producción memoiza el resultado. En desarrollo siempre resuelve.
    #
    # @return [Class, nil] La clase constante (ej: Choto) o nil si no se encuentra/configura.
    def reporter_class
      return nil unless configuration

      klass_name = configuration.reporter_class
      return nil unless klass_name.present?

      if cache_classes?
        @reporter_class_cache ||= resolve_class(klass_name)
      else
        resolve_class(klass_name)
      end
    end

    # Sincroniza el correlation_id del Tracer en la clase Current configurada.
    # Debe llamarse después de hidratar el Tracer (post `hydrate` o `parse_trace_id`).
    #
    # @return [void]
    def sync_correlation_id
      curr = current_class
      return unless curr&.respond_to?(:correlation_id=) && Tracer.root_id.present?

      curr.correlation_id = Tracer.correlation_id
    end

    private

    def resolve_class(klass_name)
      klass_name.is_a?(String) ? klass_name.safe_constantize : klass_name
    end

    def cache_classes?
      return false unless defined?(Rails)

      config = Rails.application.config
      # Rails 7.1+ reemplazó cache_classes por enable_reloading (semántica inversa).
      # Soportamos ambas APIs para mantener compatibilidad con Rails 6, 7 y 8.
      if config.respond_to?(:enable_reloading)
        !config.enable_reloading
      else
        config.cache_classes
      end
    end
  end
end
