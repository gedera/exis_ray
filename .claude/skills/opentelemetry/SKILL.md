---
name: opentelemetry
description: This skill should be used when adding new log fields, designing new telemetry events, or reviewing field naming in this gem. Activates when the user mentions "otel", "opentelemetry", "semantic conventions", "field naming", "span", "trace", or asks about how to name a new log field.
version: 1.0.0
---

# OpenTelemetry Alignment — ExisRay

ExisRay sigue el **OpenTelemetry Log Data Model**. Cuando se agregan campos nuevos, priorizar los nombres de OTel Semantic Conventions antes de inventar nombres propios.

## Mapeo de Campos ExisRay → OTel

| Campo ExisRay  | OTel Semantic Convention    | Tipo   |
| :------------- | :-------------------------- | :----- |
| `body`         | `body`                      | String |
| `level`        | `severity_text`             | String |
| `duration_s`   | `duration` (en segundos)    | Float  |
| `method`       | `http.request.method`       | String |
| `status`       | `http.response.status_code` | Integer|
| `path`         | `url.path`                  | String |
| `user_id`      | `user.id`                   | String/Integer |

## Convenciones de Naming

- **`snake_case`** siempre para keys
- **Unidades en la key, número en el valor:**
  - `duration_s=1.25` (Float) — nunca `duration="1.25s"`
  - `duration_ms=42` (Integer)
  - `record_count=500` (Integer)
  - `memory_mb=128` (Integer)
- **`_human`** para representación legible opcional: `duration_human="2 minutes"`

## Campos Reservados

No usar estos nombres para otros propósitos — tienen semántica fija en ExisRay:

`time`, `level`, `service`, `root_id`, `trace_id`, `source`, `correlation_id`,
`user_id`, `isp_id`, `sidekiq_job`, `task`, `body`, `tags`

## Log Body vs Campos Estructurados

- **Texto libre** → va en `body` (OTel log body)
- **Datos estructurados** → elevar al nivel raíz via KV string o Hash

```ruby
# Correcto — datos estructurados al nivel raíz
logger.info "component=sync event=complete status=success duration_s=1.25"
# → {"component":"sync","event":"complete","status":"success","duration_s":1.25}

# Correcto — texto libre va en body
logger.info "Esto es un mensaje de texto libre"
# → {"body":"Esto es un mensaje de texto libre"}
```

## Trace Context (AWS X-Ray compatible)

ExisRay usa el formato AWS X-Ray pero es compatible con OTel trace context:

- `root_id` → equivalente a `trace_id` en OTel (solo el ID raíz, sin prefijos)
- `trace_id` → header completo X-Ray: `Root=1-...;Self=...;CalledFrom=...`
- `source` → entrypoint de ejecución (no tiene equivalente directo en OTel)
