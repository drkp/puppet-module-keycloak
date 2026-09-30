# frozen_string_literal: true

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'keycloak_api'))

Puppet::Type.type(:keycloak_ldap_user_provider).provide(:kcadm, parent: Puppet::Provider::KeycloakAPI) do
  desc ''

  mk_resource_methods

  # Keycloak spells most LDAP component config keys as the camelized property
  # name with `ldap` upper-cased, e.g. `usernameLDAPAttribute`. A few keys are
  # spelled with camel-case `Ldap` instead and have to be mapped explicitly.
  def self.config_key_for(property)
    case property.to_sym
    when :enable_ldap_password_policy
      # LDAPConstants.ENABLE_LDAP_PASSWORD_POLICY
      'enableLdapPasswordPolicy'
    else
      camelize(property).gsub(%r{ldap}i, 'LDAP')
    end
  end

  def config_key_for(property)
    self.class.config_key_for(property)
  end

  def self.instances
    components = []
    realms.each do |realm|
      output = kcadm('get', 'components', realm)
      Puppet.debug("#{realm} components: #{output}")
      begin
        data = JSON.parse(output)
      rescue JSON::ParserError
        Puppet.debug('Unable to parse output from kcadm get components')
        data = []
      end

      data.each do |d|
        next unless d['providerType'] == 'org.keycloak.storage.UserStorageProvider'
        next unless d['providerId'] == 'ldap'

        component = {}
        component[:ensure] = :present
        component[:id] = d['id']
        component[:resource_name] = d['name']
        component[:realm] = d['parentId']
        component[:name] = "#{component[:resource_name]} on #{component[:realm]}"
        type_properties.each do |property|
          config_key = config_key_for(property)
          next unless d['config'].key?(config_key)

          value = d['config'][config_key][0]
          if property == :user_object_classes
            value = value.split(',')
          end
          if !!value == value # rubocop:disable Style/DoubleNegation
            value = value.to_s.to_sym
          end
          component[property.to_sym] = value
        end
        components << new(component)
      end
    end
    components
  end

  def self.prefetch(resources)
    components = instances
    resources.each_key do |name|
      provider = components.find { |c| c.id == resources[name][:id] }
      if provider
        resources[name].provider = provider
      end
    end
  end

  def get_parent_id(realm)
    output = kcadm('get', "realms/#{realm}", nil, nil, ['id'])
    Puppet.debug("#{realm} realms: #{output}")
    begin
      data = JSON.parse(output)
    rescue JSON::ParserError
      Puppet.debug("Unable to parse output from kcadm get realms/#{realm}")
      data = {}
    end
    data['id']
  end

  def create
    raise(Puppet::Error, "Realm is mandatory for #{resource.type} #{resource.name}") if resource[:realm].nil?

    data = {}
    data[:id] = resource[:id] || name_uuid(resource[:name])
    data[:name] = resource[:resource_name]
    data[:parentId] = get_parent_id(resource[:realm]) || resource[:realm]
    data[:providerId] = 'ldap'
    data[:providerType] = 'org.keycloak.storage.UserStorageProvider'
    data[:config] = {}
    type_properties.each do |property|
      next unless resource[property.to_sym]

      value = if property == :user_object_classes
                resource[property.to_sym].join(',')
              else
                resource[property.to_sym]
              end
      next if value == :absent

      data[:config][config_key_for(property)] = [value]
    end

    t = Tempfile.new('keycloak_component')
    t.write(JSON.pretty_generate(data))
    t.close
    Puppet.debug(IO.read(t.path))
    begin
      kcadm('create', 'components', resource[:realm], t.path)
    rescue Puppet::ExecutionFailure => e
      raise Puppet::Error, "kcadm create component failed\nError message: #{e.message}"
    end
    @property_hash[:ensure] = :present
  end

  def destroy
    raise(Puppet::Error, "Realm is mandatory for #{resource.type} #{resource.name}") if resource[:realm].nil?

    begin
      kcadm('delete', "components/#{id}", resource[:realm])
    rescue Puppet::ExecutionFailure => e
      raise Puppet::Error, "kcadm delete realm failed\nError message: #{e.message}"
    end

    @property_hash.clear
  end

  def exists?
    @property_hash[:ensure] == :present
  end

  def initialize(value = {})
    super(value)
    @property_flush = {}
  end

  type_properties.each do |prop|
    define_method "#{prop}=".to_sym do |value|
      @property_flush[prop] = value
    end
  end

  def flush
    unless @property_flush.empty?
      raise(Puppet::Error, "Realm is mandatory for #{resource.type} #{resource.name}") if resource[:realm].nil?

      data = {}
      data[:providerId] = 'ldap'
      data[:providerType] = 'org.keycloak.storage.UserStorageProvider'
      data[:config] = {}
      type_properties.each do |property|
        next unless @property_flush[property.to_sym]

        value = if property == :user_object_classes
                  resource[property.to_sym].join(',')
                else
                  resource[property.to_sym]
                end
        if value == :absent
          value = ''
        end
        data[:config][config_key_for(property)] = [value]
      end

      t = Tempfile.new('keycloak_component')
      t.write(JSON.pretty_generate(data))
      t.close
      Puppet.debug(IO.read(t.path))
      begin
        kcadm('update', "components/#{id}", resource[:realm], t.path)
      rescue Puppet::ExecutionFailure => e
        raise Puppet::Error, "kcadm update component failed\nError message: #{e.message}"
      end
    end
    # Collect the resources again once they've been changed (that way `puppet
    # resource` will show the correct values after changes have been made).
    @property_hash = resource.to_hash
  end
end
