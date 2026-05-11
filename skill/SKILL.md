---
name: exis-ray
description: Skill de conocimiento completo sobre ExisRay, la capa de observabilidad y trazabilidad distribuida del ecosistema Wispro. Consultame para integración, arquitectura, API, errores y antipatrones.
---

# ExisRay Expert

Observabilidad y trazabilidad distribuida para microservicios Rails (AWS X-Ray compatible).

Para el complemento del estándar de logging Wispro (regla Data First, mapeo OpenTelemetry, ciclo de vida de jobs/requests), ver `references/standard.md`.

---

## Glosario

| Termino | Definicion |
|:--------|:-----------|
| **Trace ID** | String completo de trazabilidad: `Root=...;Self=...;CalledFrom=...;TotalTimeSoFar=...ms` |
| **Root ID** | Identificador unico del request original. Se propaga a todos los servicios downstream. Formato: `1-<timestamp_hex>-<random_hex>` |
| **Self ID** | Identificador del span actual generado por el servicio que propaga |
| **source** | Entrypoint de ejecucion. Valores validos: `http`, `sidekiq`, `task`, `system` |
| **correlation_id** | Compuesto `ServiceName;RootID`. Se asigna a `Current.correlation_id` para auditar identidad de negocio |
| **propagation_trace_header** | Header HTTP/AMQP para salida (`X-Amzn-Trace-Id`). Formato estandar HTTP |
| **trace_header** | Header HTTP para entrada (`HTTP_X_AMZN_TRACE_ID`). Formato Rack |
| **hydrate** | Inicializar el Tracer con un header entrante: parsea, asigna `created_at`, `source` y campos del trace |
| **Current** | `ActiveSupport::CurrentAttributes` subclass para contexto de negocio (user_id, isp_id, correlation_id) |
| **Reporter** | `ActiveSupport::CurrentAttributes` subclass para reporte de errores a Sentry (legacy y moderno) |
| **JsonFormatter** | `Logger::Formatter` que emite JSON estructurado, auto-inyecta contexto del Tracer y Current |
| **LogSubscriber** | Reemplaza Lograge. Se suscribe a `process_action.action_controller` y suprime los subscribers default de Rails |
| **TaskMonitor** | Wrapper para Rake/Cron que genera root_id propio y loguea `task_started`/`task_finished` con duracion |

---

## Arquitectura

### Responsabilidad core

ExisRay unifica trazabilidad distribuida, logging estructurado JSON, contexto de negocio thread-safe y reporte de errores en una sola gema. Se auto-instrumenta via Railtie sin configuracion adicional del desarrollador.

### Mapa de componentes

```
                        +-----------------+
                        |    Railtie      |  auto-instrumenta todo en after_initialize
                        +--------+--------+
                                 |
          +----------+-----------+----------+----------+
          |          |           |          |          |
   HttpMiddleware  Sidekiq   BugBunny   ActiveRes  Faraday
    (Rack mw)     Client/    Pub/Con    (prepend)  (Faraday mw)
          |        Server      |
          v          v         v
   +------+----------+---------+------+
   |           ExisRay::Tracer        |  ActiveSupport::CurrentAttributes
   |  trace_id, root_id, self_id,    |  thread-safe, reset per request
   |  source, created_at, ...        |
   +----------------------------------+
          |                    |
   ExisRay::Current      ExisRay::Reporter
   (user_id, isp_id,    (Sentry scope:
    correlation_id)       contexts, tags,
                          fingerprint)
          |
   ExisRay::JsonFormatter  <-- intercepta Rails.logger
   ExisRay::LogSubscriber  <-- reemplaza ActionController::LogSubscriber
```

### Flujo runtime (HTTP request)

