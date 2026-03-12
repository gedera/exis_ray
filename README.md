# ExisRay

**ExisRay** is a robust observability framework designed for Ruby on Rails microservices. It unifies **Distributed Tracing** (AWS X-Ray compatible), **Business Context Propagation**, **Error Reporting**, and **Structured JSON Logging** into a single, cohesive gem.

It acts as the backbone of your architecture, ensuring that every request, background task (Sidekiq/Cron), log line, and external API call carries the necessary context to debug issues across a distributed system.

## 🚀 Features

* **Distributed Tracing:** Automatically parses, generates, and propagates Trace headers (compatible with AWS ALB `X-Amzn-Trace-Id`).
* **Structured JSON Logging:** Optionally unifies all your application logs (HTTP requests, Sidekiq jobs, and Rake tasks) into a clean, single-line JSON format, perfect for Datadog, ELK, or CloudWatch.
* **Unified Tagging:** If JSON logging is disabled, it automatically injects the global `Root ID` into every Rails log line.
* **Context Management:** Thread-safe storage for business identity (`User`, `ISP`, `CorrelationId`) with automatic cleanup.
* **Error Reporting:** A wrapper for Sentry (Legacy & Modern SDKs) that enriches errors with the full trace and business context.
* **Sidekiq Integration:** Automatic context propagation (User/ISP/Trace) and log formatting between the Enqueuer and the Worker.
* **Task Monitor:** A specialized monitor for Rake/Cron tasks to initialize traces and format logs where no HTTP request exists.
* **HTTP Clients:** Automatically patches `ActiveResource` and provides middleware for `Faraday`.

---

## 📦 Installation

Add this line to your application's Gemfile:

```ruby
gem "exis_ray"
```

And then execute:

```bash
$ bundle install
```

*(Note: ExisRay automatically installs and configures `lograge` as a dependency to handle HTTP log condensation).*

---

## ⚙️ Configuration

Create an initializer to configure the behavior. This is crucial to link ExisRay with your specific application logic.

**File:** `config/initializers/exis_ray.rb`

```ruby
ExisRay.configure do |config|
  # 1. Trace Header (Incoming)
  # The HTTP header used to read the Trace ID from the Load Balancer (Rack format).
  # Default: "HTTP_X_AMZN_TRACE_ID" (AWS Standard).
  config.trace_header = "HTTP_X_WP_TRACE_ID"

  # 2. Propagation Header (Outgoing)
  # The header sent to downstream services via ActiveResource/Faraday.
  config.propagation_trace_header = "X-Wp-Trace-Id"

  # 3. Dynamic Classes (Required)
  # Link your app's specific classes to the gem.
  # We use Strings to avoid "uninitialized constant" errors during boot.
  config.current_class  = "Current"   # Your Context Model
  config.reporter_class = "Choto"     # Your Sentry Wrapper

  # 4. Log Format (New!)
  # Choose the output format for your application logs.
  # Options: :text (default Rails behavior) or :json (Structured logging).
  config.log_format = :json
end
```

---

## 📖 Implementation Guide

### 1. Define Business Context (`Current`)

Inherit from `ExisRay::Current` to manage your global state. This class handles thread-safety and ensures data is wiped after every request.

**File:** `app/models/current.rb`

```ruby
class Current < ExisRay::Current
  # Add app-specific attributes here
  attribute :billing_cycle, :permissions

  # ExisRay provides: user_id, isp_id, correlation_id
end
```

### 2. Define Error Reporter (`Reporter`)

Inherit from `ExisRay::Reporter` to standardize error handling. This wrapper automatically attaches the `Trace ID`, `User`, `ISP`, and `Tags` to every Sentry event.

**File:** `app/models/choto.rb`

```ruby
class Choto < ExisRay::Reporter
  # Optional hook to add service-specific context
  def self.build_custom_context
    if ExisRay.current_class.respond_to?(:olt)
      add_tags(olt_id: ExisRay.current_class.olt&.id)
    end
  end
end
```

### 3. Hydrate Context (Controller)

In your `ApplicationController`, verify the incoming request and set the context. ExisRay handles the Trace ID automatically, you just handle the Business Logic.

**File:** `app/controllers/application_controller.rb`

```ruby
before_action :set_exis_ray_context

def set_exis_ray_context
  # 1. User Context (e.g., from Devise)
  Current.user = current_user if current_user

  # 2. ISP Context (e.g., from Headers)
  Current.isp_id = request.headers["X-Isp-Id"]
end
```

---

## 🛠 Usage Scenarios

### A. Structured JSON Logging

When `config.log_format = :json` is enabled, ExisRay transforms all your application outputs into single-line, context-rich JSON objects.

**HTTP Requests (via Lograge):**
```json
{"time":"2026-03-12T14:30:00Z","level":"INFO","service":"App-HTTP","root_id":"Root=1-65a...bc","trace_id":"Root=1-65a...bc;Self=...","request_id":"9876-abcd-...","user_id":42,"isp_id":10,"method":"GET","path":"/api/v1/users","format":"html","controller":"UsersController","action":"index","status":200,"duration":45.2,"view":20.1,"db":15.0}
```

**Sidekiq Jobs & Rake Tasks:**
```json
{"time":"2026-03-12T14:31:00Z","level":"INFO","service":"Sidekiq-HardWorker","root_id":"Root=1-65a...bc","user_id":42,"message":"[ExisRay] Processing payment..."}
```

### B. Automatic Sidekiq Integration

If `Sidekiq` is present, ExisRay automatically configures Client and Server middlewares. **No code changes are required in your workers.**

**How it works:**
1.  **Enqueue:** When you call `Worker.perform_async`, the current `Trace ID` and `Current` attributes are injected into the job payload.
2.  **Process:** When the worker executes, `Current` is hydrated with the original data.
3.  **Logs:** Sidekiq logs will automatically include the propagated `Root ID` and Business Context (either as text tags or structured JSON).

### C. Background Tasks (Cron/Rake)

For Rake tasks or Cron jobs (where no HTTP request exists), use `ExisRay::TaskMonitor`. It generates a fresh `Root ID`.

**File:** `lib/tasks/billing.rake`

```ruby
task generate_invoices: :environment do
  ExisRay::TaskMonitor.run("billing:generate_invoices") do
    InvoiceService.process_all
  end
end
```

### D. HTTP Clients

ExisRay ensures traceability across microservices.

#### ActiveResource (Automatic)
If `ActiveResource` is detected, ExisRay automatically patches it. All outgoing requests will include:
* `X-Wp-Trace-Id` (Trace Header)
* `UserId`, `IspId`, `CorrelationId`

#### Faraday (Manual)
For Faraday, you must explicitly add the middleware:

```ruby
conn = Faraday.new(url: "[https://api.internal](https://api.internal)") do |f|
  f.use ExisRay::FaradayMiddleware
  f.adapter Faraday.default_adapter
end
```

---

## 🏗 Architecture

* **`ExisRay::Tracer`**: The infrastructure layer. Handles AWS X-Ray format parsing and ID generation.
* **`ExisRay::Current`**: The business layer. Manages domain identity (`User`, `ISP`).
* **`ExisRay::Reporter`**: The observability layer. Bridges the gap between your app and Sentry.
* **`ExisRay::JsonFormatter`**: The central logging engine. Intercepts HTTP, Sidekiq, and Tasks to output clean JSON.
* **`ExisRay::TaskMonitor`**: The entry point for non-HTTP processes.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
