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
