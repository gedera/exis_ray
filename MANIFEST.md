# Observability & Telemetry Manifest

Este documento define el estándar obligatorio de telemetría y logging estructurado para todo nuestro ecosistema de software. El objetivo es garantizar que cualquier sistema, independientemente de su propósito, emita datos que sean **analizables, consistentes y escalables**.

## Objetivo
Transformar el logging tradicional en un **flujo de eventos de datos**. Esto permite que herramientas de análisis puedan generar dashboards de rendimiento, alertas inteligentes y rastreo de errores sin necesidad de procesamiento manual de texto o transformaciones complejas.

## Reglas Fundamentales

### 1. Unidad en la Key, Número en el Valor (Data First)
La regla de oro para que las métricas sean operables es separar la unidad del dato numérico. **Nunca** incluir unidades dentro de los valores de los logs.
*   Incorrecto: `duration="0.5s"`, `memory="128MB"`.
*   Correcto: `duration_s=0.5`, `memory_mb=128`.

**Sufijos de unidad recomendados:**
- `_s`: Segundos (Float). Estándar para duraciones y latencias visibles al negocio.
- `_ms`: Milisegundos (Integer). Para precisión técnica interna de alta frecuencia.
- `_count`: Cantidades o volúmenes (Integer). Ej: `record_count`, `retry_count`.
- `_bytes` / `_kb` / `_mb`: Unidades de almacenamiento o memoria.
- `_human`: (Opcional) Texto explicativo legible para humanos (ej: `duration_human="2 hours"`).

### 2. Contexto de Identidad
Cada línea de log debe llevar los metadatos necesarios para identificar su origen técnico de forma inmediata:
*   `component`: Nombre de la gema, librería o módulo responsable (ej: `exis_ray`, `storage_engine`).
*   `event`: Nombre de la acción puntual o hito alcanzado (ej: `http_request`, `engine.complete`).
*   `source`: El punto de entrada de la ejecución (`http`, `sidekiq`, `task`, `system`).

### 3. Convenciones de Naming & Tipos
- **Naming:** Las llaves (keys) deben usar siempre `snake_case`.
- **Valores Numéricos:** Deben emitirse como números reales (sin sufijos de texto) para permitir que el motor de logs realice el casting automático.
- **Formato:** Pares `key=value` en una sola línea estructurada.

---

## Infraestructura de Datos (Automática)

La gema `exis_ray` inyecta automáticamente los siguientes metadatos en cada línea de log JSON, por lo que **no deben incluirse manualmente** en los mensajes:

| Llave | Descripción | Origen |
| :--- | :--- | :--- |
| `time` | Marca de tiempo en formato ISO8601 UTC. | Logger |
| `level` | Nivel de severidad (INFO, ERROR, DEBUG, etc.). | Logger |
| `service` | Nombre de la aplicación en `snake_case`. | Tracer |
| `source` | Entrypoint: `http`, `sidekiq`, `task` o `system`. | Tracer |
| `root_id` | Identificador único de la traza distribuida (AWS X-Ray). | Tracer |
| `correlation_id` | ID compuesto para rastreo cruzado. | Tracer |
| `user_id` / `isp_id` | Identidad del sujeto de negocio (si está presente). | Current |
| `sidekiq_job` | Nombre de la clase del Worker (solo en Sidekiq). | Tracer |
| `task` | Nombre de la tarea Rake o Cron (solo en TaskMonitor). | Tracer |

---

## Ciclo de Vida del Evento

### Procesos, Trabajos y Tareas (Jobs/Tasks)
Todo proceso aislado debe reportar su inicio y su finalización con una estructura consistente:
- `event`: Identificador de estado (ej: `task_started`, `task_finished`).
- `status`: Resultado final de la operación (`success`, `failed`, `aborted`). En contexto de tareas/jobs, siempre es un string semántico, no un código HTTP.
- `duration_s`: Tiempo total de ejecución (calculado con reloj monotónico).
- `error_class` / `error_message`: Obligatorios solo en caso de fallo.

### Peticiones de Interfaz (APIs/HTTP)
Los logs de cierre de peticiones deben estandarizar el reporte de rendimiento para telemetría:
- `status`: Código de respuesta HTTP (Integer). En contexto HTTP siempre es el código numérico (ej: `200`, `404`, `500`).
- `duration_s`: Tiempo total de respuesta del servidor.
- `[subsystem]_runtime_s`: Desglose opcional de tiempos por capa (ej: `db_runtime_s`, `view_runtime_s`).

---

## Ejemplo de Implementación Estándar

**En el código fuente:**
```ruby
# Reporte de éxito con métricas integradas
logger.info "component=data_processor event=sync_complete status=success duration_s=1.25 record_count=500"

# Reporte de error con contexto técnico
logger.error "component=data_processor event=sync_complete status=failed error_class=Timeout error_message=\"Server reset\""
```

**Resultado JSON unificado:**
```json
{
  "time": "2026-03-24T14:00:00Z",
  "level": "INFO",
  "service": "my_application",
  "component": "data_processor",
  "event": "sync_complete",
  "status": "success",
  "duration_s": 1.25,
  "record_count": 500,
  "source": "task",
  "root_id": "Root=1-...",
  "correlation_id": "my_application;Root=..."
}
```
