# frozen_string_literal: true

module ExisRay
  # Wrapper para monitorear tareas en segundo plano (Rake/Cron) o scripts aislados.
  #
  # Esta clase inicializa un contexto de trazabilidad simulado (ya que no hay
  # una petición HTTP entrante) generando un nuevo `Root ID`. Luego, configura
  # el reporte de errores y el contexto global antes de ejecutar el bloque provisto.
  module TaskMonitor
    # Ejecuta un bloque de código dentro de un contexto monitoreado por ExisRay.
    #
    # @param task_name [String, Symbol] Nombre identificador de la tarea (ej: "billing:generate").
    # @yield El bloque de código que representa la lógica de la tarea.
    # @raise [StandardError] Re-lanza cualquier excepción ocurrida tras registrarla.
    # @return [void]
    def self.run(task_name)
      setup_tracer(task_name)

      short_name = task_name.to_s.split(":").last

      # Configurar Reporter (Sentry u otro)
      if (rep = ExisRay.reporter_class) && rep.respond_to?(:transaction_name=)
        rep.transaction_name = short_name
        rep.add_tags(service: :cron, task: short_name) if rep.respond_to?(:add_tags)
      end

      # Configurar Current Attributes
      if (curr = ExisRay.current_class) && curr.respond_to?(:correlation_id=)
        curr.correlation_id = ExisRay::Tracer.correlation_id
      end

      log_event(:info, "Iniciando tarea: #{task_name}", task: task_name, status: "started")

      # Bloque de ejecución con o sin tags dependiendo de la configuración
      execute_with_optional_tags { yield }

      log_event(:info, "Finalizada con éxito.", task: task_name, status: "success")
    rescue StandardError => e
      log_event(:error, "Falló la tarea #{task_name}: #{e.message}", task: task_name, status: "failed", error: e.message)
      raise e
    ensure
      # Limpieza centralizada obligatoria para evitar filtraciones de memoria o contexto
      ExisRay::Tracer.reset
      ExisRay.current_class&.reset  if ExisRay.current_class.respond_to?(:reset)
      ExisRay.reporter_class&.reset if ExisRay.reporter_class.respond_to?(:reset)
    end

    # --- Métodos Privados ---

    # Inicializa el Tracer con datos específicos de la tarea y el entorno.
    #
    # @param task_name [String, Symbol] El nombre de la tarea en ejecución.
    # @return [void]
    def self.setup_tracer(task_name)
      ExisRay::Tracer.service_name = task_name.to_s.tr(":", "-").camelize
      ExisRay::Tracer.request_id   = SecureRandom.uuid
      ExisRay::Tracer.created_at   = Time.now.utc.to_f

      pod_id = get_pod_identifier
      ExisRay::Tracer.root_id = ExisRay::Tracer.send(:generate_new_root, pod_id)
    end

    # Obtiene un identificador único del contenedor o máquina actual.
    #
    # @return [String] El sufijo del hostname o "local" por defecto.
    def self.get_pod_identifier
      (ENV["HOSTNAME"] || "local").split("-").last.to_s
    end

    # Ejecuta el bloque inyectando tags de Rails solo si estamos en modo texto.
    # En modo JSON, JsonFormatter ya se encarga de inyectar el root_id.
    #
    # @yield El bloque de ejecución de la tarea.
    # @return [void]
    def self.execute_with_optional_tags
      if !ExisRay.configuration.json_logs? && Rails.logger.respond_to?(:tagged)
        Rails.logger.tagged(ExisRay::Tracer.root_id) { yield }
      else
        yield
      end
    end

    # Envía un evento al logger de Rails adaptándose al formato configurado.
    #
    # @param level [Symbol] Nivel de severidad (:info, :error).
    # @param message [String] Mensaje en texto plano para el modo clásico.
    # @param payload [Hash] Datos estructurados para el modo JSON.
    # @return [void]
    def self.log_event(level, message, **payload)
      if ExisRay.configuration.json_logs?
        Rails.logger.send(level, payload.merge(message: "[ExisRay] #{message}"))
      else
        Rails.logger.send(level, "[ExisRay] #{message}")
      end
    end

    private_class_method :get_pod_identifier, :setup_tracer, :execute_with_optional_tags, :log_event
  end
end
