# Glosario — exis_ray

> meta: artefacto · RFC-009 (DDD ubiquitous language / bounded context + ISO 11179) · generado dev-enrich · anclado a commit `00cf803` · cobertura **parcial — sembrado inicial, acreta por PR**

## 1. Resumen

Lenguaje ubicuo del bounded context **exis_ray** (observabilidad/trazabilidad del ecosistema Wispro). Significado de cada término **en esta gema**. Gema sin capa de datos (`docs/data` = n/a): el `Binding` apunta al símbolo público estable que *es* el concepto (ISO 11179, materialización no-tabular), no a tablas.

## 2. Cuerpo

## entrypoint

Punto donde la ejecución entra al servicio y nace (o se continúa) un contexto de trazabilidad. Hay exactamente 4: HTTP, Sidekiq, BugBunny consumer, TaskMonitor. **Invariante:** todo entrypoint garantiza un `root_id` — si no llega trace header entrante, genera uno fresco. Un servicio que es entrypoint sin trace upstream (ej. collector/ingest) igual emite logs correlacionables y con `source`.

**Binding:** `ExisRay::HttpMiddleware`, `ExisRay::Sidekiq::ServerMiddleware`, `ExisRay::BugBunny::ConsumerTracingMiddleware`, `ExisRay::TaskMonitor`.

## root_id

Identificador raíz de un trace distribuido (formato AWS X-Ray: `1-<ts_hex>-<rand_hex>`, prefijado `Root=`). **Constante a lo largo de toda la cadena** de servicios: nace en el primer entrypoint y se propaga sin cambiar. Es el campo de correlación primario de logs.

**Binding:** `ExisRay::Tracer.root_id`.

## trace_id

Header de traza entrante completo, sin parsear: `Root=...;Self=...;CalledFrom=...;TotalTimeSoFar=...ms`. Presente solo cuando el servicio es **eslabón intermedio** (recibió header upstream). Un entrypoint sin trace upstream tiene `root_id` (fresco) pero no `trace_id`.

**Binding:** `ExisRay::Tracer.trace_id`.

## self_id

Identificador del span del servicio actual dentro del trace. Se genera por servicio y viaja en el header saliente como `Self=`.

**Binding:** `ExisRay::Tracer.self_id`.

## source

Entrypoint de ejecución que originó la línea de log. Valores válidos: `http`, `sidekiq`, `task`, `system`. **Campo mandatorio** del estándar Wispro de logging — toda línea debe tenerlo. Se emite dentro del bloque de tracer context, que está gateado por `root_id`; por eso la invariante "todo entrypoint garantiza root_id" es lo que hace que `source` nunca falte.

**Binding:** `ExisRay::Tracer.source`.

## request_id

UUID v4 del request HTTP, provisto por `ActionDispatch::RequestId` (`env["action_dispatch.request_id"]`). **Distinto ciclo de vida que `root_id`**: identificador por-request de Rails, no formato X-Ray, no constante a lo largo de la cadena. Se emite en logs fuera del guard de `root_id` — un servicio puede querer correlación por request aunque no haya trace context activo.

**Binding:** `ExisRay::Tracer.request_id`.

## correlation_id

ID de correlación de negocio compuesto `ServiceName;RootID`, sincronizado al `Current` configurado por la app host. Liga logs de negocio con el trace.

**Binding:** `ExisRay::Tracer.correlation_id`, `ExisRay::Current#correlation_id`.

## trace context

Conjunto thread-safe de atributos de trazabilidad activos en la request/job actual (`root_id`, `trace_id`, `self_id`, `source`, `request_id`, `created_at`, ...). Vive en `ActiveSupport::CurrentAttributes`; se hidrata en el entrypoint y se resetea al finalizar. "Hay trace context activo" ≡ `root_id` presente.

**Binding:** `ExisRay::Tracer` (subclase de `ActiveSupport::CurrentAttributes`).

## propagation header

Header saliente que lleva el trace al siguiente servicio (`X-Amzn-Trace-Id` por default): `Root=...;Self=...;CalledFrom=<service>;TotalTimeSoFar=<acc>ms`. Lo genera `Tracer.generate_trace_header`. Distinto del header **entrante** (formato Rack `HTTP_X_AMZN_TRACE_ID`).

**Binding:** `ExisRay::Tracer.generate_trace_header`, `ExisRay.configuration.propagation_trace_header`.

## 3. Inferencias

| Término | confidence | a verificar |
|---|---|---|
| Significado de negocio de cada término | `inferred` (LLM ancló al código; significado lo confirma humano) | revisar que la prosa refleje el uso real en servicios consumidores |
| `trace context activo ≡ root_id presente` | `declared` | `JsonFormatter#inject_tracer_context` lo implementa literal |

## 4. Cobertura y fronteras

- **Sembrado inicial** disparado por PR issue #9; cubre los términos del núcleo trace/log. Acreta por PR (ausencia ≠ inexistencia).
- **Términos no cubiertos aún:** `Reporter`/Sentry context, `total_time_so_far`, `called_from`, `log_fields`, `sidekiq_job`, `task`.
- **Frontera:** comportamiento/secuencias → `docs/behavior/behavior.md`. Estructura de datos → n/a (gema sin DB).
