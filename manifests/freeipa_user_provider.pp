#
# @summary setup IPA as an LDAP user provider for Keycloak
#
# @example Add FreeIPA as a user provider
#   keycloak::freeipa_user_provider { 'ipa.example.org':
#     ensure          => 'present',
#     realm           => 'EXAMPLE.ORG',
#     bind_dn         => 'uid=ldapproxy,cn=sysaccounts,cn=etc,dc=example,dc=org',
#     bind_credential => 'secret',
#     users_dn        => 'cn=users,cn=accounts,dc=example,dc=org',
#     priority        => 10,
#   }
#
# @param ensure
#   LDAP user provider status
# @param id
#    ID to use for user provider
# @param ipa_host
#   Hostname of the FreeIPA server (e.g. ipa.example.org)
# @param realm
#   Keycloak realm
# @param bind_dn
#   LDAP bind dn
# @param bind_credential
#   LDAP bind password
# @param users_dn
#   The DN for user search
# @param priority
#   Priority for this user provider
# @param ldaps
#   Use LDAPS protocol instead of LDAP
# @param enabled
#   Enable or disable the user provider without removing it
# @param trust_email
#   Trust email addresses from FreeIPA as verified (trustEmail)
# @param enable_ldap_password_policy
#   Enforce the LDAP server's password policy on bind by sending a password
#   policy request control; a `pwdMustChange`/`changeAfterReset` response is
#   surfaced as a forced password change (enableLdapPasswordPolicy).
#   Requires Keycloak 26.6.0 or later; left unmanaged when undef.
# @param use_password_modify_extended_op
#   Use the extended LDAP password modify operation for password updates
#   (usePasswordModifyExtendedOp)
# @param validate_password_policy
#   Validate a new password against the realm's password policy before
#   writing it to LDAP (validatePasswordPolicy)
# @param edit_mode
#   Whether the user store is read-only, writable, or unsynced (editMode).
#   `WRITABLE` requires a bind_dn with write access to the FreeIPA directory,
#   and typically use_password_modify_extended_op for password changes.
# @param full_sync_period
#   Synchronize all users this often (fullSyncPeriod)
# @param changed_sync_period
#   Synchronize changed users this often (changedSyncPeriod)
#
define keycloak::freeipa_user_provider (
  String $realm,
  String $bind_dn,
  String $bind_credential,
  String $users_dn,
  Enum['present', 'absent'] $ensure = 'present',
  Optional[String] $id = undef,
  Stdlib::Host $ipa_host = $title,
  Integer $priority = 10,
  Boolean $ldaps = false,
  Boolean $enabled = true,
  Boolean $trust_email = false,
  Optional[Boolean] $enable_ldap_password_policy = undef,
  Boolean $use_password_modify_extended_op = false,
  Boolean $validate_password_policy = false,
  Enum['READ_ONLY', 'WRITABLE', 'UNSYNCED'] $edit_mode = 'READ_ONLY',
  Optional[Integer] $full_sync_period = undef,
  Optional[Integer] $changed_sync_period = undef
) {
  if $ldaps {
    $connection_url = "ldaps://${ipa_host}:636"
  }
  else {
    $connection_url = "ldap://${ipa_host}:389"
  }

  keycloak_ldap_user_provider { "${ipa_host} on ${realm}":
    ensure                                   => $ensure,
    id                                       => $id,
    auth_type                                => 'simple',
    bind_credential                          => $bind_credential,
    bind_dn                                  => $bind_dn,
    connection_url                           => $connection_url,
    edit_mode                                => $edit_mode,
    import_enabled                           => 'true',
    priority                                 => $priority,
    rdn_ldap_attribute                       => 'uid',
    search_scope                             => '1',
    use_kerberos_for_password_authentication => 'false',
    use_truststore_spi                       => 'always',
    user_object_classes                      => ['inetOrgPerson', ' organizationalPerson'],
    username_ldap_attribute                  => 'uid',
    users_dn                                 => $users_dn,
    uuid_ldap_attribute                      => 'ipaUniqueID',
    vendor                                   => 'rhds',
    enabled                                  => $enabled,
    trust_email                              => $trust_email,
    enable_ldap_password_policy              => $enable_ldap_password_policy,
    use_password_modify_extended_op          => $use_password_modify_extended_op,
    validate_password_policy                 => $validate_password_policy,
    full_sync_period                         => $full_sync_period,
    changed_sync_period                      => $changed_sync_period,
  }
}
