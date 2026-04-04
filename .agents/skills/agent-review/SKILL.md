---
name: agent-review
description: Review de código entre agentes AI via ClickUp. Úsala SIEMPRE que el usuario mencione "review", "crear review", "review para gemini/opencode/claude", "que revise gemini/opencode/claude", "tengo reviews pendientes", o quiera que otro agente revise el trabajo realizado. Crea tickets con checklist de revisores, permite agregar revisores, y guía el proceso de review. Requiere MCP de ClickUp.
---

# Agent Review

Skill para crear y gestionar reviews de código entre agentes AI. Un agente trabaja, crea un ticket de review en ClickUp, y otros agentes lo revisan y dan feedback — todo trazable.

## Configuración

### MCP de ClickUp
Requiere el MCP de ClickUp. Verificá que esté en `mcps:` del `skills.yml`:

```yaml
mcps:
  - clickup
```

### Lista en ClickUp

| Lista | ID | Uso |
|---|---|---|
| **Agent Reviews** | `901415149921` | Reviews de código entre agentes |

## Flujos

### 1. Crear review

**Trigger:** El usuario dice "creá un review para Gemini" o "review para Gemini y OpenCode".

#### Paso 1 — Recopilar contexto
Analizá TODO el trabajo realizado en la sesión actual revisando estas 3 fuentes:
1. **Commits sin pushear:** `git log @{u}..HEAD --oneline` (o desde el último tag si no hay upstream)
2. **Cambios sin commitear:** `git diff` y `git diff --cached` (staged + unstaged)
3. **Archivos nuevos:** `git status` para detectar archivos no trackeados

Con base en ese análisis completo, armá el resumen para la descripción del ticket:
- **Resumen de cambios:** qué se hizo y por qué
- **Decisiones tomadas:** elecciones de diseño, trade-offs
- **Cambios pendientes:** qué falta por hacer
- **Dudas o riesgos:** puntos que merecen atención del revisor

#### Paso 2 — Crear ticket
Usá `clickup_create_task` en la lista Agent Reviews (`901415149921`):

**Título:** `[proyecto] — descripción concreta de lo que se hizo`
- Ejemplo: `[bug_bunny] Implementar reconexión con backoff exponencial`
- Ejemplo: `[billing-api] Migrar endpoint de pagos a V2`
- NO poner "review" en el título — ya se sabe por la lista.

**Descripción:**

El agente debe analizar los commits sin pushear, cambios sin commitear y archivos nuevos, **entender** qué se hizo, y **escribir** la descripción en sus propias palabras. No copiar output de git ni listar archivos mecánicamente. Referenciar archivos solo cuando aportan contexto puntual (ej: "Breaking change en `reconnect!` de `connection.rb:45`").

```markdown
**Proyecto:** [nombre]
**Autor:** [Claude/Gemini/OpenCode]
**Fecha:** [YYYY-MM-DD]
**Revisores:** [lista de agentes que deben revisar]

## Resumen
[Qué se hizo y por qué — 2-3 líneas]

## Qué se hizo
[Descripción clara y detallada del trabajo realizado. Explicar la lógica,
los componentes creados o modificados, y cómo encajan. Referenciar archivos
solo cuando es relevante para entender un punto específico.]

## Decisiones
[Elecciones de diseño y justificación de cada una]

## Pendiente
[Qué falta por hacer o commitear, si corresponde]

## Atención
[Puntos que el revisor debería mirar con cuidado: breaking changes,
riesgos, dependencias de test, etc.]

## Checklist
- [ ] [Agente revisor 1]
- [ ] [Agente revisor 2]
```

#### Paso 3 — Agregar tags
Con `clickup_add_tag_to_task`:
- Tag del **proyecto** (ej: `bug_bunny`, `billing-api`)
- Tag de cada **agente revisor** (ej: `gemini`, `opencode`). NO taguear al autor.

#### Paso 4 — Confirmar
Mostrá al usuario: "Review creado: [link]. Revisores: [lista]. Cuando levantes [agente], decile 'tengo reviews pendientes'."

---

### 2. Agregar revisor a review existente

**Trigger:** El usuario dice "agregá a OpenCode al review".

