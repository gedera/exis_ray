# frozen_string_literal: true

require "spec_helper"
require "exis_ray/task_monitor"

RSpec.describe ExisRay::TaskMonitor do
  let(:captured_logs) { [] }
  let(:test_logger) do
    logs = captured_logs
    Class.new do
      define_method(:info)  { |msg| logs << [:info,  msg] }
      define_method(:error) { |msg| logs << [:error, msg] }
      def tagged(*_tags)
        yield
      end
    end.new
  end

  before do
    stub_const("Rails", Class.new do
      class << self
        attr_reader :logger
      end

      class << self
        attr_writer :logger
      end
    end)
    Rails.logger = test_logger

    # Evitar que ExisRay.configuration.json_logs? explote si el Configuration real
    # no está stubeado — TaskMonitor solo llama a `.tagged` si estamos en modo texto.
    allow(ExisRay.configuration).to receive(:json_logs?).and_return(true)

    # Aislar el Tracer/Current/Reporter entre tests
    ExisRay::Tracer.reset
    allow(ExisRay).to receive_messages(current_class: nil, reporter_class: nil)
  end

  after { ExisRay::Tracer.reset }

  describe ".run" do
    context "cuando el bloque se ejecuta con éxito" do
      it "loguea task_started con outcome=started" do
        described_class.run("billing:invoices") { :ok }

        start_log = captured_logs.find { |_, msg| msg.include?("task_started") }
        expect(start_log).not_to be_nil
        expect(start_log[0]).to eq(:info)
        expect(start_log[1]).to include("outcome=started")
        expect(start_log[1]).to include("event=task_started")
        expect(start_log[1]).to include("task=billing:invoices")
      end

      it "loguea task_finished con outcome=success (breaking rename v0.6.0)" do
        described_class.run("billing:invoices") { :ok }

        finish_log = captured_logs.find { |_, msg| msg.include?("task_finished") }
        expect(finish_log).not_to be_nil
        expect(finish_log[0]).to eq(:info)
        expect(finish_log[1]).to include("outcome=success")
        expect(finish_log[1]).to include("duration_s=")
      end

      it "no usa el campo viejo 'status=' en los mensajes de task lifecycle" do
        described_class.run("billing:invoices") { :ok }

        lifecycle = captured_logs.map { |_, msg| msg }.select { |m| m.include?("event=task_") }
        lifecycle.each do |msg|
          expect(msg).not_to match(/\bstatus=/)
        end
      end

      it "resetea el Tracer en el ensure" do
        described_class.run("task:x") { :ok }

        expect(ExisRay::Tracer.task).to be_nil
      end
    end

    context "cuando el bloque lanza una excepción" do
      it "loguea task_finished con outcome=failed y re-lanza" do
        expect do
          described_class.run("task:boom") { raise "kaboom" }
        end.to raise_error(RuntimeError, "kaboom")

        finish_log = captured_logs.find { |lvl, msg| lvl == :error && msg.include?("task_finished") }
        expect(finish_log).not_to be_nil
        expect(finish_log[1]).to include("outcome=failed")
        expect(finish_log[1]).to include("error_class=RuntimeError")
        expect(finish_log[1]).to include("error_message=")
        expect(finish_log[1]).to include("exception.type=RuntimeError")
        expect(finish_log[1]).to include("exception.message=")
        expect(finish_log[1]).to include("exception.stacktrace=")
      end

      it "resetea el Tracer incluso en caso de error" do
        begin
          described_class.run("task:boom") { raise "kaboom" }
        rescue StandardError
          nil
        end

        expect(ExisRay::Tracer.task).to be_nil
      end
    end
  end
end
