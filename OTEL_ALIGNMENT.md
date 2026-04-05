# ExisRay ↔ OpenTelemetry — Alineación y Roadmap

> **Propósito**: registrar el estado actual de alineación de ExisRay con las convenciones de OpenTelemetry (Semantic Conventions + Log Data Model), documentar divergencias deliberadas, y planificar los pasos para acercar la gema a OTel sin perder las decisiones de diseño que le dan valor.
>
> **No es un mandato de conformidad**: ExisRay no pretende ser una implementación OTel. Usa AWS X-Ray como wire format de trazas y un formato de log propio más legible por humanos. Pero donde acercarse a OTel es barato y aporta interoperabilidad, queremos hacerlo.
>
> **Fuentes**:
> - `skill/references/standard.md` — estándar Wispro actual.
> - `.agents/skills/opentelemetry/references/` — concepts, collector/OTLP, instrumentation.
> - Código actual: `lib/exis_ray/log_subscriber.rb`, `lib/exis_ray/task_monitor.rb`, `lib/exis_ray/bug_bunny/*`.

---

## TL;DR

ExisRay ya está **conceptualmente bien alineada** con OTel en lo fundamental: separación resource vs operation, propagación de contexto en fronteras async, correlación de logs con trace IDs, low-cardinality attributes, naming por operación en lugar de URL. Las divergencias principales son deliberadas y defendibles (formato AWS X-Ray en wire, flat JSON en lugar de resource/attributes anidado, sufijos de unidad en keys).

Sin embargo, hay:

- **1 error concreto** en la tabla de mapeo de `standard.md` (hay que corregir).
- **1 inconsistencia semántica real** en el uso de `status` (doble significado entre HTTP y jobs).
- **~6 campos OTel estándar faltantes** que son wins baratos (severity number, exception.*, service.version, deployment.environment, http.route, user_agent.original).
- **~4 áreas** donde podríamos alinearnos más sin romper nada (semantic conventions de messaging para BugBunny, span.kind, resource attributes, atributos con namespace `wispro.*`).

---

## ✅ Lo que ya está alineado

Esto no se toca. Documentado para no olvidarlo en futuras revisiones.

| Área | Cómo OTel lo pide | Cómo ExisRay lo hace |
|:-----|:------------------|:----------------------|
| **Log correlation** | Cada log debe incluir `trace_id` y `span_id` | `JsonFormatter` auto-inyecta `trace_id` y `root_id` (equivalente conceptual de trace_id); `Tracer.self_id` cumple rol de span_id. |
| **Low-cardinality attrs** | Evitar PII e identificadores de alta cardinalidad | Solo `user_id`/`isp_id` permitidos. PII crudo prohibido. Filtrado regex de claves sensibles. |
| **Operation naming** | Spans nombrados por operación, no por URL | `component=billing event=sync_complete`, nunca `event="GET /users/123"`. |
| **Propagación en async** | Context preservado en queues y background | `Sidekiq::ClientMiddleware`, `BugBunny::PublisherTracing`, `TaskMonitor` generan contexto nuevo si falta. |
| **Resource vs operation split** | `service.*` es resource-level, lo demás operation-level | `service` auto-inyectado por `JsonFormatter` (resource); `component`/`event`/etc emitidos por el call site (operation). |
| **Structured logging** | `Body` libre + `Attributes` estructurados | `JsonFormatter` acepta String libre → `body`; KV → atributos al root; Hash → merge directo. Los tres casos mapean al Log Data Model. |
| **Event name pattern** | OTel Events API usa `event.name` | ExisRay ya tiene `event=<snake_case>` — mapeo directo y natural a `event.name`. |
| **Severity** | `severity_text` con valores ERROR/WARN/INFO/DEBUG | ExisRay usa exactamente esos valores. |
| **Reloj monotónico** | OTel recomienda clocks monotónicos para duración | ExisRay obliga `Process::CLOCK_MONOTONIC`. |

---

## 🔴 Errores concretos a corregir

### 1. Mapeo inventado: `duration_s → duration`

**Archivo**: `skill/references/standard.md` línea ~41.

**Problema**: OTel no tiene un atributo semántico genérico llamado `duration`. Las duraciones en OTel se expresan de dos formas:
- **En spans**: implícitamente, por diferencia entre `start_time_unix_nano` y `end_time_unix_nano`. No hay atributo.
- **En metrics**: con nombres específicos de convención, ej: `http.server.request.duration` (histograma, en segundos, unit `s` vía UCUM).

El mapeo `duration_s → duration` es aspiracional y no existe en las specs.

