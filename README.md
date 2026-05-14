# ExisRay

Capa de observabilidad y trazabilidad distribuida para microservicios Rails del ecosistema Wispro. Unifica tracing (AWS X-Ray compatible), logging JSON estructurado, propagación de contexto de negocio y reporte de errores en una sola gema.

## Features

- **Distributed Tracing** — Parseo, generación y propagación automática de headers `X-Amzn-Trace-Id`.
- **Structured JSON Logging** — Logs HTTP, Sidekiq y Rake en formato JSON single-line con contexto inyectado.
- **Context Propagation** — `user_id`, `isp_id` y `correlation_id` viajan automáticamente entre servicios.
- **Error Reporting** — Wrapper de Sentry que enriquece cada evento con trace context e identidad de negocio.
- **Auto-instrumentación** — HTTP, Sidekiq, ActiveResource y BugBunny se configuran automáticamente via Railtie.
- **Compatibilidad** — Ruby >= 2.6, Rails 6, 7 y 8.

## Cómo funciona

ExisRay opera en tres capas que se combinan automáticamente:

```
                          ┌─────────────────────────────────┐
                          │         App Host (Rails)         │
                          │  Current ← user_id, isp_id      │
                          │  Reporter ← Sentry context       │
                          └──────────────┬──────────────────┘
                                         │
              ┌──────────────────────────┼──────────────────────────┐
              │                          │                          │
     ┌────────▼────────┐      ┌─────────▼─────────┐     ┌─────────▼─────────┐
     │  HTTP Request    │      │  Sidekiq Job       │     │  BugBunny Msg     │
     │  HttpMiddleware  │      │  ServerMiddleware   │     │  ConsumerTracing  │
     └────────┬────────┘      └─────────┬─────────┘     └─────────┬─────────┘
              │                          │                          │
              └──────────────────────────┼──────────────────────────┘
                                         │
                                         ▼
                              ┌─────────────────────┐
                              │   ExisRay::Tracer    │
                              │  (CurrentAttributes) │
                              │                      │
                              │  root_id, trace_id,  │
                              │  source, self_id,    │
                              │  called_from,        │
                              │  total_time_so_far   │
                              └──────────┬──────────┘
                                         │
                         ┌───────────────┼───────────────┐
                         │               │               │
                         ▼               ▼               ▼
                   JsonFormatter    FaradayMiddleware  PublisherTracing
                   (logs + context) (HTTP saliente)   (RabbitMQ saliente)
```

**Flujo de propagación:**

1. Un request/job/mensaje llega al servicio. El middleware correspondiente hidrata el `Tracer` con el header entrante (o genera un nuevo `root_id` si no trae uno).
2. `JsonFormatter` inyecta automáticamente `root_id`, `trace_id`, `source` y el contexto de negocio (`user_id`, `isp_id`, `correlation_id`) en cada línea de log.
3. Cuando el servicio llama a otro servicio (HTTP, Sidekiq, RabbitMQ), el middleware de salida genera un nuevo header con `Tracer.generate_trace_header`, que incluye el `root_id` original, el `self_id` del servicio actual, el `CalledFrom` y el tiempo acumulado.
4. El servicio destino repite desde el paso 1. El `root_id` se mantiene constante a lo largo de toda la cadena.

## Instalación

```ruby
gem "exis_ray"
```

## Quick Start

Configuración mínima para un servicio Rails nuevo:

```ruby
# 1. Configurar ExisRay (config/initializers/exis_ray.rb)
ExisRay.configure do |config|
  config.log_format     = Rails.env.production? ? :json : :text
  config.current_class  = "Current"
  config.reporter_class = "Reporter"
end

# 2. Crear Current (app/models/current.rb)
class Current < ExisRay::Current
  # ExisRay provee: user_id, isp_id, correlation_id
  # Agregar atributos específicos de la app:
  attribute :permissions
end

# 3. Crear Reporter (app/models/reporter.rb)
class Reporter < ExisRay::Reporter
end

# 4. Hidratar el Current en cada request (app/controllers/application_controller.rb)
class ApplicationController < ActionController::Base
  before_action :set_context

  private

  def set_context
    Current.user = current_user if current_user
    Current.isp_id = request.headers["X-Isp-Id"]
  end
end
```

