# frozen_string_literal: true

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'keycloak_api'))

Puppet::Type.type(:keycloak_resource_validator).provide(:kcadm, parent: Puppet::Provider::KeycloakAPI) do
  desc "A provider for the resource type `keycloak_resource_validator`,
        which validates a Keycloak resource exists."

  # Test to see if the resource exists, returns true if it does, false if it
  # does not.
  #
  # Here we simply monopolize the resource API, to execute a test to see if the
  # database is connectable. When we return a state of `false` it triggers the
  # create method where we can return an error message.
  #
  # @return [bool] did the test succeed?
  def exists?
    start_time = Time.now
    timeout = resource[:timeout]

    success = validator

    while success == false && ((Time.now - start_time) < timeout)
      # It can take several seconds for the keycloak server to start up;
      # especially on the first install.  Therefore, our first connection attempt
      # may fail.  Here we have somewhat arbitrarily chosen to retry every 2
      # seconds until the configurable timeout has expired.
      Puppet.notice("Failed to find resource #{description}; sleeping 2 seconds before retry")
      sleep 2
      success = validator
    end

    unless success
      Puppet.notice("Failed to find resource #{description} within timeout window of #{timeout} seconds; giving up.")
    end

    success
  end

  # This method is called when the exists? method returns false.
  #
  # @return [void]
  def create
    # If `#create` is called, that means that `#exists?` returned false, which
    # means that the connection could not be established... so we need to
    # cause a failure here.
    raise Puppet::Error, "Unable to find resource #{description}"
  end

  def description
    if resource[:provider_type]
      "#{resource[:provider_type]} provider #{resource[:provider_id]} in serverinfo"
    else
      "#{resource[:test_key]}=#{resource[:test_value]} at #{resource[:test_url]}"
    end
  end

  def test_realms
    return @test_realms if @test_realms

    @test_realms = if resource[:realm]
                     [resource[:realm]]
                   else
                     realms
                   end
  end

  # Returns the existing validator, if one exists otherwise creates a new object
  # from the class.
  #
  # @api private
  # Returns true if the checked resource is present.
  #
  # Two modes:
  # - test_url/test_key/test_value: poll a realm-scoped admin endpoint and
  #   look for test_key=test_value among the top-level pairs of each element.
  # - provider_type/provider_id: poll the global serverinfo endpoint and
  #   require provider_id to be present in the loaded providers of the given
  #   SPI. This is registration-agnostic, so it remains true after a required
  #   action has been registered (unregistered-required-actions cannot be used
  #   for that because it filters out registered provider IDs).
  def validator
    if resource[:provider_type]
      provider_loaded?
    else
      test_resource?
    end
  end

  def provider_loaded?
    output = kcadm('get', 'serverinfo')
    data = JSON.parse(output)
    providers = data.dig('providers', resource[:provider_type].to_s, 'providers')
    return false unless providers.is_a?(Array)

    providers.include?(resource[:provider_id].to_s)
  rescue JSON::ParserError
    Puppet.debug('Unable to parse output from kcadm get serverinfo')
    false
  end

  def test_resource?
    test_realms.each do |realm|
      output = kcadm('get', resource[:test_url], realm)
      begin
        data = JSON.parse(output)
      rescue JSON::ParserError
        Puppet.debug('Unable to parse output from kcadm get resource')
        next
      end
      data.each do |d|
        d.each_pair do |k, v|
          next unless k == resource[:test_key].to_s
          return true if v == resource[:test_value].to_s
        end
      end
    end
    false
  end
end
