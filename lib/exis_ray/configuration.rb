# frozen_string_literal: true

module ExisRay
  # Clase de configuración global para la gema.
  # Permite personalizar los headers de trazabilidad y definir las clases de la aplicación host
  # que la gema utilizará para gestionar el contexto (Current) y el reporte de errores (Reporter).
  class Configuration
    # @!attribute [rw] trace_header
    #   @return [String] La key del header HTTP (formato Rack) donde se buscará el Trace ID entrante.
    #   Por defecto es 'HTTP_X_AMZN_TRACE_ID'.
    attr_accessor :trace_header

    # @!attribute [rw] propagation_trace_header
    #   @return [String] La key del header HTTP que se enviará a otros servicios (formato estándar).
    #   Por defecto es 'X-Amzn-Trace-Id'.
    attr_accessor :propagation_trace_header

    # @!attribute [rw] reporter_class
    #   @return [String, Class, nil] El nombre de la clase de la aplicación host que hereda de {ExisRay::Reporter}.
    #   Se recomienda usar un String para evitar problemas de carga (autoloading) durante la inicialización.
    #   @example 'Choto'
    attr_accessor :reporter_class

    # @!attribute [rw] current_class
    #   @return [String, Class, nil] El nombre de la clase de la aplicación host que hereda de {ExisRay::Current}.
    #   Se utiliza para inyectar/leer user_id, isp_id y correlation_id.
    #   @example 'Current'
    attr_accessor :current_class

    # @!attribute [rw] log_format
    #   @return [Symbol] El formato en el que se emitirán los logs de la aplicación.
    #   Puede ser `:text` (comportamiento por defecto de Rails) o `:json` (formato estructurado).
    #   @example :json
    attr_accessor :log_format

    # @!attribute [rw] log_subscriber_class
    #   @return [String, nil] Nombre de la subclase de ExisRay::LogSubscriber de la app host.
    #   Usada para inyectar campos extra en cada log de request HTTP via `extra_fields`.
    #   Si es nil, se usa ExisRay::LogSubscriber directamente (sin campos extra).
    #   @example 'MyLogSubscriber'
    attr_accessor :log_subscriber_class

    # @!attribute [rw] service_version
    #   @return [String, nil] Versión del servicio. Equivale a `service.version` de OTel.
    #   Por defecto intenta leer `Rails.application.config.x.version` si Rails está disponible.
    #   @example '1.2.3'
    attr_accessor :service_version

    # @!attribute [rw] deployment_environment
    #   @return [String, nil] Entorno de despliegue. Equivale a `deployment.environment` de OTel.
    #   Por defecto lee `Rails.env` si Rails está disponible.
    #   @example 'production'
    attr_accessor :deployment_environment

    # @!attribute [r] global_fields
    #   @return [Hash] Campos fijos por proceso que se inyectan en cada línea de log.
    #   Útil para constantes de proceso (TENANT_ID, SERVICE_ID, STACK_ID) en servicios multi-tenant.
    #   El hash se filtra (claves sensibles → [FILTERED]) y se congela al setear, por lo que los
    #   valores son inmutables durante la vida del proceso y el cost por log line es despreciable.
    #   Precedencia: los campos canónicos del Tracer/Current y los del propio mensaje pisan
    #   global_fields en caso de colisión. Default `{}`.
    #   @example
    #     config.global_fields = { tenant_id: ENV.fetch("TENANT_ID"), stack_id: ENV.fetch("STACK_ID") }
    attr_reader :global_fields

    # Claves sensibles que deben filtrarse automáticamente. Espejo de
    # {ExisRay::JsonFormatter::SENSITIVE_KEYS} para evitar duplicar la regex al boot.
    SENSITIVE_KEYS = /password|pass|passwd|secret|token|api_key|auth/i

    # Inicializa la configuración con valores por defecto compatibles con AWS X-Ray.
    def initialize
      @trace_header = "HTTP_X_AMZN_TRACE_ID"
      @propagation_trace_header = "X-Amzn-Trace-Id"
      @reporter_class = nil
      @current_class = nil
      @log_format = :text
      @log_subscriber_class = nil
      @service_version = default_service_version
      @deployment_environment = default_deployment_environment
      @global_fields = {}.freeze
    end

    # Setea los campos fijos por proceso. El hash se normaliza (filtrado de claves sensibles)
    # y se congela para garantizar inmutabilidad runtime y mover el cost al boot.
    #
    # @param hash [Hash, nil] Pares clave/valor a inyectar en cada log. `nil` se trata como `{}`.
    # @return [Hash] El hash normalizado y congelado.
    def global_fields=(hash)
      @global_fields = normalize_global_fields(hash)
    end

    # Lee la versión del servicio desde la configuración de Rails.
    # Busca primero en `config.version` (atributo directo) y luego en `config.x.version`
    # (custom config namespace). Retorna nil si ninguno está definido.
    #
    # @return [String, nil]
    def default_service_version
      return unless defined?(Rails) && Rails.application&.config

      config = Rails.application.config

      # Primero: config.version (atributo directo definido en Application)
      version = config.version if config.respond_to?(:version)
      return version.to_s if version.present?

      # Fallback: config.x.version (custom config namespace)
      if config.respond_to?(:x) && config.x.respond_to?(:version)
        x_version = config.x.version
        return x_version.to_s if x_version.present?
      end

      nil
    rescue StandardError
      nil
    end

    def default_deployment_environment
      return unless defined?(Rails) && Rails.respond_to?(:env)

      Rails.env.to_s
    end

    # Indica si la aplicación está configurada para emitir logs en formato estructurado (JSON).
    #
    # @return [Boolean] `true` si `log_format` es `:json`, `false` en caso contrario.
    def json_logs?
      @log_format == :json
    end

    private

    # Normaliza el hash de global_fields: descarta nil, filtra claves sensibles, y congela
    # tanto el hash como sus valores string (para evitar mutaciones runtime).
    #
    # @param hash [Hash, nil]
    # @return [Hash] hash congelado.
    def normalize_global_fields(hash)
      return {}.freeze if hash.nil? || hash.empty?

      filtered = hash.each_with_object({}) do |(k, v), acc|
        acc[k] = k.to_s.match?(SENSITIVE_KEYS) ? "[FILTERED]" : v
      end
      filtered.freeze
    end
  end
end
