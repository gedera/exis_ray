# frozen_string_literal: true

require "spec_helper"

RSpec.describe ExisRay::Tracer do
  describe ".service_name" do
    it "retorna app por defecto sin Rails" do
      hide_const("Rails")
      expect(described_class.service_name).to eq("app")
    end
  end

  describe ".correlation_id" do
    before { described_class.root_id = nil }
    after { described_class.reset }

    it "compone ServiceName;RootID" do
      hide_const("Rails")
      described_class.root_id = "1-abc123-def456"
      expect(described_class.correlation_id).to eq("app;1-abc123-def456")
    end

    it "retorna ServiceName;nil cuando root_id es nil" do
      hide_const("Rails")
      described_class.root_id = nil
      expect(described_class.correlation_id).to eq("app;")
    end
  end

  describe ".parse_trace_id" do
    after { described_class.reset }

    it "parsea header AWS X-Ray completo" do
      described_class.trace_id = "Root=1-5759b146-abc123;Self=1-5759b146-def456;CalledFrom=my_service;TotalTimeSoFar=42ms"
      described_class.parse_trace_id

      expect(described_class.root_id).to eq("1-5759b146-abc123")
      expect(described_class.self_id).to eq("1-5759b146-def456")
      expect(described_class.called_from).to eq("my_service")
      expect(described_class.total_time_so_far).to eq(42)
    end

    it "setea total_time_so_far a 0 cuando no esta en el header" do
      described_class.trace_id = "Root=1-5759b146-abc123"
      described_class.parse_trace_id

      expect(described_class.total_time_so_far).to eq(0)
    end

    it "parsea TotalTimeSoFar sin sufijo ms" do
      described_class.trace_id = "Root=1-abc;TotalTimeSoFar=100ms"
      described_class.parse_trace_id

      expect(described_class.total_time_so_far).to eq(100)
    end

    it "genera nuevo root si el header no trae Root" do
      described_class.trace_id = "SomeRandomHeader=value"
      described_class.parse_trace_id

      expect(described_class.root_id).to match(/^1-/)
    end

    it "no hace nada si trace_id es nil" do
      described_class.trace_id = nil
      described_class.parse_trace_id

      expect(described_class.root_id).to be_nil
    end

    it "no hace nada si trace_id esta vacio" do
      described_class.trace_id = ""
      described_class.parse_trace_id

      expect(described_class.root_id).to be_nil
    end

    it "solo parsea partes con formato key=value" do
      described_class.trace_id = "Root=1-abc;Self=1-def"
      described_class.parse_trace_id

      expect(described_class.root_id).to eq("1-abc")
      expect(described_class.self_id).to eq("1-def")
    end

    it "ignora partes sin formato key=value" do
      described_class.trace_id = "Root=1-abc;invalid_part;Self=1-def"
      described_class.parse_trace_id

      expect(described_class.root_id).to eq("1-abc")
      expect(described_class.self_id).to eq("1-def")
    end
  end

  describe ".current_duration_ms" do
    after { described_class.reset }

    it "calcula duracion en milisegundos" do
      described_class.created_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) - 1.5

      expect(described_class.current_duration_ms).to be_a(Integer)
      expect(described_class.current_duration_ms).to be >= 1400
    end

    it "retorna 0 si created_at es nil" do
      described_class.created_at = nil

      expect(described_class.current_duration_ms).to eq(0)
    end
  end

  describe ".current_duration_s" do
    after { described_class.reset }

    it "calcula duracion en segundos" do
      described_class.created_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) - 1.5

      expect(described_class.current_duration_s).to be_a(Float)
      expect(described_class.current_duration_s).to be >= 1.4
    end

    it "retorna 0.0 si created_at es nil" do
      described_class.created_at = nil

      expect(described_class.current_duration_s).to eq(0.0)
    end
  end

  describe ".format_duration" do
    it "formatea menos de 1s como ms" do
      expect(described_class.format_duration(0.045)).to eq("45.0ms")
    end

    it "formatea entre 1-60s con s" do
      expect(described_class.format_duration(5.25)).to eq("5.25s")
    end

    it "formatea 60s o mas con duracion humana" do
      expect(described_class.format_duration(125)).to include("2 minutes")
    end
  end

  describe ".generate_trace_header" do
    after { described_class.reset }

    it "genera header con root, self, called_from y total_time" do
      hide_const("Rails")
      described_class.root_id = "1-abc-def"
      described_class.created_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) - 0.1

      header = described_class.generate_trace_header

      expect(header).to include("Root=1-abc-def")
      expect(header).to include("Self=1-")
      expect(header).to include("CalledFrom=app")
      expect(header).to include("TotalTimeSoFar=")
    end

    it "agrega prefijo Root= si no esta" do
      hide_const("Rails")
      described_class.root_id = "1-abc-def"

      header = described_class.generate_trace_header

      expect(header).to match(/^Root=1-abc-def;/)
    end

    it "genera nuevo root si root_id es nil" do
      hide_const("Rails")
      described_class.root_id = nil

      header = described_class.generate_trace_header

      expect(header).to include("Root=1-")
    end

    it "acumula total_time_so_far" do
      hide_const("Rails")
      described_class.root_id = "1-abc"
      described_class.total_time_so_far = 100
      described_class.created_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) - 0.05

      header = described_class.generate_trace_header

      expect(header).to match(/TotalTimeSoFar=\d+ms/)
      match = header.match(/TotalTimeSoFar=(\d+)ms/)
      expect(match[1].to_i).to be > 100
    end
  end

  describe ".generate_new_root" do
    it "genera formato Root=1-hex-ts-hex" do
      result = described_class.send(:generate_new_root)

      expect(result).to match(/^Root=1-[0-9a-f]+-[0-9a-f]+$/)
    end

    it "incluye sufijo si se provee" do
      result = described_class.send(:generate_new_root, "worker01")

      expect(result).to match(/^Root=1-[0-9a-f]+-/)
    end

    it "no incluye espacios en blanco" do
      result = described_class.send(:generate_new_root)

      expect(result).not_to include(" ")
    end
  end

  describe ".clean_request_id" do
    after { described_class.reset }

    it "retorna request_id sin guiones y limitado" do
      described_class.request_id = "abc-def-123-456-789-abc-def"

      result = described_class.send(:clean_request_id)

      expect(result).not_to include("-")
      expect(result.length).to be <= 24
    end

    it "usa SecureRandom si request_id es nil" do
      described_class.request_id = nil

      result = described_class.send(:clean_request_id)

      expect(result.length).to eq(24)
      expect(result).to match(/^[0-9a-f]+$/)
    end
  end
end