1. `HttpMiddleware` lee `trace_header` del env Rack, llama `Tracer.hydrate(trace_id:, source: "http")`
2. `Tracer.parse_trace_id` extrae `root_id`, `self_id`, `called_from`, `total_time_so_far`
3. `ExisRay.sync_correlation_id` asigna `Tracer.correlation_id` a `Current.correlation_id`
4. Controller ejecuta `before_action` para setear `Current.user_id`, `Current.isp_id`
5. `JsonFormatter` intercepta cada `Rails.logger.*` e inyecta automaticamente: `time`, `level`, `severity_number`, `service`, `service_version`, `deployment_environment`, `root_id`, `trace_id`, `source`, `user_id`, `isp_id`, `correlation_id`
6. `LogSubscriber` emite un unico Hash al finalizar el request (method, path, http_status, http_route, duration_s, user_agent_original, server_address, etc.)
7. En llamadas salientes, `FaradayMiddleware`/`ActiveResourceInstrumentation` inyectan `propagation_trace_header` con `Tracer.generate_trace_header`
8. Al finalizar, `ActiveSupport::CurrentAttributes` hace reset automatico

---

## API Publica

### Configuracion

```ruby
ExisRay.configure do |config|
  config.trace_header            = "HTTP_X_AMZN_TRACE_ID"  # String, default
  config.propagation_trace_header = "X-Amzn-Trace-Id"      # String, default
  config.current_class           = "Current"                # String, default "Current"
  config.reporter_class          = "Reporter"               # String, default "Reporter"
  config.log_format              = :json                    # Symbol, :text (default) | :json
  config.log_subscriber_class    = "MyLogSubscriber"        # String|nil, default nil
  config.service_version         = "1.2.3"                  # String|nil, default: Rails config.version o config.x.version
  config.deployment_environment  = "production"             # String|nil, default: Rails.env
end

ExisRay.configuration.json_logs?  # => true si log_format == :json
```

Las clases se pasan como String para evitar `uninitialized constant` durante boot. Se resuelven via `safe_constantize`. En produccion se memoizan; en desarrollo se resuelven en cada request para soportar Zeitwerk reloading.

### ExisRay::Tracer

```ruby
# Hidratar desde header entrante (usado por middlewares internamente)
ExisRay::Tracer.hydrate(trace_id: "Root=1-abc;Self=...", source: "http")
# => void. Asigna created_at, source, trace_id y parsea campos.

# Generar header para propagar al siguiente servicio
ExisRay::Tracer.generate_trace_header
# => "Root=1-abc;Self=1-...;CalledFrom=my_app;TotalTimeSoFar=42ms"

# Nombre del servicio (inferido de Rails.application)
ExisRay::Tracer.service_name  # => "cold_storage_service"

# Correlation ID compuesto
ExisRay::Tracer.correlation_id  # => "cold_storage_service;1-abc-def"

# Duracion desde created_at
ExisRay::Tracer.current_duration_s   # => 1.2345 (Float, segundos)
ExisRay::Tracer.current_duration_ms  # => 1235   (Integer, milisegundos)

# Formateo humano de duracion
ExisRay::Tracer.format_duration(0.007)  # => "7.0ms"
ExisRay::Tracer.format_duration(5.25)   # => "5.25s"
ExisRay::Tracer.format_duration(125)    # => "2 minutes 5 seconds"

# Atributos (ActiveSupport::CurrentAttributes)
ExisRay::Tracer.trace_id          # String completo del header
ExisRay::Tracer.root_id           # Solo la parte Root
ExisRay::Tracer.self_id           # Solo la parte Self
ExisRay::Tracer.called_from       # Nombre del servicio upstream
ExisRay::Tracer.total_time_so_far # Integer, ms acumulados
ExisRay::Tracer.source            # "http"|"sidekiq"|"task"|"system"
ExisRay::Tracer.request_id        # UUID del request (ActionDispatch)
ExisRay::Tracer.sidekiq_job       # Nombre del worker (solo en Sidekiq)
ExisRay::Tracer.task              # Nombre de la task (solo en TaskMonitor)
ExisRay::Tracer.created_at        # Float, Process::CLOCK_MONOTONIC
```

### ExisRay::Current (clase base abstracta)

```ruby
class Current < ExisRay::Current
  attribute :billing_cycle, :permissions  # atributos custom de la app
end

# Atributos provistos por ExisRay::Current:
Current.user_id        = 42
Current.isp_id         = 10
Current.correlation_id = "service;Root=1-abc"

# Lazy-loaded objects (requieren modelos ::User, ::Isp en la app)
Current.user           # => User.find_by(id: user_id), memoizado por request
Current.isp            # => Isp.find_by(id: isp_id), memoizado por request
Current.user = user_obj  # setter: asigna user_id desde object.id

# Predicados
Current.user?           # => true si user_id no es nil
Current.isp?            # => true si isp_id no es nil
Current.correlation_id? # => true si correlation_id es present?
```

