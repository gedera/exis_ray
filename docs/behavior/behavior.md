# Comportamiento — exis_ray

> meta: artefacto · RFC-007 (UML 2.x sequence / BPMN 2.0, render Mermaid) · generado dev-enrich · anclado a commit `00cf803` (v0.8.0 + fix issue #9) · cobertura **parcial incremental**

## 1. Resumen

Comportamiento runtime de la trazabilidad distribuida: hidratación del `Tracer` en cada entrypoint y emisión del contexto en cada línea de log. Documentación **incremental** — este artefacto se inició con el PR del issue #9 (flujo de entrypoint HTTP); el resto de flujos se acreta cuando se tocan.

## 2. Cuerpo

### Cobertura (obligatoria — RFC-007 §2.a)

| Flujo | Estado | Origen |
|---|---|---|
| Hidratación de trace en entrypoint HTTP + emisión en logs | **documentado** | PR issue #9 |
| Hidratación en entrypoint Sidekiq (server middleware) | **referenciado** (no diagramado) | — |
| Hidratación en entrypoint BugBunny consumer | **referenciado** (no diagramado) | — |
| Hidratación en entrypoint TaskMonitor (Rake/Cron) | **referenciado** (no diagramado) | — |
| Propagación saliente (Faraday / ActiveResource / BugBunny publisher) | **NO documentado** | — |
| Ciclo de vida RPC reply (BugBunny) | **NO documentado** | — |

Ausencia de un flujo en este artefacto ≠ inexistencia del flujo. Acreta por PR.

### Flujo: Hidratación de trace en entrypoint HTTP + emisión en logs

Invariante de paridad: los 4 entrypoints (`HttpMiddleware`, `Sidekiq::ServerMiddleware`, `BugBunny::ConsumerTracingMiddleware`, `TaskMonitor`) garantizan un `root_id` aunque no llegue trace header entrante. Antes del fix de issue #9, `HttpMiddleware` era el único sin ese fallback: un servicio que es **punto de entrada** (no eslabón intermedio) emitía logs sin `root_id`, y por efecto cascada sin `source` (campo mandatorio del estándar Wispro).

```mermaid
sequenceDiagram
    participant Cliente
    participant HM as HttpMiddleware
    participant T as ExisRay::Tracer
    participant App as Rack app / Controller
    participant JF as JsonFormatter

    Cliente->>HM: request (con o sin trace_header)
    HM->>T: hydrate(trace_id: env[trace_header], source: "http")
    T->>T: created_at, source="http", trace_id=...
    T->>T: parse_trace_id
    alt trace_header presente (eslabón intermedio)
        T->>T: root_id = data["Root"] (parseado del header)
    else sin trace_header (servicio entrypoint)
        T-->>HM: root_id queda nil
        HM->>T: root_id ||= generate_new_root  %% fix issue #9 Gap A
        T->>T: root_id = "Root=1-<ts>-<rand>" (fresco)
    end
    HM->>T: request_id = env["action_dispatch.request_id"]
    HM->>HM: ExisRay.sync_correlation_id
    HM->>App: @app.call(env)
    App->>JF: Rails.logger.info "event=..."
    JF->>T: request_id?  %% issue #9 Gap C: fuera del guard de root_id
    JF->>JF: payload[:request_id] = T.request_id (si presente)
    JF->>T: root_id?
    alt root_id presente (siempre en entrypoint, post-fix)
        JF->>JF: payload += root_id, trace_id, source, ...
    end
    JF-->>App: línea JSON con source + correlación
    Note over HM,App: rescue StandardError ⇒ @app.call(env) igual<br/>(logging nunca rompe el flujo principal)
```

Contexto: `JsonFormatter#inject_tracer_context` corta todo su bloque con `return unless root_id` (Gap B — efecto cascada de Gap A). El fix de Gap A (root fresco en `HttpMiddleware`) des-gatea ese bloque y `source` vuelve a emitirse. `request_id` se emite **fuera** de ese guard (Gap C): tiene distinto ciclo de vida que `root_id` (UUID v4 de Rails vs formato X-Ray) y un servicio puede querer correlación por request aunque no haya trace context.

## 3. Inferencias

| Afirmación | confidence | a verificar por humano |
|---|---|---|
| Los 4 entrypoints comparten la invariante "siempre hay root_id" | `declared` | código de los 4 middlewares lo confirma (issue #9 lo tabula) |
| `request_id` no se emitía en ninguna línea pre-fix | `declared` | confirmado: `JsonFormatter` solo lo usaba interno vía `clean_request_id` |
| Orden de emisión (request_id antes del guard de root_id) | `declared` | `json_formatter.rb#inject_tracer_context` post-fix |

## 4. Cobertura y fronteras

- **Incremental:** solo el flujo de entrypoint HTTP está diagramado. Sidekiq/BugBunny/TaskMonitor referenciados por paridad pero no diagramados (acretan cuando se toquen).
- **Fuera de alcance:** estructura de datos (gema sin DB → no aplica), interfaz Ruby pública / topología (capas F2 de `dev-structure`, no implementadas).
- **Significado de términos** (`root_id`, `source`, etc.) → `docs/glossary/glossary.md`.
