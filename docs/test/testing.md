# Test — exis_ray

> meta: artefacto test · RFC-013 (shape v2.1, `proposed`) · generado
> manualmente (**piloto RFC-013** — suplemento de gema para validar §j/§k) ·
> anclado a `spec/` · fecha 2026-06-01 · cobertura: completa para los
> componentes aislados; gap real en inyección del Railtie (sin dummy app) y
> matrix de versiones (CI mono-versión).

## 1. Resumen

Estrategia y cobertura de test de la gema (Railtie de observabilidad). Stack:
**RSpec**, 8 suites / **176** examples, **sin SimpleCov**. Cada componente se
testea **aislado con mocks de Rails** (`stub_const`), no contra una app real.
Filosofía **test-last + FDD**. Este artefacto es el **suplemento gema** del
piloto RFC-013: ejercita §j (inyección al host + matrix) y confirma que §k
(concurrencia) es **n/a** acá.

## 2. Cuerpo

### a. Hecho verificable

- **Suites:** 8 / **176** examples (todos unit aislados).
- **Modo:** `railtie`/`library` (no http/worker — es gema).
- **Factories:** 0 (Structs/doubles inline).
- **Regresiones post-incidente:** 2 (#9, #12) — **con** comentario de origen
  (§h, convención ya practicada).
- **% coverage:** `n/a (sin tooling)`.
- **Inyecciones al host testeadas:** 0 de ~7 (§j) — sin dummy app.
- **Matrix:** declarado Ruby ≥2.6 / Rails ≥6; testeado CI **solo 3.4.4** (§j).
- **Tests de concurrencia:** 0 (§k n/a).

### b. Estrategia / pirámide

Todo **unit aislado**: cada clase (`Tracer`, `HttpMiddleware`, `JsonFormatter`,
`LogSubscriber`, `Configuration`, `Current`, `Reporter`, `TaskMonitor`) se
testea sola, mockeando `Rails`/`Logger`/`ActionDispatch`. Sin nivel
integration/system (no hay app real). Mapeo: la gema no mapea a capas de
servicio — los componentes son su propia superficie (RFC-004 interfaz).
Momento: **test-last**.

### c. Inventario de suites

| Suite | Nivel | Modo | Nº specs |
|---|---|---|---|
| `spec/exis_ray/json_formatter_spec.rb` | unit | library | 54 |
| `spec/exis_ray/log_subscriber_spec.rb` | unit | railtie | 29 |
| `spec/exis_ray/tracer_spec.rb` | unit | library | 27 |
| `spec/exis_ray/configuration_spec.rb` | unit | library | 27 |
| `spec/exis_ray/current_spec.rb` | unit | library | 16 |
| `spec/exis_ray/reporter_spec.rb` | unit | library | 8 |
| `spec/exis_ray/task_monitor_spec.rb` | unit | library | 8 |
| `spec/exis_ray/http_middleware_spec.rb` | unit | railtie | 7 |

Invocación: `bundle exec rake` (RSpec + RuboCop), ~1.2s.

### d. Cobertura declarada

| Flujo crítico | Cubierto? | Spec | Fuente del gap |
|---|---|---|---|
| Trace propagation (parse X-Ray headers, root_id) | sí | `spec/exis_ray/tracer_spec.rb`, `http_middleware_spec.rb` | — |
| JSON log formatting + OTel + filtrado sensible | sí | `spec/exis_ray/json_formatter_spec.rb` | — |
| LogSubscriber (HTTP status → log level) | sí | `spec/exis_ray/log_subscriber_spec.rb` | — |
| **Inyección del Railtie en app real** | **no** | — (sin `spec/dummy/`) | inferido — componentes testeados aislados; la inyección (`lib/exis_ray/railtie.rb`) no se ejercita (§j) |

`% coverage: n/a`. Gap nominal: la **inyección** (lo que distingue a una gema
Railtie) no tiene test — solo la lógica de cada componente por separado.

### e. Fixtures / factories / test data

Sin FactoryBot, sin fixtures, sin PII. Datos sintéticos inline: Structs
(`build_event`, `build_route` en `log_subscriber_spec.rb`), `stub_const` de
`Rails`/`Tracer`/`Logger`. n/a la columna entidad (gema sin capa de datos).

### f. Topología de integration/system tests

**n/a** — no se levanta nada real (sin DB/broker/app). Todo mockeado:
`Rails`, `Rails.application`, `Logger`, `ActionDispatch::*` vía `stub_const`/
`instance_double`. Estado requerido para correr: **ninguno** (solo
`activesupport`). No es el sub-caso "gema-envuelve-infra" (exis_ray no envuelve
infra externa; instrumenta el host).

### g. Contract tests (cross RFC-018)

**n/a** — la gema no **consume** servicios (no tiene `docs/consumed/`). Nota: sí
**inyecta** hooks a otras gemas (`BugBunny.consumer_middlewares`, Sidekiq
client/server middleware, `ActiveResource::Base.prepend` —
`lib/exis_ray/railtie.rb:71,96,116`), pero **ninguno tiene test** (cae en §j,
no en §g — es inyección, no consumo).

### h. Tests de no-regresión / nacidos de incidentes

| Test | Incidente | Qué reproduce |
|---|---|---|
| `spec/exis_ray/json_formatter_spec.rb:410` `describe "...(issue #9)"` | issue #9 | inyección de contexto de tracer; root_id nil pero request_id presente (Gap C) |
| `spec/exis_ray/json_formatter_spec.rb:466` `describe "...(issue #12)"` | issue #12 | dedup de claves Symbol/String (no duplicar en JSON) |

- **Convención §h ya practicada** ✅ — exis_ray ancla el incidente en el
  `describe`. Valida que la convención v2.1 es factible y de bajo costo. (Forma
  observada: `(issue #N)` en el describe; la norma sugiere `# Regresión: #N` en
  comentario — ambas cumplen el objetivo de link recuperable sin `git blame`.)

### i. Ejecución, gates y flaky

- **Ejecución:** `bundle exec rake` (RSpec + RuboCop), ~1.2s. Sin gates de
  suite (no hay integration que excluir).
- **Flaky:** 0 (176 pasan consistentes, sin `sleep`/`Thread`).
- **CI:** `.github/workflows/main.yml` — corre la suite, pero ver §j (matrix).

### j. Inyección al host + matrix de versiones

**Sección de alto valor para esta gema** (motivó §j en v2.1).

**Inyección al host** — `lib/exis_ray/railtie.rb` inyecta ~7 cosas; **ninguna
testeada en app real** (no hay `spec/dummy/`):

| Inyección | file:line | Testeada? |
|---|---|---|
| `HttpMiddleware` (`insert_after ActionDispatch::RequestId`) | `railtie.rb:17` | **sin-test** de inyección (lógica del middleware sí, aislada — `mock-rails`) |
| `config.log_tags` (request_id proc) | `railtie.rb:31` | sin-test |
| `Rails.logger.formatter = JsonFormatter.new` | `railtie.rb:57` | sin-test (formatter sí, aislado) |
| `LogSubscriber` (subscribe a ActionController) | `railtie.rb:61` | sin-test (subscriber sí, aislado con `mock-rails`) |
| `BugBunny.consumer_middlewares.use` | `railtie.rb:71` | **sin-test** |
| `ActiveResource::Base.prepend` instrumentation | `railtie.rb:96` | **sin-test** |
| Sidekiq client/server middleware | `railtie.rb:107,116` | **sin-test** |

Gap: lo que **define** a la gema (inyectar al host) es lo único sin test.
Cruza RFC-012 §i del repo (mismo inventario de inyecciones, lado config). Un
`spec/dummy/` cerraría el gap.

**Matrix de versiones:**

| | Valor |
|---|---|
| Declarado (gemspec) | Ruby `>= 2.6.0` · activesupport/railties `>= 6.0` (`exis_ray.gemspec:15,38`) |
| Testeado (CI) | **solo Ruby 3.4.4** (`.github/workflows/main.yml:17`) — sin Appraisal, sin matrix de Rails |
| Gap | rango Ruby 2.6–3.3 y Rails 6–7 **declarado pero no ejercitado** |

### k. Tests de concurrencia / async

**n/a** — exis_ray no tiene threads ni callbacks en reader-thread. Confirma que
§k es **específica de gemas que gestionan concurrencia** (`bug_bunny`), no
universal. (Input para §5 de la RFC: §k aplicó a 1 de 4 repos validados →
evaluar si va como sección top-level o sub-bloque condicional.)

## 3. Inferencias

- "Inyección sin test" se infiere de la ausencia de `spec/dummy/` + presencia
  de hooks en `railtie.rb`. No medido (sin coverage).

## 4. Cobertura y fronteras

- Cobertura completa de los **componentes aislados**; gap en la **integración
  Railtie↔Rails real** y en la **matrix de versiones**. Ambos son los hallazgos
  que §j hace visibles — el valor del artefacto para una gema.