Con esto, ExisRay auto-instrumenta HTTP y Sidekiq (si está presente). Los logs en producción salen en JSON con trace context completo.

## Configuración

```ruby
# config/initializers/exis_ray.rb
ExisRay.configure do |config|
  # Header entrante (formato Rack). Default: "HTTP_X_AMZN_TRACE_ID"
  config.trace_header = "HTTP_X_AMZN_TRACE_ID"

  # Header saliente (formato HTTP). Default: "X-Amzn-Trace-Id"
  config.propagation_trace_header = "X-Amzn-Trace-Id"

  # Clases de la app host (strings para evitar problemas de autoloading)
  config.current_class  = "Current"    # hereda de ExisRay::Current
  config.reporter_class = "Reporter"   # hereda de ExisRay::Reporter

  # Formato de logs: :text (default) o :json
  config.log_format = Rails.env.production? ? :json : :text

  # Subclase de LogSubscriber para campos HTTP extra (opcional)
  # config.log_subscriber_class = "MyLogSubscriber"

  # Campos fijos por proceso inyectados en cada log (opcional).
  # Útil para servicios multi-tenant. El hash se filtra (claves sensibles → [FILTERED])
  # y se congela al setear, así que el cost por log line es despreciable.
  # config.global_fields = {
  #   tenant_id: ENV.fetch("TENANT_ID"),
  #   service_id: ENV.fetch("SERVICE_ID"),
  #   stack_id: ENV.fetch("STACK_ID")
  # }
end
```

### Precedencia de `global_fields`

`global_fields` se mergea **antes** que el contexto del Tracer/Current y el cuerpo del mensaje. Esto significa:

- Los campos canónicos (`service`, `trace_id`, `root_id`, `user_id`, etc.) **pisan** `global_fields` si hay colisión: no podés usarlo para overrideear esos campos, solo para agregar nuevos.
- Las keys que aparezcan en el mensaje del developer (ej. `Rails.logger.info "tenant_id=99"`) **pisan** `global_fields` por call site, permitiendo override puntual.

## Clases de la App Host

### Current (contexto de negocio)

`ExisRay::Current` extiende `ActiveSupport::CurrentAttributes` y provee tres atributos base: `user_id`, `isp_id` y `correlation_id`. Al asignarlos, propaga automáticamente a PaperTrail (`whodunnit`), ActiveResource (headers) y Reporter (tags de Sentry).

```ruby
# app/models/current.rb
class Current < ExisRay::Current
  # Atributos heredados: user_id, isp_id, correlation_id
  # Helpers heredados: user, user=, isp, isp=, user?, isp?, correlation_id?
  #
  # Agregar atributos específicos de la app:
  attribute :permissions
end
```

**Helpers disponibles:**

| Método | Descripción |
|:-------|:------------|
| `Current.user = object` | Asigna `user_id` desde `object.id` |
| `Current.user` | Lazy-loads `::User.find_by(id: user_id)` (cacheado por request) |
| `Current.isp = object` | Asigna `isp_id` desde `object.id` |
| `Current.isp` | Lazy-loads `::Isp.find_by(id: isp_id)` (cacheado por request) |
| `Current.user?` / `Current.isp?` | Predicate: true si el ID no es nil |
| `Current.correlation_id?` | Predicate: true si está presente (no vacío) |

### Reporter (reporte de errores)

`ExisRay::Reporter` es un wrapper de Sentry que enriquece automáticamente cada evento con el trace context del `Tracer` y el contexto de negocio del `Current`. Soporta Sentry SDK moderno y legacy (Raven/Session).

