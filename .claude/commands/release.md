---
name: release
description: Prepare a new ExisRay release — bump version, update CHANGELOG, commit, push to main, and create git tag.
argument-hint: <version> (e.g. 0.5.9)
allowed-tools: [Read, Edit, Write, Bash, Glob, Grep]
---

# Release ExisRay $ARGUMENTS

Seguí estos pasos para preparar y publicar la versión `$ARGUMENTS`.

## 1. Verificar cambios pendientes

Revisá qué cambios hay desde el último release:

```bash
git log --oneline $(git describe --tags --abbrev=0)..HEAD
git diff --stat
```

## 2. Verificar que los tests pasan

```bash
bundle exec rspec
```

Si hay fallos, detenerse y resolverlos antes de continuar.

## 3. Bump de versión

Editá `lib/exis_ray/version.rb`:
```ruby
VERSION = "$ARGUMENTS"
```

## 4. Actualizar CHANGELOG.md

Agregá una nueva entrada al tope del CHANGELOG con el formato:

```markdown
## [$ARGUMENTS] - FECHA_HOY

### Added / Changed / Fixed / Removed
- **Componente:** Descripción del cambio.
```

Basate en los commits desde el último tag para identificar qué va en cada sección.

## 5. Commit

```bash
git add lib/exis_ray/version.rb CHANGELOG.md [otros archivos modificados]
git commit -m "chore: bump version to $ARGUMENTS and update CHANGELOG"
```

## 6. Push a main y tag

```bash
git push origin HEAD:main
git tag v$ARGUMENTS
git push origin v$ARGUMENTS
```

El tag dispara el build automático en RubyGems vía CI.
