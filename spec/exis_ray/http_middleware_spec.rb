# frozen_string_literal: true

require "spec_helper"

RSpec.describe ExisRay::HttpMiddleware do
  subject(:middleware) { described_class.new(app) }

  let(:app) { ->(_env) { [200, {}, ["ok"]] } }
  let(:trace_header) { ExisRay.configuration.trace_header }

  after { ExisRay::Tracer.reset }

  describe "#call" do
    context "cuando la request NO trae trace header entrante (entrypoint, issue #9 Gap A)" do
      let(:env) { { "action_dispatch.request_id" => "req-uuid-123" } }

      it "genera un root_id fresco igual que los demás entrypoints" do
        middleware.call(env)

        expect(ExisRay::Tracer.root_id).to match(/\ARoot=1-/)
      end

      it "setea source=http (des-gatea el bloque de tracer en JsonFormatter, Gap B)" do
        middleware.call(env)

        expect(ExisRay::Tracer.source).to eq("http")
      end

      it "setea request_id desde el env de Rails" do
        middleware.call(env)

        expect(ExisRay::Tracer.request_id).to eq("req-uuid-123")
      end
    end

    context "cuando la request trae trace header entrante (eslabón intermedio)" do
      let(:env) do
        {
          trace_header => "Root=1-5759b146-abc123;Self=1-5759b146-def456;CalledFrom=upstream",
          "action_dispatch.request_id" => "req-uuid-456"
        }
      end

      it "respeta el root_id entrante y no genera uno nuevo" do
        middleware.call(env)

        expect(ExisRay::Tracer.root_id).to eq("1-5759b146-abc123")
      end

      it "setea source=http y request_id" do
        middleware.call(env)

        expect(ExisRay::Tracer.source).to eq("http")
        expect(ExisRay::Tracer.request_id).to eq("req-uuid-456")
      end
    end

    it "invoca la app y retorna su respuesta" do
      expect(middleware.call({})).to eq([200, {}, ["ok"]])
    end

    it "no rompe el flujo principal si la hidratación falla" do
      allow(ExisRay::Tracer).to receive(:hydrate).and_raise(StandardError)

      expect(middleware.call({})).to eq([200, {}, ["ok"]])
    end
  end
end
