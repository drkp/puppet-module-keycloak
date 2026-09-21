# frozen_string_literal: true

require 'spec_helper'

describe Puppet::Type.type(:keycloak_resource_validator).provider(:kcadm) do
  let(:type) do
    Puppet::Type.type(:keycloak_resource_validator)
  end
  let(:resource) do
    type.new(name: 'configure-mfa loaded',
             provider_type: 'required-action',
             provider_id: 'configure-mfa')
  end

  describe 'provider_loaded?' do
    it 'finds a provider in the dict-shaped serverinfo (Keycloak >= 26)' do
      serverinfo = {
        'providers' => {
          'required-action' => {
            'internal' => true,
            'providers' => {
              'configure-mfa' => { 'order' => 0 },
              'CONFIGURE_TOTP' => { 'order' => 1 }
            }
          }
        }
      }
      expect(resource.provider).to receive(:kcadm).with('get', 'serverinfo')
        .and_return(serverinfo.to_json)
      expect(resource.provider.provider_loaded?).to be(true)
    end

    it 'returns false when the provider is absent from a dict-shaped serverinfo' do
      serverinfo = {
        'providers' => {
          'required-action' => {
            'internal' => true,
            'providers' => {
              'CONFIGURE_TOTP' => { 'order' => 0 }
            }
          }
        }
      }
      expect(resource.provider).to receive(:kcadm).with('get', 'serverinfo')
        .and_return(serverinfo.to_json)
      expect(resource.provider.provider_loaded?).to be(false)
    end

    it 'finds a provider in an array-shaped serverinfo' do
      serverinfo = {
        'providers' => {
          'required-action' => {
            'internal' => true,
            'providers' => ['configure-mfa', 'CONFIGURE_TOTP']
          }
        }
      }
      expect(resource.provider).to receive(:kcadm).with('get', 'serverinfo')
        .and_return(serverinfo.to_json)
      expect(resource.provider.provider_loaded?).to be(true)
    end

    it 'returns false when the provider group is missing' do
      expect(resource.provider).to receive(:kcadm).with('get', 'serverinfo')
        .and_return({ 'providers' => {} }.to_json)
      expect(resource.provider.provider_loaded?).to be(false)
    end

    it 'returns false on unparseable output' do
      expect(resource.provider).to receive(:kcadm).with('get', 'serverinfo')
        .and_return('not json')
      expect(resource.provider.provider_loaded?).to be(false)
    end
  end
end
