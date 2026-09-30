# frozen_string_literal: true

require 'spec_helper'

describe Puppet::Type.type(:keycloak_ldap_user_provider).provider(:kcadm) do
  let(:type) do
    Puppet::Type.type(:keycloak_ldap_user_provider)
  end
  let(:resource) do
    type.new(name: 'foo',
             realm: 'test',)
  end

  describe 'self.instances' do
    it 'creates instances' do
      allow(described_class).to receive(:realms).and_return(['master', 'test'])
      allow(described_class).to receive(:kcadm).with('get', 'components', 'master').and_return(my_fixture_read('get-master.out'))
      allow(described_class).to receive(:kcadm).with('get', 'components', 'test').and_return(my_fixture_read('get-test.out'))
      expect(described_class.instances.length).to eq(1)
    end

    it 'returns the resource for a fileset' do
      allow(described_class).to receive(:realms).and_return(['master', 'test'])
      allow(described_class).to receive(:kcadm).with('get', 'components', 'master').and_return(my_fixture_read('get-master.out'))
      allow(described_class).to receive(:kcadm).with('get', 'components', 'test').and_return(my_fixture_read('get-test.out'))
      property_hash = described_class.instances[0].instance_variable_get('@property_hash')
      expect(property_hash[:name]).to eq('LDAP on test')
    end

    it 'reads enableLdapPasswordPolicy' do
      allow(described_class).to receive(:realms).and_return(['master', 'test'])
      allow(described_class).to receive(:kcadm).with('get', 'components', 'master').and_return(my_fixture_read('get-master.out'))
      allow(described_class).to receive(:kcadm).with('get', 'components', 'test').and_return(my_fixture_read('get-test.out'))
      property_hash = described_class.instances[0].instance_variable_get('@property_hash')
      expect(property_hash[:enable_ldap_password_policy]).to eq('true')
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
  describe 'self.config_key_for' do
    it 'upper-cases LDAP for the attribute keys' do
      expect(described_class.config_key_for(:username_ldap_attribute)).to eq('usernameLDAPAttribute')
      expect(described_class.config_key_for(:rdn_ldap_attribute)).to eq('rdnLDAPAttribute')
      expect(described_class.config_key_for(:uuid_ldap_attribute)).to eq('uuidLDAPAttribute')
    end

    it 'uses the camel-case Ldap spelling Keycloak expects for the password policy key' do
      expect(described_class.config_key_for(:enable_ldap_password_policy)).to eq('enableLdapPasswordPolicy')
    end

    it 'leaves keys without ldap in the name alone' do
      expect(described_class.config_key_for(:use_password_modify_extended_op)).to eq('usePasswordModifyExtendedOp')
      expect(described_class.config_key_for(:validate_password_policy)).to eq('validatePasswordPolicy')
    end

    it 'is available as an instance method' do
      expect(resource.provider.config_key_for(:enable_ldap_password_policy)).to eq('enableLdapPasswordPolicy')
    end
  end

  describe 'create' do
    it 'creates a realm' do
      temp = Tempfile.new('keycloak_component')
      allow(Tempfile).to receive(:new).with('keycloak_component').and_return(temp)
      allow(resource.provider).to receive(:get_parent_id).with('test').and_return('test')
      expect(resource.provider).to receive(:kcadm).with('create', 'components', 'test', temp.path)
      resource.provider.create
      property_hash = resource.provider.instance_variable_get('@property_hash')
      expect(property_hash[:ensure]).to eq(:present)
    end

    it 'writes the config keys Keycloak expects' do
      resource = type.new(name: 'foo', realm: 'test',
                          enable_ldap_password_policy: true,
                          use_password_modify_extended_op: true)
      temp = Tempfile.new('keycloak_component')
      allow(Tempfile).to receive(:new).with('keycloak_component').and_return(temp)
      allow(resource.provider).to receive(:get_parent_id).with('test').and_return('test')
      allow(resource.provider).to receive(:kcadm)
      resource.provider.create
      config = JSON.parse(File.read(temp.path))['config']
      expect(config['enableLdapPasswordPolicy']).to eq(['true'])
      expect(config).not_to have_key('enableLDAPPasswordPolicy')
      expect(config['usePasswordModifyExtendedOp']).to eq(['true'])
    end

    it 'omits the password policy key when it is not managed' do
      temp = Tempfile.new('keycloak_component')
      allow(Tempfile).to receive(:new).with('keycloak_component').and_return(temp)
      allow(resource.provider).to receive(:get_parent_id).with('test').and_return('test')
      allow(resource.provider).to receive(:kcadm)
      resource.provider.create
      config = JSON.parse(File.read(temp.path))['config']
      expect(config).not_to have_key('enableLdapPasswordPolicy')
    end
  end

  describe 'destroy' do
    it 'deletes a realm' do
      hash = resource.to_hash
      resource.provider.instance_variable_set(:@property_hash, hash)
      expect(resource.provider).to receive(:kcadm).with('delete', 'components/b84ed8ed-a7b1-502f-83f6-90132e68adef', 'test')
      resource.provider.destroy
      property_hash = resource.provider.instance_variable_get('@property_hash')
      expect(property_hash).to eq({})
    end
  end

  describe 'flush' do
    it 'updates a realm' do
      hash = resource.to_hash
      resource.provider.instance_variable_set(:@property_hash, hash)
      temp = Tempfile.new('keycloak_component')
      allow(Tempfile).to receive(:new).with('keycloak_component').and_return(temp)
      expect(resource.provider).to receive(:kcadm).with('update', 'components/b84ed8ed-a7b1-502f-83f6-90132e68adef', 'test', temp.path)
      resource.provider.connection_url = 'foobar'
      resource.provider.flush
    end

    it 'writes the config key Keycloak expects' do
      resource = type.new(name: 'foo', realm: 'test', enable_ldap_password_policy: true)
      resource.provider.instance_variable_set(:@property_hash, resource.to_hash)
      temp = Tempfile.new('keycloak_component')
      allow(Tempfile).to receive(:new).with('keycloak_component').and_return(temp)
      allow(resource.provider).to receive(:kcadm)
      resource.provider.enable_ldap_password_policy = :true
      resource.provider.flush
      config = JSON.parse(File.read(temp.path))['config']
      expect(config['enableLdapPasswordPolicy']).to eq(['true'])
      expect(config).not_to have_key('enableLDAPPasswordPolicy')
    end
  end
end
