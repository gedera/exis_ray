# ExisRay

**ExisRay** is a robust observability framework designed for Ruby on Rails microservices. It unifies **Distributed Tracing** (AWS X-Ray compatible), **Business Context Propagation**, and **Error Reporting** into a single, cohesive gem.

It acts as the backbone of your architecture, ensuring that every request, background task, log line, and external API call carries the necessary context to debug issues across a distributed system.

## 🚀 Features

* **Distributed Tracing:** Automatically parses, generates, and propagates Trace headers (compatible with AWS ALB `X-Amzn-Trace-Id`).
* **Unified Logging:** Injects the global `Root ID` into every Rails log line automatically, making Kibana/CloudWatch filtering effortless.
* **Context Management:** Thread-safe storage for business identity (`User`, `ISP`) and audit trails, with automatic cleanup.
* **Error Reporting:** A wrapper for Sentry (Legacy & Modern SDKs) that enriches errors with the full trace and business context.
* **Background Monitoring:** A specialized monitor for Rake/Cron tasks to initialize traces where no HTTP request exists.
* **ActiveResource Integration:** Automatically patches outgoing requests to propagate headers (`Trace ID`, `User ID`, `ISP ID`) to downstream services.

---

## 📦 Installation

Add this line to your application's Gemfile:

```ruby
gem 'exis_ray'
```

And then execute:

```bash
$ bundle install
```

---

## ⚙️ Configuration

Create an initializer to configure the behavior. This is crucial to link ExisRay with your specific application logic.

**File:** `config/initializers/exis_ray.rb`

```ruby
ExisRay.configure do |config|
  # 1. Trace Header (Optional)
  # The HTTP header used to read/propagate the Trace ID.
  # Default: 'HTTP_X_AMZN_TRACE_ID' (AWS Standard).
  # You can customize it to your internal standard:
  config.trace_header = 'HTTP_X_WP_TRACE_ID'

  # 2. Reporter Class (Required for Background Tasks)
  # The class in your host application that inherits from ExisRay::Reporter.
  # This allows the TaskMonitor to inject tags (like task name) into the 
  # correct class so Sentry picks them up.
  config.reporter_class = 'Choto' # or 'ErrorReport', 'AppReporter'
end
```

---

## 📖 Usage Guide

### 1. Business Context (`Current`)

Inherit from `ExisRay::Current` to manage your global state. This class handles thread-safety and ensures data is wiped after every request to prevent leaks.

**Definition:** `app/models/current.rb`

```ruby
class Current < ExisRay::Current
  # Add app-specific attributes here
  attribute :billing_cycle, :permissions
end
```

**Usage:**

```ruby
# Setting context (e.g., in ApplicationController)
Current.user = current_user
Current.isp_id = request.headers['X-Isp-Id']

# Reading context (Anywhere)
Current.user.email
Current.correlation_id
```

> **Note:** Setting `Current.user` or `Current.isp` automatically sets headers for `ActiveResource` and metadata for `PaperTrail`.

---

### 2. Error Reporting (`Reporter`)

Inherit from `ExisRay::Reporter` to standardize error handling. This wrapper automatically attaches the `Trace ID`, `User`, `ISP`, and `Tags` to every Sentry event.

**Definition:** `app/models/choto.rb`

```ruby
class Choto < ExisRay::Reporter
  # Optional hook to add service-specific context
  def self.build_custom_context
    if Current.respond_to?(:olt) && Current.olt.present?
      add_tags(
        olt_id: Current.olt.id, 
        model: Current.olt.model
      )
    end
  end
end
```

**Usage:**

```ruby
def charge_customer
  # ... logic ...
rescue StandardError => e
  # Sends exception to Sentry + Trace ID + User Context + OLT Tags
  Choto.exception(e, tags: { action: 'payment_processing' })
end
```

---

### 3. Background Tasks (`TaskMonitor`)

Since Rake tasks and Cron jobs don't have an incoming HTTP request, they lack a Trace ID by default. Use `ExisRay::TaskMonitor` to wrap your logic. It generates a fresh `Root ID` and sets up the logging context.

**Usage:** `lib/tasks/billing.rake`

```ruby
task generate_invoices: :environment do
  # Wraps execution in a monitored context
  ExisRay::TaskMonitor.run('billing:generate_invoices') do
    # 1. Logs are tagged: [Root=1-65a...bc] [ExisRay] Initiando tarea...
    # 2. 'Choto.transaction_name' is set automatically.
    # 3. ActiveResource calls will propagate the new Trace ID.
    InvoiceService.process_all
  end
end
```

---

### 4. Automatic Integrations

You don't need to write code for these; they work out of the box.

#### 📝 Logging
ExisRay automatically configures Rails logs.
* **Web Request:** Uses the incoming Trace ID.
* **Background Job:** Uses the generated Root ID.

```text
[Root=1-653a1f9...b2] Started GET "/users" for 127.0.0.1...
[Root=1-653a1f9...b2] Processing by UsersController#index...
```

#### 🌐 ActiveResource
If `ActiveResource` is detected, ExisRay patches it to inject headers into all outgoing requests:
* `X-Wp-Trace-Id` (or configured header)
* `UserId`
* `IspId`
* `CorrelationId`

---

#### 🔌 Faraday

Unlike ActiveResource, Faraday connections are often manually configured. You must explicitly add the middleware to your connection block.

```ruby
# In your Service or API Client
conn = Faraday.new(url: '[https://other-microservice.internal](https://other-microservice.internal)') do |f|
  # Add this line to propagate Trace ID & Context automatically
  f.use ExisRay::FaradayMiddleware

  f.adapter Faraday.default_adapter
end

## 🏗 Architecture

* **`ExisRay::Tracer`**: The infrastructure layer. Handles AWS X-Ray format parsing, ID generation, and time calculation (`TotalTimeSoFar`).
* **`ExisRay::Current`**: The business layer. Manages domain identity (`User`, `ISP`).
* **`ExisRay::Reporter`**: The observability layer. Bridges the gap between your app and Sentry.
* **`ExisRay::TaskMonitor`**: The entry point for non-HTTP processes.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
