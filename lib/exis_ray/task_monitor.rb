module ExisRay
  # Wrapper de observabilidad diseñado para envolver la ejecución de tareas en segundo plano
  # (como Rake Tasks o Cron Jobs) donde no existe un Middleware HTTP que inicie la traza.
  #
  # @example Uso básico en una tarea Rake
  #   # config/initializers/exis_ray.rb
  #   ExisRay.configure { |c| c.reporter_class = 'Choto' }
  #
  #   # lib/tasks/billing.rake
  #   task generate_invoices: :environment do
  #     ExisRay::TaskMonitor.run('billing:generate_invoices') do
  #       InvoiceService.process_all
  #     end
  #   end
  module TaskMonitor
    # Ejecuta un bloque de código dentro de un contexto de trazabilidad monitoreado.
    #
    # Realiza las siguientes acciones:
    # 1. Inicializa {ExisRay::Tracer} con un nuevo Root ID y un Service Name derivado de la tarea.
    # 2. Resuelve la clase de reporte configurada (ej: `Choto`) e inyecta el nombre de la transacción.
    # 3. Sincroniza el Correlation ID con `Current` (si existe).
    # 4. Configura tags en el logger de Rails para que todas las líneas incluyan el Root ID.
    # 5. Garantiza la limpieza (reset) del contexto al finalizar, incluso si hay errores.
    #
    # @param task_name [String, Symbol] El nombre identificador de la tarea (ej: 'billing:generate').
    #   Se normalizará para generar el ServiceName (ej: 'Wispro-Cron-Billing-Generate').
    # @yield El bloque de lógica de negocio que se va a ejecutar.
    # @return [Object] El resultado de la ejecución del bloque.
    # @raise [StandardError] Re-lanza cualquier error ocurrido en el bloque para no silenciar fallos.
    def self.run(task_name)
      # 1. Configuración de Infraestructura
      setup_tracer(task_name)

      # 2. Configuración de Negocio (Integración dinámica)
      short_name = task_name.to_s.split(':').last

      # Buscamos la clase real configurada por el usuario (ej: Choto)
      reporter_klass = resolve_reporter_class

      if reporter_klass && reporter_klass.respond_to?(:transaction_name=)
        reporter_klass.transaction_name = short_name
        # Usamos try/respond_to por seguridad
        reporter_klass.add_tags(service: :cron, task: short_name) if reporter_klass.respond_to?(:add_tags)
      end

      # Puente con Current para auditoría
      if defined?(::Current) && ::Current.respond_to?(:correlation_id=)
        ::Current.correlation_id = ExisRay::Tracer.correlation_id
      end

      # 3. Ejecución con Logs Taggeados
      # Usamos el Root ID para facilitar búsquedas (grep/Kibana)
      tags = ["Root=#{ExisRay::Tracer.root_id}"]

      Rails.logger.tagged(*tags) do
        Rails.logger.info "[ExisRay] Iniciando tarea: #{task_name}"
        yield
        Rails.logger.info "[ExisRay] Finalizada con éxito."
      end

    rescue StandardError => e
      # El error hereda los tags porque estamos dentro del bloque logger.tagged
      Rails.logger.error "[ExisRay] Falló la tarea #{task_name}: #{e.message}"
      raise e
    ensure
      # 4. Limpieza (Vital para evitar contaminación de memoria en procesos persistentes)
      ::Current.reset if defined?(::Current)
      ExisRay::Tracer.reset

      # Limpiamos también la clase de reporte específica de la app
      reporter_klass.reset if reporter_klass && reporter_klass.respond_to?(:reset)
    end

    # --- Métodos Privados del Módulo ---

    # Prepara el Tracer con valores frescos para una nueva ejecución aislada.
    #
    # @api private
    # @param task_name [String] Nombre crudo de la tarea.
    def self.setup_tracer(task_name)
      # Normalizamos el nombre: 'billing:generate' -> 'Billing-Generate'
      clean_task_name = task_name.to_s.gsub(':', '-').camelize

      # Obtenemos el nombre base de la app (ej: Wispro)
      app_name = defined?(Rails) ? Rails.application.class.module_parent_name : 'App'

      ExisRay::Tracer.service_name = "#{app_name}-Cron-#{clean_task_name}"
      ExisRay::Tracer.request_id   = SecureRandom.uuid
      ExisRay::Tracer.created_at   = Time.now.utc.to_f

      # Obtenemos el ID del Pod/Contenedor para saber dónde corrió
      pod_id = get_pod_identifier

      # Usamos .send para invocar el método privado generate_new_root de Tracer
      ExisRay::Tracer.root_id = ExisRay::Tracer.send(:generate_new_root, pod_id)
    end

    # Intenta obtener el identificador único del contenedor/pod.
    #
    # @api private
    # @return [String] El sufijo del hostname o 'local'.
    def self.get_pod_identifier
      hostname = ENV['HOSTNAME'] || 'local'
      # Si el hostname es 'wispro-worker-deployment-ax99', devuelve 'ax99'
      hostname.split('-').last.to_s
    end

    # Resuelve la clase de reporte configurada en {ExisRay::Configuration}.
    #
    # @api private
    # @return [Class, nil] La clase constante (ej: Choto) o nil si no está configurada.
    def self.resolve_reporter_class
      klass_name = ExisRay.configuration.reporter_class
      return nil unless klass_name.present?

      # Si es un String ("Choto"), lo convertimos a constante de forma segura.
      # Si ya es una clase, la devolvemos tal cual.
      klass_name.is_a?(String) ? klass_name.safe_constantize : klass_name
    end

    # Definición explícita de privacidad para métodos internos
    private_class_method :setup_tracer, :get_pod_identifier, :resolve_reporter_class
  end
end
