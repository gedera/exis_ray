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

    it "reporter_class por defecto es Reporter" do
      expect(config.reporter_class).to eq("Reporter")
    end

    it "current_class por defecto es Current" do
      expect(config.current_class).to eq("Current")
    end

    it "log_format por defecto es :text" do
      expect(config.log_format).to eq(:text)
    end

    it "log_subscriber_class por defecto es nil" do
      expect(config.log_subscriber_class).to be_nil
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
