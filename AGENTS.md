# ExisRay — Project Intelligence

> Fuente de verdad del repositorio. Reglas, convenciones, estructura, entorno y
> arquitectura viven acá. `CLAUDE.md` queda reservado para notas específicas de
> Claude Code. Si una regla aplica a cualquier agente, vive en este archivo.

## ¿Qué es ExisRay?

ExisRay es la capa de observabilidad y trazabilidad distribuida del ecosistema Wispro. Se integra con Rails para emitir logs estructurados en JSON, propagar trace context entre servicios (HTTP, Sidekiq, RabbitMQ), y mantener identidad de negocio (user_id, isp_id, correlation_id) en cada línea de log.

El estándar de logging que implementa está definido en `skill/SKILL.md` (API, arquitectura, reglas generales) y `skill/references/standard.md` (Data First, mapeo OpenTelemetry, ciclo de vida). Son la fuente de verdad — cualquier duda sobre formato, campos, o semántica de niveles se resuelve ahí.

## Documentación

- **Para humanos**: `docs/` + `README.md`. Ver README para índice.
- **Para agentes AI**: `skill/SKILL.md` + `skill/references/`. Es la skill empaquetada que otros proyectos consumen via `wispro-agent sync`.
- **Nunca referenciar `skill/` desde `docs/` o `README.md`** — son audiencias distintas.

## Mapa de conocimiento (cómo leer la doc de este repo)

- **Tu conocimiento = la UNIÓN de este repo + sus asociados.** No termina en el `docs/<capa>/` local: incluye la doc de los servicios/gemas de `skills.yml`. Un flujo que cruza servicios (e2e) **no vive como doc estática** en ningún repo — se compone on-demand recorriendo el grafo (RFC-021): seguí las anclas hasta los repos asociados y unificá.
- **Entrá por** [`skill/SKILL.md`](skill/SKILL.md) — índice de agente; resume el contrato y linkea el detalle.
- **Cobertura de capas de este repo** (gema de observabilidad, sin DB, instrumenta al host):

  | capa | RFC | estado | artefacto / motivo |
  |---|---|---|---|
  | comportamiento | RFC-007 | **presente** | [`docs/behavior/behavior.md`](docs/behavior/behavior.md) — parcial incremental |
  | glosario | RFC-009 | **presente** | [`docs/glossary/glossary.md`](docs/glossary/glossary.md) — sembrado, acreta |
  | test | RFC-013 | **presente** | [`docs/test/testing.md`](docs/test/testing.md) — piloto RFC-013 |
  | configuración | RFC-012 | **presente** | [`docs/config/configuracion.md`](docs/config/configuracion.md) — inventario base; enriquecimiento §f pendiente |
  | datos | RFC-002 | `n/a` | gema sin DB (sin `db/schema.rb`) |
  | operaciones | RFC-003 | `n/a` | no expone superficie propia (HTTP/CLI/eventos) — instrumenta al host |
  | dependencias consumidas | RFC-018 | `n/a` | inyecta hooks de tracing, no consume servicios |
  | eventos | RFC-005 | `n/a` | no produce eventos propios; propaga trace en mensajes ajenos |
  | interfaz | RFC-004 | **pendiente** | API Ruby pública (`lib/exis_ray/`); contrato hoy embebido en `skill/SKILL.md` (coexistencia transitoria RFC-008 §2) |
  | topología | RFC-006 | **pendiente** | deps + adapters Sidekiq/BugBunny/Faraday/ActiveResource |
  | release | RFC-014 | **pendiente** | `version.rb` + `CHANGELOG.md` + `.github/workflows/release.yml` (tag `v*` → RubyGems) |
  | errores | RFC-020 | **pendiente** | excepciones de validación de config en el Railtie |

- **Navegar una ancla cross-repo:** tomá la key de servicio en `skills.yml` (`services.<dep>.repo`) → ese repo es checkout hermano local o alcanzable por GitHub MCP. La doc de los asociados ES parte de tu conocimiento accesible.

## Convenciones del framework

- Este repo **consume skills del framework** declaradas en `skills.yml` (manifiesto raíz). Ese archivo enumera los MCPs y las skills que el repo trae al contexto del agente.
- Las skills sincronizadas en `.agents/skills/` traen **conocimiento de dependencias**. **Leer la skill de una dependencia ANTES de responder sobre ella.**
- El sync de skills lo hace el CLI: `wispro-agent sync`.

