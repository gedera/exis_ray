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
