---
name: gem-release
description: Automatiza el proceso de liberación (release) de gemas Ruby siguiendo estándares de industria. Úsala cuando necesites subir una nueva versión a RubyGems. Ejecuta quality-code, propone versión, genera CHANGELOG, regenera la skill y publica. Soporta [patch|minor|major].
---

# Gem Release Expert

Sos el responsable de garantizar que el proceso de publicación de una gema sea seguro, pase todos los controles de calidad y tenga documentación de clase mundial.

## Parámetros de Uso
- `/gem-release` — El agente analiza los cambios y propone el tipo de bump.
- `/gem-release patch|minor|major` — Override manual del tipo de bump.

## Flujo de Trabajo Obligatorio

### Paso 1 — Quality Code
Ejecutá `quality-code` para validar linting, tests, YARD incremental y skill.

### Paso 2 — Propuesta de Versión
No asumas rutas fijas. Investigá el entorno:
- Detectá el nombre de la gema del `.gemspec`.
- Localizá el archivo de versión (`lib/**/version.rb`).
- Leé la versión actual.
- **Análisis de cambios:** Revisá **todas** las fuentes de cambios:
  1. Commits desde el último tag: `git log [último-tag]...HEAD`
  2. Diff commiteado contra el tag: `git diff [último-tag]...HEAD`
  3. Cambios sin commitear (staged + unstaged): `git status` y `git diff` / `git diff --cached`
  
  **Importante:** Los cambios sin commitear son parte del release.
  
  Clasificá todos los cambios en conjunto:
  - **major** — Breaking changes: métodos/clases eliminados o renombrados, cambios en firmas de métodos públicos, cambios incompatibles en comportamiento.
  - **minor** — Nuevas funcionalidades: métodos/clases nuevos, nuevas opciones de configuración, funcionalidad extendida sin romper compatibilidad.
  - **patch** — Bugfixes, mejoras de performance, refactors internos sin cambios en la API pública.
- **Propuesta:** Mostrá un resumen de los cambios, la clasificación y la versión propuesta (Actual → Nueva). Esperá confirmación.
- Si el usuario pasó un override (`/gem-release major`), usá ese tipo directamente.

### Paso 3 — Documentación y Skill
1. **Skill Experta:** Ejecutá `skill-builder` en modo **completo** para regenerar `skill/SKILL.md` (y `references/`, `scripts/` si aplica) con la API actualizada de la nueva versión.
2. **Gemspec — Empaquetado de la Skill:** Ejecutá `/skill-manager check` para validar que el gemspec esté en orden. Verificá que `skill/` esté incluido en `spec.files`.
   - Si `spec.files` usa `git ls-files`, asegurate de que `skill/` esté commiteado.
   - Si `spec.files` usa un glob explícito, asegurate de que incluya `skill/**/*`.
   - Asegurá la presencia de `metadata["documentation_uri"]` apuntando a `skill/`.

### Paso 4 — Aplicación del Release
1. Actualizá el archivo `version.rb` con la Nueva Versión.
2. **Generar entrada de CHANGELOG** (ver sección "Generación de CHANGELOG" abajo).
3. **Persistencia Git:**
   - `git add .`
   - `git commit -m "release: v[NUEVA_VERSION]"`
   - `git tag -a v[NUEVA_VERSION] -m "Version [NUEVA_VERSION]"`

### Paso 5 — Push (Requiere confirmación)
Mostrá un resumen del commit y el tag creados. Esperá confirmación explícita antes de pushear.
- `git push origin main`
- `git push origin v[NUEVA_VERSION]`

**Nota:** No es necesario hacer `gem build` ni `gem push` manualmente. Un GitHub Action se encarga de buildear y publicar la gema en RubyGems cuando detecta el tag.

---

## Generación de CHANGELOG

### Fuente de datos
Leer todos los commits desde el último tag: `git log [último-tag]...HEAD --format="%H %s (%an)"`

### Filtrado
Ignorar commits que matcheen:
- `release:` — commits de release anteriores
- `Merge branch` / `Merge pull request` — merges automáticos
- `chore:` — tareas de mantenimiento sin impacto funcional

### Agrupación por tipo
Clasificar cada commit por su prefijo conventional commit:

```markdown
## [X.X.X] — YYYY-MM-DD

### Nuevas funcionalidades
- Agregar endpoint de facturación (#123) — @dev1
- Soportar filtro por fecha en listado — @dev2

### Correcciones
- Corregir cálculo de IVA en pagos parciales — @dev1
- Resolver timeout en conexión a Redis — @dev3

### Mejoras internas
- Extraer servicio de notificaciones — @dev2
- Optimizar queries de reportes — @dev1
```

**Mapeo de prefijos:**
- `feat:` → **Nuevas funcionalidades**
- `fix:` → **Correcciones**
- `refactor:`, `perf:`, `style:` → **Mejoras internas**
- `docs:` → **Documentación**
- `test:` → **Tests**
- Sin prefijo reconocido → **Otros cambios**

### Formato
- Cada entrada: descripción limpia (sin el prefijo), PR o issue si está en el mensaje, autor (`@nombre`).
- Fecha en formato `YYYY-MM-DD`.
- Si el `CHANGELOG.md` no existe, crearlo con header `# Changelog`.
- La entrada nueva va al tope del archivo, debajo del header.

### Atribución
Extraer el autor de cada commit con `git log --format="%an"`. Esto permite saber qué dev contribuyó a cada cambio en el release.

---

## Reglas de Seguridad y Estilo
- **Tag con `v`:** Los tags de gemas usan formato `vX.X.X`.
- **Stop on Failure:** Si quality-code falla, detenete. No fuerces el release.
- **Confirmation:** Siempre esperá confirmación antes de persistir cambios en Git y publicar.
- **Sin Hardcoding:** No uses versiones de Ruby o rutas específicas. Confiá en el entorno configurado.
- **CHANGELOG is Law:** Todo release debe tener su entrada en CHANGELOG.md.
