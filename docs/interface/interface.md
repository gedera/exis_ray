# Interfaz — exis_ray

> meta: artefacto · RFC-004 (RBS firmas como modelo conceptual) · generado arch-structure · anclado a commit `b7b96c7` (v0.11.0) · cobertura **superficie pública consumer-facing completa**

## 1. Resumen

API Ruby pública de la gema: módulo `ExisRay` (config + resolución de clases host), 2 bases abstractas que el host subclasea (`Current`, `Reporter`), el contexto de trazabilidad (`Tracer`), el formatter/subscriber de logs, el monitor de tasks, y 7 middlewares de propagación (HTTP/Faraday/ActiveResource/Sidekiq×2/BugBunny×2). Las clases configurables (`Configuration`) se documentan en detalle en [`docs/config/configuracion.md`](../config/configuracion.md).

## 2. Superficie pública (símbolo · tipo · firma · nota)

### `ExisRay` (módulo raíz)

| símbolo | tipo | firma | nota |
|---|---|---|---|
| `ExisRay::VERSION` | const | `String` | `"0.11.0"` (`version.rb:5`) |
| `ExisRay::Error` | class | `< StandardError` | error base de la gema (`exis_ray.rb:36`) |
| `ExisRay.configure` | method | `() { (Configuration) -> void } -> void` | bloque de configuración (`exis_ray.rb:60`) |
| `ExisRay.configuration` | method | `() -> Configuration` | instancia singleton (`exis_ray.rb:46`) |
| `ExisRay.configuration=` | writer | `(Configuration) -> void` | reemplaza la config — uso en tests (`exis_ray.rb:40`) |
| `ExisRay.current_class` | method | `() -> Class?` | resuelve `config.current_class`; memoizado en prod, re-resuelto en dev (`exis_ray.rb:71`) |
| `ExisRay.reporter_class` | method | `() -> Class?` | resuelve `config.reporter_class` (`exis_ray.rb:88`) |
| `ExisRay.sync_correlation_id` | method | `() -> void` | copia `Tracer.correlation_id` → `Current.correlation_id` (`exis_ray.rb:105`) |

### `ExisRay::Configuration` (clase)

| símbolo | tipo | firma | nota |
|---|---|---|---|
| `Configuration#<attr>` | accessor (rw) | — | 10 opciones (`trace_header`, `log_format`, `current_class`, ...) — inventario y semántica en [`docs/config/`](../config/configuracion.md) |
| `Configuration#json_logs?` | method | `() -> bool` | `true` si `log_format == :json` (`configuration.rb:122`) |

### `ExisRay::Tracer` (`< ActiveSupport::CurrentAttributes`)

| símbolo | tipo | firma | nota |
|---|---|---|---|
| `Tracer.<attr>` | accessor (rw) | — | `trace_id · request_id · root_id · self_id · called_from · total_time_so_far · created_at · sidekiq_job · source · task` (`tracer.rb:15`) |
| `Tracer.hydrate` | method | `(trace_id:, source:) -> void` | inicializa el contexto desde header entrante (`tracer.rb:78`) |
| `Tracer.generate_trace_header` | method | `() -> String` | header para propagar al siguiente servicio (`tracer.rb:115`) |
| `Tracer.parse_trace_id` | method | `() -> void` | extrae `root_id`/`self_id`/`called_from`/`total_time_so_far` del `trace_id` (`tracer.rb:40`) |
| `Tracer.service_name` | method | `() -> String` | nombre del servicio (de `Rails.application`) (`tracer.rb:22`) |
| `Tracer.correlation_id` | method | `() -> String` | compuesto `service_name;root_id` (`tracer.rb:32`) |
| `Tracer.current_duration_s` | method | `() -> Float` | segundos desde `created_at` (monotónico) (`tracer.rb:89`) |
| `Tracer.current_duration_ms` | method | `() -> Integer` | milisegundos desde `created_at` (`tracer.rb:67`) |
| `Tracer.format_duration` | method | `(Float seconds) -> String` | formato humano (`"7.0ms"`, `"2 minutes 5 seconds"`) (`tracer.rb:102`) |

