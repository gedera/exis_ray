---
name: readme-writer
description: This skill should be used when updating README.md or CHANGELOG.md after adding a new feature, fixing a bug, or releasing a version. Activates when the user mentions "readme", "changelog", "documentation", "release notes", "document this feature", or asks to update the docs.
version: 1.0.0
---

# README & CHANGELOG Writer — ExisRay

## README.md — Estructura y Estilo

El README de ExisRay sigue esta estructura fija. No reorganizar secciones existentes — solo agregar o actualizar.

### Tono y Estilo
- Conciso y técnico — el lector es un dev Rails que quiere integrar la gema rápido
- Ejemplos de código reales, no abstractos
- Mostrar el output (JSON) cuando sea relevante para entender el valor
- Español para texto corrido, inglés para nombres de clases/métodos/campos

### Secciones del README
1. **Badges + descripción una línea**
2. **Features** — lista bullets con las capacidades principales
3. **Installation** — Gemfile + bundle
4. **Configuration** — initializer con todos los options documentados
5. **Usage por integración** — una subsección por integración (HTTP, Sidekiq, BugBunny, etc.)
6. **Advanced** — subclassing Current, Reporter, LogSubscriber

### Cómo documentar una nueva integración

```markdown
## E. NombreIntegración

Descripción en 1-2 oraciones de qué hace y por qué es útil.

### Setup

\`\`\`ruby
# Código mínimo para activar la integración
\`\`\`

### Output

\`\`\`json
{
  "time": "...",
  "root_id": "...",
  "component": "...",
  "event": "..."
}
\`\`\`
```

---

## CHANGELOG.md — Formato

Seguir [Keep a Changelog](https://keepachangelog.com/). Cada entrada en orden cronológico inverso.

### Estructura de una entrada

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added
- **NombreFeature:** Descripción clara de qué se agregó y por qué es útil.
  Mencionar el componente afectado y el beneficio para el usuario.

### Changed
- **NombreComponente:** Qué cambió y por qué (motivación técnica o de UX).

### Fixed
- **Descripción del bug:** Qué fallaba, en qué condición, cómo se resolvió.

### Removed
- **NombreComponente:** Qué se eliminó y qué lo reemplaza (si aplica).
```

### Reglas
- Una entrada por item significativo — no agrupar cosas no relacionadas
- Mencionar el nombre del componente en **negrita** al inicio
- Describir el beneficio para el usuario, no solo el cambio técnico
- Si hay breaking change, marcarlo explícitamente: `⚠️ Breaking:`
- Versiones de patch (0.5.x): bugs y fixes pequeños
- Versiones minor (0.x.0): features nuevas, integraciones
- Versiones major (x.0.0): breaking changes
