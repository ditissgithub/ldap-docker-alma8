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


# Only run if no config has happened fully before
if [ ! -f /etc/openldap/CONFIGURED ]; then

    user=`id | grep -Po "(?<=uid=)\d+"`
    if (( user == 0 ))
    then
        
        # start the daemon in another process and make config changes
        slapd -h "ldap:/// ldaps:/// ldapi:///" -d $OPENLDAP_DEBUG_LEVEL &
        for ((i=30; i>0; i--))
        do
            ping_result=`ldapsearch 2>&1 | grep "Can.t contact LDAP server"`
            if [ -z "$ping_result" ]
            then
                break
            fi
            sleep 1
        done
        if [ $i -eq 0 ]
        then
            echo "slapd did not start correctly"
            exit 1
        fi

        # Generate hash of password
        OPENLDAP_ROOT_PASSWORD_HASH=$(slappasswd -s "${LDAP_ROOT_PASSWD}")
        echo $OPENLDAP_ROOT_PASSWORD_HASH >> /ldap_root_hash_pw

        #Set OpenLDAP admin password.
        sed -i -e "s OPENLDAP_ROOT_PASSWORD ${OPENLDAP_ROOT_PASSWORD_HASH} g" /ldap_config/chrootpw.ldif |
        ldapadd -Y EXTERNAL -H ldapi:/// -f /ldap_config/chrootpw.ldif > /dev/null 2>&1
        
        # Import basic Schemas.
        ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif -d $OPENLDAP_DEBUG_LEVEL > /dev/null 2>&1
        ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif -d $OPENLDAP_DEBUG_LEVEL > /dev/null 2>&1
        ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif -d $OPENLDAP_DEBUG_LEVEL > /dev/null 2>&1

        # Update configuration with root password and Set your domain name on LDAP DB
        sed -i -e "s OPENLDAP_ROOT_PASSWORD ${OPENLDAP_ROOT_PASSWORD_HASH} g" /ldap_config/chdomain.ldif |
            ldapmodify -Y EXTERNAL -H ldapi:/// -d $OPENLDAP_DEBUG_LEVEL > /dev/null 2>&1
      
      
        ldapadd -x -D cn=${cn},dc=${base_secondary_dc},dc=${base_primary_dc} -w ${LDAP_ROOT_PASSWD} -f /ldap_config/basedomain.ldif > /dev/null 2>&1


  

        # stop the daemon
        pid=$(ps -A | grep slapd | awk '{print $1}')
        kill -2 $pid || echo $?

        # ensure the daemon stopped
        for ((i=30; i>0; i--))
        do
            exists=$(ps -A | grep $pid)
            if [ -z "${exists}" ]
            then
                break
            fi
            sleep 1
        done
        if [ $i -eq 0 ]
        then
            echo "slapd did not stop correctly"
            exit 1
        fi
    else
          # Something has gone wrong with our image build
          echo "FAILURE: Default configuration files from /contrib/ are not present in the image at /opt/openshift."
          exit 1
    fi

    # Test configuration files, log checksum errors. Errors may be tolerated and repaired by slapd so don't exit
    LOG=`slaptest 2>&1`
    CHECKSUM_ERR=$(echo "${LOG}" | grep -Po "(?<=ldif_read_file: checksum error on \").+(?=\")")
    for err in $CHECKSUM_ERR
    do
        echo "The file ${err} has a checksum error. Ensure that this file is not edited manually, or re-calculate the checksum."
    done

    rm -rf /ldap_config/*.template

    touch /etc/openldap/CONFIGURED
fi

# Start the slapd service
exec slapd -h "ldap:/// ldaps:///" -d $OPENLDAP_DEBUG_LEVEL
