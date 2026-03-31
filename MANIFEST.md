# Observability & Telemetry Manifest

Este documento define el estándar obligatorio de telemetría y logging estructurado para todo nuestro ecosistema de software. El objetivo es garantizar que cualquier sistema, independientemente de su propósito, emita datos que sean **analizables, consistentes y escalables**.

## Objetivo
Transformar el logging tradicional en un **flujo de eventos de datos**. Esto permite que herramientas de análisis puedan generar dashboards de rendimiento, alertas inteligentes y rastreo de errores sin necesidad de procesamiento manual de texto o transformaciones complejas.

---

## Reglas Fundamentales

### 1. Formato de Mensaje

Todo log debe emitirse como una línea de pares `key=value` en el siguiente orden:

```
component=x event=y [campos adicionales]
```

- `component`: nombre de la gema, librería o módulo responsable (ej: `exis_ray`, `storage_engine`). Siempre en `snake_case`.
- `event`: nombre puntual de la acción o hito (ej: `http_request`, `sync_complete`). Siempre en `snake_case`.
- Los campos adicionales van a continuación, en cualquier orden.

Valores con espacios deben ir entre comillas dobles: `error_message="Server reset connection"`.

### 2. Niveles de Log

Cada nivel tiene una semántica estricta. Usar el nivel incorrecto es un error.

| Nivel   | Cuándo usarlo |
| :------ | :------------ |
| `ERROR` | Se lanzó una excepción o el sistema no pudo completar una operación crítica. |
| `WARN`  | Ocurrió algo inesperado pero la ejecución continuó. |
| `INFO`  | Flujo normal del sistema. Eventos relevantes para el negocio u operaciones. |
| `DEBUG` | Detalle técnico interno. Solo útil durante desarrollo o diagnóstico. |

**Regla de DEBUG:** Siempre usar block form para evitar interpolación innecesaria:
```ruby
# Correcto
logger.debug { "component=cache event=miss key=#{key}" }

# Incorrecto — evalúa la interpolación aunque DEBUG esté desactivado
logger.debug "component=cache event=miss key=#{key}"
```

**Prohibido:** Nunca usar `Kernel#warn` ni escribir directamente a `$stderr`. Todo output debe ir por el logger configurado.

### 3. Unidad en la Key, Número en el Valor (Data First)

La regla de oro para que las métricas sean operables es separar la unidad del dato numérico. **Nunca** incluir unidades dentro de los valores.

```
# Incorrecto
duration="0.5s"   memory="128MB"

# Correcto
duration_s=0.5    memory_mb=128
```

**Sufijos de unidad:**
- `_s`: Segundos (Float). Estándar para duraciones y latencias.
- `_ms`: Milisegundos (Integer). Para precisión técnica interna de alta frecuencia.
- `_count`: Cantidades o volúmenes (Integer). Ej: `record_count`, `retry_count`.
- `_bytes` / `_kb` / `_mb`: Unidades de almacenamiento o memoria.
- `_human`: (Opcional) Texto legible para humanos. Ej: `duration_human="2 minutes 5 seconds"`.

### 4. Medición de Duraciones

Las duraciones **siempre** deben medirse con reloj monotónico. Nunca con `Time.now` (susceptible a saltos de reloj del sistema).

```ruby
# Correcto
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
# ... operación ...
duration_s = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

# Incorrecto
start = Time.now
duration_s = Time.now - start
```

### 5. Source: Entrypoint de Ejecución

El campo `source` identifica el punto de entrada del proceso. Es obligatorio y solo acepta estos valores:

| Valor      | Cuándo usarlo |
| :--------- | :------------ |
| `http`     | Request HTTP entrante (procesado por Rack/Rails). |
| `sidekiq`  | Job procesado por Sidekiq. |
| `task`     | Tarea programada o proceso de larga duración (Rake, Cron, TaskMonitor). |
| `system`   | Ejecución iniciada por otro sistema interno (ej: consumidor RabbitMQ/BugBunny). |

`source` es inyectado automáticamente por el middleware correspondiente. **No lo incluyas manualmente.**

### 6. Seguridad y Privacidad

**Filtrado de claves sensibles:** Cualquier campo cuya key coincida con el patrón `password|pass|passwd|secret|token|api_key|auth` debe reemplazar su valor por `[FILTERED]`. Esto es aplicado automáticamente por `ExisRay::JsonFormatter` en todos los logs.

**Sin PII:** Nunca loguear datos crudos de usuarios. Solo se permiten identificadores: `user_id`, `isp_id`.

```
# Incorrecto
component=auth event=login email=user@example.com password=abc123

# Correcto
component=auth event=login user_id=42 password=[FILTERED]
```

### 7. Resiliencia del Logger

