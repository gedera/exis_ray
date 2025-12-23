# lib/exis_ray.rb
require "exis_ray/version"

# Dependencias externas
require "active_support"
require "active_support/current_attributes"

# Componentes internos del Core
require "exis_ray/configuration"
require "exis_ray/tracer"
require "exis_ray/task_monitor"
require "exis_ray/http_middleware"
require "exis_ray/current"
require "exis_ray/reporter"

# Solo si faraday está instalado (para no obligar a quien no lo usa)
require "exis_ray/faraday_middleware" if defined?(Faraday)
require "exis_ray/active_resource_instrumentation" if defined?(ActiveResource::Base)

# Integración automática con Rails
# Solo cargamos el Railtie si la constante Rails está definida.
# Esto permite usar la gema en scripts de Ruby puro o Sinatra sin que explote.
require "exis_ray/railtie" if defined?(Rails)

module ExisRay
  class Error < StandardError; end

  class << self
    # Acceso a la configuración global (Singleton)
    def configuration
      @configuration ||= Configuration.new
    end

    # Bloque de configuración
    def configure
      yield(configuration)
    end
  end
end