**Fix**: reemplazar esa fila por notas más precisas:
- `duration_s` en logs es una **extensión Wispro**, no OTel estándar.
- Donde corresponda, indicar mapeo a la métrica específica: `http.server.request.duration` para requests HTTP.

**Prioridad**: baja (es un error de documentación, no de código). Hacer junto con el próximo pass de `standard.md`.

---

### 2. `status` tiene dos significados incompatibles

**Archivos**: `lib/exis_ray/log_subscriber.rb:101` (HTTP integer) y `lib/exis_ray/task_monitor.rb:32,42,48` (string semántico).

**Problema concreto**:

```
# HTTP (LogSubscriber)
{"component":"exis_ray","event":"http_request","status":200,"duration_s":0.12}

# Task (TaskMonitor)
{"component":"exis_ray","event":"task_finished","status":"success","duration_s":1.25}
```

El mismo campo `status` es a veces `Integer` (código HTTP), a veces `String` (semántico). Esto rompe:
- **Queries en log aggregators**: `status:>=500` no funciona si hay logs donde `status` es string.
- **Type inference** del backend: oscila entre `long` y `keyword`.
- **Alineación con OTel**: OTel separa `http.response.status_code` (integer) de `otel.status_code` (enum UNSET/OK/ERROR) — son campos distintos intencionalmente.

**Fix propuesto** (cambio breaking, requiere versión mayor):

| Contexto | Campo actual | Campo propuesto |
|:---------|:-------------|:----------------|
| HTTP request | `status: 200` | `http_status: 200` (o `http.response.status_code` si vamos full OTel) |
| Task/Job lifecycle | `status: "success"` | `outcome: "success"` |

Alternativa sin breaking change: dejar `status` como está pero documentar explícitamente la dualidad en `standard.md` y avisar a consumidores de logs que hagan type coercion. Peor solución, pero viable.

**Prioridad**: media. No bloquea nada hoy, pero es deuda técnica que crece con cada servicio nuevo que adopta la gema.

---

## 📋 Gaps — campos OTel estándar que ExisRay no emite

Wins relativamente baratos. Ordenados por ratio valor/esfuerzo.

### G1. `severity_number` (SeverityText numérico)

OTel Log Data Model define `SeverityNumber` además de `SeverityText`. Tabla oficial:

| `SeverityText` | `SeverityNumber` |
|:---------------|:-----------------|
| DEBUG | 5 |
| INFO  | 9 |
| WARN  | 13 |
| ERROR | 17 |
| FATAL | 21 |

**Dónde agregar**: `JsonFormatter` — mapear el nivel Ruby (`Logger::DEBUG` = 0, etc.) al número OTel al inyectar `level`.

**Esfuerzo**: 15 minutos. Solo agregar una constante y una línea en el formatter.

**Valor**: herramientas OTel-native pueden filtrar/ordenar por severidad numéricamente.

---

### G2. `exception.type` / `exception.message` / `exception.stacktrace`

Actualmente `TaskMonitor` emite `error_class` y `error_message`. OTel define `exception.type` / `exception.message` / `exception.stacktrace`.

**Dónde agregar**: `TaskMonitor`, `LogSubscriber` (para errores HTTP no rescatados), eventualmente `BugBunny::ConsumerTracingMiddleware`.

**Decisión pendiente**: ¿renombrar `error_class` → `exception.type` (breaking), o emitir ambos durante una transición? Mi recomendación: emitir ambos por 1-2 versiones, marcar `error_class`/`error_message` como deprecated en CHANGELOG, remover en versión mayor.

**Esfuerzo**: 1-2 horas (toca varios archivos + tests).

**Valor**: alto. Son los campos estándar que todo backend OTel espera para errores.

---

### G3. `service.version` y `deployment.environment` como resource attrs

ExisRay auto-inyecta `service` (que equivale a `service.name`), pero no `service.version` ni `deployment.environment`. Son los otros dos resource attributes que OTel considera prácticamente obligatorios.

**Dónde agregar**: `Configuration` con defaults sensatos:
- `service.version`: leer de `Rails.application.config.version` si existe, o de un ENV var, o del tag git.
- `deployment.environment`: `Rails.env` directamente.

Luego `JsonFormatter` los inyecta automáticamente como `service_version` y `deployment_environment` (o con namespace OTel-like si decidimos ir por ahí).

**Esfuerzo**: 1 hora.

**Valor**: alto. Los backends OTel usan estos tres campos (`service.name` + `service.version` + `deployment.environment`) para agrupar/desagrupar servicios — sin ellos, versiones distintas del mismo servicio se mezclan.

---