### `ExisRay::Current` (`< ActiveSupport::CurrentAttributes`, base abstracta — el host subclasea)

| símbolo | tipo | firma | nota |
|---|---|---|---|
| `Current.<attr>` | accessor (rw) | — | `user_id · isp_id · correlation_id` (`current.rb:9`) |
| `Current.user_id=` | setter | `(Integer?) -> void` | usa `!nil?` (acepta `0`) + sincroniza PaperTrail/ActiveResource (`current.rb:54`) |
| `Current.isp_id=` | setter | `(Integer?) -> void` | ídem (`current.rb:63`) |
| `Current.correlation_id=` | setter | `(String?) -> void` | propaga a Session/Reporter (`current.rb:71`) |
| `Current.user=` / `Current.user` | accessor | `(obj) -> void` / `() -> User?` | asigna `user_id` de `obj.id` / lazy-load memoizado (`current.rb:84,88`) |
| `Current.isp=` / `Current.isp` | accessor | `(obj) -> void` / `() -> Isp?` | ídem (`current.rb:95,99`) |
| `Current.user?` / `Current.isp?` | predicate | `() -> bool` | true si el id `!nil?` (`current.rb:106,110`) |
| `Current.correlation_id?` | predicate | `() -> bool` | true si `present?` (`current.rb:116`) |
| `Current.log_fields` | hook | `() -> Hash` | **override** para inyectar campos custom en cada log; default `{}` (`current.rb:31`) |

### `ExisRay::Reporter` (`< ActiveSupport::CurrentAttributes`, base abstracta — el host subclasea)

| símbolo | tipo | firma | nota |
|---|---|---|---|
| `Reporter.report` | method | `(String message, context: {}, tags: {}, fingerprint: [], transaction_name: nil) -> void` | reporta mensaje a Sentry (`reporter.rb:24`) |
| `Reporter.exception` | method | `(Exception excep, context: {}, tags: {}, fingerprint: [], transaction_name: nil) -> void` | reporta excepción (`reporter.rb:33`) |
| `Reporter.add_context` | method | `(Hash attrs) -> void` | acumula contexto (`reporter.rb:58`) |
| `Reporter.add_tags` | method | `(Hash attrs) -> void` | acumula tags (`reporter.rb:64`) |
| `Reporter.add_fingerprint` | method | `(value) -> void` | acumula fingerprint (`reporter.rb:52`) |
| `Reporter.build_custom_context` | hook | `() -> void` | **override** para contexto específico del servicio (`reporter.rb:70`) |
| `Reporter.sentry_user_context` | hook | `(current) -> Hash` | **override**; default `{ id: user_id }` (`reporter.rb:196`) |
| `Reporter.sentry_isp_context` | hook | `(current) -> Hash` | **override** (`reporter.rb:205`) |

### `ExisRay::JsonFormatter` (`< ::Logger::Formatter`)

| símbolo | tipo | firma | nota |
|---|---|---|---|
| `JsonFormatter#call` | method | `(severity, timestamp, progname, msg) -> String` | interfaz `Logger::Formatter`; emite JSON single-line con contexto inyectado (`json_formatter.rb:49`) |

### `ExisRay::LogSubscriber` (`< ActiveSupport::LogSubscriber`)

| símbolo | tipo | firma | nota |
|---|---|---|---|
| `LogSubscriber.install!` | method | `() -> void` | suscribe y suprime los subscribers default de Rails (`log_subscriber.rb:68`) |
| `LogSubscriber.attached?` | method | `() -> bool` | si ya está instalado (`log_subscriber.rb:76`) |
| `LogSubscriber.extra_fields` | hook | `(event) -> Hash` | **override** para campos HTTP extra; default `{}` (`log_subscriber.rb:58`) |
| `LogSubscriber#process_action` | method | `(event) -> void` | interfaz subscriber; emite el log de cierre de request (`log_subscriber.rb:33`) |

### `ExisRay::TaskMonitor` (módulo)

| símbolo | tipo | firma | nota |
|---|---|---|---|
| `TaskMonitor.run` | method | `(String task_name) { () -> void } -> void` | genera `root_id`, loguea `task_started`/`task_finished`, re-lanza excepciones, resetea contexto (`task_monitor.rb:16`) |

