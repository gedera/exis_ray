# Configuración — exis_ray

> meta: artefacto · RFC-012 (12-Factor App §III, shape v2.2) · generado arch-structure + arch-enrich · anclado a commit `7db39ca` (v0.11.0) · cobertura **inventario base completa · §f enriquecido 11/11 · §j mapeado 2/2**

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

### §j Inyección a gemas configuradas

| gema configurada | superficie tocada | file:line | mapeo opción local → gema | ancla |
|---|---|---|---|---|
| `::BugBunny` | `consumer_middlewares.use ConsumerTracingMiddleware`; `configuration.rpc_reply_headers`; `configuration.on_rpc_reply` | `railtie.rb:71-88` | `propagation_trace_header` → key del header en `rpc_reply_headers` (`railtie.rb:75`) y lectura en `on_rpc_reply` (`railtie.rb:79`). El middleware/consumer no mapea opción de valor. | **integración opcional** (guard `defined?(::BugBunny)`), **no es dependencia declarada** (ausente de gemspec/Gemfile.lock) → sin ancla cross-repo, no aplica `skills.yml` |
| `::Sidekiq` | `configure_client` / `configure_server` (middleware chains); `Sidekiq.logger.formatter` | `railtie.rb:106-121` | `log_format=:json` (vía `json_logs?`) → `Sidekiq.logger.formatter = ExisRay::JsonFormatter.new` (`railtie.rb:121`). Las chains de middleware no mapean opción de valor. | **integración opcional** (guard `defined?(::Sidekiq)`), no es dependencia declarada → sin `docs/config/` a linkear |

## f. Enriquecimiento semántico

> cobertura: 11/11 vars enriquecidas; ausencia ≠ "no aplica".

### f.1 Propagación de trace context (`*trace_header`)

| var | categoría | failure-mode | side-effect | scope-override | business-reason / definición |
|---|---|---|---|---|---|
| `trace_header` | integration | silent-default (cae al header AWS X-Ray si no se setea) | per-request (leído por request) | boot-only | key del header **Rack entrante** que `HttpMiddleware` lee para hidratar el Tracer (`http_middleware.rb:13`); cambiarla solo si el edge/LB usa otro header de traza |
| `propagation_trace_header` | integration | silent-default | per-request | boot-only | key del header **saliente** que inyectan Faraday/ActiveResource/BugBunny-publisher + RPC reply (`faraday_middleware.rb:20`, `active_resource_instrumentation.rb:31`, `bug_bunny/publisher_tracing.rb:33`, `railtie.rb:75,79`); debe coincidir con el `trace_header` (forma HTTP) del downstream o la cadena se corta |

### f.2 Wiring de clases del host (`*_class`)

| var | categoría | failure-mode | side-effect | scope-override | business-reason / definición |
|---|---|---|---|---|---|
| `current_class` | orchestration | boot-crash @ after-initialize si la clase no hereda de `ExisRay::Current` (`railtie.rb:45-47`); silent-default (`nil` → contexto de negocio no-op) si no existe | restart (prod: memoizado `@current_class_cache`, `exis_ray.rb:78`) · per-request (dev: re-resuelto para Zeitwerk reload, `exis_ray.rb:80`) | boot-only en prod · mutable-singleton en dev | clase del host que provee `user_id`/`isp_id`/`correlation_id`; se pasa como String para evitar `uninitialized constant` en boot |
| `reporter_class` | orchestration | boot-crash @ after-initialize si no hereda de `ExisRay::Reporter` (`railtie.rb:50-52`); silent-default (`nil` → no se reporta a Sentry) | restart · per-request (idem `current_class`, `exis_ray.rb:95-97`) | boot-only en prod · mutable-singleton en dev | clase del host que envía errores a Sentry con trace context; consumida por TaskMonitor/middlewares al rescatar |
| `log_subscriber_class` | observability | silent-default (`nil` → `ExisRay::LogSubscriber` base sin `extra_fields`) | restart (`install!` en after_initialize, `log_subscriber.rb:295`) | boot-only | subclase para inyectar `extra_fields` en el log de cierre HTTP; **solo aplica si `json_logs?`** (ver §g) |

### f.3 Estrategia de logging (`log_format`)

| var | categoría | failure-mode | side-effect | scope-override | business-reason / definición |
|---|---|---|---|---|---|
| `log_format` | observability | silent-default (`:text` → tags de Rails, sin JsonFormatter) | restart (decisión tomada en boot tras `load_config_initializers`, `railtie.rb:28-29`) | boot-only | conmuta **toda** la estrategia: `:json` instala JsonFormatter global + LogSubscriber + formatter de Sidekiq (`railtie.rb:56-65,121`); `:text` solo agrega `root_id` como `log_tag`. **Ramificador** (§g). |

### f.4 Metadata de recurso OTel

