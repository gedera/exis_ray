require "exis_ray/version"

# Dependencias externas
# Necesario para 'safe_constantize', 'present?', y 'CurrentAttributes'
require "active_support"
require "active_support/core_ext/string/inflections" # Para safe_constantize
require "active_support/current_attributes"

# Componentes internos del Core
require "exis_ray/configuration"
require "exis_ray/tracer"
require "exis_ray/task_monitor"
require "exis_ray/http_middleware"
require "exis_ray/current"
require "exis_ray/reporter"

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
    # Convierte el String configurado (ej: 'Current') en la clase real constante.
    #
    # @return [Class, nil] La clase constante (ej: Current) o nil si no se encuentra/configura.
    def current_class
      return nil unless configuration

      klass_name = configuration.current_class
      return nil unless klass_name.present?

      # Si es String, lo convertimos a constante de forma segura.
      klass_name.is_a?(String) ? klass_name.safe_constantize : klass_name
    end

    # Resuelve y retorna la clase configurada para el reporte de errores (Reporter).
    # Convierte el String configurado (ej: 'Choto') en la clase real constante.
    #
    # @return [Class, nil] La clase constante (ej: Choto) o nil si no se encuentra/configura.
    def reporter_class
      return nil unless configuration

      klass_name = configuration.reporter_class
      return nil unless klass_name.present?

      klass_name.is_a?(String) ? klass_name.safe_constantize : klass_name
    end
  end
end
