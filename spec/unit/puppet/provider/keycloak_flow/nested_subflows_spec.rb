# frozen_string_literal: true

require 'spec_helper'

# Regression: instances() must discover non-built-in flows with nested
# subflows without raising, the discovered provider instances must carry only
# attributes declared on the keycloak_flow type (no dead keys like
# :display_name / :configurable, which have no accessor and would break any
# path that reconstructs a Type from the property hash), and prefetch must
# match every flow in the hierarchy against its declarative resource.
describe Puppet::Type.type(:keycloak_flow).provider(:kcadm) do
  let(:type) { Puppet::Type.type(:keycloak_flow) }

  # the attributes declared on the keycloak_flow type (params + properties)
  def declared_attrs
    (type.validproperties.map(&:name) + type.parameters).map(&:to_sym)
  end

  def mock_mfa_topology
    allow(described_class).to receive(:realms).and_return(['EXAMPLE.COM'])
    allow(described_class).to receive(:kcadm)
      .with('get', 'authentication/flows', 'EXAMPLE.COM')
      .and_return(my_fixture_read('get-flows-mfa.out'))
    allow(described_class).to receive(:kcadm)
      .with('get', 'authentication/flows/browser-custom/executions', 'EXAMPLE.COM')
      .and_return(my_fixture_read('get-browser-custom-executions.out'))
  end

  # provider objects expose their instance hash via @property_hash
  def hash_of(provider)
    provider.instance_variable_get('@property_hash')
  end

  describe 'self.instances with a non-built-in flow and nested subflows' do
    before(:each) { mock_mfa_topology }

    it 'discovers the top-level flow and all three subflow levels without raising' do
      names = described_class.instances.map { |i| hash_of(i)[:name] }
      expect(names).to include(
        'browser-custom on EXAMPLE.COM',
        'Organization under browser-custom on EXAMPLE.COM',
        'forms under browser-custom on EXAMPLE.COM',
        'Browser - Conditional Organization under Organization on EXAMPLE.COM',
        'Browser - Conditional OTP under forms on EXAMPLE.COM'
      )
    end

    it 'builds subflow resources with identity that matches the manifest declaration' do
      flows = described_class.instances.map { |i| hash_of(i) }
      forms = flows.find { |f| f[:name] == 'forms under browser-custom on EXAMPLE.COM' }
      expect(forms).not_to be_nil
      expect(forms[:alias]).to eq('forms')
      expect(forms[:flow_alias]).to eq('browser-custom')
      expect(forms[:realm]).to eq('EXAMPLE.COM')
      expect(forms[:top_level]).to eq(:false)
      expect(forms[:requirement]).to eq('ALTERNATIVE')
      expect(forms[:priority]).to eq(30)

      otp = flows.find { |f| f[:name] == 'Browser - Conditional OTP under forms on EXAMPLE.COM' }
      expect(otp).not_to be_nil
      expect(otp[:alias]).to eq('Browser - Conditional OTP')
      expect(otp[:flow_alias]).to eq('forms') # parent resolution via level-1 -> last level-0 display name
      expect(otp[:requirement]).to eq('CONDITIONAL')
      expect(otp[:priority]).to eq(20)

      org = flows.find { |f| f[:name] == 'Browser - Conditional Organization under Organization on EXAMPLE.COM' }
      expect(org).not_to be_nil
      expect(org[:flow_alias]).to eq('Organization')
    end

    it 'carries only declared type attributes in each discovered instance hash' do
      allowed = declared_attrs | [:name, :ensure]
      described_class.instances.each do |i|
        dead = hash_of(i).keys - allowed
        expect(dead).to be_empty,
          "instance #{hash_of(i)[:name]} carries undeclared attributes: #{dead.inspect}"
      end
    end

    it 'prefetch matches declarative resources for every flow in the hierarchy' do
      resources = {}
      [
        { name: 'browser-custom on EXAMPLE.COM',
          alias: 'browser-custom', realm: 'EXAMPLE.COM', top_level: true },
        { name: 'Organization under browser-custom on EXAMPLE.COM',
          alias: 'Organization', flow_alias: 'browser-custom', realm: 'EXAMPLE.COM',
          top_level: false, priority: 26 },
        { name: 'forms under browser-custom on EXAMPLE.COM',
          alias: 'forms', flow_alias: 'browser-custom', realm: 'EXAMPLE.COM',
          top_level: false, priority: 30 },
        { name: 'Browser - Conditional Organization under Organization on EXAMPLE.COM',
          alias: 'Browser - Conditional Organization', flow_alias: 'Organization',
          realm: 'EXAMPLE.COM', top_level: false, priority: 10 },
        { name: 'Browser - Conditional OTP under forms on EXAMPLE.COM',
          alias: 'Browser - Conditional OTP', flow_alias: 'forms',
          realm: 'EXAMPLE.COM', top_level: false, priority: 20 }
      ].each do |attrs|
        resources[attrs[:name]] = type.new(attrs)
      end

      described_class.prefetch(resources)

      resources.each_value do |resource|
        expect(resource.provider).not_to be_nil,
          "prefetch did not match #{resource[:name]}"
      end
    end
  end
end
