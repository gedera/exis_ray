---
name: exis-ray
description: Conocimiento completo de ExisRay, la capa de observabilidad y trazabilidad distribuida del ecosistema Wispro (logging JSON estructurado, trace context AWS X-Ray, propagación entre servicios). ACTIVAR cuando un servicio o gema Rails integra/configura ExisRay, emite o debuggea logs JSON estructurados, propaga trace context (header X-Amzn-Trace-Id) entre HTTP/Sidekiq/BugBunny, usa ExisRay::Tracer/Current/Reporter/JsonFormatter/TaskMonitor, edita el initializer de ExisRay, o resuelve errores/antipatrones de logging-trazabilidad Wispro.
---

# ExisRay Expert

Observabilidad y trazabilidad distribuida para microservicios Rails (AWS X-Ray compatible).

Para el complemento del estándar de logging Wispro (regla Data First, mapeo OpenTelemetry, ciclo de vida de jobs/requests), ver `references/standard.md`.

### Artefactos de detalle (RFC-008)

Este SKILL.md **resume e indexa**; el contrato y el significado de detalle viven en `docs/<capa>/`. **Version-lock por construcción:** `gemspec.files` empaqueta `docs/**` en el mismo tag que este `SKILL.md`; los links son rutas relativas dentro del paquete del release (nunca rama/`HEAD`/URL flotante). Contrato resumido anclado a **v0.10.0** (post fix issues #9, #11, #12):

- [`docs/behavior/behavior.md`](../docs/behavior/behavior.md) — secuencias de hidratación de trace por entrypoint + emisión en logs (parcial, incremental).
- [`docs/glossary/glossary.md`](../docs/glossary/glossary.md) — lenguaje ubicuo del bounded context (`root_id`, `trace_id`, `source`, `request_id`, `entrypoint`, ...).
- Datos = n/a (gema sin DB). Operaciones/Interfaz/Topología = F2 `dev-structure`, no implementado: contrato Ruby permanece embebido abajo (coexistencia transitoria RFC-008 §2).

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

1. `HttpMiddleware` lee `trace_header` del env Rack, llama `Tracer.hydrate(trace_id:, source: "http")`. **Si no llega header** (servicio entrypoint, no eslabón intermedio) genera un `root_id` fresco — paridad con `Sidekiq::ServerMiddleware`/`BugBunny::ConsumerTracingMiddleware`/`TaskMonitor`. Captura `request_id` de `action_dispatch.request_id`. Secuencia detallada: `docs/behavior/behavior.md`.
2. `Tracer.parse_trace_id` extrae `root_id`, `self_id`, `called_from`, `total_time_so_far`
3. `ExisRay.sync_correlation_id` asigna `Tracer.correlation_id` a `Current.correlation_id`
4. Controller ejecuta `before_action` para setear `Current.user_id`, `Current.isp_id`
5. `JsonFormatter` intercepta cada `Rails.logger.*` e inyecta el contexto de ejecucion en cada linea. **No es incondicional:** cada campo tiene un guard especifico (ver tabla "Condiciones de emision" mas abajo). En particular `inject_tracer_context` corta el bloque `root_id`/`trace_id`/`source`/`task`/`sidekiq_job` con `return unless Tracer.root_id` — la invariante "todo entrypoint garantiza `root_id`" es lo que hace que `source` (mandatorio) nunca falte. `request_id` se emite **fuera** de ese guard (distinto ciclo de vida que `root_id`). El developer aporta `component` (modulo de negocio) y `event` (que paso); estos NO son auto-inyectados porque dependen del call site, no del contexto de ejecucion.
6. `LogSubscriber` emite un unico Hash al finalizar el request con campos default (`component`, `event`, `method`, `path`, `http_route`, `format`, `controller`, `action`, `http_status`, `duration_s`, `duration_human`, `view_runtime_s`, `db_runtime_s`, `user_agent_original`, `server_address`, y en error `error_class`/`error_message`/`exception.*`).
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

#### Hook `log_fields` — inyectar campos custom en cada log

Class method overridable que retorna un Hash de campos extra para JsonFormatter. Cubre tanto **constantes de proceso** (frozen constants en la subclass) como **valores dinámicos per-request** (atributos de Current) en un solo lugar. Default `{}`.

```ruby
class Current < ExisRay::Current
  TENANT_ID = ENV.fetch("TENANT_ID").freeze   # static, frozen al boot
  attribute :region                             # dynamic, per-request

  def self.log_fields
    { tenant_id: TENANT_ID, region: region }.compact
  end
end
```

Reglas:

- `JsonFormatter` filtra claves sensibles del hash retornado (mismo regex que el resto del formatter).
- Si el override revienta, el formatter rescata silenciosamente (logging no afecta flujo principal).
- Precedencia: campos canónicos del Tracer y keys del mensaje del developer pisan `log_fields` en colisión. Solo sirve para agregar fields nuevos, no para overrideear los canónicos.

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

Reemplaza Lograge. Se suscribe a `process_action.action_controller` y emite un Hash por request HTTP. Severity es `ERROR` si `http_status >= 500`, sino `INFO`.

**Campos default emitidos** (mergeados al payload JSON; nunca duplicarlos manualmente):

| Campo | Tipo | Notas |
|:------|:-----|:------|
| `component` | String | Siempre `"exis_ray"` |
| `event` | String | Siempre `"http_request"` |
| `method` | String | Verbo HTTP |
| `path` | String | URL concreta del request |
| `http_route` | String | Template (ej: `/users/:id`). Baja cardinalidad para dashboards |
| `format` | Symbol/String | `html`, `json`, etc. |
| `controller` | String | Class name del controller |
| `action` | String | Nombre del action |
| `http_status` | Integer | Status HTTP final |
| `duration_s` | Float | Segundos (Rails reporta ms, se convierte), redondeo 4 decimales |
| `duration_human` | String | Legible: `"42.5ms"`, `"1.25s"`, `"2 minutes 5 seconds"` |
| `view_runtime_s` | Float\|nil | Solo si Rails lo reporta |
| `db_runtime_s` | Float\|nil | Solo si ActiveRecord lo reporta |
| `user_agent_original` | String | Header `User-Agent` |
| `server_address` | String | Hostname sin puerto (de `Host` header) |
| `error_class`, `error_message` | String | Solo en fallo (legacy) |
| `exception.type`, `exception.message`, `exception.stacktrace` | String | Solo en fallo (OTel; stack limitado a 20 lineas) |

Para inyectar campos extra, sobreescribir `extra_fields`:

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

- **Hash**: merge directo al payload JSON. Util para payloads complejos o con valores nested.
- **String KV** (`"event=foo bar=baz"`): parsea pares y los eleva al root del JSON. Util para one-liners rapidos.
- **String libre**: asigna al campo `body` (OTel log body).

Casteo automatico: integers, floats, objetos JSON (`{...}`, `[...]`). Filtra claves sensibles (`password|secret|token|api_key|auth`) a `[FILTERED]`. Fallback a JSON minimo si el formateo falla.

#### Criterio auto-inyectado vs manual

- **Auto-inyectado** (formatter conoce desde `Tracer`/`Current`): contexto de **ejecucion** — quien hace el request, de donde viene, en que servicio, con que identidad.
- **Manual** (lo aporta cada `Rails.logger.*`): contexto del **call site** — que modulo (`component`) y que paso (`event`). El formatter no puede saber esto sin recorrer el stack en cada log.

Por eso `component` y `event` jamas se auto-inyectan, aunque el estandar Wispro los exija.

#### Condiciones de emision por campo

La auto-inyeccion **no es incondicional**: cada campo tiene un guard. `inject_tracer_context` corta su bloque con `return unless Tracer.root_id`, asi que `root_id`/`trace_id`/`source`/`task`/`sidekiq_job` solo se emiten cuando hay trace context activo. Los 4 entrypoints (HTTP, Sidekiq server, BugBunny consumer, TaskMonitor) garantizan ese `root_id` (fresco si no llega header), por eso `source` (mandatorio) nunca falta en una linea originada por un entrypoint. `request_id` se emite **fuera** del guard de `root_id` — distinto ciclo de vida.

| Campo | Condicion de emision | Entrypoint que la garantiza |
|:------|:---------------------|:----------------------------|
| `time`, `level`, `severity_number`, `service`, `service_version`, `deployment_environment` | Siempre (no depende de Tracer/Current) | — |
| `request_id` | `Tracer.request_id` presente. **Fuera del guard de `root_id`** (issue #9 Gap C): distinto ciclo de vida (UUID v4 de Rails vs formato X-Ray). | HTTP (via `ActionDispatch::RequestId`). Otros entrypoints solo si la app lo setea explicitamente. |
| `root_id` | `Tracer.root_id` presente. **Gatea todo el bloque de tracer context.** | Los 4 entrypoints garantizan `root_id` fresco si no llega trace header (issue #9 Gap A). |
| `source` | `Tracer.source` presente **y** `root_id` presente (esta dentro del bloque gateado). | Idem `root_id`. Como `source` es mandatorio del estandar Wispro, la invariante "todo entrypoint garantiza `root_id`" es lo que evita que falte. |
| `trace_id` | `Tracer.trace_id` presente **y** `root_id` presente. Solo cuando el servicio es **eslabon intermedio** (recibio trace header upstream). | — (entrypoint que no recibe header tiene `root_id` fresco pero `trace_id` nil). |
| `sidekiq_job` | `Tracer.sidekiq_job` presente **y** `root_id` presente. | Sidekiq `ServerMiddleware`. |
| `task` | `Tracer.task` presente **y** `root_id` presente. | `TaskMonitor.run`. |
| `correlation_id` | `Current.correlation_id` presente. | `ExisRay.sync_correlation_id` (HTTP middleware lo llama; otros entrypoints solo si la app lo invoca). |
| `user_id`, `isp_id` | `Current.<attr>` no nil. | Lo setea la app (login, before_actions, etc.). |
| `Current.log_fields` (cualquier key) | La subclass de `Current` overrideo el hook y retorno un Hash no vacio. | — |
| `tags` | Rails tagged logging activo. **Antipatron con JSON** (rompe el formato) — ver FAQ. | — |

Para el detalle por entrypoint (que setea que y cuando), ver [`docs/behavior/behavior.md`](../docs/behavior/behavior.md). Para el significado de cada campo, [`docs/glossary/glossary.md`](../docs/glossary/glossary.md).

#### Ejemplos: KV vs Hash producen output equivalente

```ruby
# KV string — one-liner rapido
Rails.logger.info("component=billing event=invoice_paid invoice_id=42 total=199.99")

# Hash style — payloads complejos / nested
Rails.logger.info(component: "billing", event: "invoice_paid",
                  invoice: { id: 42, total: 199.99 })

# String libre — fallback, va a `body`
Rails.logger.info("usuario hizo click")
```

#### Output JSON resultante (mismo para KV y Hash del ejemplo)

```json
{"time":"2026-05-11T09:15:00.123Z","level":"INFO","severity_number":9,"service":"box_radius_manager","service_version":"1.2.3","deployment_environment":"production","root_id":"1-abc","trace_id":"Root=1-abc;Self=...","source":"http","user_id":42,"isp_id":10,"correlation_id":"box_radius_manager;1-abc","component":"billing","event":"invoice_paid","invoice_id":42,"total":199.99}
```

Los campos hasta `correlation_id` los inyecta el formatter automaticamente. De `component` en adelante son los campos del mensaje del developer.

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
