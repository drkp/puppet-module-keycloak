# frozen_string_literal: true

require_relative '../../puppet_x/keycloak/integer_property'

Puppet::Type.newtype(:keycloak_resource_validator) do
  desc <<-DESC
Verify that a specific Keycloak resource is available
  DESC

  ensurable

  newparam(:name, namevar: true) do
    desc 'An arbitrary name used as the identity of the resource.'
  end

  newparam(:test_url) do
    desc 'URL to use for testing if the Keycloak database is up'
  end

  newparam(:test_key) do
    desc 'Key to lookup'
  end

  newparam(:test_value) do
    desc 'Value to lookup'
  end

  newparam(:provider_type) do
    desc 'SPI name (e.g. required-action) whose loaded providers are checked via the serverinfo endpoint. Set together with provider_id for a loaded-SPI-provider readiness check; mutually exclusive with test_url/test_key/test_value.'
  end

  newparam(:provider_id) do
    desc 'Provider ID that must be present in the loaded providers of provider_type'
  end

  newparam(:realm) do
    desc 'Realm to query'
  end

  newparam(:timeout) do
    desc 'The max number of seconds that the validator should wait before giving up and deciding that keycloak is not running; defaults to 15 seconds.'
    defaultto 30

    validate do |value|
      # This will raise an error if the string is not convertible to an integer
      Integer(value)
    end

    munge do |value|
      Integer(value)
    end
  end

  newparam(:dependent_resources) do
    desc 'Resources that should autorequire this validator, eg: Keycloak_flow_execution[foobar]'
  end

  validate do
    if self[:provider_type] || self[:provider_id]
      raise "Keycloak_resource_validator[#{self[:name]}] provider_type and provider_id must be set together" if self[:provider_type].nil? || self[:provider_id].nil?
      if self[:test_url] || self[:test_key] || self[:test_value]
        raise "Keycloak_resource_validator[#{self[:name]}] test_url/test_key/test_value are mutually exclusive with provider_type/provider_id"
      end
    else
      raise "Keycloak_resource_validator[#{self[:name]}] test_url is required" if self[:test_url].nil?
      raise "Keycloak_resource_validator[#{self[:name]}] test_key is required" if self[:test_key].nil?
      raise "Keycloak_resource_validator[#{self[:name]}] test_value is required" if self[:test_value].nil?
    end
  end
end