## Knowledge Base

- Las skills en `.agents/skills/` incluyen conocimiento de dependencias.
- Leer la skill de una dependencia ANTES de responder sobre ella.
- Rebuild / sincronización: `wispro-agent sync`.

### Entorno

- Versión de Ruby: leer `.ruby-version`
- Versión de Rails y gemas: leer `Gemfile.lock`
- Gestor de Ruby: chruby (no usar rvm ni rbenv)
- Package manager: Bundler

### RuboCop

- Usamos rubocop-rails-omakase como base.
- Correr `bundle exec rubocop -a` antes de commitear.
- No deshabilitar cops sin justificación en el PR.

### YARD

- Documentación incremental: si tocás un método, documentalo con YARD.
- Consultar la skill `yard` para tags y tipos correctos.
- Verificar cobertura: `bundle exec yard stats --list-undoc`

### Testing

- Framework: RSpec
- Correr: `bundle exec rspec`
- Todo código nuevo debe tener tests.

### Releases o Nuevas versiones

- Usar `/gem-release` para publicar nuevas versiones.
- El GitHub Action publica a RubyGems automáticamente al pushear un tag `v*`.

---

## Arquitectura & Componentes

### Core

- **`ExisRay::Tracer`** — Contexto de trazabilidad distribuida (AWS X-Ray). Extiende `ActiveSupport::CurrentAttributes` para thread-safety. Campos: `trace_id`, `root_id`, `self_id`, `source`, `created_at`, `request_id`, `sidekiq_job`, `task`.
- **`ExisRay::JsonFormatter`** — Formateador global. Acepta Hash, KV strings (`key=value`) y texto libre. Inyecta automáticamente el contexto del Tracer y del Current en cada línea. Castea valores numéricos y filtra claves sensibles.
- **`ExisRay::Current`** — Contexto de negocio (user_id, isp_id, correlation_id). Clase abstracta — la app host la subclasifica.
- **`ExisRay::Reporter`** — Wrapper de Sentry. Clase abstracta — la app host la subclasifica.
- **`ExisRay::Configuration`** — Configuración global con defaults para AWS X-Ray.

### Integraciones HTTP

- **`ExisRay::HttpMiddleware`** — Rack middleware. Hidrata el Tracer con el header entrante. Se inserta automáticamente después de `ActionDispatch::RequestId`.
- **`ExisRay::LogSubscriber`** — Logger nativo de requests HTTP. Reemplaza Lograge. Solo activo con `json_logs: true`.
- **`ExisRay::FaradayMiddleware`** — Inyecta `propagation_trace_header` en requests salientes via Faraday.
- **`ExisRay::ActiveResourceInstrumentation`** — Ídem para ActiveResource.

### Integraciones Sidekiq

- **`ExisRay::Sidekiq::ClientMiddleware`** — Inyecta `exis_ray_trace` en el payload del job antes de encolarlo.
- **`ExisRay::Sidekiq::ServerMiddleware`** — Hidrata el Tracer al inicio de cada job. Genera root_id nuevo si el job no trae trace.

### Integraciones BugBunny (RabbitMQ)

- **`ExisRay::BugBunny::PublisherTracing`** — Middleware para `BugBunny::Client`/`BugBunny::Resource`. Inyecta `propagation_trace_header` en cada mensaje publicado.
- **`ExisRay::BugBunny::ConsumerTracingMiddleware`** — Consumer middleware. Corre antes de todos los logs internos de BugBunny. Hidrata el Tracer desde el header AMQP entrante o genera root_id nuevo.
- **Railtie hooks** — `rpc_reply_headers` inyecta el trace actualizado en el reply del consumer. `on_rpc_reply` hidrata el Tracer en el thread del publisher al recibir la respuesta.

### Procesos en Background

- **`ExisRay::TaskMonitor`** — Lifecycle manager para Rake/Cron. Genera root_id, loguea `task_started`/`task_finished` con `duration_s` y `status`.

---

## Métodos Clave

```ruby
# Hidratar el Tracer (HTTP, Sidekiq, BugBunny consumer)
ExisRay::Tracer.hydrate(trace_id: header_string, source: 'http')

# Sincronizar correlation_id al Current configurado
ExisRay.sync_correlation_id

# Generar header de propagación para el siguiente servicio
ExisRay::Tracer.generate_trace_header
# => "Root=1-abc123-...;Self=...;CalledFrom=wispro_agent;TotalTimeSoFar=42ms"

# Acceder a la configuración
ExisRay.configuration.propagation_trace_header  # => 'X-Amzn-Trace-Id'
ExisRay.configuration.json_logs?                # => true/false
```

