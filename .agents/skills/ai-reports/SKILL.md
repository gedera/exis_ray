---
name: ai-reports
description: Gestiona reportes generados por agentes AI en el espacio ai_knowledge de ClickUp. Úsala cuando detectes un bug en una dependencia, quieras sugerir una mejora, o necesites registrar un TODO. Requiere MCP de ClickUp.
---

# AI Reports

Skill para reportar bugs, mejoras y TODOs desde cualquier proyecto del ecosistema al espacio `ai_knowledge` de ClickUp. Usá esta skill cuando un agente detecte un problema con una dependencia, identifique una oportunidad de mejora, o necesite registrar una tarea.

## Configuración

### MCP de ClickUp
Esta skill requiere el MCP de ClickUp. Verificá que esté en `mcps:` del `skills.yml`:

```yaml
mcps:
  - clickup
```

Si el MCP no está disponible, generá un archivo local como fallback (ver sección Fallback).

### Espacio y Listas

| Lista | ID | Uso |
|---|---|---|
| **Bug Reports** | `901415148810` | Bugs detectados en gemas o servicios del ecosistema. |
| **Improvements** | `901415148812` | Sugerencias de mejora para skills, gemas o servicios. |

## Alcance — Solo dependencias propias

**Regla:** Solo reportar bugs e improvements para gemas, servicios y skills que están bajo nuestro control — es decir, declaradas en el `skills.yml` del proyecto actual (`gems:`, `services:` o `skills:`).

Si el problema es en una dependencia externa (ej: `rails`, `redis`, `sidekiq`), **no crear reporte**. Informar al usuario que el problema está fuera de nuestro control y sugerirle que abra un issue en el repo del mantenedor.

## Cuándo reportar

### Bug Report
Cuando el agente detecta un problema en una dependencia **propia** (declarada en `skills.yml`):
- Un método no se comporta como dice la skill/documentación
- Un error se repite en Sentry y el origen es una dependencia propia
- Un test falla por un bug en una gema interna
- Incompatibilidad entre versiones de dependencias propias

### Improvement
Cuando el agente identifica una oportunidad de mejora en algo **propio**:
- Una skill podría cubrir un caso que no contempla
- Un patrón de código se repite en varios servicios y podría extraerse
- La documentación de una gema propia es insuficiente o incorrecta
- Un flujo podría automatizarse


## Flujo de reporte

### Paso 1 — Preguntar destino
Preguntá al usuario: "¿Querés reportarlo en ClickUp o generar un archivo local?"

### Paso 2 — Clasificar
Determiná el tipo de reporte:
- **Bug** → lista Bug Reports (`901415148810`)
- **Improvement** → lista Improvements (`901415148812`)

### Paso 3 — Generar contenido

#### Template de Bug Report
```
Título: [gema/servicio] — descripción breve del problema

Descripción:
## Contexto
- **Reportado desde:** [nombre del proyecto actual]
- **Versión del proyecto:** [versión actual]
- **Versión de la dependencia:** [versión de la gema/servicio afectado]

## Problema
[Descripción clara del bug]

## Reproducción
[Pasos o código para reproducir]

## Stacktrace
[Si hay stacktrace relevante]

## Impacto
[Frecuencia, severidad, usuarios afectados]

## Sugerencia
[Si el agente tiene una hipótesis de la causa o solución]
```

#### Template de Improvement
```
Título: [gema/servicio/skill] — descripción breve de la mejora

Descripción:
## Contexto
- **Detectado en:** [nombre del proyecto actual]

## Situación actual
[Qué pasa hoy]

## Mejora propuesta
[Qué debería pasar]

## Beneficio
[Por qué vale la pena]
```

### Paso 4 — Crear el reporte

**Con MCP de ClickUp:**
Usá `clickup_create_task` con:
- `list_id` según el tipo de reporte
- `name` del template
- `description` del template
- `priority` según severidad (bug crítico → urgent, mejora → normal)

Después de crear el task, agregar **tags** con `clickup_add_tag_to_task`:
- **Tipo:** `gem` o `service` (según la dependencia afectada)
- **Nombre:** el nombre de la gema o servicio (ej: `bug_bunny`, `billing-api`)