```ruby
# app/models/reporter.rb
class Reporter < ExisRay::Reporter
  # Hook opcional para contexto adicional en Sentry
  def self.build_custom_context
    add_tags(plan: ExisRay.current_class.isp&.plan)
  end

  # Hook opcional para controlar qué datos del usuario se envían a Sentry.
  # Default: solo { id: current.user_id }
  def self.sentry_user_context(current)
    { id: current.user_id, email: current.user&.email }
  end
end
```

**API pública:**

```ruby
# Reportar un mensaje
Reporter.report("algo inesperado", context: { order_id: 123 }, tags: { severity: "high" })

# Reportar una excepción
Reporter.exception(error, context: { order_id: 123 }, fingerprint: ["order-failure"])

# Acumular contexto durante el request (se envía con el próximo report/exception)
Reporter.add_context(order: { id: 123, total: 500 })
Reporter.add_tags(feature: "checkout")
Reporter.add_fingerprint("checkout-error")
```

## Integraciones

### HTTP (automático)

El Railtie inserta `ExisRay::HttpMiddleware` después de `ActionDispatch::RequestId`. Hidrata el Tracer con el header entrante y sincroniza el `correlation_id` en cada request. No requiere configuración.

### Sidekiq (automático)

El Railtie registra client y server middleware. El trace context se propaga automáticamente entre enqueuer y worker. El `JsonFormatter` se aplica al logger de Sidekiq si `json_logs?` está activo. No requiere cambios en los workers.

### BugBunny — Publisher (manual)

Agregar `PublisherTracing` al middleware stack del cliente:

```ruby
# BugBunny::Client
client = BugBunny::Client.new(pool: pool) do |stack|
  stack.use ExisRay::BugBunny::PublisherTracing
end

# BugBunny::Resource (se hereda a subclases)
class ApplicationResource < BugBunny::Resource
  client_middleware do |stack|
    stack.use ExisRay::BugBunny::PublisherTracing
  end
end
```

### BugBunny — Consumer (automático)

El Railtie registra `ConsumerTracingMiddleware` en el consumer middleware stack, más los hooks RPC (`rpc_reply_headers` y `on_rpc_reply`) para propagación completa en llamadas síncronas.

### Faraday (manual)

```ruby
conn = Faraday.new(url: "https://api.internal") do |f|
  f.use ExisRay::FaradayMiddleware
end
```

### ActiveResource (automático)

El Railtie prepend `ActiveResourceInstrumentation` a `ActiveResource::Base`. Inyecta el `propagation_trace_header` en cada request saliente.

### TaskMonitor (Rake/Cron)

Genera un contexto de trazabilidad para tareas que no tienen request HTTP entrante:

```ruby
task generate_invoices: :environment do
  ExisRay::TaskMonitor.run("billing:generate_invoices") do
    InvoiceService.process_all
  end
end
```

`TaskMonitor` genera un `root_id` nuevo, configura Reporter y Current, loguea `task_started`/`task_finished` con `duration_s` y `outcome`, y limpia el contexto al finalizar. Si el bloque lanza una excepción, la registra como `outcome=failed` con `exception.type`, `exception.message` y `exception.stacktrace` (OTel) y la re-lanza.

## JSON Logging

Con `log_format: :json`, `ExisRay::JsonFormatter` reemplaza el formatter de Rails y emite cada línea como JSON single-line con contexto inyectado automáticamente:

```json
{"time":"2026-04-01T14:30:00Z","level":"INFO","severity_number":9,"service":"wispro_agent","service_version":"1.2.3","deployment_environment":"production","root_id":"1-65f...abc","trace_id":"Root=1-65f...;Self=...","source":"http","user_id":42,"isp_id":10,"component":"exis_ray","event":"http_request","method":"GET","path":"/api/v1/users","http_route":"/api/v1/users","http_status":200,"duration_s":0.0452,"user_agent_original":"Mozilla/5.0","server_address":"api.example.com"}
```

