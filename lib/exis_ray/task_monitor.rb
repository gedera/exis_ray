module ExisRay
  # Wrapper para monitorear tareas en segundo plano (Rake/Cron).
  module TaskMonitor
    # Ejecuta un bloque dentro de un contexto monitoreado.
    # @param task_name [String] Nombre identificador (ej: 'billing:generate').
    def self.run(task_name)
      setup_tracer(task_name)

      short_name = task_name.to_s.split(':').last

      # Configurar Reporter
      if (rep = ExisRay.reporter_class) && rep.respond_to?(:transaction_name=)
        rep.transaction_name = short_name
        rep.add_tags(service: :cron, task: short_name) if rep.respond_to?(:add_tags)
      end

      # Configurar Current
      if (curr = ExisRay.current_class) && curr.respond_to?(:correlation_id=)
        curr.correlation_id = ExisRay::Tracer.correlation_id
      end

      # Logs con Root ID
      tags = [ExisRay::Tracer.root_id]
      Rails.logger.tagged(*tags) do
        Rails.logger.info "[ExisRay] Iniciando tarea: #{task_name}"
        yield
        Rails.logger.info "[ExisRay] Finalizada con éxito."
      end

    rescue StandardError => e
      Rails.logger.error "[ExisRay] Falló la tarea #{task_name}: #{e.message}"
      raise e
    ensure
      # Limpieza centralizada
      ExisRay::Tracer.reset
      ExisRay.current_class&.reset  if ExisRay.current_class.respond_to?(:reset)
      ExisRay.reporter_class&.reset if ExisRay.reporter_class.respond_to?(:reset)
    end

    def self.setup_tracer(task_name)
      clean_task_name = task_name.to_s.gsub(':', '-').camelize
      app_name = defined?(Rails) ? Rails.application.class.module_parent_name : 'App'

      ExisRay::Tracer.service_name = "#{app_name}-#{clean_task_name}"
      ExisRay::Tracer.request_id   = SecureRandom.uuid
      ExisRay::Tracer.created_at   = Time.now.utc.to_f

      pod_id = get_pod_identifier
      ExisRay::Tracer.root_id = ExisRay::Tracer.send(:generate_new_root, pod_id)
    end

    def self.get_pod_identifier
      (ENV['HOSTNAME'] || 'local').split('-').last.to_s
    end

    private_class_method :get_pod_identifier, :setup_tracer
  end
end