Los setters auto-sincronizan con `ActiveResource::Base.headers` y `PaperTrail.request` cuando estan definidos.

### ExisRay::Reporter (clase base abstracta)

```ruby
class Choto < ExisRay::Reporter
  def self.build_custom_context
    # Hook para agregar contexto especifico del servicio
    add_tags(olt_id: Current.olt&.id) if Current.respond_to?(:olt)
  end

  # Hooks opcionales para controlar datos enviados a Sentry
  def self.sentry_user_context(current)
    { id: current.user_id, email: current.user&.email }
  end

  def self.sentry_isp_context(current)
    { id: current.isp_id, name: current.isp&.name }
  end
end

# Reportar mensaje
Choto.report("algo paso", context: { key: "val" }, tags: { env: "prod" },
             fingerprint: ["custom"], transaction_name: "MyJob")

# Reportar excepcion
Choto.exception(error, context: {}, tags: {}, fingerprint: [])

# Builders
Choto.add_context(trace: { root_id: "..." })
Choto.add_tags(user_id: 42)
Choto.add_fingerprint("custom-group")
```

Soporta Sentry moderno (`Sentry.capture_exception`) y legacy (`Session`/`Raven`). Detecta automaticamente via constante `NEW_SENTRY`.

### ExisRay::TaskMonitor

```ruby
ExisRay::TaskMonitor.run("billing:generate_invoices") do
  InvoiceService.process_all
end
# Genera root_id propio, loguea task_started/task_finished con outcome y duration_s.
# En caso de error emite: error_class, error_message (legacy) + exception.type,
# exception.message, exception.stacktrace (OTel, limitado a 20 lineas).
# Re-lanza excepciones despues de loguearlas.
# Hace reset de Tracer, Current y Reporter en ensure.
```

### ExisRay::LogSubscriber

```ruby
class MyLogSubscriber < ExisRay::LogSubscriber
  def self.extra_fields(event)
    { ip: event.payload[:ip], user_agent: event.payload[:headers]["HTTP_USER_AGENT"] }
  end
end

# Registrar en configuracion:
ExisRay.configure { |c| c.log_subscriber_class = "MyLogSubscriber" }
```

### ExisRay::JsonFormatter

Se asigna automaticamente a `Rails.logger.formatter` cuando `log_format: :json`. Acepta tres tipos de mensaje:

- **Hash**: merge directo al payload JSON
- **String KV** (`"event=foo bar=baz"`): parsea pares y los eleva al root del JSON
- **String libre**: asigna al campo `body`

Casteo automatico: integers, floats, objetos JSON (`{...}`, `[...]`). Filtra claves sensibles (`password|secret|token|api_key|auth`) a `[FILTERED]`. Fallback a JSON minimo si el formateo falla.

### Middlewares de propagacion

```ruby
# Faraday (manual)
conn = Faraday.new(url: "https://api.internal") do |f|
  f.use ExisRay::FaradayMiddleware
end

# ActiveResource: auto-instrumentado via prepend en Railtie

# BugBunny publisher (manual en el client)
client = BugBunny::Client.new(pool: pool) do |stack|
  stack.use ExisRay::BugBunny::PublisherTracing
end

# BugBunny consumer: auto-registrado en Railtie
# BugBunny.consumer_middlewares.use ExisRay::BugBunny::ConsumerTracingMiddleware
```

### Helpers del modulo ExisRay

```ruby
ExisRay.current_class      # => Class resuelta de config.current_class
ExisRay.reporter_class     # => Class resuelta de config.reporter_class
ExisRay.sync_correlation_id  # Sincroniza Tracer.correlation_id -> Current.correlation_id
ExisRay.configuration      # => ExisRay::Configuration instance
```

---

## FAQ

