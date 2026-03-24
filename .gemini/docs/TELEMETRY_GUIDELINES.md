# OpenTelemetry Implementation Guidelines

This document provides expert guidance for aligning code and logs with OpenTelemetry (OTel) standards. Follow these rules for all new instrumentation.

## 1. Log Data Model
- **Body:** Use `body` for the primary log message.
- **Attributes:** Metadata must be flat Key-Value pairs.
- **Severity:** `level` maps to `severity_text`.

## 2. Semantic Conventions
When adding attributes, check the official OTel [Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/).

### HTTP Attributes
- `http.request.method`: GET, POST, etc.
- `http.response.status_code`: 200, 404, etc.
- `url.path`: The request path.
- `user_agent.original`: The raw User-Agent string.

### Database Attributes
- `db.system`: postgresql, redis, etc.
- `db.operation`: select, update, etc.
- `db.collection.name`: table or collection name.

## 3. Metrics & Units
- Always use the lowest common denominator for units (seconds, bytes).
- Use `_s` suffix for time duration.
- Avoid compound strings like `"10ms"`. Use `duration_s=0.01`.

## 4. Distributed Tracing
- **TraceID:** 16-byte array, represented as a 32-char lowercase hex string.
- **SpanID:** 8-byte array, represented as a 16-char lowercase hex string.
- **Context Propagation:** Follow W3C Trace Context (traceparent) when possible, or maintain AWS X-Ray compatibility as per project requirements.
