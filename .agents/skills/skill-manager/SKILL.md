---
name: skill-manager
description: Configura, valida y sincroniza la infraestructura de skills en cualquier proyecto Ruby (gema o servicio). Úsala para inicializar `skills.yml`, verificar la skill del proyecto (`skill/`), sincronizar skills de dependencias a `.agents/skills/`, o validar que todo el estándar se cumpla. Requiere `skill-builder`.
---

# Skill Manager

Skill unificada que gestiona toda la infraestructura de skills de un proyecto Ruby, sea gema o microservicio. Detecta automáticamente el tipo de proyecto y actúa en consecuencia.

## Detección de tipo de proyecto

- **Gema**: existe `.gemspec` en la raíz.
- **Servicio**: existe `config/application.rb`.
- Si ambos existen, priorizar gema.

## Requisitos
- La skill `skill-builder` debe estar disponible para generar `skill/SKILL.md`.

---

## Flujo de Trabajo (Modo Update)

### Paso 1 — Determinar escenario de complejidad de la skill
Analizá el proyecto para determinar qué estructura de `skill/` corresponde:

- **Escenario 1 (simple):** Proyecto pequeño → solo `skill/SKILL.md`.
- **Escenario 2 (con referencias):** API extensa o catálogo de errores grande → `SKILL.md` + `references/`.
- **Escenario 3 (con scripts):** Necesita herramientas de diagnóstico, migración o validación → `SKILL.md` + `scripts/`.
- **Escenario 4 (completa):** Combina referencias y scripts → `SKILL.md` + `references/` + `scripts/`.

Si `skill/` ya existe, evaluá si el escenario debe escalar.

### Paso 2 — Generar o actualizar la skill del proyecto
Ejecutá `skill-builder` para generar o actualizar `skill/`. El skill-builder detecta automáticamente si es gema o servicio y analiza el código correspondiente.

### Paso 3 — Gemspec (solo gemas)
Si el proyecto es una gema, verificá que el `.gemspec` cumpla:

1. **`metadata["documentation_uri"]`** apuntando a la carpeta de skill.
   - Si falta, inferí la URL desde `homepage_uri` o `source_code_uri`:
     `spec.metadata["documentation_uri"] = "https://github.com/[ORG]/[GEM_NAME]/blob/v#{spec.version}/skill"`

2. **`spec.files` incluye `skill/`** para que la skill se empaquete dentro de la gema.
   - Si usa `git ls-files`: verificá que `skill/` no esté en `.gitignore`.
   - Si usa un glob explícito: asegurate de que incluya `skill/**/*`.

- Mostrá el diff y pedí confirmación antes de escribir.

### Paso 4 — Configurar skills.yml
Si no existe `skills.yml` en la raíz, crealo detectando dependencias en el `Gemfile` y repos conocidos.

```yaml
# skills.yml — Manifiesto único de skills del proyecto

# --- MCPs requeridos ---
# Declara qué MCPs necesita el proyecto. Las skills verifican
# disponibilidad antes de usarlos. Si falta alguno, avisan pero no se rompen.

mcps:
  - github
  - clickup

# --- Dependencias (sync) ---

gems:              # Skills empaquetadas en gemas (copia local)
  - name: mi_gema

services:          # Skills de microservicios (GitHub → skill/)
  - name: mi_servicio
    repo: wispro/mi_servicio

skills:            # Skills de repos GitHub (con path opcional)
  # Sin path → usa convención .agents/skills/[name]/
  - name: gem-release
    repo: wispro/ai_knowledge
  - name: skill-manager
    repo: wispro/ai_knowledge
  # Con path → para skills.sh u otros repos con estructura distinta
  - name: rabbitmq-expert
    repo: martinholovsky/claude-skills-generator
    path: skills/rabbitmq-expert

# --- Configuración de skills ---
# Cada skill puede tener su sección de configuración específica.
# Las skills leen su sección del skills.yml del proyecto.

sentry:
  projects:
    - billing-api
    - billing-workers
```

*Mostrá diff y pedí confirmación.*

### Paso 5 — Configurar sincronización
Asegurate de que el script de sync esté configurado para ejecutarse:
- Agregá al final de `bin/setup`:
  ```bash
  ruby .agents/skills/skill-manager/scripts/sync.rb
  ```

### Paso 6 — Git
- Agregá las skills de dependencias al `.gitignore` (cada entrada declarada en `skills.yml`):
  ```gitignore
  # Skills de dependencias (generadas por skill-manager sync)
  .agents/skills/[dep-name]/
  ```

### Paso 7 — CLAUDE.md
El bloque "Knowledge Base" debe estar al **tope absoluto** del archivo:
```markdown
## Knowledge Base
- **Mandato Crítico:** Las skills en `.agents/skills/` incluyen conocimiento de dependencias.
- **Protocolo de Consulta:** El agente DEBE leer la skill de una dependencia antes de responder sobre ella.
- **Rebuild:** `ruby .agents/skills/skill-manager/scripts/sync.rb` actualiza las skills de dependencias.
```

---

## Script de sincronización

El script `scripts/sync.rb` lee `skills.yml` y sincroniza todas las skills de dependencias a `.agents/skills/`.

| Sección | Fuente | Mecanismo |
|---|---|---|
| `gems` | Gema Ruby instalada | Copia local desde `gem_dir/skill/` |
| `services` | Repo de microservicio | GitHub API → `skill/` del repo |
| `skills` | Repo GitHub | GitHub API → path configurable (default: `.agents/skills/[name]/`) |

### Ejecución directa
```bash
ruby .agents/skills/skill-manager/scripts/sync.rb
```

### Requisitos del script
- Ruby (stdlib — sin dependencias externas)
- `gh` CLI o `GITHUB_TOKEN` en el entorno (para repos privados)
- `skills.yml` en la raíz del proyecto

---

## MCP de GitHub (opcional)

Si tenés un MCP de GitHub disponible, el agente puede usarlo para:
- **Inspeccionar repos** sin depender de `GITHUB_TOKEN` en el entorno.
- **Detectar estructura de skills** en dependencias.
- **Armar `skills.yml` inicial**: explorar repos del `Gemfile` y detectar cuáles tienen skill.
- **Verificar cambios**: comparar la skill local con la remota antes de actualizar.

Si el MCP no está disponible, se ejecuta el script de sync como fallback.

---

## Modos de Uso

### /skill-manager check
Valida el cumplimiento del estándar sin modificar archivos:
1. Verificá que exista `skill/SKILL.md`.
2. Verificá consistencia: todo archivo en `references/` y `scripts/` debe estar referenciado en `SKILL.md`, y viceversa.
3. **(Solo gemas)** Verificá `documentation_uri` y que `spec.files` incluya `skill/`.
4. Verificá existencia de `skills.yml`.
5. Verificá `.gitignore` y `bin/setup`.
6. Reportá: OK o lista de errores con pasos para resolverlos.

### /skill-manager update
Ejecuta el flujo de trabajo completo (Pasos 1-7). Configura toda la infraestructura sin tocar contenido existente de skills.

### /skill-manager sync
Actualiza las skills de dependencias en `.agents/skills/`:
1. Si hay MCP de GitHub disponible, usalo para inspeccionar repos y descargar skills.
2. Si no hay MCP, ejecutá el script `scripts/sync.rb`.
3. Reportá qué skills se actualizaron, cuáles son nuevas y cuáles no tienen skill.
