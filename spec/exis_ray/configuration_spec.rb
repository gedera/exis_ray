# frozen_string_literal: true

require "spec_helper"

RSpec.describe ExisRay::Configuration do
  describe "valores por defecto" do
    subject(:config) { described_class.new }

    it "trace_header por defecto es HTTP_X_AMZN_TRACE_ID" do
      expect(config.trace_header).to eq("HTTP_X_AMZN_TRACE_ID")
    end

    it "propagation_trace_header por defecto es X-Amzn-Trace-Id" do
      expect(config.propagation_trace_header).to eq("X-Amzn-Trace-Id")
    end

    it "reporter_class por defecto es nil" do
      expect(config.reporter_class).to be_nil
    end

    it "current_class por defecto es nil" do
      expect(config.current_class).to be_nil
    end

    it "log_format por defecto es :text" do
      expect(config.log_format).to eq(:text)
    end

    it "log_subscriber_class por defecto es nil" do
      expect(config.log_subscriber_class).to be_nil
    end

    it "service_version por defecto es nil fuera de Rails" do
      expect(config.service_version).to be_nil
    end

    it "deployment_environment por defecto es nil fuera de Rails" do
      expect(config.deployment_environment).to be_nil
    end

    it "global_fields por defecto es un hash vacío congelado" do
      expect(config.global_fields).to eq({})
      expect(config.global_fields).to be_frozen
    end
  end

  describe "#global_fields=" do
    let(:config) { described_class.new }

    it "asigna el hash provisto" do
      config.global_fields = { tenant_id: "42", stack_id: "edge-1" }

      expect(config.global_fields).to eq(tenant_id: "42", stack_id: "edge-1")
    end

    it "congela el hash para garantizar inmutabilidad runtime" do
      config.global_fields = { tenant_id: "42" }

      expect(config.global_fields).to be_frozen
      expect { config.global_fields[:tenant_id] = "99" }.to raise_error(FrozenError)
    end

    it "filtra claves sensibles reemplazando el valor por [FILTERED]" do
      config.global_fields = { tenant_id: "42", api_key: "secret", token: "abc" }

      expect(config.global_fields[:tenant_id]).to eq("42")
      expect(config.global_fields[:api_key]).to eq("[FILTERED]")
      expect(config.global_fields[:token]).to eq("[FILTERED]")
    end

    it "trata nil como hash vacío" do
      config.global_fields = nil

      expect(config.global_fields).to eq({})
      expect(config.global_fields).to be_frozen
    end

    it "trata hash vacío como hash vacío congelado" do
      config.global_fields = {}

      expect(config.global_fields).to eq({})
      expect(config.global_fields).to be_frozen
    end

    it "soporta claves string para filtrado de sensibles" do
      config.global_fields = { "password" => "x", "tenant_id" => "42" }

      expect(config.global_fields["password"]).to eq("[FILTERED]")
      expect(config.global_fields["tenant_id"]).to eq("42")
    end
  end

  describe "resource attributes OTel" do
    it "permite setear service_version" do
      config = described_class.new
      config.service_version = "2.0.0"

      expect(config.service_version).to eq("2.0.0")
    end

    it "permite setear deployment_environment" do
      config = described_class.new
      config.deployment_environment = "staging"

      expect(config.deployment_environment).to eq("staging")
    end

    describe "#default_service_version" do
      it "retorna nil cuando Rails no está definido" do
        expect(described_class.new.default_service_version).to be_nil
      end

      it "lee config.version (atributo directo) con prioridad sobre config.x.version" do
        rails_config = Struct.new(:version).new("1.2.3")
        allow(rails_config).to receive(:respond_to?).and_call_original
        app = Struct.new(:config).new(rails_config)
        stub_const("Rails", Class.new do
          define_singleton_method(:application) { app }
        end)

        expect(described_class.new.default_service_version).to eq("1.2.3")
      end

      it "cae a config.x.version si config.version no está definido" do
        x_config = Struct.new(:version).new("3.0.0")
        rails_config = Struct.new(:x).new(x_config)
        app = Struct.new(:config).new(rails_config)
        stub_const("Rails", Class.new do
          define_singleton_method(:application) { app }
        end)

        expect(described_class.new.default_service_version).to eq("3.0.0")
      end

      it "retorna nil si config.x.version es un OrderedOptions vacío (no un string)" do
        x_config = ActiveSupport::OrderedOptions.new
        rails_config = Struct.new(:x).new(x_config)
        app = Struct.new(:config).new(rails_config)
        stub_const("Rails", Class.new do
          define_singleton_method(:application) { app }
        end)

        expect(described_class.new.default_service_version).to be_nil
      end
    end

    describe "#default_deployment_environment" do
      it "retorna nil cuando Rails no está definido" do
        expect(described_class.new.default_deployment_environment).to be_nil
      end
    end
  end

  describe "#json_logs?" do
    it "retorna true cuando log_format es :json" do
      config = described_class.new
      config.log_format = :json

      expect(config.json_logs?).to be true
    end

    it "retorna false cuando log_format es :text" do
      config = described_class.new
      config.log_format = :text

      expect(config.json_logs?).to be false
    end
  end

  describe "mutabilidad" do
    it "permite cambiar trace_header" do
      config = described_class.new
      config.trace_header = "HTTP_X_CUSTOM_TRACE"

      expect(config.trace_header).to eq("HTTP_X_CUSTOM_TRACE")
    end

    it "permite cambiar propagation_trace_header" do
      config = described_class.new
      config.propagation_trace_header = "X-Custom-Trace-Id"

      expect(config.propagation_trace_header).to eq("X-Custom-Trace-Id")
    end

    it "permite cambiar reporter_class" do
      config = described_class.new
      config.reporter_class = "CustomReporter"

      expect(config.reporter_class).to eq("CustomReporter")
    end

    it "permite cambiar current_class" do
      config = described_class.new
      config.current_class = "CustomCurrent"

      expect(config.current_class).to eq("CustomCurrent")
    end

    it "permite cambiar log_format" do
      config = described_class.new
      config.log_format = :json

      expect(config.log_format).to eq(:json)
    end

    it "permite cambiar log_subscriber_class" do
      config = described_class.new
      config.log_subscriber_class = "MyLogSubscriber"

      expect(config.log_subscriber_class).to eq("MyLogSubscriber")
    end
  end
end
