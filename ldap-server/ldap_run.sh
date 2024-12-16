#!/bin/bash
set -x
# Reduce maximum number of open file descriptors to 1024
ulimit -n 1024

# Exit immediately if a command exits with a non-zero status
set -e

# Check if required environment variables are set
required_vars=(LDAP_ROOT_PASSWD base_primary_dc base_secondary_dc base_subdomain_dc CN OU1 OU2 OU3 OU4 OU5 OU6 OU7 primary_server_uri secondary_server_uri)

for var in "${required_vars[@]}"; do
  if [ -z "${!var}" ]; then
    echo "Error: Environment variable $var is not set." >&2
    exit 1
  fi
done

# Generate configuration files from templates
envsubst < /ldap_config/basedomain.ldif.template > /ldap_config/basedomain.ldif
envsubst < /ldap_config/chdomain.ldif.template > /ldap_config/chdomain.ldif
envsubst < /ldap_config/ldap.conf.template > /etc/openldap/ldap.conf

# Set default OpenLDAP debug level if not provided
OPENLDAP_DEBUG_LEVEL=${OPENLDAP_DEBUG_LEVEL:-256}


# Run initial setup if not already configured
if [ ! -f /etc/openldap/CONFIGURED ]; then
  # Check if running as root
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "Error: Script must be run as root." >&2
    exit 1
  fi

  # Start slapd in the background
  slapd -h "ldap:/// ldaps:/// ldapi:///" -d $OPENLDAP_DEBUG_LEVEL &
  slapd_pid=$!

  # Wait for slapd to start
  for i in {1..30}; do
    if ldapsearch -Y EXTERNAL -H ldapi:/// -s base -b "cn=config" &>/dev/null; then
      break
    fi
    sleep 1
  done

  if ! ps -p $slapd_pid &>/dev/null; then
    echo "Error: slapd failed to start." >&2
    exit 1
  fi

  # Generate root password hash
  OPENLDAP_ROOT_PASSWORD_HASH=$(slappasswd -s "${LDAP_ROOT_PASSWD}")
  echo "${OPENLDAP_ROOT_PASSWORD_HASH}" > /ldap_root_hash_pw

  # Set root password
  sed "s|OPENLDAP_ROOT_PASSWORD|${OPENLDAP_ROOT_PASSWORD_HASH}|g" /ldap_config/chrootpw.ldif | \
    ldapadd -Y EXTERNAL -H ldapi:/// || { echo "Error: Failed to set root password."; exit 1; }

  # Add basic schemas
  for schema in cosine inetorgperson nis; do
    ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/${schema}.ldif || \
      { echo "Error: Failed to add schema ${schema}."; exit 1; }
  done

  # Configure the domain
  sed "s|OPENLDAP_ROOT_PASSWORD|${OPENLDAP_ROOT_PASSWORD_HASH}|g" /ldap_config/chdomain.ldif | \
    ldapmodify -Y EXTERNAL -H ldapi:/// || { echo "Error: Failed to configure domain."; exit 1; }

  # Add basedomain entries
  ldapadd -x -D "cn=${CN},dc=${base_secondary_dc},dc=${base_primary_dc}" \
    -w "${LDAP_ROOT_PASSWD}" -f /ldap_config/basedomain.ldif || \
    { echo "Error: Failed to add basedomain entries."; exit 1; }

  # Stop slapd
  kill -2 $slapd_pid
  wait $slapd_pid || { echo "Error: slapd did not stop correctly."; exit 1; }

  # Test configuration files
  slaptest || echo "Warning: Configuration test failed. Check the output for details."

  # Cleanup
  rm -rf /ldap_config/*.template
  touch /etc/openldap/CONFIGURED
fi

# Start slapd in the foreground
exec slapd -h "ldap:/// ldaps:/// ldapi:///" -d $OPENLDAP_DEBUG_LEVEL
