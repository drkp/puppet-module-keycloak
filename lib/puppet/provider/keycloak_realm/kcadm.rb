# frozen_string_literal: true

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'keycloak_api'))

Puppet::Type.type(:keycloak_realm).provide(:kcadm, parent: Puppet::Provider::KeycloakAPI) do
  desc ''

  mk_resource_methods

  def flow_properties
    [
      :browser_flow,
      :registration_flow,
      :direct_grant_flow,
      :reset_credentials_flow,
      :client_authentication_flow,
      :docker_authentication_flow,
    ]
  end

  def self.smtp_server_properties
    [
      :smtp_server_user,
      :smtp_server_password,
      :smtp_server_host,
      :smtp_server_port,
      :smtp_server_auth,
      :smtp_server_starttls,
      :smtp_server_ssl,
      :smtp_server_envelope_from,
      :smtp_server_from,
      :smtp_server_from_display_name,
      :smtp_server_reply_to,
      :smtp_server_reply_to_display_name,
    ]
  end

  def self.browser_security_headers
    [
      :content_security_policy,
    ]
  end

  # Properties stored in the realm `attributes` map rather than as top level
  # fields of the realm representation.
  def self.attributes_properties
    [
      :frontend_url,
    ]
  end

  def attributes_properties
    self.class.attributes_properties
  end

  # Read the current `attributes` map of a realm.
  #
  # Keycloak treats the `attributes` map of a realm update as authoritative:
  # any attribute present on the realm but absent from the submitted map is
  # removed. Updates that touch an attribute backed property therefore have to
  # resend every attribute that should be kept. An unreadable response must
  # abort the update rather than degrade to an empty map, which would delete
  # every attribute of the realm.
  #
  # The full representation is fetched deliberately. `kcadm --fields attributes`
  # renders a nested object as `{}` unless sub fields are given as
  # `attributes(*)`, which would silently look like a realm with no attributes.
  def realm_attributes(realm)
    output = kcadm('get', "realms/#{realm}")
    Puppet.debug("Realm #{realm} attributes: #{output}")
    begin
      data = JSON.parse(output)
    rescue JSON::ParserError => e
      raise Puppet::Error, "Unable to parse attributes of realm #{realm}, refusing to update realm attributes\nError message: #{e.message}"
    end
    unless data.is_a?(Hash) && (data['attributes'].nil? || data['attributes'].is_a?(Hash))
      raise Puppet::Error, "Unexpected attributes for realm #{realm}, refusing to update realm attributes"
    end

    data['attributes'] || {}
  end

  # Apply an attribute backed property to a realm attribute map, removing the
  # entry when the desired value is empty.
  def merge_realm_attribute(attributes, property, value)
    key = camelize(property)
    if value.to_s.empty?
      attributes.delete(key)
    else
      attributes[key] = value.to_s
    end
    attributes
  end

  def self.get_client_scopes(realm, type)
    output = kcadm('get', "realms/#{realm}/default-#{type}-client-scopes")
    Puppet.debug("Realms #{realm} #{type} client scopes: #{output}")
    data = JSON.parse(output)
    scopes = {}
    data.each do |d|
      scopes[d['name']] = d['id']
    end
    Puppet.debug("Returned scopes: #{scopes}")
    scopes
  end

  def get_client_scopes(*args)
    self.class.get_client_scopes(*args)
  end

  def self.get_realm_roles(realm)
    output = kcadm('get', 'roles', realm)
    Puppet.debug("Realms #{realm} roles: #{output}")
    data = JSON.parse(output)
    roles = []
    data.each do |d|
      # filter out 'create-realm' role from master realm as it should not be removed
      if !d['composite'] && d['name'] != 'create-realm'
        roles.push(d['name'])
      end
    end
    Puppet.debug("Returned roles: #{roles}")
    roles
  end

  def get_realm_roles(*args)
    self.class.get_realm_roles(*args)
  end

  def self.get_events_config(realm)
    output = kcadm('get', 'events/config', realm)
    Puppet.debug("#{realm} events/config: #{output}")
    begin
      data = JSON.parse(output)
    rescue JSON::ParserError
      Puppet.debug('Unable to parse output from kcadm get events/config')
      data = {}
    end
    data.delete('enabledEventTypes')
    data
  end

  def available_flows(realm)
    output = kcadm('get', 'authentication/flows', realm, nil, ['alias'])
    Puppet.debug("#{realm} authentication/flows: #{output}")
    begin
      data = JSON.parse(output)
    rescue JSON::ParserError
      Puppet.debug('Unable to parse output from kcadm get authentication/flows')
      return []
    end
    data.map { |f| f['alias'] }
  end

  def self.instances
    realms = []
    begin
      output = kcadm('get', 'realms')
      Puppet.debug("Realms: #{output}")
      data = JSON.parse(output)
    rescue Puppet::ExecutionFailure => e
      Puppet.notice("Failed to get realms: #{e}")
      data = []
    rescue JSON::ParserError
      Puppet.debug('Unable to parse output from kcadm get realms')
      data = []
    end
    data.each do |d|
      realm = {}
      realm[:ensure] = :present
      realm[:id] = d['id']
      realm[:name] = d['realm']
      events_config = get_events_config(d['realm'])
      type_properties.each do |property|
        next if [:default_client_scopes, :optional_client_scopes, :roles].include?(property)

        value = if property.to_s =~ %r{events}
                  events_config[camelize(property)]
                elsif browser_security_headers.include?(property)
                  d['browserSecurityHeaders'][camelize(property)]
                elsif smtp_server_properties.include?(property)
                  d['smtpServer'][camelize(property.to_s.gsub(%r{smtp_server_}, ''))]
                elsif attributes_properties.include?(property)
                  # An absent attribute is reported as an empty string so that
                  # `frontend_url => ''` is a stable way to express "no override".
                  (d['attributes'] || {})[camelize(property)] || ''
                else
                  d[camelize(property)]
                end
        if !!value == value # rubocop:disable Style/DoubleNegation
          value = value.to_s.to_sym
        end
        realm[property.to_sym] = value
      end
      default_scopes = get_client_scopes(realm[:name], 'default')
      realm[:default_client_scopes] = default_scopes.keys.map { |k| k.to_s }
      optional_scopes = get_client_scopes(realm[:name], 'optional')
      realm[:optional_client_scopes] = optional_scopes.keys.map { |k| k.to_s }
      realm[:roles] = get_realm_roles(realm[:name])
      realm[:custom_properties] = {}
      d.each_pair do |k, v|
        # The attributes map is surfaced through dedicated properties such as
        # frontend_url. It cannot round trip through custom_properties, which
        # rejects Hash values.
        next if k == 'attributes'
        next if type_properties.include?(k.to_sym)

        realm[:custom_properties][k] = v
      end
      realms << new(realm)
    end
    realms
  end

  def self.prefetch(resources)
    realms = instances
    resources.each_key do |name|
      provider = realms.find { |realm| realm.name == name }
      if provider
        resources[name].provider = provider
      end
    end
  end

  def create
    data = {}
    events_config = {}
    data[:id] = resource[:id]
    data[:realm] = resource[:name]
    (resource[:custom_properties] || {}).each_pair do |k, v|
      data[k] = v unless type_properties.include?(k.to_sym)
    end
    type_properties.each do |property|
      next if flow_properties.include?(property)
      next if [:default_client_scopes, :optional_client_scopes, :roles].include?(property)

      if self.class.browser_security_headers.include?(property) && !data.key?('browserSecurityHeaders')
        data['browserSecurityHeaders'] = {}
      end
      if self.class.smtp_server_properties.include?(property) && !data.key?('smtpServer')
        data['smtpServer'] = {}
      end
      if property.to_s =~ %r{events}
        events_config[camelize(property)] = convert_property_value(resource[property.to_sym])
      elsif resource[property.to_sym]
        if self.class.browser_security_headers.include?(property)
          data['browserSecurityHeaders'][camelize(property)] = convert_property_value(resource[property.to_sym])
        elsif self.class.smtp_server_properties.include?(property) && resource[property]
          data['smtpServer'][camelize(property.to_s.gsub(%r{smtp_server_}, ''))] = resource[property]
        elsif attributes_properties.include?(property)
          # A new realm has no attributes to preserve, so only the managed ones
          # are sent. An empty value means "no override" and is simply omitted.
          unless resource[property].to_s.empty?
            data['attributes'] ||= {}
            data['attributes'][camelize(property)] = resource[property]
          end
        else
          data[camelize(property)] = convert_property_value(resource[property.to_sym])
        end
      end
    end

    t = Tempfile.new('keycloak_realm')
    t.write(JSON.pretty_generate(data))
    t.close
    Puppet.debug(IO.read(t.path))
    begin
      [
        :login_theme,
        :account_theme,
        :admin_theme,
        :email_theme,
      ].each do |theme|
        if resource[theme]
          check_theme_exists(resource[theme], "Keycloak_realm[#{resource[:name]}]")
        end
      end
      kcadm('create', 'realms', nil, t.path)
    rescue Puppet::ExecutionFailure => e
      raise Puppet::Error, "kcadm create realm failed\nError message: #{e.message}"
    end
    scope_id = nil
    if resource[:default_client_scopes]
      default_scopes = default_scopes ||= get_client_scopes(resource[:name], 'default')
      remove_default_scopes = default_scopes.keys - resource[:default_client_scopes]
      begin
        remove_default_scopes.each do |s|
          scope_id = default_scopes[s]
          kcadm('delete', "realms/#{resource[:name]}/default-default-client-scopes/#{scope_id}")
        end
      rescue Puppet::ExecutionFailure => e
        raise Puppet::Error, "kcadm delete realms/#{resource[:name]}/default-default-client-scopes/#{scope_id}: #{e.message}"
      end
    end
    if resource[:optional_client_scopes]
      optional_scopes = optional_scopes ||= get_client_scopes(resource[:name], 'optional')
      remove_optional_scopes = optional_scopes.keys - resource[:optional_client_scopes]
      begin
        remove_optional_scopes.each do |s|
          scope_id = optional_scopes[s]
          kcadm('delete', "realms/#{resource[:name]}/default-optional-client-scopes/#{scope_id}")
        end
      rescue Puppet::ExecutionFailure => e
        raise Puppet::Error, "kcadm delete realms/#{resource[:name]}/default-optional-client-scopes/#{scope_id}: #{e.message}"
      end
    end
    if resource[:default_client_scopes]
      default_scopes = default_scopes ||= get_client_scopes(resource[:name], 'default')
      add_default_scopes = resource[:default_client_scopes] - default_scopes.keys
      begin
        add_default_scopes.each do |s|
          scope_id = default_scopes[s]
          kcadm('update', "realms/#{resource[:name]}/default-default-client-scopes/#{scope_id}")
        end
      rescue Puppet::ExecutionFailure => e
        raise Puppet::Error, "kcadm update realms/#{resource[:name]}/default-default-client-scopes/#{scope_id}: #{e.message}"
      end
    end
    if resource[:optional_client_scopes]
      optional_scopes = optional_scopes ||= get_client_scopes(resource[:name], 'optional')
      add_optional_scopes = resource[:optional_client_scopes] - optional_scopes.keys
      begin
        add_optional_scopes.each do |s|
          scope_id = optional_scopes[s]
          kcadm('update', "realms/#{resource[:name]}/default-optional-client-scopes/#{scope_id}")
        end
      rescue Puppet::ExecutionFailure => e
        raise Puppet::Error, "kcadm update realms/#{resource[:name]}/default-optional-client-scopes/#{scope_id}: #{e.message}"
      end
    end
    role = nil
    if resource[:roles] && resource[:manage_roles].to_s == 'true'
      roles = get_realm_roles(resource[:name])
      remove_roles = roles - resource[:roles]
      begin
        remove_roles.each do |s|
          role = s
          kcadm('delete', "roles/#{role}", resource[:name])
        end
      rescue Puppet::ExecutionFailure => e
        raise Puppet::Error, "kcadm delete realms/#{resource[:name]}/roles/#{role}: #{e.message}"
      end
      add_roles = resource[:roles] - roles
      begin
        add_roles.each do |s|
          role = s
          role_data = { 'description' => "${role_#{role}}", 'name' => role }
          role_data_t = Tempfile.new('keycloak_realm_role')
          role_data_t.write(JSON.pretty_generate(role_data))
          role_data_t.close
          Puppet.debug(IO.read(role_data_t.path))
          kcadm('create', 'roles', resource[:name], role_data_t.path)
        end
      rescue Puppet::ExecutionFailure => e
        raise Puppet::Error, "kcadm create realms/#{resource[:name]}/roles/#{role}: #{e.message}"
      end
    end
    unless events_config.empty?
      events_config_t = Tempfile.new('keycloak_events_config')
      events_config_t.write(JSON.pretty_generate(events_config))
      events_config_t.close
      Puppet.debug(IO.read(events_config_t.path))
      begin
        kcadm('update', 'events/config', resource[:name], events_config_t.path)
      rescue Puppet::ExecutionFailure => e
        raise Puppet::Error, "kcadm update events config failed\nError message: #{e.message}"
      end
    end
    @property_hash[:ensure] = :present
  end

  def destroy
    begin
      kcadm('delete', "realms/#{resource[:name]}")
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
      data = {}
      events_config = {}
      realm_attrs = nil
      (@property_flush[:custom_properties] || resource[:custom_properties] || {}).each_pair do |k, v|
        data[k] = v unless type_properties.include?(k.to_sym)
      end
      type_properties.each do |property|
        next if [:default_client_scopes, :optional_client_scopes, :roles].include?(property)

        if flow_properties.include?(property) && !available_flows(resource[:name]).include?(resource[property.to_sym])
          Puppet.warning("Keycloak_realm[#{resource[:name]}]: #{property} '#{resource[property.to_sym]}' does not exist, skipping")
          next
        end
        if attributes_properties.include?(property)
          # Only rewrite the attribute map when this property actually changed.
          # Keycloak removes every realm attribute that is missing from a
          # submitted map, so the current attributes are read back and merged
          # into rather than sending just the managed keys.
          if @property_flush.key?(property.to_sym)
            realm_attrs ||= realm_attributes(resource[:name])
            merge_realm_attribute(realm_attrs, property, @property_flush[property.to_sym])
          end
          next
        end
        if self.class.browser_security_headers.include?(property) && !data.key?('browserSecurityHeaders')
          data['browserSecurityHeaders'] = {}
        end
        if self.class.smtp_server_properties.include?(property) && !data.key?('smtpServer')
          data['smtpServer'] = {}
        end
        if @property_flush[property.to_sym] || resource[property.to_sym]
          if self.class.browser_security_headers.include?(property)
            data['browserSecurityHeaders'][camelize(property)] = convert_property_value(resource[property.to_sym])
          elsif self.class.smtp_server_properties.include?(property) && resource[property]
            data['smtpServer'][camelize(property.to_s.gsub(%r{smtp_server_}, ''))] = resource[property]
          else
            data[camelize(property)] = convert_property_value(resource[property.to_sym])
          end
        end
        if property.to_s =~ %r{events}
          events_config[camelize(property)] = convert_property_value(resource[property.to_sym])
        end
      end

      # Assigned last so that the authoritative map read back from Keycloak
      # always wins over anything carried in via custom_properties.
      data['attributes'] = realm_attrs if realm_attrs

      unless data.empty?
        t = Tempfile.new('keycloak_realm')
        t.write(JSON.pretty_generate(data))
        t.close
        Puppet.debug(IO.read(t.path))
        begin
          [
            :login_theme,
            :account_theme,
            :admin_theme,
            :email_theme,
          ].each do |theme|
            if @property_flush[theme]
              check_theme_exists(@property_flush[theme], "Keycloak_realm[#{resource[:name]}]")
            end
          end
          kcadm('update', "realms/#{resource[:name]}", nil, t.path)
        rescue Puppet::ExecutionFailure => e
          raise Puppet::Error, "kcadm update realm failed\nError message: #{e.message}"
        end
      end
      scope_id = nil
      if @property_flush[:default_client_scopes]
        default_scopes = default_scopes ||= get_client_scopes(resource[:name], 'default')
        remove_default_scopes = default_scopes.keys - @property_flush[:default_client_scopes]
        begin
          remove_default_scopes.each do |s|
            scope_id = default_scopes[s]
            kcadm('delete', "realms/#{resource[:name]}/default-default-client-scopes/#{scope_id}")
          end
        rescue Puppet::ExecutionFailure => e
          raise Puppet::Error, "kcadm delete realms/#{resource[:name]}/default-default-client-scopes/#{scope_id}: #{e.message}"
        end
      end
      if @property_flush[:optional_client_scopes]
        optional_scopes = optional_scopes ||= get_client_scopes(resource[:name], 'optional')
        remove_optional_scopes = optional_scopes.keys - @property_flush[:optional_client_scopes]
        begin
          remove_optional_scopes.each do |s|
            scope_id = optional_scopes[s]
            kcadm('delete', "realms/#{resource[:name]}/default-optional-client-scopes/#{scope_id}")
          end
        rescue Puppet::ExecutionFailure => e
          raise Puppet::Error, "kcadm delete realms/#{resource[:name]}/default-optional-client-scopes/#{scope_id}: #{e.message}"
        end
      end
      if @property_flush[:default_client_scopes]
        default_scopes = default_scopes ||= get_client_scopes(resource[:name], 'default')
        add_default_scopes = @property_flush[:default_client_scopes] - default_scopes.keys
        begin
          add_default_scopes.each do |s|
            scope_id = default_scopes[s]
            kcadm('update', "realms/#{resource[:name]}/default-default-client-scopes/#{scope_id}")
          end
        rescue Puppet::ExecutionFailure => e
          raise Puppet::Error, "kcadm update realms/#{resource[:name]}/default-default-client-scopes/#{scope_id}: #{e.message}"
        end
      end
      if @property_flush[:optional_client_scopes]
        optional_scopes = optional_scopes ||= get_client_scopes(resource[:name], 'optional')
        add_optional_scopes = @property_flush[:optional_client_scopes] - optional_scopes.keys
        begin
          add_optional_scopes.each do |s|
            scope_id = optional_scopes[s]
            kcadm('update', "realms/#{resource[:name]}/default-optional-client-scopes/#{scope_id}")
          end
        rescue Puppet::ExecutionFailure => e
          raise Puppet::Error, "kcadm update realms/#{resource[:name]}/default-optional-client-scopes/#{scope_id}: #{e.message}"
        end
      end
      role = nil
      if @property_flush[:roles] && resource[:manage_roles].to_s == 'true'
        remove_roles = @property_hash[:roles] - @property_flush[:roles]
        begin
          remove_roles.each do |s|
            role = s
            kcadm('delete', "roles/#{role}", resource[:name])
          end
        rescue Puppet::ExecutionFailure => e
          raise Puppet::Error, "kcadm delete realms/#{resource[:name]}/roles/#{role}: #{e.message}"
        end
        add_roles = @property_flush[:roles] - @property_hash[:roles]
        begin
          add_roles.each do |s|
            role = s
            role_data = { 'description' => "${role_#{role}}", 'name' => role }
            role_data_t = Tempfile.new('keycloak_realm_role')
            role_data_t.write(JSON.pretty_generate(role_data))
            role_data_t.close
            Puppet.debug(IO.read(role_data_t.path))
            kcadm('create', 'roles', resource[:name], role_data_t.path)
          end
        rescue Puppet::ExecutionFailure => e
          raise Puppet::Error, "kcadm create realms/#{resource[:name]}/roles/#{role}: #{e.message}"
        end
      end
      unless events_config.empty?
        events_config_t = Tempfile.new('keycloak_events_config')
        events_config_t.write(JSON.pretty_generate(events_config))
        events_config_t.close
        Puppet.debug(IO.read(events_config_t.path))
        begin
          kcadm('update', 'events/config', resource[:name], events_config_t.path)
        rescue Puppet::ExecutionFailure => e
          raise Puppet::Error, "kcadm update events config failed\nError message: #{e.message}"
        end
      end
    end
    # Collect the resources again once they've been changed (that way `puppet
    # resource` will show the correct values after changes have been made).
    @property_hash = resource.to_hash
  end
end
