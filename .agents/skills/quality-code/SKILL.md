---
name: quality-code
description: Validación de calidad para proyectos Ruby (gemas y servicios). Ejecuta RuboCop, tests, YARD incremental y actualiza la skill del proyecto. Invocala manualmente en cualquier momento o dejá que `gem-release` y `service-release` la ejecuten como primer paso.
---

# Quality Code

Barrera de calidad para proyectos Ruby. Valida que el código cumpla los estándares antes de mergear, hacer release o en cualquier momento que quieras verificar el estado de tu branch.

## Detección de tipo de proyecto

- **Gema**: existe `.gemspec` en la raíz.
- **Servicio**: existe `config/application.rb`.

## Flujo de Trabajo

### Paso 1 — Linting
- Ejecutá `bundle exec rubocop -a` (o `-A`) para corregir ofensas automáticas.
- Si quedan ofensas que no se pueden auto-corregir, reportalas y detenete.

### Paso 2 — Tests
- Ejecutá `bundle exec rspec` (o el test runner detectado).
- Si un test falla, el proceso se detiene inmediatamente.

### Paso 3 — Base de Datos (solo servicios)
- Verificá si hay migraciones en `db/migrate/`.
- Asegurate de que `db/schema.rb` esté actualizado y consistente.

### Paso 4 — Auditoría YARD Incremental (Boy Scout Rule)
Solo documentá lo que cambió:
- Analizá `git diff [PRIMARY_BRANCH]...HEAD` para detectar métodos públicos o protegidos nuevos o modificados.
- **Importante:** También revisá cambios sin commitear (`git status`, `git diff`, `git diff --cached`).
- Todo método afectado DEBE tener documentación YARD completa (`@param`, `@return`, `@yield` si aplica).
- Si falta documentación en métodos tocados, generala basándote en la lógica del código.

### Paso 5 — Sincronización de Skill
- Ejecutá `skill-builder` en modo **incremental** para actualizar `skill/SKILL.md` (y `references/`, `scripts/` si aplica) con los cambios actuales.
- Auditá si el `README.md` necesita actualizarse por los cambios.

### Paso 6 — Reporte
Mostrá un resumen de lo ejecutado:
- RuboCop: OK / X ofensas corregidas
- Tests: OK / X tests, X failures
- YARD: OK / X métodos documentados
- Skill: actualizada / sin cambios
- README: actualizado / sin cambios

## Reglas
- **Stop on Failure:** Si los tests o el linting fallan, detenete. No continues con los pasos siguientes.
- **Sin Hardcoding:** No uses versiones de Ruby o rutas específicas. Confiá en el entorno configurado.
- **Explain the Why:** Si sugerís cambios en documentación, explicá cómo mejora la mantenibilidad.