| var | categoría | failure-mode | side-effect | scope-override | business-reason / definición |
|---|---|---|---|---|---|
| `service_version` | observability | silent-default (`nil` → campo `service_version` omitido del log) | per-request (emitido por línea, `json_formatter.rb:89`) | boot-only (computado una vez de Rails config) | equivale a `service.version` de OTel |
| `deployment_environment` | observability | silent-default (`nil` → campo omitido) | per-request (`json_formatter.rb:94`) | boot-only (derivado de `Rails.env`) | equivale a `deployment.environment` de OTel |

### f.5 Feature-flags de migración OTel (transitorios)

| var | categoría | failure-mode | side-effect | scope-override | business-reason / definición |
|---|---|---|---|---|---|
| `emit_legacy_exception_keys` | feature-flag | silent-default (`true` → emite `error_class`/`error_message` además de `exception.*`) | per-request en error (`log_subscriber.rb:156`, `task_monitor.rb:138`) | boot-only | flag transitorio ventana OTel v1.0. **Ramp:** partial (default `true`). **Cleanup:** cuando dashboards/alertas/queries migren a `exception.*`. Roadmap: default `false` en v0.12.0, removido en v1.0 |
| `emit_legacy_path_key` | feature-flag | silent-default (`true` → emite `path` además de `url.path`) | per-request (`log_subscriber.rb:115`) | boot-only | flag transitorio. **Ramp:** partial. **Cleanup:** cuando consumers migren a `url.path`. Roadmap: default `false` en v0.12.0, removido en v1.0 |

### f.6 Identidad de pod (`HOSTNAME`)

| var | categoría | failure-mode | side-effect | scope-override | business-reason / definición |
|---|---|---|---|---|---|
| `HOSTNAME` | infra | silent-default (`"local"` si ausente) | per-task (leído al generar root en TaskMonitor, `task_monitor.rb:81`) | boot-only (env del contenedor) | sufijo del hostname (post último `-`) como `pod_id` en el `root_id` de tasks; en K8s/Docker lo inyecta el orquestador |

**Threading (§h):** los callbacks RPC de BugBunny (`on_rpc_reply`, `railtie.rb:77-88`) corren en el **thread del publisher** y resuelven `reporter_class`/`current_class` vía los helpers memoizados. `ExisRay::Tracer`/`Current` heredan `ActiveSupport::CurrentAttributes` (thread/fiber-local). Constraint: el valor de config es un singleton global; las clases resueltas se comparten entre threads — safe porque son class objects inmutables tras boot.

**Ramificadores intra-config (§g):**

- `log_format=:json` (vía `json_logs?`) ramifica la aplicabilidad de **`log_subscriber_class`** (inerte en `:text` — `install!` solo corre en modo json) y dispara `JsonFormatter` global + `Sidekiq.logger.formatter` (`railtie.rb:56-65,121`).
- `emit_legacy_exception_keys` / `emit_legacy_path_key` ramifican **qué keys se emiten** en el log, no la aplicabilidad de otras vars.

## 3. Inferencias

| ítem | confidence | a verificar |
|---|---|---|
| `HOSTNAME` clasificada `requerida=no` | declared | fallback `"local"` explícito en `task_monitor.rb:81` — confirmado |
| `service_version`/`deployment_environment` como `derived` | declared | defaults computados en `initialize` vía `default_*` — confirmado |
| sin secretos | declared | ninguna opción matchea `*_KEY|*_SECRET|*_PASS|*_TOKEN` ni literal sensible — confirmado |
| `reporter_class`/`current_class` aceptan String o Class | declared | YARD `@return [String, Class, nil]`; el `safe_constantize` del Railtie asume String — verificar uso real |
| `::BugBunny`/`::Sidekiq` sin ancla cross-repo (§j) | declared | son **integraciones opcionales** (guard `defined?`), no dependencias declaradas (ausentes de gemspec/Gemfile.lock) — la gema inyecta hooks si el host las tiene. Por eso NO van en `skills.yml`: no hay relación de consumo que anclar |
| `scope-override` boot-only vs mutable-singleton de `*_class` (§f.2) | inferred | depende de `cache_classes?` (`exis_ray.rb:118-128`): prod memoiza (boot-only), dev re-resuelve por request (mutable). Verificar que el host no mute `configuration.*_class` post-boot |

## 4. Cobertura y fronteras

- **Inventario base completo** para v0.11.0 — las 11 vars/opciones del código están listadas.
- **Enriquecimiento §f completo 11/11** — categoría · failure-mode · side-effect · scope-override · business-reason por opción, + threading (§h) y ramificadores (§g). Anclado al consumidor real (`file:line`); las inferencias quedan en §3 para verificación humana.
- **Mapeo §j → gema completo 2/2** — `propagation_trace_header`→BugBunny RPC headers; `log_format`→Sidekiq formatter. Ancla cross-repo de BugBunny pendiente (no declarada en `skills.yml`, ver §3).
- **Fuera de alcance:** `ENV["TENANT_ID"]` en `current.rb:22` es **ejemplo en comentario YARD** (no consumo real) → no se lista. Vars de Rails core (`SECRET_KEY_BASE`, `RAILS_ENV`, etc.) las aporta la app host, no esta gema.
- **`config.x.version`** (lectura de `service_version`) depende del host — la gema solo lee, no define.
