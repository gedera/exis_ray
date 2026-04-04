---
name: skill-builder
description: Genera o actualiza la skill empaquetada (`skill/`) para cualquier proyecto Ruby (gema o servicio). Detecta automáticamente el tipo de proyecto y analiza el código correspondiente. Soporta desde un SKILL.md simple hasta skills con references y scripts. Es invocada por `skill-manager`, `gem-release` (regeneración completa) y `quality-code` (actualización incremental).
---

# Skill Builder

Sos un experto en crear skills de conocimiento para proyectos Ruby. Tu objetivo es generar o actualizar `skill/SKILL.md` — un artefacto autocontenido que permite a cualquier agente de IA responder preguntas sobre integración, arquitectura, API, errores y antipatrones del proyecto.

## Detección de tipo de proyecto

- **Gema**: existe `.gemspec` en la raíz.
- **Servicio**: existe `config/application.rb`.
- Si ambos existen, priorizar gema.

**Distribución en gemas:** La skill queda en `skill/` en la raíz del repositorio. Al publicar con `gem-release`, `skill/` se empaqueta en el `.gem`, de modo que los consumidores acceden a la skill directamente desde la gema instalada (`Gem.loaded_specs["[name]"].gem_dir + "/skill/"`) sin descargas adicionales.

**Distribución en servicios:** La skill queda en `skill/` en la raíz del repositorio. Los consumidores la descargan vía `skill-manager sync` desde GitHub.

## Escenarios de Complejidad

La estructura de `skill/` depende de la complejidad del proyecto. `skill-manager` determina el escenario inicial, pero puede evolucionar con el tiempo:

### Escenario 1 — Proyecto simple
```
skill/
  SKILL.md
```
La skill entera cabe en un solo archivo. Secciones autocontenidas de ≤400 tokens.

### Escenario 2 — Con referencias
```
skill/
  SKILL.md
  references/
    api-detallada.md
    errores.md
```
Cuando la API o contratos son extensos, o el catálogo de errores es grande.

### Escenario 3 — Con scripts
```
skill/
  SKILL.md
  scripts/
    diagnostico.rb
```
Cuando el proyecto necesita herramientas ejecutables (diagnóstico, migración, validación).

### Escenario 4 — Completa
```
skill/
  SKILL.md
  references/
    api-detallada.md
    errores.md
  scripts/
    diagnostico.rb
    migration_helper.rb
```

### Criterios para escalar

