# frozen_string_literal: true

require "spec_helper"

RSpec.describe ExisRay::Reporter do
  # ActiveSupport::CurrentAttributes necesita un nombre de clase para el almacenamiento thread-local.
  class TestReporter < ExisRay::Reporter; end

  before do
    TestReporter.reset
  end

  describe ".report_to_new_sentry?" do
    it "retorna false/nil cuando NEW_SENTRY no esta definido" do
      hide_const("NEW_SENTRY")
      expect(TestReporter.report_to_new_sentry?).to be_falsey
    end

    it "retorna true cuando NEW_SENTRY es truthy" do
      stub_const("NEW_SENTRY", true)
      expect(TestReporter.report_to_new_sentry?).to be true
    end
  end

  describe "gestion de tags y contextos" do
    it "permite agregar tags y los acumula" do
      TestReporter.add_tags(foo: "bar")
      TestReporter.add_tags(baz: "qux")

      expect(TestReporter.tags).to eq("foo" => "bar", "baz" => "qux")
    end

    it "permite agregar contexto y lo acumula" do
      TestReporter.add_context(extra: { a: 1 })
      TestReporter.add_context(other: { b: 2 })

      expect(TestReporter.contexts).to eq("extra" => { "a" => 1 }, "other" => { "b" => 2 })
    end

    it "limpia todo al resetear" do
      TestReporter.tags = { a: 1 }
      TestReporter.contexts = { b: 2 }
      TestReporter.reset

      expect(TestReporter.tags).to eq({})
      expect(TestReporter.contexts).to eq({})
    end
  end

  describe ".build_from_current (preservacion de 0)" do
    let(:current_mock) do
      double("Current", user_id: 0, isp_id: 0, user: nil, isp: nil)
    end

    before do
      allow(ExisRay).to receive(:current_class).and_return(current_mock)
    end

    it "incluye user_id=0 en los tags (no debe usar .present?)" do
      allow(current_mock).to receive(:respond_to?).with(:user_id).and_return(true)
      allow(current_mock).to receive(:respond_to?).with(:isp_id).and_return(true)
      allow(current_mock).to receive(:respond_to?).with(:user).and_return(true)
      allow(current_mock).to receive(:respond_to?).with(:isp).and_return(true)

      TestReporter.send(:build_from_current)

      expect(TestReporter.tags).to include("user_id" => 0)
      expect(TestReporter.tags).to include("isp_id" => 0)
    end

    it "no incluye ids si son nil" do
      allow(current_mock).to receive(:user_id).and_return(nil)
      allow(current_mock).to receive(:isp_id).and_return(nil)
      allow(current_mock).to receive(:respond_to?).and_return(true)

      TestReporter.send(:build_from_current)

      expect(TestReporter.tags).not_to have_key("user_id")
      expect(TestReporter.tags).not_to have_key("isp_id")
    end
  end

  describe ".build_from_tracer" do
    before do
      stub_const("ExisRay::Tracer", double("Tracer", root_id: "root-123", request_id: "req-456"))
    end

    it "extrae root_id y request_id del tracer" do
      TestReporter.send(:build_from_tracer)

      expect(TestReporter.tags).to include("correlation_id" => "root-123")
      expect(TestReporter.contexts["trace"]).to eq("root_id" => "root-123", "request_id" => "req-456")
    end
  end
end