**P: Necesito agregar campos custom al log de cada HTTP request. Como lo hago?**
Subclasea `ExisRay::LogSubscriber`, sobreescribi `self.extra_fields(event)` retornando un Hash, y configura `config.log_subscriber_class = "MiSubscriber"`.

**P: Uso BugBunny::Resource. Donde pongo el PublisherTracing?**
En un `ApplicationResource` base con `client_middleware`. Las subclases heredan el stack automaticamente:
```ruby
class ApplicationResource < BugBunny::Resource
  client_middleware do |stack|
    stack.use ExisRay::BugBunny::PublisherTracing
  end
end
```

**P: Que pasa si un mensaje llega sin header de traza?**
El `ConsumerTracingMiddleware` genera un `root_id` nuevo automaticamente. Los logs del consumer siempre tendran contexto de trazabilidad.

**P: El Tracer funciona en threads separados?**
Si. Hereda de `ActiveSupport::CurrentAttributes`, que usa `IsolatedExecutionState` (thread-local o fiber-local segun Rails). Cada thread tiene su propio contexto.

**P: Como propago el trace en un request Faraday?**
Agrega `f.use ExisRay::FaradayMiddleware` al stack de Faraday. Solo inyecta header si hay `root_id` activo.

**P: Puedo usar ExisRay sin JSON logging?**
Si. Con `log_format: :text` (default), ExisRay inyecta el `root_id` como tag de Rails via `config.log_tags`. El JsonFormatter y LogSubscriber no se activan.

**P: Por que no usar `ActiveSupport::TaggedLogging` con JSON logging?**
`TaggedLogging` agrega tags como texto plano al inicio de cada línea **antes** del formatter, lo cual rompe el JSON:
```
[request_id] {"time":"...","level":"INFO",...}   # ← texto antes del JSON
```
`ExisRay::JsonFormatter` ya inyecta los tags (`request_id`, `trace_id`, etc.) como campos JSON. Usar ambos genera JSON inválido.

Configuración correcta en production.rb:
```ruby
config.colorize_logging = false
config.logger = ActiveSupport::Logger.new(STDOUT)
config.logger.formatter = ExisRay::JsonFormatter
```

**P: Que pasa con los logs de Sidekiq (el propio logger de Sidekiq)?**
Si `json_logs?` es true, el Railtie asigna `Sidekiq.logger.formatter = ExisRay::JsonFormatter.new`, asi los logs internos de Sidekiq tambien salen en JSON.

**P: El Railtie valida que current_class y reporter_class hereden de las bases?**
Solo cuando `eager_load=true` (produccion/staging). En desarrollo con lazy loading las clases pueden no estar cargadas aun.

---

## Antipatrones

### Incluir campos auto-inyectados en logs manuales

```ruby
# MAL - duplica campos y puede causar inconsistencias
Rails.logger.info("time=#{Time.now} level=INFO root_id=#{ExisRay::Tracer.root_id} event=boot")

# BIEN - JsonFormatter inyecta time, level, service, root_id, trace_id, source automaticamente
Rails.logger.info("event=boot status=ok")
```

### Usar Time.now para medir duraciones

```ruby
# MAL - Time.now es afectado por NTP adjustments y cambios de timezone
start = Time.now
do_work
Rails.logger.info("duration_s=#{Time.now - start}")

# BIEN - CLOCK_MONOTONIC es monotonicamente creciente
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
do_work
Rails.logger.info("duration_s=#{(Process.clock_gettime(Process::CLOCK_MONOTONIC) - start).round(4)}")
```

### Hidratar el Tracer manualmente en controllers

```ruby
# MAL - HttpMiddleware ya hace esto automaticamente
class ApplicationController < ActionController::Base
  before_action do
    ExisRay::Tracer.trace_id = request.headers["X-Amzn-Trace-Id"]
    ExisRay::Tracer.parse_trace_id
  end
end

# BIEN - solo setear contexto de negocio
class ApplicationController < ActionController::Base
  before_action do
    Current.user = current_user if current_user
    Current.isp_id = request.headers["X-Isp-Id"]
  end
end
```

### Usar Lograge junto con ExisRay