- **→ references/** cuando una sección de `SKILL.md` supera los 400 tokens y es conocimiento de referencia (API, contratos, errores, catálogos).
- **→ scripts/** cuando el proyecto necesita herramientas ejecutables para diagnóstico, migración o validación que complementen el conocimiento.

## Modos de Ejecución

- **Completo** (invocado por `gem-release` o manualmente): Regenera la skill desde cero analizando todo el código.
- **Incremental** (invocado por `quality-code`): Actualiza solo las secciones afectadas por el diff del PR.

---

## Paso 1 — Descubrir el estado actual

Leer en orden:
1. `skill/SKILL.md` — si existe, es la skill actual.
2. `skill/references/` — referencias existentes.
3. `skill/scripts/` — scripts existentes.
4. `CLAUDE.md` — propósito del artefacto, arquitectura, decisiones clave.

Según el tipo de proyecto:

**Si es gema:**
5. `.gemspec` — nombre, descripción, dependencias.
6. `lib/` — API pública, responsabilidades de clases, firmas de métodos.
7. `spec/` o `test/` — patrones de uso, casos borde, errores esperados.

**Si es servicio:**
5. `config/application.rb` — nombre, configuración.
6. `config/routes.rb` — endpoints HTTP expuestos.
7. `app/` — controllers, models, services, jobs.
8. Queues/mensajería — contratos de eventos (Sidekiq, ActiveJob, etc.).
9. `db/migrate/` — esquema y evolución del modelo de datos.
10. `spec/` o `test/` — patrones de uso, casos borde, errores esperados.

En modo **incremental**, analizar también `git diff [PRIMARY_BRANCH]...HEAD` para identificar qué cambió.

---

## Paso 2 — Analizar el código y determinar escenario

**Común a ambos tipos:**
- **Arquitectura**: Flujo de datos, componentes core, thread safety, dependencias.
- **Uso**: Ejemplos de integración, patrones comunes.
- **Errores**: Excepciones personalizadas, causas, resoluciones.
- **Antipatrones**: Usos incorrectos identificados en tests o código.
- **Scripts necesarios**: ¿Hay flujos de diagnóstico, migración o validación que justifiquen un script?

**Específico de gemas:**
- **API Pública**: Bloque de configuración, clases principales, métodos públicos, parámetros.

**Específico de servicios:**
- **Contratos**: Endpoints HTTP, queues, eventos publicados/consumidos, webhooks.
- **Infraestructura**: Variables de entorno, servicios externos, bases de datos.

Con base en el análisis, determiná qué escenario de complejidad corresponde (1-4). Si la skill ya existe, evaluá si el escenario debe escalar.

---

## Paso 3 — Generar la Skill

Generar `skill/SKILL.md` (y `references/` o `scripts/` si el escenario lo requiere).

### Reglas de escritura (RAG-optimized)

1. **Idioma: español** — Todo el contenido en español. Mantener términos técnicos estándar (ej: "middleware", "routing").
2. **Cada sección <= 400 tokens** — Autocontenida, sin asumir contexto de otras secciones. Si una sección supera este límite, extraerla a `references/`.
3. **Sin prosa introductoria** — Ir directo al contenido técnico.
4. **Sin frontmatter complejo** — No incluir version, profile o audiences.
5. **Sin duplicación** — Si un tema está en `references/`, la skill solo lo referencia.

### Estructura de SKILL.md

#### Titulo y Descripcion

```markdown
# [Nombre] Expert

Skill de conocimiento completo sobre [Nombre]. Consultame para cualquier pregunta sobre integración, arquitectura, API, errores y antipatrones.
```

#### Glosario

Términos del dominio. Formato: `**Término** — Definición concisa (1-3 líneas).`

#### Arquitectura

- Responsabilidad core.
- Mapa de componentes (diagrama ASCII).
- Flujo en runtime y decisiones de diseño.

**Formato de diagramas ASCII:**
- Cajas con `┌─┐└─┘`, flechas con `────>` (horizontal) y `│▼` (vertical).
- Máximo 4-5 componentes por diagrama. Si hay más, dividir en sub-diagramas por capa.
- Sin texto decorativo fuera de las cajas.

Ejemplo:
```
┌──────────┐     ┌──────────┐     ┌──────────┐
│ Request  │────>│ Middleware│────>│ Handler  │
└──────────┘     └──────────┘     └──────────┘
                       │
                       ▼
                 ┌──────────┐
                 │  Cache   │
                 └──────────┘
```

#### API Publica (gemas)

- Bloque de configuración (tipos, defaults, restricciones).
- Clases y métodos (firma, parámetros, retorno).
- Ejemplos de código para operaciones principales.
- Si la API es extensa, mantener un resumen acá y extraer el detalle a `references/api-detallada.md`.

#### Contratos (servicios)

- Endpoints HTTP (método, path, parámetros, respuesta).
- Queues y eventos (nombre, payload, productor/consumidor).
- Webhooks (si aplica).
- Si los contratos son extensos, extraer a `references/contratos.md`.

#### FAQ

Formato Q&A estricto. H3 para la pregunta, respuesta <= 150 palabras. Sin preámbulo.

#### Antipatrones

Qué NO hacer. Por cada uno: nombre, código incorrecto, razón y alternativa.

#### Errores

Catálogo de excepciones. Por cada una: nombre, causa, reproducción y resolución.
Si el catálogo es extenso, mantener los errores más comunes acá y extraer el catálogo completo a `references/errores.md`.

#### Referencias (si existen)

Índice de archivos en `references/` y `scripts/` con descripción de una línea.

```markdown
## Referencias

- [API Detallada](references/api-detallada.md) — Documentación completa de clases y métodos
- [Catálogo de Errores](references/errores.md) — Todas las excepciones con resolución
- [Diagnóstico](scripts/diagnostico.rb) — Script para verificar configuración en runtime
```

---

## Paso 4 — Actualizar README.md

Invocá la skill `documentation-writer` para auditar y actualizar el README.

**Regla fundamental:** El README es para **humanos** (devs que usan la gema/servicio). La skill (`skill/`) es para **agentes**. Son audiencias distintas. **Nunca referenciar `skill/` desde el README.**

### README de una gema (máx 150 líneas)

```markdown
# [Nombre de la gema]

Descripción en una línea.

## Instalación

gem 'nombre', '~> X.X'

## Quick Start

[Ejemplo mínimo funcional — copiar, pegar, funciona]

## Uso

[Ejemplos de las operaciones principales]

## Configuración

[Bloque de configuración con opciones, defaults y descripción]

## Contribuir

[Cómo correr tests, linting, etc.]
```

### README de un servicio (máx 150 líneas)

```markdown
# [Nombre del servicio]

Descripción en una línea.

## Setup

[Pasos para levantar el servicio localmente: bin/setup, docker, etc.]

## Endpoints / Contratos

[Resumen de los endpoints o queues principales]

## Variables de entorno

[Lista de env vars necesarias]

## Testing

[Cómo correr tests]

## Deploy

[Cómo se despliega: branch, tag, Codefresh]
```

### Qué NO poner en el README
- Links a `skill/` ni a `skill/SKILL.md`
- Documentación interna para agentes
- Diagramas ASCII extensos (esos van en la skill)
- Catálogo completo de errores (eso va en la skill)
- FAQ técnico detallado (eso va en la skill)

---

## Paso 5 — Mostrar resumen y esperar aprobación

Mostrá un resumen de los cambios realizados:
- Tipo de proyecto detectado (gema o servicio).
- Escenario de complejidad determinado (y si escaló respecto al anterior).
- Secciones nuevas, modificadas o eliminadas en `SKILL.md`.
- Archivos nuevos o actualizados en `references/` o `scripts/`.
- Cambios en README.md.

Preguntá: "¿Querés ver el diff completo antes de escribir los archivos?"

**Esperá la aprobación explícita del desarrollador** antes de persistir los cambios.