Esto permite filtrar en ClickUp:
- Todos los bugs de gemas → tag `gem`
- Bugs de una gema específica → tag `bug_bunny`
- Todos los bugs de servicios → tag `service`
- Bugs de un servicio específico → tag `billing-api`

**Mostrar link del task creado al usuario.**

### Paso 5 — Confirmar
Mostrá un resumen: "Task creado en ClickUp: [link]. Lista: [nombre]. Tags: [tipo, nombre]. Prioridad: [prioridad]."

---

## Cerrar reportes resueltos

Cuando el agente está en el repo de una gema o servicio y resuelve un bug que tiene un ticket en ClickUp:

### Paso 1 — Buscar tickets abiertos
Usá `clickup_search` o `clickup_filter_tasks` para buscar en Bug Reports (`901415148810`) por el tag de la gema/servicio actual.

### Paso 2 — Identificar el ticket
Si el fix matchea con un reporte abierto (por descripción, error, o referencia), mostrá el ticket al usuario y preguntá: "¿Este fix resuelve el ticket [título] ([link])?"

### Paso 3 — Cerrar
Con confirmación del usuario, usá `clickup_update_task` para:
- Cambiar status a **done** o **closed**
- Agregar un comentario con `clickup_create_task_comment`: "Resuelto en [proyecto] v[versión]. Commit: [hash]."

---

## Conversación entre agentes via comentarios

Los tickets funcionan como hilo de comunicación asíncrona entre el servicio que reportó y la gema/servicio afectado.

### Leer comentarios pendientes
Cuando el agente entra a un repo, puede verificar si hay tickets con actividad nueva:

1. Buscar tickets abiertos en Bug Reports (`901415148810`) e Improvements (`901415148812`) con el tag de la gema/servicio actual.
2. Para cada ticket, leer comentarios con `clickup_get_task_comments`.
3. Si hay comentarios nuevos (preguntas, pedidos de info), mostrá un resumen al usuario: "Hay [N] tickets con actividad nueva para [nombre]."

### Responder a un comentario
Cuando el agente tiene información que aportar a un ticket:

1. Usá `clickup_create_task_comment` para agregar la respuesta.
2. Identificá el contexto: desde qué proyecto se responde, qué se investigó, qué se encontró.

Ejemplo de flujo:
```
1. billing-api reporta: "bug_bunny: reconexión falla después de timeout"
2. bug_bunny lee, comenta: "¿Qué versión de RabbitMQ? ¿SSL habilitado?"
3. billing-api lee, responde: "RabbitMQ 3.12, SSL on, timeout 30s"
4. bug_bunny comenta: "Bug en connection.rb:45. Fix en v4.9.1"
5. bug_bunny cierra el ticket
```

### Formato de comentarios
```
**Desde:** [nombre del proyecto] v[versión]
**Agente:** [Claude/Gemini/OpenCode]

[Contenido del comentario]
```

---

## Fallback — Archivo local

Si el MCP de ClickUp no está disponible, generá un archivo local:

```
.reports/
  2026-04-04-bug-bug_bunny-reconnect.md
  2026-04-04-improvement-sentry-skill-pagination.md
  2026-04-04-todo-investigar-redis-timeout.md
```

Formato del nombre: `YYYY-MM-DD-[tipo]-[descripción-breve].md`

El contenido usa los mismos templates. Estos archivos se pueden subir a ClickUp después manualmente o en el próximo sync.

## Integración con otras skills

Las siguientes skills pueden invocar `ai-reports` cuando detectan algo reportable:

- **`quality-code`** — Si detecta un patrón problemático recurrente en una dependencia.
- **`sentry`** — Si un error apunta a un bug en una gema interna.
- **`skill-builder`** — Si al analizar el código encuentra antipatrones o documentación faltante en dependencias.
- **`gem-release` / `service-release`** — Si durante el release se detectan issues que no bloquean pero deberían registrarse.

En todos los casos, la skill pregunta al usuario antes de crear el reporte.