### Middlewares de propagación

| símbolo | tipo | firma | nota |
|---|---|---|---|
| `ExisRay::HttpMiddleware` | class (Rack) | `#initialize(app)` · `#call(env) -> Array` | auto-insertado tras `ActionDispatch::RequestId` (`http_middleware.rb`) |
| `ExisRay::FaradayMiddleware` | class (`< Faraday::Middleware`) | `#call(env)` | **manual** en el stack Faraday (`faraday_middleware.rb`) |
| `ExisRay::ActiveResourceInstrumentation` | module (prepend) | `#headers -> Hash` | auto-prepend a `ActiveResource::Base` (`active_resource_instrumentation.rb`) |
| `ExisRay::Sidekiq::ClientMiddleware` | class | `#call(worker_class, job, queue, redis_pool = nil) { }` | auto-registrado (client) (`sidekiq/client_middleware.rb`) |
| `ExisRay::Sidekiq::ServerMiddleware` | class | `#call(worker, job, queue) { }` | auto-registrado (server) (`sidekiq/server_middleware.rb`) |
| `ExisRay::BugBunny::PublisherTracing` | class (`< ::BugBunny::Middleware::Base`) | `#on_request(env)` | **manual** en el cliente (`bug_bunny/publisher_tracing.rb`) |
| `ExisRay::BugBunny::ConsumerTracingMiddleware` | class (`< ::BugBunny::ConsumerMiddleware::Base`) | `#call(delivery_info, properties, body)` | auto-registrado (consumer) (`bug_bunny/consumer_tracing_middleware.rb`) |

## 3. Inferencias

| ítem | confidence | a verificar |
|---|---|---|
| `Tracer`/`Reporter`/`TaskMonitor` no declaran `private` | declared | métodos helper (`generate_new_root`, `clean_request_id`, `build_from_*`, `*_to_old/new_sentry`, `setup_tracer`, ...) quedan **reachable** Ruby-wise pero NO son contrato — ver §4 (Hyrum's Law) |
| accesores de `Current`/`Tracer`/`Reporter` como métodos de clase | declared | son `ActiveSupport::CurrentAttributes` → los `attribute :x` exponen `.x`/`.x=` a nivel de clase, thread/fiber-local |
| middlewares "manual" vs "auto" | declared | Faraday y BugBunny-publisher requieren registro manual; el resto los inyecta el Railtie (ver `docs/config` §i) |

## 4. Cobertura y fronteras

- **Superficie consumer-facing completa** para v0.11.0 — lo que un host app usa o subclasea.
- **Helpers públicos-Ruby pero NO contrato:** `Tracer.generate_new_root` / `.clean_request_id`; `Reporter.build_from_tracer` / `.build_from_current` / `.*_to_old_sentry` / `.*_to_new_sentry` / `.session_*`; `TaskMonitor.setup_tracer` / `.pod_identifier` / `.log_event` / `.format_*`; helpers privados de `Current` (`assign_session_request_id`, `sync_reporter_correlation_id`, `sanitize_header_value` — sí marcados `private`, `current.rb:120`). Reachable por falta de `private` (salvo Current), pero son detalle de implementación; cambiar su firma no es breaking de contrato.
- **Internos del formatter/subscriber:** los `inject_*`/`extract_*`/`parse_*` de `JsonFormatter` y `LogSubscriber` son privados de implementación — el contrato es `#call` / `#process_action` + los hooks de override.
- **Constantes:** `JsonFormatter::SENSITIVE_KEYS`, `::SEVERITY_NUMBER`, `::KV_DETECT_RE` son detalle interno, no contrato.
- **Configuración:** el shape de `Configuration` (defaults, tipos, failure-modes) vive en [`docs/config/configuracion.md`](../config/configuracion.md) — acá solo se lista la clase y `json_logs?`.
- **Comportamiento runtime** (secuencias de hidratación/emisión) → [`docs/behavior/behavior.md`](../behavior/behavior.md); **significado de términos** → [`docs/glossary/glossary.md`](../glossary/glossary.md).