1. Buscar el ticket de review más reciente del proyecto actual en Agent Reviews (`901415149921`) por tag del proyecto.
2. Agregar al revisor en el checklist (comentario con actualización).
3. Agregar tag del nuevo agente.
4. Confirmar: "OpenCode agregado como revisor a [link]."

---

### 3. Revisar

**Trigger:** El usuario dice "tengo reviews pendientes" o "revisá los reviews".

#### Paso 1 — Buscar reviews pendientes
Buscar en Agent Reviews (`901415149921`) tickets abiertos donde este agente está como revisor sin marcar.

#### Paso 2 — Leer el ticket
Para cada review pendiente, mostrá un resumen al usuario:
- Proyecto, agente autor, fecha
- Resumen del trabajo
- Puntos de atención

#### Paso 3 — Revisar los cambios
Analizá los cambios locales del proyecto:
- Leer los archivos mencionados en el ticket
- Verificar coherencia entre lo descrito y lo implementado
- Evaluar decisiones de diseño
- Identificar bugs potenciales, mejoras, o riesgos

#### Paso 4 — Dar feedback
Crear comentario en el ticket con `clickup_create_task_comment`:

```
## Review — [agente]
**Desde:** [proyecto]
**Agente:** [Claude/Gemini/OpenCode]
**Fecha:** [YYYY-MM-DD]

### Veredicto: [Aprobado / Aprobado con observaciones / Requiere cambios]

### Observaciones
[Feedback detallado punto por punto]

### Sugerencias
[Mejoras opcionales]

### Issues encontrados
[Bugs o problemas que necesitan atención]
```

#### Paso 5 — Marcar como revisado
Actualizar el checklist marcando al agente como revisado. Si todos los revisores marcaron, informar al usuario que el review está completo.

---

### 4. Verificar y cerrar review (agente autor)

**Trigger:** El usuario dice "revisá mi review", "cómo está mi review", "cerrá el review" al agente que creó el review original.

#### Paso 1 — Buscar reviews creados por este agente
Buscar en Agent Reviews (`901415149921`) tickets abiertos por tag del proyecto actual donde este agente es el autor.

#### Paso 2 — Leer feedback de los revisores
Leer los comentarios del ticket con `clickup_get_task_comments`. Para cada revisor:
- ¿Comentó? ¿Marcó su check?
- ¿Cuál fue su veredicto? (Aprobado / Aprobado con observaciones / Requiere cambios)
- ¿Qué observaciones o issues encontró?

#### Paso 3 — Mostrar resumen al usuario
```
Review: [título]
Revisores:
  ✅ [Agente A] — Aprobado con observaciones: [resumen]
  ✅ [Agente B] — Aprobado: [resumen]
  ⬜ [Agente C] — Pendiente

Estado: Todos revisaron / Falta [agente]
```

#### Paso 4 — Cerrar si corresponde
- Si **todos** revisaron y **ninguno** pidió "Requiere cambios": cerrar el ticket con `clickup_update_task` (status → **done**).
- Si algún revisor pidió **"Requiere cambios"**: informar al usuario qué cambios piden y NO cerrar.
- Si **faltan revisores**: informar quién falta y NO cerrar.

---

## Nota sobre agentes

Esta skill funciona con **cualquier agente AI** que tenga acceso al MCP de ClickUp (Claude Code, Gemini CLI, OpenCode, o cualquier otro). Los nombres de agentes en los ejemplos son ilustrativos — el flujo es el mismo independientemente de qué agentes se usen como autor o revisores.

---

## Ejemplo de flujo completo

```
1. Usuario trabaja con Agente A en bug_bunny
   → Agente A implementa reconexión con backoff exponencial

2. Usuario: "creá un review para Agente B y Agente C"
   → Agente A crea ticket en ClickUp con resumen, decisiones, checklist

3. Usuario abre Agente B en el repo de bug_bunny
   Usuario: "tengo reviews pendientes"
   → Agente B busca en ClickUp, encuentra el ticket
   → Agente B revisa los cambios, comenta feedback, marca su check

4. Usuario abre Agente C en el repo
   Usuario: "revisá los reviews"
   → Agente C lee ticket + review de Agente B
   → Agente C comenta feedback, marca su check

5. Usuario vuelve a Agente A
   Usuario: "revisá mi review"
   → Agente A lee los comentarios de los revisores
   → Agente A muestra resumen de veredictos
   → Si todos aprobaron, cierra el ticket
```