### G4. `http.route` (route template, distinto de `url.path`)

`LogSubscriber` emite `path` (URL concreta, ej `/users/42`) y `controller`/`action` (ej `UsersController`/`show`). OTel pide `http.route` = plantilla de ruta, ej `/users/:id`.

**Dónde agregar**: `LogSubscriber.build_payload`. Se puede extraer de `Rails.application.routes.recognize_path` o del payload de ActionController si está disponible.

**Esfuerzo**: 2-3 horas (hay que manejar casos donde no se puede resolver la ruta, rutas dinámicas, etc.).

**Valor**: medio-alto. Reduce cardinalidad de agregación (`/users/:id` vs miles de `/users/<id_concreto>`). Es el campo correcto para dashboards de latencia por endpoint.

---

### G5. `user_agent.original`, `server.address`, `network.protocol.version`

Atributos HTTP estándar que `LogSubscriber` no emite. Están disponibles en el payload del evento de Rails o en `request.env`.

**Dónde agregar**: `LogSubscriber.build_payload`. Algunos ya son accesibles via `event.payload[:headers]`.

**Esfuerzo**: 1 hora.

**Valor**: medio. Útil para análisis de tráfico, bots, etc. Hoy los usuarios lo agregan manualmente via subclase `extra_fields`, lo cual funciona pero debería ser default.

---

### G6. Messaging semantic conventions para BugBunny

OTel tiene semantic conventions específicas para mensajería:

- `messaging.system = "rabbitmq"`
- `messaging.operation = "publish" | "receive" | "process"`
- `messaging.destination.name = <exchange>`
- `messaging.rabbitmq.destination.routing_key = <routing_key>`
- `messaging.message.id = <uuid>`

**Dónde agregar**: `BugBunny::PublisherTracing` (lado publish) y hook de consumer (lado receive/process). Los dos ya tienen acceso a la metadata AMQP.

**Esfuerzo**: 2-3 horas.

**Valor**: alto para observabilidad de flujos RPC entre servicios. Permite que dashboards OTel-native (Tempo, Jaeger, Honeycomb) rendericen correctamente los spans de RabbitMQ.

**Dependencia**: coordinar con la gema BugBunny — tal vez tenga sentido que este aporte viva en BugBunny, no en ExisRay. Revisar antes de implementar.

---

## 🟡 Divergencias deliberadas (documentar, no cambiar)

Estas son decisiones conscientes donde ExisRay se aparta de OTel por buenas razones. Hay que **dejarlas por escrito en `standard.md`** para que el equipo sepa que son intencionales.

### D1. Wire format AWS X-Ray, no W3C Trace Context

OTel estándar: `traceparent: 00-<trace-id>-<parent-id>-<flags>` + `tracestate`.
ExisRay: `X-Amzn-Trace-Id: Root=1-...;Self=...;CalledFrom=...;TotalTimeSoFar=...ms`.

**Razón**: toda la infra de Wispro vive en AWS y usa X-Ray como backend de trazas. Adoptar W3C obligaría a un shim bidireccional y no resolvería ningún problema real. Si algún día migramos a un backend OTel-native, se convertirá en una traducción en el edge (HTTP middleware) — no hay que refactorar todo el core.

**Acción**: agregar sección "Wire Format" a `standard.md` explicando esto.

---

### D2. Flat JSON en lugar de resource/attributes anidado

OTel Log Data Model anida: `{"Resource": {...}, "Attributes": {...}, "Body": "..."}`.
ExisRay emite flat: `{"service": "...", "component": "...", "event": "...", ...}`.

**Razón**: los log aggregators comunes (CloudWatch, Loki, Datadog classic) indexan mejor JSON flat. Queries como `component:auth AND event:login_failed` son triviales en flat; en anidado requieren dot-path o JSON path en cada query.

**Acción**: documentar en `standard.md`. Si en el futuro se exporta a un backend OTel-native, el exporter puede hacer el unflatten al emitir.

---

### D3. Sufijos de unidad en keys (`_s`, `_ms`, `_bytes`)

OTel usa unit metadata UCUM (en metrics) o nombres de atributo sin sufijo (en attrs). ExisRay usa sufijos en el nombre del campo.

**Razón**: en logs flat JSON, un campo llamado `duration` sin indicación de unidad es ambiguo. El sufijo hace que el consumidor humano y el parser automático sepan inmediatamente la unidad sin metadata externa. Es la regla "Data First" del manifiesto Wispro.

**Acción**: documentar. Cuando se mapee a métricas OTel (ver G1-G6), usar los nombres OTel sin sufijo en la métrica, reteniendo el sufijo en el log.