```ruby
# MAL - ExisRay::LogSubscriber reemplaza Lograge. Tenerlos juntos causa logs duplicados
# Gemfile
gem "lograge"
gem "exis_ray"

# BIEN - remover lograge del Gemfile y su config. ExisRay hace lo mismo internamente.
```

### Olvidar el PublisherTracing en BugBunny::Client

```ruby
# MAL - el consumer no recibira trace context, trazabilidad rota
client = BugBunny::Client.new(pool: pool) do |stack|
  stack.use BugBunny::Middleware::JsonResponse
end

# BIEN - PublisherTracing primero en el stack
client = BugBunny::Client.new(pool: pool) do |stack|
  stack.use ExisRay::BugBunny::PublisherTracing
  stack.use BugBunny::Middleware::JsonResponse
end
```

### Usar Kernel#warn o $stderr para logging

```ruby
# MAL - bypasea JsonFormatter, no tiene contexto de trazabilidad
warn "algo salio mal"
$stderr.puts "error critico"

# BIEN - usa Rails.logger para que JsonFormatter lo capture
Rails.logger.warn("component=my_module event=something_wrong detail=algo")
Rails.logger.error("component=my_module event=critical_error")
```

### No usar block form para DEBUG

```ruby
# MAL - el string se interpola siempre, incluso si log level es INFO
Rails.logger.debug("component=heavy event=detail payload=#{expensive_serialize}")

# BIEN - block form: solo se evalua si log level es DEBUG
Rails.logger.debug { "component=heavy event=detail payload=#{expensive_serialize}" }
```

---

## Errores

### `ExisRay: current_class 'X' not found or doesn't inherit from ExisRay::Current`

**Causa:** La clase configurada en `config.current_class` no existe o no hereda de `ExisRay::Current`. Solo se valida cuando `eager_load=true`.
**Resolucion:** Verificar que la clase existe en `app/models/` y hereda de `ExisRay::Current`:
```ruby
class Current < ExisRay::Current
end
```

### `ExisRay: reporter_class 'X' not found or doesn't inherit from ExisRay::Reporter`

**Causa:** Igual que arriba pero para `config.reporter_class`.
**Resolucion:** La clase debe heredar de `ExisRay::Reporter`.

### NoMethodError en `current_tags` dentro de JsonFormatter

**Causa:** El formatter se usa fuera del contexto de Rails (tests, scripts) donde `ActiveSupport::TaggedLogging::Formatter` no esta completamente inicializado.
**Resolucion:** JsonFormatter tiene guard con `respond_to?(:current_tags)`. Si persiste, stubear `current_tags` en el test:
```ruby
allow(formatter).to receive(:current_tags).and_return([])
```

### Logs duplicados en HTTP requests (lineas multi-linea de Rails + JSON)

**Causa:** `LogSubscriber.install!` no se ejecuto correctamente, los subscribers default de Rails siguen activos.
**Resolucion:** Verificar que `config.log_format = :json` esta seteado ANTES de que el Railtie corra `after_initialize`. Debe estar en `config/initializers/exis_ray.rb`.

### Trace context no se propaga en Sidekiq jobs

**Causa:** El `ClientMiddleware` no esta registrado (raro si Sidekiq se carga antes del Railtie).
**Resolucion:** Verificar con:
```ruby
Sidekiq.configure_client { |c| puts c.client_middleware.entries.map(&:klass) }
```
Debe incluir `ExisRay::Sidekiq::ClientMiddleware`.

### `user_id=0` no aparece en los logs

**Causa:** Bug previo donde se filtraba con `present?` (0 es falsy en Ruby para `present?`).
**Resolucion:** ExisRay usa `!nil?` para `user_id`/`isp_id`, asi que `0` es un valor valido. Si no aparece, verificar que `Current.user_id` esta seteado y que `ExisRay.current_class` resuelve correctamente.

### JSON malformado en logs (caracteres especiales)

**Causa:** `JSON.generate` por defecto con `ascii_only: false` preserva unicode. Si el log aggregator no soporta UTF-8 puede romper.
**Resolucion:** ExisRay usa `ascii_only: false` intencionalmente. Si necesitas ASCII puro, sobreescribi el formatter. El fallback interno siempre genera JSON valido.
