# frozen_string_literal: true

require 'spec_helper'

describe Puppet::Type.type(:keycloak_realm).provider(:kcadm) do
  let(:type) do
    Puppet::Type.type(:keycloak_realm)
  end
  let(:resource) do
    type.new(name: 'test')
  end

  describe 'self.instances' do
    it 'creates instances' do
      allow(described_class).to receive(:kcadm).with('get', 'realms').and_return(my_fixture_read('get.out'))
      allow(described_class).to receive(:get_client_scopes).with('test', 'default').and_return('profile' => '8a6759cb-3950-48a2-b29b-c2c06fc3379b')
      allow(described_class).to receive(:get_client_scopes).with('test', 'optional').and_return('address' => '1cda5a52-aa2c-4b07-b620-30b703619581')
      allow(described_class).to receive(:get_client_scopes).with('master', 'default').and_return('profile' => '8a6759cb-3950-48a2-b29b-c2c06fc3379b')
      allow(described_class).to receive(:get_client_scopes).with('master', 'optional').and_return('address' => '1cda5a52-aa2c-4b07-b620-30b703619581')
      allow(described_class).to receive(:get_events_config).with('test').and_return({})
      allow(described_class).to receive(:get_events_config).with('master').and_return({})
      allow(described_class).to receive(:get_realm_roles).with('test').and_return(['offline_access', 'uma_authorization'])
      allow(described_class).to receive(:get_realm_roles).with('master').and_return(['offline_access', 'uma_authorization'])
      expect(described_class.instances.length).to eq(2)
    end

    it 'returns the resource for a fileset' do
      allow(described_class).to receive(:kcadm).with('get', 'realms').and_return(my_fixture_read('get.out'))
      allow(described_class).to receive(:get_client_scopes).with('test', 'default').and_return('profile' => '8a6759cb-3950-48a2-b29b-c2c06fc3379b')
      allow(described_class).to receive(:get_client_scopes).with('test', 'optional').and_return('address' => '1cda5a52-aa2c-4b07-b620-30b703619581')
      allow(described_class).to receive(:get_client_scopes).with('master', 'default').and_return('profile' => '8a6759cb-3950-48a2-b29b-c2c06fc3379b')
      allow(described_class).to receive(:get_client_scopes).with('master', 'optional').and_return('address' => '1cda5a52-aa2c-4b07-b620-30b703619581')
      allow(described_class).to receive(:get_events_config).with('test').and_return({})
      allow(described_class).to receive(:get_events_config).with('master').and_return({})
      allow(described_class).to receive(:get_realm_roles).with('test').and_return(['offline_access', 'uma_authorization'])
      allow(described_class).to receive(:get_realm_roles).with('master').and_return(['offline_access', 'uma_authorization'])
      property_hash = described_class.instances[0].instance_variable_get('@property_hash')
      expect(property_hash[:enabled]).to eq(:true)
      expect(property_hash[:login_with_email_allowed]).to eq(:false)
      expect(property_hash[:default_client_scopes]).to eq(['profile'])
      expect(property_hash[:optional_client_scopes]).to eq(['address'])
      expect(property_hash[:roles]).to eq(['offline_access', 'uma_authorization'])
    end

    it 'reads frontend_url from the realm attributes' do
      allow(described_class).to receive(:kcadm).with('get', 'realms').and_return(my_fixture_read('get.out'))
      allow(described_class).to receive(:get_client_scopes).and_return({})
      allow(described_class).to receive(:get_events_config).and_return({})
      allow(described_class).to receive(:get_realm_roles).and_return([])
      instances = described_class.instances
      expect(instances[1].instance_variable_get('@property_hash')[:frontend_url]).to eq('https://master.example.com')
    end

    it 'reports an absent frontendUrl attribute as an empty string' do
      allow(described_class).to receive(:kcadm).with('get', 'realms').and_return(my_fixture_read('get.out'))
      allow(described_class).to receive(:get_client_scopes).and_return({})
      allow(described_class).to receive(:get_events_config).and_return({})
      allow(described_class).to receive(:get_realm_roles).and_return([])
      instances = described_class.instances
      expect(instances[0].instance_variable_get('@property_hash')[:frontend_url]).to eq('')
    end
  end
  #   describe 'self.prefetch' do
  #     let(:instances) do
  #       all_realms.map { |f| described_class.new(f) }
  #     end
  #     let(:resources) do
  #       all_realms.each_with_object({}) do |f, h|
  #         h[f[:name]] = type.new(f.reject {|k,v| v.nil?})
  #       end
  #     end
  #
  #     before(:each) do
  #       allow(described_class).to receive(:instances).and_return(instances)
  #     end
  #
  #     it 'should prefetch' do
  #       resources.keys.each do |r|
  #         expect(resources[r]).to receive(:provider=).with(described_class)
  #       end
  #       described_class.prefetch(resources)
  #     end
  #   end

  describe 'create' do
    it 'creates a realm' do
      temp = Tempfile.new('keycloak_realm')
      etemp = Tempfile.new('keycloak_events_config')
      rtemp = Tempfile.new('keycloak_realm_role')
      allow(Tempfile).to receive(:new).with('keycloak_realm').and_return(temp)
      allow(Tempfile).to receive(:new).with('keycloak_events_config').and_return(etemp)
      allow(Tempfile).to receive(:new).with('keycloak_realm_role').and_return(rtemp)
      allow(described_class).to receive(:get_realm_roles).with('test').and_return(['offline_access', 'uma_authorization'])
      expect(resource.provider).to receive(:kcadm).with('create', 'realms', nil, temp.path)
      expect(resource.provider).to receive(:kcadm).with('create', 'roles', 'test', rtemp.path)
      expect(resource.provider).to receive(:kcadm).with('update', 'events/config', 'test', etemp.path)
      resource[:roles] = ['offline_access', 'uma_authorization', 'new_role']
      resource.provider.create
      property_hash = resource.provider.instance_variable_get('@property_hash')
      expect(property_hash[:ensure]).to eq(:present)
    end

    it 'sends frontend_url as a realm attribute' do
      temp = Tempfile.new('keycloak_realm')
      etemp = Tempfile.new('keycloak_events_config')
      allow(Tempfile).to receive(:new).with('keycloak_realm').and_return(temp)
      allow(Tempfile).to receive(:new).with('keycloak_events_config').and_return(etemp)
      allow(described_class).to receive(:get_realm_roles).with('test').and_return(['offline_access', 'uma_authorization'])
      allow(resource.provider).to receive(:kcadm)
      resource[:frontend_url] = 'https://keycloak.example.com'
      resource.provider.create
      data = JSON.parse(File.read(temp.path))
      expect(data['attributes']).to eq('frontendUrl' => 'https://keycloak.example.com')
    end

    it 'does not send an attributes map when frontend_url is empty' do
      temp = Tempfile.new('keycloak_realm')
      etemp = Tempfile.new('keycloak_events_config')
      allow(Tempfile).to receive(:new).with('keycloak_realm').and_return(temp)
      allow(Tempfile).to receive(:new).with('keycloak_events_config').and_return(etemp)
      allow(described_class).to receive(:get_realm_roles).with('test').and_return(['offline_access', 'uma_authorization'])
      allow(resource.provider).to receive(:kcadm)
      resource[:frontend_url] = ''
      resource.provider.create
      data = JSON.parse(File.read(temp.path))
      expect(data).not_to have_key('attributes')
    end
  end

  describe 'destroy' do
    it 'deletes a realm' do
      expect(resource.provider).to receive(:kcadm).with('delete', 'realms/test')
      resource.provider.destroy
      property_hash = resource.provider.instance_variable_get('@property_hash')
      expect(property_hash).to eq({})
    end
  end

  describe 'flush' do
    it 'updates a realm' do
      temp = Tempfile.new('keycloak_realm')
      etemp = Tempfile.new('keycloak_events_config')
      rtemp = Tempfile.new('keycloak_realm_role')
      allow(Tempfile).to receive(:new).with('keycloak_realm').and_return(temp)
      allow(Tempfile).to receive(:new).with('keycloak_events_config').and_return(etemp)
      allow(Tempfile).to receive(:new).with('keycloak_realm_role').and_return(rtemp)
      allow(resource.provider).to receive(:kcadm).with('get', 'authentication/flows', 'test', nil, ['alias']).and_return('[]')
      expect(resource.provider).to receive(:kcadm).with('update', 'realms/test', nil, temp.path)
      expect(resource.provider).to receive(:kcadm).with('delete', 'roles/offline_access', 'test')
      expect(resource.provider).to receive(:kcadm).with('create', 'roles', 'test', rtemp.path)
      expect(resource.provider).to receive(:kcadm).with('update', 'events/config', 'test', etemp.path)
      property_hash = resource.provider.instance_variable_get('@property_hash')
      property_hash[:roles] = ['offline_access', 'uma_authorization']
      resource.provider.login_with_email_allowed = :false
      resource.provider.roles = ['uma_authorization', 'new_role']
      resource.provider.flush
    end
  end

  describe 'flush frontend_url' do
    # A full realm representation, which is what `kcadm get realms/<name>`
    # returns. The read back deliberately avoids `--fields attributes`.
    let(:current_attributes) do
      {
        'id' => 'test',
        'realm' => 'test',
        'attributes' => {
          'acr.loa.map' => '{"gold":3}',
          'parRequestUriLifespan' => '120',
          'frontendUrl' => 'https://old.example.com',
        },
      }.to_json
    end

    let(:temp) { Tempfile.new('keycloak_realm') }

    before(:each) do
      etemp = Tempfile.new('keycloak_events_config')
      allow(Tempfile).to receive(:new).with('keycloak_realm').and_return(temp)
      allow(Tempfile).to receive(:new).with('keycloak_events_config').and_return(etemp)
      allow(resource.provider).to receive(:kcadm).with('get', 'authentication/flows', 'test', nil, ['alias']).and_return('[]')
      allow(resource.provider).to receive(:kcadm).with('update', 'events/config', 'test', etemp.path)
    end

    it 'merges the new value into the existing attributes' do
      allow(resource.provider).to receive(:kcadm).with('get', 'realms/test').and_return(current_attributes)
      expect(resource.provider).to receive(:kcadm).with('update', 'realms/test', nil, temp.path)
      resource.provider.frontend_url = 'https://new.example.com'
      resource.provider.flush
      attributes = JSON.parse(File.read(temp.path))['attributes']
      expect(attributes['frontendUrl']).to eq('https://new.example.com')
      expect(attributes['acr.loa.map']).to eq('{"gold":3}')
      expect(attributes['parRequestUriLifespan']).to eq('120')
    end

    it 'removes the attribute when set to an empty string but keeps the others' do
      allow(resource.provider).to receive(:kcadm).with('get', 'realms/test').and_return(current_attributes)
      expect(resource.provider).to receive(:kcadm).with('update', 'realms/test', nil, temp.path)
      resource.provider.frontend_url = ''
      resource.provider.flush
      attributes = JSON.parse(File.read(temp.path))['attributes']
      expect(attributes).not_to have_key('frontendUrl')
      expect(attributes['acr.loa.map']).to eq('{"gold":3}')
      expect(attributes['parRequestUriLifespan']).to eq('120')
    end

    it 'does not touch attributes when only other properties change' do
      resource[:frontend_url] = 'https://new.example.com'
      expect(resource.provider).not_to receive(:kcadm).with('get', 'realms/test')
      expect(resource.provider).to receive(:kcadm).with('update', 'realms/test', nil, temp.path)
      resource.provider.login_with_email_allowed = :false
      resource.provider.flush
      expect(JSON.parse(File.read(temp.path))).not_to have_key('attributes')
    end

    it 'does not emit a frontendUrl top level field' do
      allow(resource.provider).to receive(:kcadm).with('get', 'realms/test').and_return(current_attributes)
      expect(resource.provider).to receive(:kcadm).with('update', 'realms/test', nil, temp.path)
      resource.provider.frontend_url = 'https://new.example.com'
      resource.provider.flush
      expect(JSON.parse(File.read(temp.path))).not_to have_key('frontendUrl')
    end

    it 'overrides an attributes key carried in through custom_properties' do
      allow(resource.provider).to receive(:kcadm).with('get', 'realms/test').and_return(current_attributes)
      expect(resource.provider).to receive(:kcadm).with('update', 'realms/test', nil, temp.path)
      resource[:custom_properties] = { 'attributes' => 'bogus' }
      resource.provider.frontend_url = 'https://new.example.com'
      resource.provider.flush
      attributes = JSON.parse(File.read(temp.path))['attributes']
      expect(attributes['frontendUrl']).to eq('https://new.example.com')
      expect(attributes['parRequestUriLifespan']).to eq('120')
    end

    it 'reads the full realm representation instead of a nested --fields selector' do
      # kcadm renders `--fields attributes` as {} unless sub fields are given
      # as `attributes(*)`, so a nested selector reads back as a realm with no
      # attributes and would delete every one of them on update.
      expect(resource.provider).not_to receive(:kcadm).with('get', 'realms/test', nil, nil, ['attributes'])
      allow(resource.provider).to receive(:kcadm).with('get', 'realms/test').and_return(current_attributes)
      expect(resource.provider).to receive(:kcadm).with('update', 'realms/test', nil, temp.path)
      resource.provider.frontend_url = 'https://new.example.com'
      resource.provider.flush
      attributes = JSON.parse(File.read(temp.path))['attributes']
      expect(attributes['parRequestUriLifespan']).to eq('120')
      expect(attributes['acr.loa.map']).to eq('{"gold":3}')
    end

    it 'refuses to update the realm when the attributes cannot be parsed' do
      allow(resource.provider).to receive(:kcadm).with('get', 'realms/test').and_return('not json')
      expect(resource.provider).not_to receive(:kcadm).with('update', 'realms/test', nil, temp.path)
      resource.provider.frontend_url = 'https://new.example.com'
      expect { resource.provider.flush }.to raise_error(Puppet::Error, %r{refusing to update realm attributes})
    end

    it 'refuses to update the realm when the attributes are not a hash' do
      allow(resource.provider).to receive(:kcadm).with('get', 'realms/test').and_return('{"attributes":"bogus"}')
      expect(resource.provider).not_to receive(:kcadm).with('update', 'realms/test', nil, temp.path)
      resource.provider.frontend_url = 'https://new.example.com'
      expect { resource.provider.flush }.to raise_error(Puppet::Error, %r{refusing to update realm attributes})
    end
  end
end