El formatter acepta tres tipos de mensaje. Los tres producen output JSON equivalente; elegí el que sea más legible para tu caso:

```ruby
# 1. String KV — one-liner rápido, valores numéricos se castean
Rails.logger.info "component=billing event=invoice_created invoice_id=123 total=45.50"

# 2. Hash style — payloads complejos o con valores nested
Rails.logger.info(component: "billing", event: "invoice_created",
                  invoice: { id: 123, total: 45.50 })

# 3. String libre — fallback, va a la clave `body`
Rails.logger.info "Algo pasó sin formato KV"
# => {"time":"...","level":"INFO","service":"...","body":"Algo pasó sin formato KV"}
```

Los mensajes Hash también son la forma que usa internamente `LogSubscriber` para emitir el cierre de cada request HTTP.

> **Nota:** `component` (módulo de negocio) y `event` (qué pasó) **no** son auto-inyectados — los aporta el call site. El formatter solo conoce el contexto de **ejecución** (quién, de dónde, con qué identidad), no el contexto del **lugar del código** que loguea.

En modo `:text`, ExisRay inyecta el `trace_id` o `root_id` como tag de Rails (`config.log_tags`) y no modifica el formatter.

### Configuración del logger en producción

Para logs JSON limpios sin códigos ANSI ni texto extra, configurar el logger así:

```ruby
# config/environments/production.rb
config.colorize_logging = false
config.logger = ActiveSupport::Logger.new(STDOUT)
config.logger.formatter = ExisRay::JsonFormatter
```

**No usar `ActiveSupport::TaggedLogging`** — agrega tags como texto al inicio de cada línea antes del formatter, lo cual rompe el JSON:

```
[request_id] {"time":"...","level":"INFO",...}   # ← texto antes del JSON (INVALIDO)
```

`ExisRay::JsonFormatter` ya inyecta los tags (`request_id`, `trace_id`, etc.) como campos JSON, así que `TaggedLogging` es redundante e incompatible.

### Campos auto-inyectados

`JsonFormatter` inyecta estos campos automáticamente en cada línea. **Nunca** los incluyas manualmente en tus logs:

| Campo | Condición |
|:------|:----------|
| `time` | Siempre (UTC ISO 8601) |
| `level` | Siempre |
| `severity_number` | Siempre (OTel SeverityNumber: DEBUG=5, INFO=9, WARN=13, ERROR=17, FATAL=21) |
| `service` | Siempre (nombre de la app Rails en snake_case) |
| `service_version` | Siempre (lee de `config.version` o `config.x.version`) |
| `deployment_environment` | Siempre (lee de `Rails.env`) |
| `config.global_fields` (cualquier key) | Si `config.global_fields` no está vacío |
| `root_id` | Cuando hay trace context activo |
| `trace_id` | Cuando hay trace context activo |
| `source` | Cuando hay trace context activo (`http`, `sidekiq`, `task`, `system`) |
| `correlation_id` | Cuando `Current.correlation_id` está presente |
| `user_id` | Cuando `Current.user_id` no es nil |
| `isp_id` | Cuando `Current.isp_id` no es nil |
| `sidekiq_job` | Solo en procesos Sidekiq |
| `task` | Solo en procesos TaskMonitor |
| `tags` | Solo si hay Rails tagged logging activo |

