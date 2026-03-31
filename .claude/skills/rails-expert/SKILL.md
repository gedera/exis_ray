---
name: rails-expert
description: This skill should be used when writing or reviewing any Rails integration code in this gem — Railtie, middleware, CurrentAttributes, initializers, ActiveSupport notifications, or compatibility across Rails 6/7/8. Activates when the user mentions "railtie", "middleware", "initializer", "after_initialize", "current_attributes", "cache_classes", "enable_reloading", "log_subscriber", "tagged_logging", or asks about Rails compatibility.
version: 1.0.0
---

# Rails Expert — ExisRay Context

Este skill cubre las integraciones de ExisRay con Rails y las reglas de compatibilidad entre versiones.

## Compatibilidad de Versiones

### Rails 7.1+ vs 6/7.0

**Reloading:**
```ruby
# Correcto — compatible con Rails 6, 7 y 8
def cache_classes?
  config = Rails.application.config
  if config.respond_to?(:enable_reloading)
    !config.enable_reloading  # Rails 7.1+ (semántica inversa)
  else
    config.cache_classes      # Rails 6/7.0
  end
end
```

**Notifications (ActiveSupport):**
```ruby
# Correcto — siempre usar respond_to? guard
if notifier.respond_to?(:all_listeners_for)
  notifier.all_listeners_for(pattern)   # Rails 7.1+
else
  notifier.listeners_for(pattern)       # Rails 6/7.0
end
```

## Railtie — Orden de Inicialización

ExisRay usa tres puntos de inicialización con propósitos distintos:

```
1. initializer "exis_ray.configure_middleware"
   → Inserta HttpMiddleware en el stack Rack
   → Corre antes de que la app arranque

2. initializer "exis_ray.configure_logging", after: :load_config_initializers
   → Lee config/initializers/exis_ray.rb antes de decidir la estrategia
   → Configura log_tags para modo texto

3. config.after_initialize
   → Todo lo demás: JsonFormatter, LogSubscriber, BugBunny, Sidekiq, ActiveResource
   → Garantiza que TODAS las gemas están cargadas (defined?(::BugBunny) funciona)
```

**Regla crítica:** Cualquier integración condicional (`defined?(::GemaExterna)`) DEBE ir en `after_initialize`, no en `initializer`. De lo contrario la condición puede evaluarse antes de que la gema esté cargada.

## CurrentAttributes

`ExisRay::Tracer` extiende `ActiveSupport::CurrentAttributes` — es thread-local y se resetea automáticamente al final de cada request HTTP (via `ActionDispatch::Executor`).

Para contextos no-HTTP (Sidekiq, BugBunny, Rake), siempre hacer reset manual en `ensure`:
```ruby
ensure
  ExisRay::Tracer.reset rescue nil
end
```

## LogSubscriber

`ExisRay::LogSubscriber` usa `ActiveSupport::Notifications`. Solo se instala con `json_logs: true`.

```ruby
ExisRay::LogSubscriber.install!
# Internamente: subscribe a process_action.action_controller
# y desuscribe los subscribers por defecto de Rails
```

## TaggedLogging (modo texto)

En modo texto (`json_logs: false`), el contexto se inyecta via `log_tags`:
```ruby
app.config.log_tags << proc { ExisRay::Tracer.trace_id.presence || ExisRay::Tracer.root_id.presence }
```
Solo funciona dentro del ciclo de un HTTP request. Procesos background (Sidekiq, BugBunny) no tienen este contexto en modo texto.