---

### D4. Campo `source` (http/sidekiq/task/system)

No tiene equivalente OTel directo. Lo más parecido es `span.kind`, pero mide otra cosa (rol en el span, no entrypoint del proceso).

**Razón**: es el campo más útil para filtrado operacional en Wispro — saber si un error viene de una request HTTP, un job o un consumer es la primera pregunta que se hace cualquiera mirando logs.

**Acción**: documentar que es una extensión Wispro. Opcionalmente, agregar también `span.kind` cuando exista (ver R3 en el roadmap).

---

### D5. Campo `component`

OTel lo más parecido es `instrumentation.scope.name` (nombre de la librería que emite). ExisRay lo usa para identificar el módulo de negocio (`component=billing`, `component=auth`).

**Razón**: `component` es dominio-específico y útil para filtrado operacional. No choca con OTel si en el futuro agregamos también `instrumentation.scope.name` para el emisor técnico.

**Acción**: documentar.

---

## 🛣 Roadmap priorizado

Ordenado por **(valor / esfuerzo)**, no cronológicamente. Decidir cuándo atacar cada uno en función de prioridades del proyecto.

### Quick wins (1 día de trabajo total)

- [ ] **R1. `severity_number` en `JsonFormatter`** — G1. 15 min. Cambio no-breaking.
- [ ] **R2. `service.version` + `deployment.environment` en `Configuration` + `JsonFormatter`** — G3. 1 h. Cambio no-breaking.
- [ ] **R3. Documentar divergencias D1-D5 en `skill/references/standard.md`** — sección nueva "Divergencias deliberadas con OTel". 30 min.
- [ ] **R4. Corregir mapeo `duration_s → duration` en `standard.md`** — Error #1. 10 min.
- [ ] **R5. Agregar `user_agent.original`, `server.address` en `LogSubscriber`** — G5. 1 h.

### Medio esfuerzo (2-4 días)

- [ ] **R6. Emitir `exception.type` + `exception.message` junto a `error_class`/`error_message` (dual durante transición)** — G2. 1-2 h + tests.
- [ ] **R7. `http.route` en `LogSubscriber`** — G4. 2-3 h + tests.
- [ ] **R8. Mapeo de messaging semantic conventions para BugBunny** — G6. 2-3 h + coordinación con gema BugBunny.

### Cambios breaking (requieren versión mayor, ej v1.0)

- [ ] **R9. Resolver dualidad de `status`**: `http_status` (Integer) + `outcome` (String). Error #2. Deprecar `status` actual por 2 versiones antes de romper.
- [ ] **R10. Renombrar `error_class`/`error_message` → `exception.type`/`exception.message`** — completar transición iniciada en R6.
- [ ] **R11. (Opcional) Agregar modo "OTel-native export"**: un formatter alternativo que emita el formato anidado de OTel Log Data Model para consumidores que lo necesiten. No reemplaza el formato flat default.

### Investigación (sin commitment aún)

- [ ] **R12. Evaluar `span.kind`**: ¿vale la pena agregarlo junto a `source`? Lo decidimos cuando tengamos un caso de uso concreto (ej: un backend OTel-native o un dashboard que lo pida).
- [ ] **R13. Evaluar namespace `wispro.*`** para campos dominio-específicos (`wispro.isp.id`, `wispro.correlation_id`). OTel recomienda prefijos de vendor para atributos custom. Sería una mejora de limpieza semántica pero rompe queries existentes.
- [ ] **R14. Evaluar exporter OTLP directo**: hoy los logs van a Rails.logger → stdout → log aggregator. Un exporter opcional que mande directo a un Collector OTLP sería una feature grande pero muy alineada con OTel.

---

## Cómo usar este documento

- **Al agregar un campo nuevo a ExisRay**: revisar si ya existe una convención OTel para ese campo en `.agents/skills/opentelemetry/references/`. Si existe, usar el nombre OTel. Si hay razón para divergir, sumarla a la sección "Divergencias deliberadas".
- **Al corregir algo de los errores #1 o #2**: mover la entrada correspondiente a CHANGELOG.
- **Al completar un item del roadmap**: marcarlo `[x]` y anotar la versión donde se incluyó.
- **Al revisar la alineación periódicamente**: verificar que las tres secciones (alineado / gaps / divergencias) siguen siendo exactas — el ecosistema OTel evoluciona, y lo que hoy es "no existe equivalente" mañana puede tener una convención nueva.

---

**Última revisión**: 2026-04-05
**Próxima revisión sugerida**: al release de v0.6.0 o cuando se ataque el primer item del roadmap.
