## [0.7.2] - 2026-05-11

### Documentación
- **Warning sobre `ActiveSupport::TaggedLogging` con JSON logging:** `TaggedLogging` antepone tags como texto raw antes del formatter, rompiendo el JSON (`[req_id] {...}`). `JsonFormatter` ya inyecta `request_id`/`trace_id` como campos JSON — usar ambos genera salida inválida. Documentada la config correcta del logger en `production.rb` (README + SKILL FAQ).
- **Skill improvements (issue #4):** (1) Clarificado el criterio auto-inyectado vs manual — el formatter solo conoce contexto de ejecución (Tracer/Current), por eso `component` y `event` deben aportarse manualmente. (2) Agregados ejemplos concretos de output JSON lado-a-lado con el input KV/Hash. (3) Completada la lista de campos default de `LogSubscriber` (17 campos con tipos y condiciones, antes truncado con "etc."). (4) Documentados los 3 modos de input del formatter (KV / Hash / string libre) con ejemplos de cada uno.

## [0.7.1] - 2026-04-06

### Fixed
- **`JsonFormatter` truncaba valores key=value sin comillas:** `KV_PARSE_RE` usaba `\S+` como fallback, cortando en el primer espacio. Ahora usa un lookahead que extiende el valor hasta el próximo token `key=` o fin de string. Ejemplo: `error_message=wrong number of arguments (given 1, expected 0)` ahora captura el valor completo en vez de truncar a `"wrong"`.

## [0.6.1] - 2026-04-05

### Added
- **`exception.type` / `exception.message` / `exception.stacktrace`** emitidos junto a los legacy `error_class` / `error_message` en `TaskMonitor` y `LogSubscriber`. Inicia la transición a la convención OTel — los legacy se removerán en v1.0. El stacktrace se toma de `payload[:exception_object]` y se limita a las primeras 20 líneas para respetar el formato one-line KV del estándar Wispro.
- **`http_route`** en `LogSubscriber` con resolución en capas: (1) `payload[:request].route_uri_pattern` para Rails 7.1+, (2) fallback iterando `Rails.application.routes.routes` y matcheando por `defaults[:controller]`, `defaults[:action]` y verb HTTP. Normaliza el controller name CamelCase (incluyendo namespaces `Api::V1::Users`) al formato snake_case que Rails usa en `route.defaults`.

### Fixed
- **`TaskMonitor.format_stacktrace`**: maneja `e.backtrace == nil` de forma segura y está envuelto en rescue para que un logger roto nunca afecte el flujo principal.
- **`private_class_method` restaurado** en `TaskMonitor`: `pod_identifier`, `setup_tracer`, `execute_with_optional_tags`, `log_event` y el nuevo `format_stacktrace` vuelven a ser privados (regresión de 0.6.0).
- **`extract_exception_data`**: las keys ahora son symbols (`:error_class`, `:"exception.type"`, etc) para ser consistentes con el resto del payload. Antes mezclaba strings y symbols, lo que causaba inconsistencias al serializar.
- **`extract_http_route`**: la implementación anterior matcheaba contra `route.requirements[:controller]`, pero Rails guarda controller/action en `route.defaults`. El método antes siempre retornaba `nil` en producción, aunque sus tests pasaban por stubear un contrato inventado. Tests reescritos para stubear la API real (`route.defaults`, `route.path.spec`, `route.verb`).

## [0.5.11] - 2026-04-04

### Documentación
- **README reescrito con Diátaxis:** Quick Start paso a paso, sección "Cómo funciona" con diagrama de flujo de propagación, referencia completa del Tracer (atributos y métodos públicos), documentación de Current (helpers, predicados, auto-sync), API pública del Reporter (`report`, `exception`, `add_context`, `add_tags`, hooks), tabla de campos auto-inyectados con condiciones, ejemplo de LogSubscriber custom, filtrado de claves sensibles, y modo `:text` explicado.
- **YARD:** Agregada documentación en `HttpMiddleware` y `Sidekiq::ClientMiddleware`.
- **CLAUDE.md:** Agregada sección Knowledge Base con instrucciones de entorno, RuboCop, YARD, testing y releases.

### Mejoras internas
- **Skills migration:** Migración de skills de `.claude/skills/` a `.agents/skills/` con nuevo skill manager (`skills.yml` + `skills.lock`).
- **TaskMonitor:** Renombrado `get_pod_identifier` → `pod_identifier` (Naming/AccessorMethodName). Líneas largas partidas con `\` para cumplir Layout/LineLength.
- **Current:** Agregado `rubocop:disable Naming/MemoizedInstanceVariableName` inline en `@user_object`/`@isp_object` — el nombre es intencional porque `resets` y los setters lo referencian para invalidar cache.
- **JsonFormatter:** Removido `require "set"` innecesario y simplificado operador de unión de sets.
- **Configuration:** Normalización de comillas a double-quotes (rubocop-omakase).
- **Gemfile:** Reordenamiento alfabético de dependencias de desarrollo.

## [0.5.10] - 2026-04-01

### Fixed
- **Thread-safety:** Removed unsafe instance variable caching of `@user`/`@isp` in `Current`. Objects are now queried directly on each access.
- **BugBunny Consumer cleanup:** `ConsumerTracingMiddleware` now properly cleans up `Current` and `Reporter` in addition to `Tracer` in the ensure block.
- **JsonFormatter crash prevention:** Added rescue block with fallback message to prevent logging failures from crashing requests.
- **Filter sensitive hash cycle detection:** Added `visited` array to detect and prevent infinite recursion with circular references.
- **FaradayMiddleware rescue:** Wrapped header injection in rescue to prevent crashes on malformed headers.
- **ActiveResourceInstrumentation rescue:** Wrapped header injection in rescue to prevent crashes on malformed headers.
- **Session isolation:** `assign_session_request_id` helper with rescue prevents global state pollution from failing Session writes.
- **Sidekiq ServerMiddleware sync:** Added `ExisRay.sync_correlation_id` call after hydrating tracer.
- **Sidekiq trace_id empty string:** Changed to `trace_header.present?` check to handle empty strings.
- **Safe middleware insertion:** Added `respond_to?` check for `include?` to handle Rails 8's `MiddlewareStackProxy`.
- **Symbol allocation optimization:** Changed to string keys in `parse_kv_string` to avoid memory leaks.
- **Sidekiq ClientMiddleware rescue:** Trace injection now wrapped in ensure block with rescue.
- **LogSubscriber double-attach:** Added `attached?` check to prevent multiple subscriber registrations.
- **LogSubscriber fallback:** Improved error handling with structured fallback message when build_payload fails.
- **user_id=0 preserved:** Changed `.present?` to `!.nil?` checks in `Current`, `JsonFormatter`, and `Reporter` to preserve 0 values.
- **ActiveResource idempotent prepend:** Added ancestor check before prepending instrumentation.
- **Parser handles malformed headers:** `parse_trace_id` now skips parts without `=` instead of crashing.
- **Reporter rescue/ensure structure:** Sentry reporting now wrapped in nested begin/rescue to prevent crashes.
- **HttpMiddleware rescue:** Added rescue to prevent crashes on malformed trace headers.
- **TaskMonitor Rails.logger guard:** Added `defined?(Rails) && Rails.logger` check.
- **ServerMiddleware queue nil guard:** Safe access with `&.` for `get_sidekiq_options`.
- **JsonFormatter timestamp nil:** Added safe navigation with fallback `Time.now` for nil timestamps.
- **Sidekiq cleanup rescue:** Extracted `cleanup_current`/`cleanup_reporter` with individual rescue blocks.
- **Current#user/#isp object lookup:** Changed from `.present?` to `!.nil?` to allow user_id=0 lookups.

## [0.5.9] - 2026-03-31

### Fixed
- **JSON Object Coercion:** `JsonFormatter` ahora intenta parsear como JSON cualquier valor string que comience con `{` o `[` al procesar KV strings. Esto permite que campos como `queue_opts` y `exchange_opts` emitidos por BugBunny como JSON compacto se serialicen como objetos reales en lugar de strings escapados.

### Added
- **CLAUDE.md:** Documentación completa del proyecto actualizada a v0.5.9: arquitectura, componentes, métodos clave, campos auto-inyectados, reglas de ejecución y guía de testing en consola.
- **`.claude/skills/`:** Skills de proyecto para rails-expert, YARD, OpenTelemetry, RuboCop Omakase y README writer — disponibles automáticamente para cualquier dev que use Claude Code en este repo.
- **`.claude/commands/release`:** Comando `/release` para automatizar el flujo de versioning.

## [0.5.8] - 2026-03-31

### Added
- **`ExisRay::BugBunny::ConsumerTracingMiddleware`:** Nuevo middleware para el consumer stack de BugBunny. Corre antes de que la gema procese cada mensaje (antes de `consumer.message_received`), garantizando que todos los logs internos de BugBunny — `consumer.message_received`, `consumer.route_matched`, `consumer.rpc_reply`, `consumer.message_processed` — incluyan `root_id`, `trace_id` y `source`. Si el mensaje no trae header de traza, genera un `root_id` nuevo automáticamente.
- **Propagación RPC bidireccional:** El `Railtie` registra automáticamente dos callbacks en BugBunny: `rpc_reply_headers` inyecta el trace header actualizado (`Self`, `TotalTimeSoFar`, `CalledFrom`) en el reply del consumer; `on_rpc_reply` hidrata el tracer en el thread del publisher al recibir la respuesta, permitiendo que `producer.rpc_response_received` y `request_complete` reflejen el viaje completo por el ecosistema de microservicios.

### Changed
- **BugBunny auto-instrumentado:** La integración BugBunny se mueve al `after_initialize` del `Railtie`, resolviendo el problema de orden de carga. Con ambas gemas en el `Gemfile`, todo se configura automáticamente sin intervención del desarrollador.
- **MANIFEST.md:** Documentación completa del estándar de observabilidad: semántica de niveles de log, block form obligatorio para DEBUG, medición de duraciones con reloj monotónico, filtrado de claves sensibles, resiliencia del logger, y tabla completa de campos auto-inyectados con condiciones de activación.

### Removed
- **`ExisRay::BugBunny::ConsumerTracing`:** Concern eliminado. Reemplazado por `ConsumerTracingMiddleware` que cubre el ciclo completo del mensaje, no solo el action del controller.

## [0.5.7] - 2026-03-27

### Fixed
- **JSON HTML Escaping:** `JsonFormatter` now uses `JSON.generate` with `ascii_only: false` instead of `.to_json`, preventing `>` from being escaped as `\u003e` in log output.
- **BugBunny Header Standardization:** `PublisherTracing` and `ConsumerTracing` now use `ExisRay.configuration.propagation_trace_header` instead of the hardcoded `'x-trace-id'` constant, aligning with the same pattern used by `FaradayMiddleware` and `ActiveResourceInstrumentation`. The header is now fully configurable and consistent across all outgoing transports.

## [0.5.6] - 2026-03-26

### Added
- **BugBunny Integration:** Added `ExisRay::BugBunny::PublisherTracing` middleware for `BugBunny::Client` and `BugBunny::Resource`. Injects the active trace context into the `x-trace-id` AMQP header on every published message.
- **BugBunny Integration:** Added `ExisRay::BugBunny::ConsumerTracing` concern for `BugBunny::Controller`. Restores the ExisRay trace context from `x-trace-id` header via `around_action`, enabling end-to-end distributed tracing across RabbitMQ message boundaries.

## [0.5.5] - 2026-03-24

### Added
- **Deep Security Filtering:** The `JsonFormatter` now recursively filters sensitive data within `Array` and nested `Hash` structures.
- **OTel Semantic Mapping:** Added formal mapping of ExisRay fields to OpenTelemetry Semantic Conventions in `MANIFEST.md`.
- **Test Hardening:** Expanded test suite to cover deep filtering and ensure correct numeric type-casting in logs.

## [0.5.4] - 2026-03-24

### Changed
- **Human-readable durations:** `duration_human` now uses a smarter format: sub-second values show as `"7.2ms"`, values under 60s show as `"1.25s"`, and longer durations use `ActiveSupport::Duration` prose (e.g., `"2 minutes 5 seconds"`).
- **Shared duration helper:** Extracted `ExisRay::Tracer.format_duration` to consolidate duration formatting used by both `LogSubscriber` and `TaskMonitor`.

## [0.5.3] - 2026-03-24

### Changed
- **OpenTelemetry Alignment:** Free-text log lines now emit their content under the `body` key instead of `message`, following the OpenTelemetry Log Data Model specification.

### Fixed
- **Robust KV Parsing:** Added support for single-quoted values (`' '`) in the KV parser. This fixes cases where human-readable durations or other strings used single quotes.
- **Quote Sanitization:** Values extracted from the KV parser now have surrounding quotes (single or double) removed before JSON emission.

## [0.5.2] - 2026-03-24

### Added
- **Official Documentation:** Introduced `MANIFEST.md` as the source of truth for observability standards.
- **Universal Type-Casting:** Improved `JsonFormatter` to apply automatic numeric casting (Integer/Float) to direct `Hash` inputs, not just KV strings.
- **Security Hardening:** Documented explicit bans on PII in logs and established valid `source` entrypoint values.

## [0.5.1] - 2026-03-24

### Fixed
- **Type-Aware KV Parser:** The `JsonFormatter` now automatically casts numeric strings to `Integer` or `Float` when parsing KV messages. This ensures compliance with the Wispro standard where `duration_s` and `count` must be numeric types in the final JSON, not strings.

## [0.5.0] - 2026-03-23

### Changed
- **Wispro-Observability-Spec (v1) Compliance:** Refactored telemetry across all execution layers (`TaskMonitor` and HTTP `LogSubscriber`).
- **Unit Standard:** Duration metrics now use `_s` suffix (Float) as the source of truth (e.g., `duration_s`, `view_runtime_s`, `db_runtime_s`).
- **Human Readability:** Added `duration_human` to both HTTP requests and Background Tasks.
- **Task Lifecycle:** The closing log now always uses `event=task_finished` with `status`, `duration_s`, and `duration_human` fields.
- **Error Consistency:** Failed tasks now include `error_class` and `error_message` fields in the JSON log.
- **Tracer Accuracy:** Improved `Tracer` with `current_duration_s` using monotonic clock precision.

## [0.4.2] - 2026-03-23

### Added
- **Full compliance with "Gabriel's Global Standards" for Logging:**
  - **Sensitive Data Filtering:** The KV parser and Hash merger now automatically filter sensitive keys (`password`, `token`, `api_key`, `auth`, etc.) replacing values with `[FILTERED]`.
  - **Standardized HTTP Logs:** Added `component=exis_ray` and `event=http_request` to all automatic Rails request logs.
  - **Dynamic Log Levels:** `LogSubscriber` now uses `ERROR` level for 5xx status codes and `INFO` for the rest.
  - **Performance:** Switched to block form for internal `DEBUG` logs in `Railtie` to avoid unnecessary string interpolation.

## [0.4.1] - 2026-03-23

### Changed
- **Data-Driven Internal Logging:** Refactored internal library logs (boot, instrumentation, task status) from plain text messages to structured Key-Value (KV) strings.
- This leverages the `JsonFormatter`'s KV parser to elevate fields like `component`, `event`, and `status` to the JSON root, eliminating the need for unstructured `message` fields in infrastructure logs.
- Simplified `TaskMonitor#log_event` and `Railtie.log_boot` to emit raw KV strings directly to the logger.
- **Improved local debugging:** The `Reporter` now uses `exception.full_message` in non-production environments to provide a more readable backtrace in the development console.

## [0.4.0] - 2026-03-23

### Breaking Changes
- **Lograge removido como dependencia.** ExisRay ya no depende de Lograge para el logging estructurado de requests HTTP. Si tu app usaba `config.lograge.custom_options`, migrá al nuevo mecanismo de subclase (ver más abajo).

### Added
- **`ExisRay::LogSubscriber`:** Nuevo subscriber propio que reemplaza Lograge. Se suscribe a `process_action.action_controller` y emite un Hash estructurado directamente al logger, compatible con Rails 6, 7 y 8.
  - Suprime `ActionController::LogSubscriber` y `ActionView::LogSubscriber` (Rails 3.0+, sin cambios en 6/7/8).
  - Suprime `Rails::Rack::Logger` para eliminar las líneas "Started GET /..." (Rails 3.2+, firma `call_app(request, env)` desde Rails 5.0+).
  - Usa `notifier.all_listeners_for` en Rails 7.1+ y `notifier.listeners_for` en Rails 6/7.0 para desuscribir los subscribers por defecto. Si `all_listeners_for` cambia en futuras versiones, revisar `ActiveSupport::Notifications::Fanout`.
- **`config.log_subscriber_class`:** Nueva opción de configuración para registrar una subclase de `ExisRay::LogSubscriber`. Permite inyectar campos extra en cada log de request HTTP sobreescribiendo `self.extra_fields(event)`. Si no se configura, se usa `ExisRay::LogSubscriber` directamente sin campos extra.

### Migration Guide
Si usabas `config.lograge.custom_options`, el equivalente es:

```ruby
# Antes
config.lograge.custom_options = ->(event) { { user_id: Current.user_id } }

# Después — app/models/my_log_subscriber.rb
class MyLogSubscriber < ExisRay::LogSubscriber
  def self.extra_fields(event)
    { user_id: Current.user_id }
  end
end

# config/initializers/exis_ray.rb
ExisRay.configure do |config|
  config.log_subscriber_class = "MyLogSubscriber"
end
```

## [0.3.4] - 2026-03-23

### Fixed
- **Compatibilidad con Rails 7.1+ y Rails 8:** `config.cache_classes` fue deprecado en Rails 7.1 en favor de `config.enable_reloading` (semántica inversa). El helper interno `cache_classes?` ahora detecta cuál API está disponible y usa la correcta, manteniendo compatibilidad con Rails 6, 7 y 8 sin deprecation warnings.

## [0.3.3] - 2026-03-23

### Fixed
- **`ActiveResourceInstrumentation` header incorrecto:** Se corrigió el uso de `trace_header` (formato Rack, ej: `HTTP_X_AMZN_TRACE_ID`) para requests salientes. Ahora se usa `propagation_trace_header` (formato HTTP, ej: `X-Amzn-Trace-Id`), igual que `FaradayMiddleware`. Antes, los microservicios downstream recibían un header con nombre incorrecto y la traza distribuida no se propagaba.
- **Header injection en `Current` setters:** Los valores asignados a `user_id=`, `isp_id=` y `correlation_id=` ahora son sanitizados antes de escribirse en `ActiveResource::Base.headers`. Se eliminan caracteres CRLF (`\r\n`) para prevenir HTTP header injection hacia otros microservicios.
- **`Reporter` exponía datos sensibles a Sentry:** `build_from_current` enviaba `user.as_json` completo (incluyendo `password_digest`, tokens, etc.) al contexto de Sentry. Ahora el comportamiento por defecto es enviar solo `{ id: }`. Se exponen los hooks `sentry_user_context` y `sentry_isp_context` para que la app host controle qué campos incluir.
- **Reloj de pared en cálculo de duración:** `Tracer.created_at` y `current_duration_ms` usaban `Time.now` (afectado por NTP/leap seconds). Ahora usan `Process.clock_gettime(Process::CLOCK_MONOTONIC)` en todos los puntos de asignación (`HttpMiddleware`, `Sidekiq::ServerMiddleware`, `TaskMonitor`) y en el cálculo de duración.
- **`generate_new_root` ignoraba sufijos no numéricos:** El sufijo del pod/hostname se convertía con `.to_i`, retornando siempre `0` para strings alfanuméricos (ej: `"worker01"` → `00000000`). Ahora se codifican los bytes del string directamente a hex, preservando la unicidad del identificador.
- **`JsonFormatter#parse_kv_string` crash con quote suelto:** Un valor de un solo caracter `"` provocaba que `value[1..-2]` retornara `nil` y `.gsub` explotara con `NoMethodError`. Corregido con `|| ""` como fallback.
- **Pérdida silenciosa de mensaje en `JsonFormatter`:** Si `kv_string?` detectaba un string como kv pero `parse_kv_string` no extraía ningún par (ej: `"key="`), el mensaje original desaparecía del JSON sin ir al campo `message`. Ahora cae al fallback correctamente.
- **`TaskMonitor#log_event` podía enmascarar excepciones del negocio:** Si el logger fallaba dentro de `log_event`, su excepción reemplazaba la excepción original de la tarea. Ahora `log_event` está protegido con `rescue StandardError` interno.
- **`current_class` y `reporter_class` resueltos dos veces en `ensure`:** En `Sidekiq::ServerMiddleware` y `TaskMonitor`, el bloque `ensure` llamaba `safe_constantize` dos veces por clase. Ahora se asigna a variable local antes del `ensure`.

### Changed
- **`sentry_user_context` y `sentry_isp_context` como hooks públicos en `Reporter`:** La subclase puede sobreescribir estos métodos para definir exactamente qué atributos del modelo se envían a Sentry, sin exponer datos sensibles por defecto.

### Performance
- **Memoización de `current_class` y `reporter_class` en producción:** En entornos con `cache_classes=true`, la resolución vía `safe_constantize` se ejecuta una sola vez. En desarrollo se sigue resolviendo por request para respetar el reloading de Zeitwerk.
- **Regex de `JsonFormatter` extraídas a constantes:** `KV_DETECT_RE` y `KV_PARSE_RE` son ahora constantes de clase, eliminando recompilaciones innecesarias en cada línea de log.
- **`Current#user` e `Current#isp` usan sentinel para cachear `nil`:** Si `find_by` no encuentra el registro, el resultado se cachea con un objeto sentinel `NOT_FOUND`. Las llamadas subsiguientes retornan `nil` sin consultar la DB.
- **`Sidekiq::ClientMiddleware` resuelve `current_class` una sola vez** por job encolado en lugar de cuatro veces.

## [0.3.2] - 2026-03-23

### Added
- **Global `source` field:** Introduced a standardized `source` field in JSON logs to identify the entry point of execution (`http`, `sidekiq`, or `task`).
- This facilitates global filtering and dashboard creation in observability platforms.

## [0.3.1] - 2026-03-23

### Changed
- **Standardized Service Name:** The `service` field in logs now always returns the Rails application name in `snake_case` (e.g., `cold_storage_service`).
- Removed dynamic service name overrides in `HttpMiddleware`, `Sidekiq::ServerMiddleware`, and `TaskMonitor`.
- **Enhanced Job/Task Visibility:** Added `sidekiq_job` and `task` fields to the JSON logs, providing specific context without overloading the `service` field.

## [0.3.0] - 2026-03-23

### Added
- **KV String Parser in JsonFormatter:** The `JsonFormatter` now automatically detects and parses messages in `key=value` format.
- Extracted pairs from strings are elevated to the JSON root, allowing structured logging from plain string messages.
- Support for quoted values with spaces (e.g., `message="some text"`) and escaped characters within logs.
- Added comprehensive RSpec suite for `ExisRay::JsonFormatter` to verify message processing logic.

## [0.2.0] - 2026-03-12

### Added
- **Structured JSON Logging:** Introduced a centralized `ExisRay::JsonFormatter` that intercepts all application logs (HTTP, Sidekiq, and Rake tasks) and formats them into context-rich, single-line JSON objects.
- Added `lograge` as a core dependency to condense standard Rails multi-line HTTP logs into single events.
- Introduced the `config.log_format` configuration option (accepts `:text` or `:json`).
- Added native support for `ActiveSupport::TaggedLogging`. Standard Rails tags (`config.log_tags`) are now automatically intercepted and injected as a `"tags"` array within the JSON payload.
- Added support for merging Lograge's `custom_options` directly into the JSON root.
- Expanded `README.md` with an "Advanced Logging Guide", detailing environment-specific setup and customization strategies.

### Changed
- Refactored `Sidekiq::ServerMiddleware` and `TaskMonitor` to intelligently adapt their logging behavior based on the active `log_format`, preventing redundant tagging in JSON mode.
- Shifted the `Railtie` logging configuration to execute `after: :load_config_initializers`. This guarantees the host application's initializers are fully loaded before ExisRay determines the log format.
- Enforced strict RuboCop compliance (`Style/StringLiterals` -> double quotes) across all internal classes, methods, and documentation examples.

### Fixed
- Fixed `NoMethodError: undefined method 'current_tags'` by ensuring `JsonFormatter` correctly includes the `ActiveSupport::TaggedLogging::Formatter` interface.
- Resolved a race condition during Rails boot where `lograge` failed to initialize if the gem configuration was set via an initializer.

## [0.1.0] - 2025-12-23

- Initial release
