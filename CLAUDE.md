# ExisRay Project Memory

## Architecture & Components
- `ExisRay::Tracer`: Distributed tracing (AWS X-Ray). Uses `CurrentAttributes` for thread-safety.
- `ExisRay::Current`: Business context (User, ISP). Abstract base class for host app subclassing.
- `ExisRay::Reporter`: Sentry wrapper. Abstract base class for host app subclassing.
- `ExisRay::JsonFormatter`: Core engine. Handles Hash, KV strings, and free-text with automatic masking and **Type Casting**.
- `ExisRay::LogSubscriber`: Native HTTP logger since v0.4.0. Replaces Lograge.
- `ExisRay::TaskMonitor`: Lifecycle manager for non-HTTP processes.

## Technical Knowledge & Compatibility

### Wispro Observability Spec (v1)
- **Manifest:** All logging MUST follow the rules defined in `MANIFEST.md`.
- **Metrics:** Always use `_s` suffix for durations (Float) and `count` for volumes (Integer). Never include units in values.
- **Type-Awareness:** `JsonFormatter` automatically casts numeric KV values to Float/Integer. Emit raw numbers in KV strings.
- **Automatic Fields:** Do not manually log `time`, `level`, `service`, `source`, `root_id`, `correlation_id`, `sidekiq_job` or `task`. These are handled by the library.

### Rails Compatibility (6, 7, 8)
- **Reloading:** Use `cache_classes?` helper (checks `respond_to?(:enable_reloading)`) to avoid deprecation warnings in Rails 7.1+.
- **Notifications:** Rails 7.1+ uses `all_listeners_for`, while 6/7.0 uses `listeners_for`. Always use `respond_to?` guards when manipulating subscribers.

### Distributed Tracing (AWS X-Ray)
- **Propagation:** Use `propagation_trace_header` (standard HTTP format) for outgoing requests.
- **Parsing:** `trace_header` (Rack format) is ONLY for incoming request parsing.

## Security & Privacy
- **Sensitive Key Filtering:** `JsonFormatter` auto-filters keys matching `password|pass|passwd|secret|token|api_key|auth` → replaced with `[FILTERED]`.
- **Header Injection Prevention:** `ExisRay::Current` sanitizes values via `sanitize_header_value` before storing user/ISP identity.
- **No PII in Logs:** Never log raw user data. Only IDs (`user_id`, `isp_id`) are permitted.

## Execution Rules
- **No Lograge:** Do not suggest or re-add the Lograge dependency.
- **Pure Data Logging:** Internal logs use KV strings (`component=exis_ray event=...`).
- **Resilience:** All logging operations must be wrapped in `rescue StandardError`.
- **Source Values:** Valid values for `source` field: `http`, `sidekiq`, `task`, `system`.
