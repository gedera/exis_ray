# frozen_string_literal: true

require "spec_helper"
require "exis_ray/log_subscriber"

RSpec.describe ExisRay::LogSubscriber do
  subject(:subscriber) { described_class.new }

  let(:logger) { instance_double(Logger, info: nil, error: nil) }

  before do
    allow(subscriber).to receive(:logger).and_return(logger)
    stub_const("Rails", Class.new do
      class << self
        attr_reader :application
      end
    end)
  end

  # Factory para construir un evento compatible con la API de ActiveSupport::Notifications::Event.
  # Solo expone los métodos que LogSubscriber usa: `payload` y `duration`.
  def build_event(payload:, duration_ms: 12.34)
    Struct.new(:payload, :duration).new(payload, duration_ms)
  end

  describe "#process_action" do
    context "cuando el request responde con status 2xx" do
      it "loguea a nivel INFO" do
        event = build_event(payload: { method: "GET", path: "/users", status: 200 })

        subscriber.process_action(event)

        expect(logger).to have_received(:info)
        expect(logger).not_to have_received(:error)
      end
    end

    context "cuando el request responde con status 4xx" do
      it "loguea a nivel INFO (los errores de cliente no son errores del servidor)" do
        event = build_event(payload: { method: "GET", path: "/missing", status: 404 })

        subscriber.process_action(event)

        expect(logger).to have_received(:info)
        expect(logger).not_to have_received(:error)
      end
    end

    context "cuando el request responde con status 5xx" do
      it "loguea a nivel ERROR (regression guard: el campo renombrado a :http_status)" do
        event = build_event(payload: { method: "POST", path: "/boom", status: 500 })

        subscriber.process_action(event)

        expect(logger).to have_received(:error)
        expect(logger).not_to have_received(:info)
      end

      it "loguea a nivel ERROR también para 503" do
        event = build_event(payload: { method: "GET", path: "/unavailable", status: 503 })

        subscriber.process_action(event)

        expect(logger).to have_received(:error)
      end
    end

    context "cuando el request termina con una excepción no rescatada" do
      it "infere status=500 y loguea a nivel ERROR" do
        event = build_event(payload: {
                              method: "GET",
                              path: "/explode",
                              status: nil,
                              exception: %w[RuntimeError kaboom]
                            })

        subscriber.process_action(event)

        expect(logger).to have_received(:error)
      end
    end

    context "cuando el propio build_payload falla" do
      it "cae al fallback sin propagar la excepción" do
        allow(subscriber).to receive(:build_payload).and_raise(RuntimeError, "boom")
        event = build_event(payload: { method: "GET", path: "/x", status: 200 })

        expect { subscriber.process_action(event) }.not_to raise_error
        expect(logger).to have_received(:error).with(hash_including(event: "log_subscriber_fallback"))
      end
    end
  end

  describe "#build_payload (privado)" do
    let(:base_payload) do
      {
        method: "GET",
        path: "/users/42",
        format: "html",
        controller: "UsersController",
        action: "show",
        status: 200,
        view_runtime: 5.0,
        db_runtime: 3.0,
        headers: {
          "HTTP_USER_AGENT" => "Mozilla/5.0",
          "HTTP_HOST" => "api.example.com:3000"
        }
      }
    end

    it "usa :http_status en lugar de :status (breaking rename v0.6.0)" do
      event = build_event(payload: base_payload, duration_ms: 120.5)

      data = subscriber.send(:build_payload, event)

      expect(data).to include(http_status: 200)
      expect(data).not_to have_key(:status)
    end

    it "convierte duration de ms (Rails) a segundos con 4 decimales" do
      event = build_event(payload: base_payload, duration_ms: 1234.5678)

      data = subscriber.send(:build_payload, event)

      expect(data[:duration_s]).to eq(1.2346)
    end

    it "convierte view_runtime y db_runtime a segundos" do
      event = build_event(payload: base_payload, duration_ms: 10)

      data = subscriber.send(:build_payload, event)

      expect(data[:view_runtime_s]).to eq(0.005)
      expect(data[:db_runtime_s]).to eq(0.003)
    end

    it "inyecta user_agent_original desde HTTP_USER_AGENT" do
      event = build_event(payload: base_payload)

      data = subscriber.send(:build_payload, event)

      expect(data[:user_agent_original]).to eq("Mozilla/5.0")
    end

    it "inyecta server_address sin el puerto (OTel server.address espera solo hostname)" do
      event = build_event(payload: base_payload)

      data = subscriber.send(:build_payload, event)

      expect(data[:server_address]).to eq("api.example.com")
    end

    # Helper: construye un mock de ActionDispatch::Journey::Route con la API REAL
    # que usa el código de producción (route.defaults, route.path.spec, route.verb).
    # Esto evita el anti-patrón anterior de stubear una API inventada.
    def build_route(controller:, action:, spec:, verb: "GET")
      path_spec = Object.new
      path_spec.define_singleton_method(:to_s) { spec }
      path = Struct.new(:spec).new(path_spec)
      Struct.new(:path, :defaults, :verb).new(path, { controller: controller, action: action }, verb)
    end

    def stub_rails_application_with_routes(route_list)
      routes = Struct.new(:routes).new(route_list)
      app = Struct.new(:routes).new(routes)
      rails = Class.new do
        class << self
          attr_accessor :application
        end
      end
      stub_const("Rails", rails)
      Rails.application = app
    end

    it "resuelve /users/42 GET a /users/:id iterando las rutas reales" do
      stub_rails_application_with_routes([
                                           build_route(controller: "users", action: "index",
                                                       spec: "/users(.:format)", verb: "GET"),
                                           build_route(controller: "users", action: "show",
                                                       spec: "/users/:id(.:format)", verb: "GET"),
                                           build_route(controller: "users", action: "update",
                                                       spec: "/users/:id(.:format)", verb: "PATCH")
                                         ])

      event = build_event(payload: base_payload)
      data = subscriber.send(:build_payload, event)

      expect(data[:http_route]).to eq("/users/:id")
    end

    it "considera el verb HTTP — distingue show (GET) de update (PATCH) en la misma path" do
      stub_rails_application_with_routes([
                                           build_route(controller: "users", action: "show",
                                                       spec: "/users/:id(.:format)", verb: "GET"),
                                           build_route(controller: "users", action: "update",
                                                       spec: "/users/:id(.:format)", verb: "PATCH")
                                         ])

      patch_payload = base_payload.merge(method: "PATCH", action: "update")
      event = build_event(payload: patch_payload)
      data = subscriber.send(:build_payload, event)

      expect(data[:http_route]).to eq("/users/:id")
    end

    it "normaliza controller CamelCase namespaced (Api::V1::UsersController → api/v1/users)" do
      stub_rails_application_with_routes([
                                           build_route(controller: "api/v1/users", action: "show",
                                                       spec: "/api/v1/users/:id(.:format)", verb: "GET")
                                         ])

      payload = base_payload.merge(controller: "Api::V1::UsersController", path: "/api/v1/users/42")
      event = build_event(payload: payload)
      data = subscriber.send(:build_payload, event)

      expect(data[:http_route]).to eq("/api/v1/users/:id")
    end

    it "prefiere route_uri_pattern del request (Rails 7.1+) por sobre el fallback" do
      request = Struct.new(:route_uri_pattern).new("/users/:id(.:format)")
      # Con rutas vacías, el fallback no podría resolver — si el test pasa, es
      # porque se usó la rama primary (route_uri_pattern).
      stub_rails_application_with_routes([])

      payload = base_payload.merge(request: request)
      event = build_event(payload: payload)
      data = subscriber.send(:build_payload, event)

      expect(data[:http_route]).to eq("/users/:id")
    end

    it "retorna nil cuando no hay ruta que matchee" do
      stub_rails_application_with_routes([
                                           build_route(controller: "admin", action: "dashboard",
                                                       spec: "/admin(.:format)", verb: "GET")
                                         ])

      event = build_event(payload: base_payload)
      data = subscriber.send(:build_payload, event)

      expect(data[:http_route]).to be_nil
    end

    it "retorna nil para http_route cuando Rails.application es nil" do
      stub_const("Rails", Class.new do
        def self.application
          nil
        end
      end)
      event = build_event(payload: base_payload)
      data = subscriber.send(:build_payload, event)

      expect(data[:http_route]).to be_nil
    end

    it "inyecta exception.* (keys symbol) cuando el request termina con excepción" do
      event = build_event(payload: base_payload.merge(
        status: nil,
        exception: ["RuntimeError", "something went wrong"]
      ))

      data = subscriber.send(:build_payload, event)

      expect(data[:"exception.type"]).to eq("RuntimeError")
      expect(data[:"exception.message"]).to eq("something went wrong")
      expect(data[:error_class]).to eq("RuntimeError")
      expect(data[:error_message]).to eq("something went wrong")
    end

    it "inyecta exception.stacktrace desde payload[:exception_object]" do
      exception_object = RuntimeError.new("boom")
      exception_object.set_backtrace(["a.rb:1", "b.rb:2", "c.rb:3"])

      event = build_event(payload: base_payload.merge(
        status: nil,
        exception: %w[RuntimeError boom],
        exception_object: exception_object
      ))

      data = subscriber.send(:build_payload, event)

      expect(data[:"exception.stacktrace"]).to eq("a.rb:1\nb.rb:2\nc.rb:3")
    end

    it "no incluye exception.stacktrace cuando no hay exception_object" do
      event = build_event(payload: base_payload.merge(
        status: nil,
        exception: %w[RuntimeError boom]
      ))

      data = subscriber.send(:build_payload, event)

      expect(data).not_to have_key(:"exception.stacktrace")
    end

    it "no falla cuando el payload no incluye headers" do
      event = build_event(payload: base_payload.except(:headers))

      expect { subscriber.send(:build_payload, event) }.not_to raise_error
    end

    it "compact elimina claves nil para no ensuciar el log" do
      event = build_event(payload: base_payload.merge(view_runtime: nil, db_runtime: nil))

      data = subscriber.send(:build_payload, event)

      expect(data).not_to have_key(:view_runtime_s)
      expect(data).not_to have_key(:db_runtime_s)
    end
  end

  describe "#extract_server_address (privado)" do
    it "retorna el host sin puerto" do
      expect(subscriber.send(:extract_server_address, "example.com:8080")).to eq("example.com")
    end

    it "retorna el host tal cual si no tiene puerto" do
      expect(subscriber.send(:extract_server_address, "example.com")).to eq("example.com")
    end

    it "retorna nil cuando el input es nil" do
      expect(subscriber.send(:extract_server_address, nil)).to be_nil
    end
  end
end
