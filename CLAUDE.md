# ExisRay Project Memory

## Architecture & Components
- `ExisRay::Tracer`: Distributed tracing (AWS X-Ray). Uses `CurrentAttributes` for thread-safety.
- `ExisRay::Current`: Business context (User, ISP). Abstract base class for host app subclassing.
- `ExisRay::Reporter`: Sentry wrapper. Abstract base class for host app subclassing.
- `ExisRay::JsonFormatter`: Core engine. Handles Hash, KV strings, and free-text with automatic masking.
- `ExisRay::LogSubscriber`: Native HTTP logger since v0.4.0. Replaces Lograge.

## Technical Knowledge & Compatibility

### Rails Compatibility (6, 7, 8)
- **Reloading:** Use `cache_classes?` helper (checks `respond_to?(:enable_reloading)`) to avoid deprecation warnings in Rails 7.1+.
- **Notifications:** Rails 7.1+ uses `all_listeners_for`, while 6/7.0 uses `listeners_for`. Always use `respond_to?` guards when manipulating subscribers.

### Distributed Tracing (AWS X-Ray)
- **Propagation:** Use `propagation_trace_header` (standard HTTP format) for outgoing requests.
- **Parsing:** `trace_header` (Rack format) is ONLY for incoming request parsing.

### Security & Privacy
- **Sentry Context:** Default `sentry_user_context` and `sentry_isp_context` to `{ id: }` only. Never send full objects to avoid leaking sensitive fields (PII/Tokens).
- **Masking:** `JsonFormatter` automatically filters `password`, `token`, `api_key`, `auth`, `secret`.

## Execution Rules
- **No Lograge:** Do not suggest or re-add the Lograge dependency.
- **Pure Data Logging:** Gem internal logs must use KV strings (`component=exis_ray event=...`).
- **Resilience:** All logging operations must be wrapped in `rescue StandardError` to ensure the host application never crashes due to a telemetry failure.
