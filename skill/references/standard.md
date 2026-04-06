# Estándar de Logging Wispro — Complemento

> Este documento recoge las reglas del estándar de logging del ecosistema Wispro que **no** están ya cubiertas en `SKILL.md`. Para formato general (`component=x event=y`), niveles, `source`, DEBUG block form, reloj monotónico, filtrado de claves sensibles y campos auto-inyectados, ver `SKILL.md`.

---

## Data First — Unidad en la key, número en el valor

Regla de oro para métricas operables: **separar la unidad del dato numérico**. Nunca incluir unidades dentro de los valores.

```
# Incorrecto
duration="0.5s"   memory="128MB"

# Correcto
duration_s=0.5    memory_mb=128
```

Sufijos de unidad estándar:

| Sufijo   | Tipo    | Uso |
|:---------|:--------|:----|
| `_s`     | Float   | Segundos. Estándar para duraciones y latencias. |
| `_ms`    | Integer | Milisegundos. Precisión técnica interna de alta frecuencia. |
| `_count` | Integer | Cantidades o volúmenes. Ej: `record_count`, `retry_count`. |
| `_bytes` / `_kb` / `_mb` | Integer | Almacenamiento o memoria. |
| `_human` | String  | (Opcional) Texto legible. Ej: `duration_human="2 minutes 5 seconds"`. |

Los valores numéricos se emiten como números reales (sin comillas) para que el motor de logs haga casting automático.

---

## Alineación con OpenTelemetry

`ExisRay` sigue el **OpenTelemetry Log Data Model**. Los campos del estándar Wispro se mapean a las convenciones semánticas oficiales de OTel:

| Campo Wispro  | OTel Semantic Convention       | Descripción |
|:--------------|:--------------------------------|:------------|
| `body`        | `body`                         | Contenido principal del log (texto libre). |
| `level`       | `severity_text`                | Nivel de importancia. |
| `http_status` | `http.response.status_code`    | Código de respuesta HTTP (Integer). |
| `outcome`     | `otel.status_code` (enum)      | Resultado semántico de tasks/jobs (`success`/`failed`). |
| `method`      | `http.request.method`          | Método HTTP. |
| `path`        | `url.path`                     | Ruta del request. |
| `user_id`     | `user.id`                      | Identificador del usuario. |

> **Nota sobre `duration_s`**: OTel no define un atributo genérico `duration`. Las duraciones se expresan implícitamente en spans (diferencia entre `start_time` y `end_time`), o en métricas específicas como `http.server.request.duration` (histograma en segundos, según la convención de métricas). En logs Wispro, `duration_s` es una **extensión propia** que permite queries directas sin contexto de span.

Para campos nuevos, seguir las OpenTelemetry Semantic Conventions siempre que exista una equivalencia oficial.

### Naming de campos OTel en formato flat

ExisRay emite JSON flat (ver divergencia D2 más abajo). Al mapear campos OTel al formato flat, aplicar estas reglas:

1. **Dots → underscores**: `messaging.system` → `messaging_system`, `exception.type` → `exception.type` (excepción: los campos `exception.*` mantienen el dot por estar en transición OTel).
2. **Preservar el prefijo semántico**: nunca abreviar el namespace OTel. `messaging.system` se convierte en `messaging_system`, **no** en `system`. El prefijo evita colisiones con otros campos del log (ej: `source: "system"` ya existe en ExisRay).
3. **Sufijo de unidad donde aplique**: si el campo OTel tiene unidad implícita, agregar el sufijo Wispro (`_s`, `_ms`, `_bytes`). Ej: `http.server.request.duration` → `duration_s`.

Ejemplos de mapeo existente:

| OTel Semantic Convention | Campo flat ExisRay |
|:-------------------------|:-------------------|
| `http.response.status_code` | `http_status` |
| `user_agent.original` | `user_agent_original` |
| `server.address` | `server_address` |
| `service.version` | `service_version` |
| `deployment.environment` | `deployment_environment` |
| `exception.type` | `exception.type` (en transición) |
| `messaging.system` | `messaging_system` |
| `messaging.operation` | `messaging_operation` |
| `messaging.destination.name` | `messaging_destination_name` |
| `messaging.message.id` | `messaging_message_id` |
| `messaging.rabbitmq.destination.routing_key` | `messaging_routing_key` |

