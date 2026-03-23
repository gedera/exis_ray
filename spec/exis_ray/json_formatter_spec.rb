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
          "event"   => "archive_lookup",
          "cutoff"  => "2025-09-01",
          "level"   => "INFO",
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
          "event"   => "archive_lookup",
          "cutoff"  => "2025-09-01",
          "level"   => "INFO",
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
          "component"   => "orders",
          "event"       => "invoice_generated",
          "duration_ms" => "42.5",
          "retries"     => "0"
        )
      end
    end

      it "cae a message si el string parece kv pero no produce ningún par" do
        result = call("key=")

        expect(result["message"]).to eq("key=")
        expect(result).not_to have_key("key")
      end
    end

    context "cuando el mensaje es un String libre (sin formato key=value)" do
      it "asigna el string completo al campo message" do
        result = call("algo salió mal")

        expect(result["message"]).to eq("algo salió mal")
        expect(result).to include("level" => "INFO", "service" => "test-service")
      end

      it "asigna un string vacío al campo message" do
        result = call("")

        expect(result["message"]).to eq("")
      end

      it "convierte objetos arbitrarios a string via to_s" do
        result = call(42)

        expect(result["message"]).to eq("42")
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
    it "retorna un hash con claves symbol" do
      result = formatter.send(:parse_kv_string, "a=1 b=2")

      expect(result).to eq({ a: "1", b: "2" })
    end

    it "desenvuelve las comillas dobles de los valores" do
      result = formatter.send(:parse_kv_string, 'msg="hello world"')

      expect(result).to eq({ msg: "hello world" })
    end
  end
end