Un fallo en el logging nunca debe interrumpir el flujo principal de la aplicación. Toda operación de logging debe estar protegida:

```ruby
# Correcto
begin
  logger.info "component=sync event=complete duration_s=#{duration_s}"
rescue StandardError
  # silenciar — el log es accesorio, no crítico
end
```

### 8. Convenciones de Naming

- Keys siempre en `snake_case`.
- Valores numéricos emitidos como números reales (sin comillas) para que el motor de logs realice casting automático.
- Para campos estándar, seguir las **OpenTelemetry Semantic Conventions** donde sea posible.

---

## 🔭 Alineación con OpenTelemetry

`exis_ray` sigue el **OpenTelemetry Log Data Model**. Los campos se mapean a las convenciones semánticas oficiales:

| Campo ExisRay  | OTel Semantic Convention    | Descripción              |
| :------------- | :-------------------------- | :----------------------- |
| `body`         | `body`                      | Contenido principal del log (texto libre). |
| `level`        | `severity_text`             | Nivel de importancia.    |
| `duration_s`   | `duration` (en segundos)    | Tiempo de ejecución.     |
| `method`       | `http.request.method`       | Método HTTP.             |
| `status`       | `http.response.status_code` | Código de respuesta HTTP.|
| `path`         | `url.path`                  | Ruta del request.        |
| `user_id`      | `user.id`                   | Identificador del usuario.|

---

## 🏗 Campos Auto-Inyectados por ExisRay

**NUNCA** incluyas manualmente los siguientes campos. `ExisRay::JsonFormatter` los inyecta automáticamente en cada línea de log:

| Campo            | Descripción                        | Condición                                      |
| :--------------- | :--------------------------------- | :--------------------------------------------- |
| `time`           | Timestamp ISO8601 UTC              | Siempre                                        |
| `level`          | Nivel de severidad                 | Siempre                                        |
| `service`        | Nombre de la aplicación            | Siempre                                        |
| `root_id`        | Trace ID raíz (AWS X-Ray)          | Cuando hay trace context activo                |
| `trace_id`       | Trace ID completo (formato X-Ray)  | Cuando hay trace context activo                |
| `source`         | Entrypoint de ejecución            | Cuando hay trace context activo                |
| `correlation_id` | ID de rastreo cruzado              | Cuando `Current.correlation_id` está presente  |
| `user_id`        | ID del usuario autenticado         | Cuando `Current.user_id` está presente         |
| `isp_id`         | ID del ISP                         | Cuando `Current.isp_id` está presente          |
| `sidekiq_job`    | Clase del Worker Sidekiq           | Solo en procesos Sidekiq                       |
| `task`           | Nombre de la tarea                 | Solo en procesos TaskMonitor                   |
| `tags`           | Tags de Rails TaggedLogging        | Solo si hay tags activos en el hilo            |

> **Regla de Oro:** Tu log manual solo debe contener datos de **tu lógica de negocio**. La infraestructura ya sabe quién eres, de dónde venís y cuál es tu ID de traza.

---

## 🛰 Ciclo de Vida del Evento

### Procesos, Trabajos y Tareas (Jobs/Tasks)

Todo proceso aislado debe reportar su inicio y su finalización con una estructura consistente:

- `event`: Identificador de estado (ej: `task_started`, `task_finished`).
- `status`: Resultado final (`success`, `failed`, `aborted`). Siempre string semántico, nunca código HTTP.
- `duration_s`: Tiempo total de ejecución (reloj monotónico).
- `error_class` / `error_message`: Obligatorios solo en caso de fallo.

### Peticiones HTTP

Los logs de cierre de petición deben estandarizar el reporte de rendimiento:

- `status`: Código HTTP (Integer). Ej: `200`, `404`, `500`.
- `duration_s`: Tiempo total de respuesta del servidor.
- `[subsystem]_runtime_s`: Desglose opcional por capa (ej: `db_runtime_s`, `view_runtime_s`).

---

## Ejemplo de Implementación Estándar

**En el código fuente:**
```ruby
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
# ... operación ...
duration_s = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

logger.info "component=data_processor event=sync_complete status=success duration_s=#{duration_s} record_count=500"

# En caso de error:
rescue => e
  logger.error "component=data_processor event=sync_complete status=failed error_class=#{e.class} error_message=\"#{e.message}\""
end
```

**Resultado JSON unificado (emitido por ExisRay):**
```json
{
  "time": "2026-03-24T14:00:00Z",
  "level": "INFO",
  "service": "my_application",
  "root_id": "1-abc123",
  "trace_id": "Root=1-abc123",
  "source": "task",
  "correlation_id": "my_application;1-abc123",
  "component": "data_processor",
  "event": "sync_complete",
  "status": "success",
  "duration_s": 1.25,
  "record_count": 500
}
```