---

## Campos Auto-Inyectados

`JsonFormatter` inyecta estos campos automáticamente. **Nunca** incluirlos manualmente en logs:

| Campo | Condición |
|:------|:----------|
| `time` | Siempre |
| `level` | Siempre |
| `severity_number` | Siempre (OTel: DEBUG=5, INFO=9, WARN=13, ERROR=17, FATAL=21) |
| `service` | Siempre |
| `service_version` | Siempre (de `config.version` o `config.x.version`) |
| `deployment_environment` | Siempre (de `Rails.env`) |
| `request_id` | Cuando `Tracer.request_id` está presente (independiente de root_id) |
| `root_id` | Cuando hay trace context activo |
| `trace_id` | Cuando hay trace context activo |
| `source` | Cuando hay trace context activo (HTTP siempre genera root fresco si no llega header) |
| `correlation_id` | Cuando `Current.correlation_id` está presente |
| `user_id` | Cuando `Current.user_id` está presente |
| `isp_id` | Cuando `Current.isp_id` está presente |
| `Current.log_fields` (cualquier key) | Si la subclass overrideó el hook (default `{}`) |
| `sidekiq_job` | Solo en procesos Sidekiq |
| `task` | Solo en procesos TaskMonitor |
| `tags` | Solo si hay Rails tagged logging activo |

---

## Reglas de Ejecución

### Logging

- Todo log interno usa KV strings: `component=exis_ray event=algo`
- `component` siempre en `snake_case`
- DEBUG siempre en block form: `logger.debug { "k=#{v}" }`
- Nunca `Kernel#warn` ni `$stderr`
- Toda operación de logging envuelta en `rescue StandardError`
- Duraciones con `Process.clock_gettime(Process::CLOCK_MONOTONIC)`, nunca `Time.now`

### Seguridad

- Claves sensibles (`password|pass|passwd|secret|token|api_key|auth`) → `[FILTERED]`
- Nunca loguear PII. Solo `user_id`, `isp_id`

### Source válidos

`http` | `sidekiq` | `task` | `system`

### Propagación de headers

- **Entrante HTTP:** `trace_header` (formato Rack: `HTTP_X_AMZN_TRACE_ID`) — solo en `HttpMiddleware`
- **Saliente (todos los transportes):** `propagation_trace_header` (formato HTTP: `X-Amzn-Trace-Id`)

### Prohibiciones

- No Lograge — reemplazado por `LogSubscriber`
- No loguear manualmente: `time`, `level`, `service`, `source`, `root_id`, `trace_id`, `correlation_id`, `sidekiq_job`, `task`

---

## Compatibilidad Rails

- **Reloading:** Usar `cache_classes?` helper (verifica `respond_to?(:enable_reloading)`) para Rails 7.1+
- **Notifications:** Rails 7.1+ usa `all_listeners_for`, Rails 6/7.0 usa `listeners_for` — siempre usar `respond_to?` guards
- **Soporte:** Rails 6, 7 y 8

---

## Integración Automática (Railtie)

El `Railtie` en `after_initialize` detecta y auto-instrumenta sin intervención del desarrollador:

| Gema detectada | Qué hace |
|:---------------|:---------|
| `BugBunny` | Registra `ConsumerTracingMiddleware` y los hooks RPC (`PublisherTracing` va en el cliente, manual) |
| `Sidekiq` | Registra client + server middleware |
| `ActiveResource` | Prepend de `ActiveResourceInstrumentation` |
| `Faraday` | Disponible como middleware opcional |

---

## Configuración Mínima

```ruby
# config/initializers/exis_ray.rb
ExisRay.configure do |config|
  config.log_format              = :json              # :text por defecto
  config.trace_header            = 'HTTP_X_AMZN_TRACE_ID'
  config.propagation_trace_header = 'X-Amzn-Trace-Id'
  config.current_class           = 'Current'
  config.reporter_class          = 'Reporter'
  config.emit_legacy_exception_keys = true            # default true; pasar a false cuando consumers usen exception.*
end

# BugBunny publisher — debe agregarse manualmente al cliente
BugBunny::Client.new(pool: pool) do |stack|
  stack.use ExisRay::BugBunny::PublisherTracing
end
```

---