**Regla de oro**: si al leer el campo aislado de su contexto no queda claro a qué dominio pertenece (ej: `system`, `operation`, `id`, `name`), le falta el prefijo.

---

## Divergencias deliberadas con OpenTelemetry

ExisRay no pretende ser una implementación OTel. Las siguientes divergencias son decisiones conscientes con razones de peso:

### Wire format AWS X-Ray, no W3C Trace Context

OTel usa `traceparent: 00-<trace-id>-<parent-id>-<flags>`. ExisRay usa `X-Amzn-Trace-Id: Root=1-...;Self=...`.

**Razón**: toda la infraestructura Wispro vive en AWS con X-Ray como backend de trazas. Si en el futuro se migra a un backend OTel-native, la traducción ocurrirá solo en el edge (HTTP middleware), sin tocar el core.

### Flat JSON, no resource/attributes anidado

OTel Log Data Model anida: `{"Resource": {...}, "Attributes": {...}, "Body": "..."}`. ExisRay emite flat: `{"service": "...", "component": "...", ...}`.

**Razón**: los agregadores comunes (CloudWatch, Loki, Datadog) indexan mejor JSON flat. Queries como `component:auth AND event:login_failed` son triviales en flat. Un exporter OTel futuro haría el unflatten al emitir.

### Sufijos de unidad en keys (`_s`, `_ms`, `_bytes`)

OTel usa unit metadata UCUM o nombres sin sufijo. ExisRay usa sufijos explícitos.

**Razón**: en JSON flat, un campo llamado `duration` sin unidad es ambiguo. El sufijo hace que el consumidor humano y el parser automático sepan la unidad sin metadata externa (regla "Data First" Wispro).

### Campo `source` (http/sidekiq/task/system)

No tiene equivalente OTel directo. Lo más parecido es `span.kind`, pero mide otra cosa.

**Razón**: es el campo más útil para filtrado operacional — saber si un error viene de una request HTTP, un job o un consumer es la primera pregunta al mirar logs. Es una **extensión Wispro**.

### Campo `component`

OTel lo más parecido es `instrumentation.scope.name`. ExisRay lo usa para identificar el módulo de negocio (`component=billing`, `component=auth`).

**Razón**: `component` es dominio-específico y útil para filtrado operacional. Convive sin conflicto con `instrumentation.scope.name` si en el futuro se agrega el emisor técnico.

---

## Ciclo de Vida del Evento

### Procesos, Jobs y Tasks

Todo proceso aislado debe reportar inicio y finalización con estructura consistente:

- `event`: identificador de estado (`task_started`, `task_finished`, `job_started`, `job_finished`).
- `outcome`: resultado final como **string semántico**, nunca un código numérico: `success`, `failed`, `aborted`.
- `duration_s`: tiempo total de ejecución (reloj monotónico).
- `error_class` y `error_message`: **obligatorios solo en caso de fallo**.

```ruby
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
begin
  InvoiceService.process_all
  duration_s = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  Rails.logger.info("component=billing event=task_finished outcome=success duration_s=#{duration_s} record_count=500")
rescue => e
  duration_s = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  Rails.logger.error("component=billing event=task_finished outcome=failed duration_s=#{duration_s} error_class=#{e.class} error_message=\"#{e.message}\"")
  raise
end
```

`ExisRay::TaskMonitor` implementa exactamente este contrato para Rake/Cron.

### Peticiones HTTP

Los logs de cierre de request estandarizan el reporte de rendimiento:

- `http_status`: **código HTTP como Integer** (ej: `200`, `404`, `500`).
- `duration_s`: tiempo total de respuesta del servidor.
- `[subsystem]_runtime_s`: desglose opcional por capa (`db_runtime_s`, `view_runtime_s`).

`ExisRay::LogSubscriber` emite este shape automáticamente — no hace falta loguearlo manualmente.

---

## Regla de Oro

> Tu log manual solo debe contener datos de **tu lógica de negocio**. La infraestructura (ExisRay) ya sabe quién sos, de dónde venís y cuál es tu ID de traza — no dupliques esos campos en los logs manuales.
