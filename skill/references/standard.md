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

| Campo Wispro  | OTel Semantic Convention    | Descripción |
|:--------------|:----------------------------|:------------|
| `body`        | `body`                      | Contenido principal del log (texto libre). |
| `level`       | `severity_text`             | Nivel de importancia. |
| `duration_s`  | `duration` (en segundos)    | Tiempo de ejecución. |
| `method`      | `http.request.method`       | Método HTTP. |
| `status`      | `http.response.status_code` | Código de respuesta HTTP. |
| `path`        | `url.path`                  | Ruta del request. |
| `user_id`     | `user.id`                   | Identificador del usuario. |

Para campos nuevos, seguir las OpenTelemetry Semantic Conventions siempre que exista una equivalencia oficial.

---

## Ciclo de Vida del Evento

### Procesos, Jobs y Tasks

Todo proceso aislado debe reportar inicio y finalización con estructura consistente:

- `event`: identificador de estado (`task_started`, `task_finished`, `job_started`, `job_finished`).
- `status`: resultado final como **string semántico**, nunca un código numérico: `success`, `failed`, `aborted`.
- `duration_s`: tiempo total de ejecución (reloj monotónico).
- `error_class` y `error_message`: **obligatorios solo en caso de fallo**.

```ruby
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
begin
  InvoiceService.process_all
  duration_s = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  Rails.logger.info("component=billing event=task_finished status=success duration_s=#{duration_s} record_count=500")
rescue => e
  duration_s = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  Rails.logger.error("component=billing event=task_finished status=failed duration_s=#{duration_s} error_class=#{e.class} error_message=\"#{e.message}\"")
  raise
end
```

`ExisRay::TaskMonitor` implementa exactamente este contrato para Rake/Cron.

### Peticiones HTTP

Los logs de cierre de request estandarizan el reporte de rendimiento:

- `status`: **código HTTP como Integer** (ej: `200`, `404`, `500`). Este es el único caso donde `status` es numérico.
- `duration_s`: tiempo total de respuesta del servidor.
- `[subsystem]_runtime_s`: desglose opcional por capa (`db_runtime_s`, `view_runtime_s`).

`ExisRay::LogSubscriber` emite este shape automáticamente — no hace falta loguearlo manualmente.

---

## Regla de Oro

> Tu log manual solo debe contener datos de **tu lógica de negocio**. La infraestructura (ExisRay) ya sabe quién sos, de dónde venís y cuál es tu ID de traza — no dupliques esos campos en los logs manuales.
