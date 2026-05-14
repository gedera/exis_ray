# frozen_string_literal: true

require "spec_helper"

RSpec.describe ExisRay::Current do
  # ActiveSupport::CurrentAttributes necesita un nombre de clase para el almacenamiento thread-local.
  # Las clases anónimas Class.new retornan nil en .name, lo que rompe internals de Rails.
  class TestCurrent < ExisRay::Current; end

  before do
    TestCurrent.reset
  end

  describe "atributos basicos" do
    it "permite setear y leer user_id" do
      TestCurrent.user_id = 123
      expect(TestCurrent.user_id).to eq(123)
    end

    it "permite setear y leer isp_id" do
      TestCurrent.isp_id = 456
      expect(TestCurrent.isp_id).to eq(456)
    end

    it "permite setear y leer correlation_id" do
      TestCurrent.correlation_id = "abc-123"
      expect(TestCurrent.correlation_id).to eq("abc-123")
    end
  end

  describe "predicados (preservacion de 0)" do
    it "user? es true si user_id es 0" do
      TestCurrent.user_id = 0
      expect(TestCurrent.instance.user?).to be true
    end

    it "user? es false si user_id es nil" do
      TestCurrent.user_id = nil
      expect(TestCurrent.instance.user?).to be false
    end

    it "isp? es true si isp_id es 0" do
      TestCurrent.isp_id = 0
      expect(TestCurrent.instance.isp?).to be true
    end

    it "isp? es false si isp_id es nil" do
      TestCurrent.isp_id = nil
      expect(TestCurrent.instance.isp?).to be false
    end
  end

  describe "lazy loading de objetos (con cache por request)" do
    let(:user_mock) { double("User", id: 123) }

    before do
      stub_const("User", double("UserClass"))
    end

    it "memoiza el objeto User dentro del mismo request" do
      TestCurrent.user_id = 123
      expect(User).to receive(:find_by).with(id: 123).once.and_return(user_mock)

      expect(TestCurrent.instance.user).to eq(user_mock)
      expect(TestCurrent.instance.user).to eq(user_mock)
    end

    it "invalida el cache al cambiar user_id" do
      TestCurrent.user_id = 123
      allow(User).to receive(:find_by).with(id: 123).and_return(user_mock)
      TestCurrent.instance.user

      new_user = double("User", id: 456)
      TestCurrent.user_id = 456
      expect(User).to receive(:find_by).with(id: 456).and_return(new_user)

      expect(TestCurrent.instance.user).to eq(new_user)
    end

    it "invalida el cache al resetear" do
      TestCurrent.user_id = 123
      allow(User).to receive(:find_by).with(id: 123).and_return(user_mock)
      TestCurrent.instance.user

      TestCurrent.reset
      TestCurrent.user_id = 123
      expect(User).to receive(:find_by).with(id: 123).and_return(user_mock)
      TestCurrent.instance.user
    end

    it "retorna nil si el modelo no esta definido" do
      hide_const("User")
      TestCurrent.user_id = 123
      expect(TestCurrent.instance.user).to be_nil
    end
  end

  describe "integracion con headers y dependencias" do
    it "limpia headers de ActiveResource al resetear" do
      stub_const("ActiveResource::Base", double("ARBase", headers: {}))
      ActiveResource::Base.headers["UserId"] = "123"

      TestCurrent.reset
      expect(ActiveResource::Base.headers).not_to have_key("UserId")
    end

    it "inyecta correlation_id en el reporter al setearlo" do
      reporter_mock = double("Reporter")
      allow(ExisRay).to receive(:reporter_class).and_return(reporter_mock)
      expect(reporter_mock).to receive(:add_tags).with(correlation_id: "corr-1")

      TestCurrent.correlation_id = "corr-1"
    end
  end

  describe ".log_fields hook" do
    it "retorna un Hash vacío por defecto" do
      expect(TestCurrent.log_fields).to eq({})
    end

    it "permite que la subclass overridee el método para inyectar campos custom" do
      stub_const("TenantCurrent", Class.new(ExisRay::Current) do
        def self.log_fields
          { tenant_id: "42", region: "us-east-1" }
        end
      end)

      expect(TenantCurrent.log_fields).to eq(tenant_id: "42", region: "us-east-1")
    end

    it "soporta combinar constantes de proceso con atributos per-request" do
      stub_const("MixedCurrent", Class.new(ExisRay::Current) do
        attribute :region

        STATIC_TENANT = "tenant-42"

        def self.log_fields
          { tenant_id: STATIC_TENANT, region: region }.compact
        end
      end)
      MixedCurrent.region = "us-east-1"

      expect(MixedCurrent.log_fields).to eq(tenant_id: "tenant-42", region: "us-east-1")

      MixedCurrent.reset
      expect(MixedCurrent.log_fields).to eq(tenant_id: "tenant-42")
    end
  end
end
