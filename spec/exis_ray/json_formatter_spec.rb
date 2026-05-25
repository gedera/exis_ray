# frozen_string_literal: true

require "spec_helper"

RSpec.describe ExisRay::JsonFormatter do
  subject(:formatter) { described_class.new }

  let(:severity)  { "INFO" }
  let(:timestamp) { Time.utc(2025, 9, 1, 12, 0, 0) }
  let(:progname)  { nil }

  before do
    # Stub Tracer y Current para aislar el formatter de dependencias externas
    stub_const("ExisRay::Tracer", Module.new do
      def self.service_name = "test-service"
      def self.root_id      = nil
      def self.trace_id     = nil
      def self.request_id   = nil
    end)

    allow(ExisRay).to receive(:current_class).and_return(nil)

    # current_tags es un método de ActiveSupport::TaggedLogging::Formatter que depende
    # de IsolatedExecutionState (thread-local). Lo stubeamos para entornos sin Rails.
    allow(formatter).to receive(:current_tags).and_return([])
  end

  def call(msg)
    JSON.parse(formatter.call(severity, timestamp, progname, msg))
  end

  describe "#call" do
    context "cuando el mensaje es un Hash" do
      it "eleva los campos al nivel raíz del JSON" do
        result = call({ event: "archive_lookup", cutoff: "2025-09-01" })

        expect(result).to include(
          "event" => "archive_lookup",
          "cutoff" => "2025-09-01",
          "level" => "INFO",
          "service" => "test-service"
        )
        expect(result).not_to have_key("message")
      end

      it "convierte claves symbol y string indistintamente" do
        result = call({ "event" => "foo", bar: "baz" })

        expect(result).to include("event" => "foo", "bar" => "baz")
      end
    end

    context "cuando el mensaje es un String con formato key=value" do
      it "parsea los pares y los eleva al nivel raíz" do
        result = call("event=archive_lookup cutoff=2025-09-01")

        expect(result).to include(
          "event" => "archive_lookup",
          "cutoff" => "2025-09-01",
          "level" => "INFO",
          "service" => "test-service"
        )
        expect(result).not_to have_key("message")
      end

      it "soporta un único par key=value" do
        result = call("event=boot")

        expect(result["event"]).to eq("event=boot".split("=").last)
        expect(result).not_to have_key("message")
      end

      it "soporta valores con espacios entre comillas dobles" do
        result = call('event=error message="algo salió mal"')

        expect(result["event"]).to eq("error")
        expect(result["message"]).to eq("algo salió mal")
      end

      it "soporta comillas escapadas dentro del valor" do
        result = call('msg="dijo \"hola\""')

        expect(result["msg"]).to eq('dijo "hola"')
      end

      it "no crashea con un quote suelto como valor (string malformado)" do
        expect { call('key="') }.not_to raise_error
      end

      it "soporta múltiples pares con tipos de valor variados" do
        result = call("component=orders event=invoice_generated duration_ms=42.5 retries=0")

        expect(result).to include(
          "component" => "orders",
          "event" => "invoice_generated",
          "duration_ms" => 42.5,
          "retries" => 0
        )
      end

      it "cae a body si el string parece kv pero no produce ningún par" do
        result = call("key=")

        expect(result["body"]).to eq("key=")
        expect(result).not_to have_key("key")
      end
    end

    context "cuando el mensaje es un String libre (sin formato key=value)" do
      it "asigna el string completo al campo body" do
        result = call("algo salió mal")

        expect(result["body"]).to eq("algo salió mal")
        expect(result).to include("level" => "INFO", "service" => "test-service")
      end

      it "asigna un string vacío al campo body" do
        result = call("")

        expect(result["body"]).to eq("")
      end

      it "convierte objetos arbitrarios a string via to_s" do
        result = call(42)

        expect(result["body"]).to eq("42")
      end
    end

    describe "campos base" do
      it "incluye time en formato ISO8601 UTC" do
        result = call("event=boot")

        expect(result["time"]).to eq("2025-09-01T12:00:00Z")
      end

      it "incluye level y service" do
        result = call("event=boot")

        expect(result["level"]).to eq("INFO")
        expect(result["service"]).to eq("test-service")
      end
    end

    describe "severity_number (OTel Log Data Model)" do
      it "inyecta severity_number=9 para INFO" do
        result = JSON.parse(formatter.call("INFO", timestamp, progname, "event=x"))

        expect(result["severity_number"]).to eq(9)
      end

      it "inyecta severity_number=13 para WARN" do
        result = JSON.parse(formatter.call("WARN", timestamp, progname, "event=x"))

        expect(result["severity_number"]).to eq(13)
      end

      it "inyecta severity_number=17 para ERROR" do
        result = JSON.parse(formatter.call("ERROR", timestamp, progname, "event=x"))

        expect(result["severity_number"]).to eq(17)
      end

      it "inyecta severity_number=5 para DEBUG" do
        result = JSON.parse(formatter.call("DEBUG", timestamp, progname, "event=x"))

        expect(result["severity_number"]).to eq(5)
      end

      it "inyecta severity_number=21 para FATAL" do
        result = JSON.parse(formatter.call("FATAL", timestamp, progname, "event=x"))

        expect(result["severity_number"]).to eq(21)
      end

      it "omite severity_number para niveles no estándar" do
        result = JSON.parse(formatter.call("CUSTOM", timestamp, progname, "event=x"))

        expect(result).not_to have_key("severity_number")
      end
    end

    describe "resource attributes OTel (service_version, deployment_environment)" do
      it "inyecta service_version cuando Configuration lo provee" do
        allow(ExisRay.configuration).to receive_messages(service_version: "1.2.3", deployment_environment: nil)

        result = call("event=boot")

        expect(result["service_version"]).to eq("1.2.3")
      end

      it "inyecta deployment_environment cuando Configuration lo provee" do
        allow(ExisRay.configuration).to receive_messages(service_version: nil, deployment_environment: "production")

        result = call("event=boot")

        expect(result["deployment_environment"]).to eq("production")
      end

      it "omite service_version cuando es nil" do
        allow(ExisRay.configuration).to receive_messages(service_version: nil, deployment_environment: "test")

        result = call("event=boot")

        expect(result).not_to have_key("service_version")
      end

      it "omite deployment_environment cuando es nil" do
        allow(ExisRay.configuration).to receive_messages(service_version: "1.0", deployment_environment: nil)

        result = call("event=boot")

        expect(result).not_to have_key("deployment_environment")
      end
    end

    describe "inyeccion de contexto de negocio" do
      let(:current_mock) do
        Class.new do
          attr_accessor :user_id, :isp_id, :correlation_id

          def initialize(user_id:, isp_id:, correlation_id:)
            @user_id = user_id
            @isp_id = isp_id
            @correlation_id = correlation_id
          end

          def respond_to?(method, *)
            %i[user_id isp_id correlation_id].include?(method)
          end
        end
      end

      before do
        allow(ExisRay).to receive(:current_class).and_return(nil)
      end

      it "incluye user_id=0 en el payload (no debe filtrarse)" do
        allow(ExisRay).to receive(:current_class).and_return(current_mock.new(user_id: 0, isp_id: nil,
                                                                              correlation_id: nil))

        result = call("event=test")

        expect(result["user_id"]).to eq(0)
      end

      it "incluye isp_id=0 en el payload (no debe filtrarse)" do
        allow(ExisRay).to receive(:current_class).and_return(current_mock.new(user_id: nil, isp_id: 0,
                                                                              correlation_id: nil))

        result = call("event=test")

        expect(result["isp_id"]).to eq(0)
      end

      it "no incluye nil user_id en el payload" do
        allow(ExisRay).to receive(:current_class).and_return(current_mock.new(user_id: nil, isp_id: nil,
                                                                              correlation_id: nil))

        result = call("event=test")

        expect(result).not_to have_key("user_id")
      end
    end

    describe "inyeccion de Current.log_fields" do
      # Mock estilo ActiveSupport::CurrentAttributes que combina los atributos canónicos
      # con un hook log_fields. Por defecto retorna {}, los tests lo redefinen vía stub.
      let(:current_class_double) do
        Class.new do
          class << self
            attr_accessor :user_id, :isp_id, :correlation_id, :_log_fields

            def respond_to_missing?(method, *)
              %i[user_id isp_id correlation_id log_fields].include?(method) || super
            end
          end

          def self.log_fields
            _log_fields || {}
          end
        end
      end

      before do
        allow(ExisRay).to receive(:current_class).and_return(current_class_double)
      end

      it "inyecta los campos retornados por log_fields en el payload" do
        current_class_double._log_fields = { tenant_id: "42", region: "us-east-1" }

        result = call("event=boot")

        # tenant_id="42" se castea a Integer por filter_sensitive_hash (igual que cualquier otro KV)
        expect(result).to include("tenant_id" => 42, "region" => "us-east-1", "event" => "boot")
      end

      it "no agrega keys cuando log_fields retorna hash vacío" do
        current_class_double._log_fields = {}

        result = call("event=boot")

        expect(result).not_to have_key("tenant_id")
      end

      it "no agrega keys cuando log_fields retorna nil" do
        current_class_double._log_fields = nil

        result = call("event=boot")

        expect(result.keys).to contain_exactly("time", "level", "severity_number", "service", "event")
      end

      it "el mensaje del developer pisa log_fields (override por call site)" do
        current_class_double._log_fields = { tenant_id: "from-current" }

        result = call("event=override tenant_id=from-message")

        expect(result["tenant_id"]).to eq("from-message")
      end

      it "filtra claves sensibles" do
        current_class_double._log_fields = { api_key: "leaked", tenant_id: "42" }

        result = call("event=boot")

        expect(result["api_key"]).to eq("[FILTERED]")
        expect(result["tenant_id"]).to eq(42)
      end

      it "no rompe el formatter si la subclass overrideó log_fields con un método que revienta" do
        allow(current_class_double).to receive(:log_fields).and_raise(StandardError, "boom")

        expect { call("event=boot") }.not_to raise_error
        result = call("event=boot")
        expect(result["event"]).to eq("boot")
      end

      it "no falla si Current configurado no implementa log_fields (backwards compat)" do
        legacy_current = Class.new do
          class << self
            attr_accessor :user_id, :isp_id, :correlation_id
          end
        end
        allow(ExisRay).to receive(:current_class).and_return(legacy_current)

        expect { call("event=boot") }.not_to raise_error
      end
    end
  end

  describe "#kv_string? (privado)" do
    it "retorna true si el string empieza con word=" do
      expect(formatter.send(:kv_string?, "event=foo")).to be true
    end

    it "retorna false para strings libres" do
      expect(formatter.send(:kv_string?, "algo salió mal")).to be false
      expect(formatter.send(:kv_string?, "")).to be false
      expect(formatter.send(:kv_string?, "=sinkey")).to be false
    end
  end

  describe "#parse_kv_string (privado)" do
    it "retorna un hash con claves string y valores casteados" do
      result = formatter.send(:parse_kv_string, "a=1 b=2")

      expect(result).to eq({ "a" => 1, "b" => 2 })
    end

    it "desenvuelve las comillas dobles de los valores" do
      result = formatter.send(:parse_kv_string, 'msg="hello world"')

      expect(result).to eq({ "msg" => "hello world" })
    end

    it "captura valores sin comillas con espacios hasta el próximo key=" do
      input = "event=unhandled_exception error_class=ArgumentError " \
              "error_message=wrong number of arguments (given 1, expected 0)"
      result = formatter.send(:parse_kv_string, input)

      expect(result).to eq({
                             "event" => "unhandled_exception",
                             "error_class" => "ArgumentError",
                             "error_message" => "wrong number of arguments (given 1, expected 0)"
                           })
    end

    it "captura valores sin comillas con espacios al final del string" do
      result = formatter.send(:parse_kv_string, "component=exis_ray event=something went wrong")

      expect(result).to eq({
                             "component" => "exis_ray",
                             "event" => "something went wrong"
                           })
    end

    it "mezcla valores con y sin comillas correctamente" do
      result = formatter.send(:parse_kv_string, 'event=error msg="hello world" detail=some extra info status=500')

      expect(result).to eq({
                             "event" => "error",
                             "msg" => "hello world",
                             "detail" => "some extra info",
                             "status" => 500
                           })
    end
  end

  describe "inyección de contexto de tracer (issue #9)" do
    def stub_tracer(root_id:, request_id:, source:, trace_id: nil)
      stub_const("ExisRay::Tracer", Module.new do
        define_singleton_method(:service_name) { "test-service" }
        define_singleton_method(:root_id) { root_id }
        define_singleton_method(:trace_id) { trace_id }
        define_singleton_method(:request_id) { request_id }
        define_singleton_method(:source) { source }
        define_singleton_method(:sidekiq_job) { nil }
        define_singleton_method(:task) { nil }
      end)
    end

    context "cuando hay trace context activo (root_id presente)" do
      before { stub_tracer(root_id: "1-abc-def", request_id: "uuid-1", source: "http", trace_id: "Root=1-abc-def") }

      it "emite root_id, trace_id, source y request_id" do
        result = call("event=acct.received")

        expect(result).to include(
          "root_id" => "1-abc-def",
          "trace_id" => "Root=1-abc-def",
          "source" => "http",
          "request_id" => "uuid-1"
        )
      end
    end

    context "cuando NO hay trace context (root_id nil) pero sí request_id (Gap C)" do
      before { stub_tracer(root_id: nil, request_id: "uuid-2", source: "http") }

      it "emite request_id aunque root_id esté ausente" do
        result = call("event=acct.received")

        expect(result["request_id"]).to eq("uuid-2")
      end

      it "no emite root_id ni trace_id" do
        result = call("event=acct.received")

        expect(result).not_to have_key("root_id")
        expect(result).not_to have_key("trace_id")
      end
    end

    context "cuando no hay request_id" do
      before { stub_tracer(root_id: "1-x-y", request_id: nil, source: "http") }

      it "no incluye la clave request_id" do
        result = call("event=acct.received")

        expect(result).not_to have_key("request_id")
      end
    end
  end

  describe "dedup de claves Symbol/String (issue #12)" do
    def stub_tracer_with_task(task_value)
      stub_const("ExisRay::Tracer", Module.new do
        define_singleton_method(:service_name) { "test-service" }
        define_singleton_method(:root_id) { "1-abc-def" }
        define_singleton_method(:trace_id) { nil }
        define_singleton_method(:request_id) { nil }
        define_singleton_method(:source) { "task" }
        define_singleton_method(:sidekiq_job) { nil }
        define_singleton_method(:task) { task_value }
      end)
    end

    it "no emite warning de `duplicate key` cuando KV string y Tracer setean la misma key" do
      stub_tracer_with_task("billing:invoices")

      warning = nil
      original_warn = Warning.method(:warn)
      Warning.singleton_class.define_method(:warn) { |msg, **| warning = msg }

      begin
        call("event=task_started task=billing:invoices outcome=started")
      ensure
        Warning.singleton_class.define_method(:warn, original_warn)
      end

      expect(warning).to be_nil
    end

    it "developer payload (KV string) pisa al contexto canónico inyectado por Tracer" do
      stub_tracer_with_task("billing:invoices")

      result = call("event=foo task=override outcome=success")

      expect(result["task"]).to eq("override")
    end

    it "emite la key como String aunque internamente fuese Symbol" do
      stub_tracer_with_task("billing:invoices")

      json_str = formatter.call(severity, timestamp, progname, "event=task_started outcome=started")

      # Si quedaran ambas (`:task` y `"task"`) el JSON tendría dos veces la key.
      expect(json_str.scan(/"task"\s*:/).size).to eq(1)
      expect(JSON.parse(json_str)["task"]).to eq("billing:invoices")
    end

    it "no incluye keys con valor nil en el output" do
      stub_const("ExisRay::Tracer", Module.new do
        define_singleton_method(:service_name) { "test-service" }
        define_singleton_method(:root_id) { nil }
        define_singleton_method(:trace_id) { nil }
        define_singleton_method(:request_id) { nil }
        define_singleton_method(:source) { nil }
        define_singleton_method(:sidekiq_job) { nil }
        define_singleton_method(:task) { nil }
      end)

      result = call("event=foo")

      expect(result).not_to have_key("root_id")
      expect(result).not_to have_key("task")
      expect(result).not_to have_key("source")
    end
  end

  describe "#filter_sensitive_hash (privado)" do
    it "filtra claves sensibles en el nivel raíz" do
      result = formatter.send(:filter_sensitive_hash, { user: "gabriel", password: "secret" })

      expect(result[:user]).to eq("gabriel")
      expect(result[:password]).to eq("[FILTERED]")
    end

    it "filtra claves sensibles en hashes anidados" do
      result = formatter.send(:filter_sensitive_hash, {
                                db: { host: "localhost", token: "abc123" }
                              })

      expect(result[:db][:host]).to eq("localhost")
      expect(result[:db][:token]).to eq("[FILTERED]")
    end

    it "filtra claves sensibles dentro de arrays de hashes" do
      result = formatter.send(:filter_sensitive_hash, {
                                users: [{ name: "gabriel", password: "secret" }, { name: "ana", password: "other" }]
                              })

      expect(result[:users][0][:name]).to eq("gabriel")
      expect(result[:users][0][:password]).to eq("[FILTERED]")
      expect(result[:users][1][:password]).to eq("[FILTERED]")
    end

    it "filtra claves sensibles en arrays primitivos cuando la clave padre es sensible" do
      result = formatter.send(:filter_sensitive_hash, { tokens: %w[abc def] })

      expect(result[:tokens]).to eq(["[FILTERED]", "[FILTERED]"])
    end

    it "no altera valores no sensibles en arrays" do
      result = formatter.send(:filter_sensitive_hash, { tags: %w[admin active] })

      expect(result[:tags]).to eq(%w[admin active])
    end
  end
end
