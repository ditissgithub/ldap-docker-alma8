FROM almalinux/8-base:latest

LABEL maintainer="satishg@cdac.in"



RUN dnf install wget vim procps-ng \
    cyrus-sasl-devel \
    libtool-ltdl-devel \
    openssl-devel \
    libdb-devel \
    make chrony gettext \ 
    libtool autoconf  tar gcc perl perl-devel -y

RUN dnf install epel-release -y && \
    dnf config-manager --set-enabled powertools && \
    dnf --enablerepo=epel -y install openldap-servers openldap-clients openldap openldap-devel
    
RUN cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG && \
    chown ldap:ldap /var/lib/ldap/* && \
    systemctl enable --now slapd

# Add defaults for config




# Add startup scripts
COPY ./ldap_run.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/ldap_run.sh

# Expose default ports for ldap and ldaps
EXPOSE 389 636

ENTRYPOINT ["/usr/local/bin/ldap_run.sh"]