`LogSubscriber` inyecta además estos campos en cada log de cierre de request HTTP. **Nunca duplicarlos** en logs manuales:

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
| `http_status` | Integer | Status HTTP final. Antes `status`, renombrado en v0.6.0 |
| `duration_s` | Float | Segundos (Rails reporta ms, se convierte), redondeo 4 decimales |
| `duration_human` | String | Legible: `"42.5ms"`, `"1.25s"`, `"2 minutes 5 seconds"` |
| `view_runtime_s` | Float\|nil | Solo si Rails lo reporta |
| `db_runtime_s` | Float\|nil | Solo si ActiveRecord lo reporta |
| `user_agent_original` | String | Header `User-Agent` |
| `server_address` | String | Hostname sin puerto del header `Host` |
| `error_class`, `error_message` | String | Solo en fallo (legacy) |
| `exception.type`, `exception.message`, `exception.stacktrace` | String | Solo en fallo (OTel; stack limitado a 20 líneas) |

Severity del log: `ERROR` si `http_status >= 500`, sino `INFO`.

### Filtrado de claves sensibles

Las claves que matcheen `/password|pass|passwd|secret|token|api_key|auth/i` se reemplazan automáticamente por `[FILTERED]`, tanto en strings KV como en Hashes (incluyendo anidados).

### LogSubscriber custom

Para inyectar campos extra en los logs de requests HTTP, crear una subclase de `ExisRay::LogSubscriber`:

```ruby
# app/subscribers/my_log_subscriber.rb
class MyLogSubscriber < ExisRay::LogSubscriber
  def self.extra_fields(event)
    { user_agent: event.payload[:headers]["HTTP_USER_AGENT"] }
  end
end

# config/initializers/exis_ray.rb
ExisRay.configure do |config|
  config.log_subscriber_class = "MyLogSubscriber"
end
```

## Referencia del Tracer

`ExisRay::Tracer` es el componente central. Extiende `ActiveSupport::CurrentAttributes` para thread-safety y se resetea automáticamente al final de cada request/job.

### Atributos

| Atributo | Tipo | Descripción |
|:---------|:-----|:------------|
| `trace_id` | `String` | Header completo parseado (`Root=...;Self=...;CalledFrom=...`) |
| `root_id` | `String` | ID raíz, constante a lo largo de toda la cadena de servicios |
| `self_id` | `String` | ID del span del servicio que generó el header |
| `called_from` | `String` | Nombre del servicio que envió el request |
| `total_time_so_far` | `Integer` | Tiempo acumulado en ms desde el inicio de la cadena |
| `source` | `String` | Entrypoint: `http`, `sidekiq`, `task`, `system` |
| `request_id` | `String` | UUID del request (Rails `ActionDispatch::RequestId`) |
| `created_at` | `Float` | Timestamp monotónico del inicio del contexto |
| `sidekiq_job` | `String` | Nombre del job Sidekiq (solo en workers) |
| `task` | `String` | Nombre de la tarea (solo en TaskMonitor) |

### Métodos públicos

```ruby
# Hidratar el Tracer (usado internamente por los middlewares)
ExisRay::Tracer.hydrate(trace_id: header_string, source: "http")

# Generar header de propagación para el siguiente servicio
ExisRay::Tracer.generate_trace_header
# => "Root=1-abc123-...;Self=1-def456-...;CalledFrom=wispro_agent;TotalTimeSoFar=42ms"

# Duración del request actual
ExisRay::Tracer.current_duration_s   # => 0.0452 (Float, segundos)
ExisRay::Tracer.current_duration_ms  # => 45 (Integer, milisegundos)

# Formatear duración human-readable
ExisRay::Tracer.format_duration(0.007)   # => "7.0ms"
ExisRay::Tracer.format_duration(1.25)    # => "1.25s"
ExisRay::Tracer.format_duration(125.0)   # => "2 minutes 5 seconds"

# Nombre del servicio (snake_case del module parent de la app Rails)
ExisRay::Tracer.service_name  # => "wispro_agent"

# Correlation ID compuesto
ExisRay::Tracer.correlation_id  # => "wispro_agent;1-65f...abc"

# Sincronizar correlation_id al Current configurado
ExisRay.sync_correlation_id
```

## Licencia

Disponible como open source bajo los términos de la [MIT License](https://opensource.org/licenses/MIT).
