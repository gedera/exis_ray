# Configuración — exis_ray

> meta: artefacto · RFC-012 (12-Factor App §III, shape v2.2) · generado arch-structure · anclado a commit `7db39ca` (v0.11.0) · cobertura **inventario base completa · enriquecimiento §f pendiente (`—` sembrado)**

## 1. Resumen

Gema de tracing/observabilidad. Configuración pública vía `ExisRay.configure do |config| ... end` (clase `ExisRay::Configuration`, 10 opciones con defaults compatibles AWS X-Ray) + 1 env var de runtime (`HOSTNAME`). Sin scheduler propio; el `Railtie` inyecta middlewares, formatter de logs e instrumentación de Sidekiq/BugBunny/ActiveResource al host durante el boot.

## 2. Cuerpo

### §a Hecho verificable

| métrica | conteo |
|---|---|
| total vars/opciones | 11 |
| requeridas | 0 |
| con default | 11 |
| derivadas | 2 |
| secretas | 0 |

### §b Inventario base

| nombre | tipo | requerida | default | origen | consumidor (file:line) | secret? |
|---|---|---|---|---|---|---|
| `trace_header` | String | no | `"HTTP_X_AMZN_TRACE_ID"` | code-default | `configuration.rb:76` | no |
| `propagation_trace_header` | String | no | `"X-Amzn-Trace-Id"` | code-default | `configuration.rb:77` | no |
| `reporter_class` | String/Class/nil | no | `nil` | code-default | `configuration.rb:78` | no |
| `current_class` | String/Class/nil | no | `nil` | code-default | `configuration.rb:79` | no |
| `log_format` | Symbol | no | `:text` | code-default | `configuration.rb:80` | no |
| `log_subscriber_class` | String/nil | no | `nil` | code-default | `configuration.rb:81` | no |
| `service_version` | String/nil | no | `derived(Rails config.version ∥ config.x.version)` | derived | `configuration.rb:82,93-111` | no |
| `deployment_environment` | String/nil | no | `derived(Rails.env)` | derived | `configuration.rb:83,113-117` | no |
| `emit_legacy_exception_keys` | Boolean | no | `true` | code-default | `configuration.rb:84` | no |
| `emit_legacy_path_key` | Boolean | no | `true` | code-default | `configuration.rb:85` | no |
| `HOSTNAME` | String | no | `"local"` (fallback) | env | `task_monitor.rb:81` | no |

> Solo shape — sin valores reales (RFC-012 §3). `requerida=no` en las 10 opciones: el `initialize` siembra default a todas; `HOSTNAME` cae a `"local"` si ausente.

### §c Meta-templates

`n/a` — sin patrón de sufijo/prefijo repetido ≥3 (no hay service discovery estática `_HOST/_PORT/_PROTOCOL`).

### §d Derivaciones simples

| var derivada | fórmula | fuente |
|---|---|---|
| `service_version` | `Rails.application.config.version` → fallback `config.x.version` → `nil` | `configuration.rb:93-111` |
| `deployment_environment` | `Rails.env.to_s` | `configuration.rb:113-117` |
| `pod_id` (no-config) | `(ENV["HOSTNAME"] ∥ "local").split("-").last` | `task_monitor.rb:81` |

### §e Scheduling

`n/a` — la gema no define `sidekiq.yml`/`queue.yml`/`recurring.yml` ni queues/cron propios. **Instrumenta** el Sidekiq del host (middlewares) pero no agenda trabajo — ver §i.

### §i Inyecciones al host (Railtie)

| inyección | gatillo | efecto | file:line |
|---|---|---|---|
| `exis_ray.configure_middleware` | initializer | inserta `ExisRay::HttpMiddleware` after `ActionDispatch::RequestId` (fallback `use`) | `railtie.rb:14-23` |
| `exis_ray.configure_logging` | initializer (after `:load_config_initializers`) | en modo texto: `app.config.log_tags << proc { trace_id ∥ root_id }` | `railtie.rb:28-36` |
| validación de clases | `config.after_initialize` | `raise` si `current_class`/`reporter_class` no heredan de base | `railtie.rb:45-53` |
| formatter JSON global | `config.after_initialize` (modo json) | `Rails.logger.formatter = ExisRay::JsonFormatter.new` | `railtie.rb:57` |
| LogSubscriber HTTP | `config.after_initialize` (modo json) | `ExisRay::LogSubscriber.install!` (reemplaza Lograge/defaults Rails) | `railtie.rb:62` |
| instrumentación BugBunny | `config.after_initialize` (si `defined?(::BugBunny)`) | consumer middleware + `rpc_reply_headers` + `on_rpc_reply` | `railtie.rb:68-90` |
| instrumentación ActiveResource | `config.after_initialize` (si `defined?(ActiveResource::Base)`) | `prepend ExisRay::ActiveResourceInstrumentation` | `railtie.rb:93-99` |
| instrumentación Sidekiq | `config.after_initialize` (si `defined?(::Sidekiq)`) | client/server middleware + `Sidekiq.logger.formatter` (modo json) | `railtie.rb:102-123` |

### §j Inyección a gemas configuradas (lista — mapeo → arch-enrich)

| gema configurada | superficie tocada | file:line | mapeo opción |
|---|---|---|---|
| `::BugBunny` | `consumer_middlewares.use`, `configuration.rpc_reply_headers`, `configuration.on_rpc_reply` | `railtie.rb:71-88` | — |
| `::Sidekiq` | `configure_client` / `configure_server` (client+server middleware chains) | `railtie.rb:106-119` | — |

### §f Enriquecimiento semántico

`—` (pendiente arch-enrich): `categoría · failure-mode · side-effect · scope-override · business-reason` por opción, threading (§h), ramificadores intra-config (§g), y el mapeo opción→gema de §j.

## 3. Inferencias

| ítem | confidence | a verificar |
|---|---|---|
| `HOSTNAME` clasificada `requerida=no` | declared | fallback `"local"` explícito en `task_monitor.rb:81` — confirmado |
| `service_version`/`deployment_environment` como `derived` | declared | defaults computados en `initialize` vía `default_*` — confirmado |
| sin secretos | declared | ninguna opción matchea `*_KEY|*_SECRET|*_PASS|*_TOKEN` ni literal sensible — confirmado |
| `reporter_class`/`current_class` aceptan String o Class | declared | YARD `@return [String, Class, nil]`; el `safe_constantize` del Railtie asume String — verificar uso real |

## 4. Cobertura y fronteras

- **Inventario base completo** para v0.11.0 — las 11 vars/opciones del código están listadas.
- **Enriquecimiento §f pendiente** — significado de negocio, failure-mode y side-effects los completa `arch-enrich` (régimen incremental).
- **Mapeo §j → gema** sembrado `—`: qué opción de BugBunny/Sidekiq se setea exactamente lo resuelve `arch-enrich`.
- **Fuera de alcance:** `ENV["TENANT_ID"]` en `current.rb:22` es **ejemplo en comentario YARD** (no consumo real) → no se lista. Vars de Rails core (`SECRET_KEY_BASE`, `RAILS_ENV`, etc.) las aporta la app host, no esta gema.
- **`config.x.version`** (lectura de `service_version`) depende del host — la gema solo lee, no define.
