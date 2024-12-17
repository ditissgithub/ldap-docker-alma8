# Use AlmaLinux base image
FROM almalinux/8-base:latest

# Maintainer information
LABEL maintainer="satishg@cdac.in"

# Install dependencies
RUN dnf install -y wget vim procps-ng cyrus-sasl-devel libtool-ltdl-devel \
    openssl-devel libdb-devel make chrony gettext libtool autoconf tar gcc \
    perl perl-devel epel-release && \
    dnf config-manager --set-enabled powertools && \
    dnf --enablerepo=epel install -y openldap-servers openldap-clients openldap openldap-devel && \
    dnf install -y nss-pam-ldapd iproute oddjob openssh-server && \
    dnf clean all

# Configure OpenLDAP default files
RUN cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG && \
    chown -R ldap:ldap /var/lib/ldap /etc/openldap

# Copy LDAP configuration files
COPY ./ldap_config /ldap_config

COPY ./ldap_int-auth/nsswitch.conf /etc/nsswitch.conf
COPY ./ldap_int-auth/password-auth /etc/pam.d/
COPY ./ldap_int-auth/system-auth /etc/pam.d/
COPY ./etc_openldap_config/ldap.conf.template /ldap_config/

# Copy startup script
COPY ./ldap_run.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/ldap_run.sh

# Expose LDAP and LDAPS ports
EXPOSE 389 636


# Set the entrypoint script
ENTRYPOINT ["/usr/local/bin/ldap_run.sh"]
