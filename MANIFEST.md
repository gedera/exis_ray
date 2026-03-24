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
- **Naming:** Las llaves (keys) deben usar siempre `snake_case`. Para campos estándar, se prefiere seguir las **OpenTelemetry Semantic Conventions**.
- **Valores Numéricos:** Deben emitirse como números reales (sin sufijos de texto) para permitir que el motor de logs realice el casting automático.
- **Formato:** Pares `key=value` en una sola línea estructurada.

## 🔭 Alineación con OpenTelemetry

Para garantizar la interoperabilidad, `exis_ray` sigue el **OpenTelemetry Log Data Model**. Siempre que sea posible, los campos deben mapearse a las convenciones semánticas oficiales:

| Campo ExisRay | OTel Semantic Convention | Descripción |
| :--- | :--- | :--- |
| `body` | `body` | El contenido principal del log. |
| `level` | `severity_text` | Nivel de importancia. |
| `duration_s` | `duration` (en segundos) | Tiempo de ejecución. |
| `method` | `http.request.method` | Método HTTP. |
| `status` | `http.response.status_code` | Código de respuesta. |
| `path` | `url.path` | Ruta del request. |
| `user_id` | `user.id` | Identificador del usuario. |

## 🏗 Infraestructura de Datos (Automática)

Para evitar logs redundantes y pesados, **NUNCA** incluyas manualmente las siguientes llaves en tus mensajes de log. La capa de infraestructura (`exis_ray`) las inyecta automáticamente en el nivel raíz del JSON:

| Llave | Descripción | Por qué no incluirla |
| :--- | :--- | :--- |
| `time` | Timestamp ISO8601 | Lo añade el Logger base. |
| `level` | INFO, ERROR, etc. | Lo añade el Logger base. |
| `service` | Nombre de la App | Se obtiene de la configuración global. |
| `source` | Entrypoint (http, task) | Lo inyecta el middleware/monitor correspondiente. |
| `root_id` | Trace ID (AWS X-Ray) | Se gestiona a nivel de hilo/petición. |
| `correlation_id`| ID de rastreo cruzado | Se genera automáticamente al inicio de la ejecución. |
| `user_id` / `isp_id`| Contexto de negocio | Se extrae del estado global de la petición. |
| `sidekiq_job` | Clase del Worker | Inyectado automáticamente en procesos Sidekiq. |
| `task` | Nombre de la tarea | Inyectado automáticamente por el TaskMonitor. |

> **Regla de Oro:** Tu log manual solo debe contener datos de **tu lógica de negocio**. La infraestructura ya sabe quién eres, de dónde vienes y cuál es tu ID de traza.

---

## 🛰 Ciclo de Vida del Evento

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
