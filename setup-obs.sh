#!/bin/bash

# This script sets up various OBS servers


add_repos() {
# Use Devel *aswell*
    zypper --no-gpg-checks ar http://repo.pub.meego.com/Mer:/OBS:/Testing:/Devel/openSUSE_11.4/Mer:OBS:Testing:Devel.repo
    zypper --no-gpg-checks ar http://repo.pub.meego.com//Mer:/OBS:/Testing/openSUSE_11.4/Mer:OBS:Testing.repo
    zypper --no-gpg-checks ref
}

install_be() {
    zypper --no-gpg-checks --non-interactive install obs-server
}

enable_be() {
    chkconfig --add obsrepserver 
    chkconfig --add obssrcserver 
    chkconfig --add obsscheduler obsdispatcher obspublisher obswarden
}

configure_be() {

    sed -i 's,^my.*frontend\s*=.*,my \$frontend = "'"${OBSFE_INT}"'";,' \
	/usr/lib/obs/server/BSConfig.pm
    sed -i -e 's,^OBS_SCHEDULER_ARCHITECTURES=.*,OBS_SCHEDULER_ARCHITECTURES="i586 x86_64 armv7el armv8el",' \
	/etc/sysconfig/obs-server
}

start_be() {
    rcobssrcserver start
    rcobsrepserver start
    rcobsdispatcher start
    rcobspublisher start
    rcobswarden start
    rcobsscheduler start
}

### worker

install_worker() {
    zypper --no-gpg-checks --non-interactive install obs-worker qemu
}

enable_worker() {
    chkconfig --add obsworker
}

configure_worker() {

    cat <<EOF > /etc/sysconfig/obs-worker
OBS_REPO_SERVERS="${OBSBE_REPO}:5252" 
OBS_SRC_SERVER="${OBSBE_SRC}:5352"
EOF
}

wait_for_srcserver() {
    while ! (echo GET / > /dev/tcp/${OBSBE_SRC}/5252) 2>/dev/null; do
	echo "Waiting for bs_srcserver on ${OBSBE_SRC}:5252"
	sleep 4
    done
    sleep 5
    echo "bs_srcserver on ${OBSBE_SRC}:5252 is ready"
}

start_worker() {
    rcobsworker start
}

### obssign

install_sign() {
    zypper --no-gpg-checks --non-interactive install --no-recommends obs-server
}
enable_sign() {
    chkconfig --add obssigner
}

start_sign() {
    rcobssigner start
}

### obsfe


install_fe() {
    zypper --no-gpg-checks --non-interactive install obs-api mysql memcached apache2 apache2-mod_xforward rubygem-passenger-apache2 
}

enable_fe() {
# Fix the bug in mysql rc.d script
    sed -i -e's/^# Default-Start:  2 3 5$/# Default-Start:  3 5/' /etc/init.d/mysql 

    chkconfig --add memcached obsapidelayed apache2 mysql
}

configure_fe() {

################ MySQL

## Webui
    sed -i -e 's,^FRONTEND_HOST = .*,FRONTEND_HOST = "'"${API_FQDN}"'",' \
	-e 's,^FRONTEND_PORT = .*,FRONTEND_PORT = 444,' \
	-e 's,^FRONTEND_PROTOCOL = .*,FRONTEND_PROTOCOL = "'"https"'",' \
	-e 's,^DOWNLOAD_URL = .*,DOWNLOAD_URL = \"http://'"${API_FQDN}:82"'\",' \
	/srv/www/obs/webui/config/environments/production.rb

## API
    sed -i -e /webui_url:/d -e /webui_host:/d -e /allow_anonymous:/d \
	/srv/www/obs/api/config/options.yml
    echo "allow_anonymous: true" >> /srv/www/obs/api/config/options.yml
    echo "webui_url: https://${API_FQDN}:443" >> /srv/www/obs/api/config/options.yml

    echo "webui_host: `ip addr | sed -n 's,.*inet \(.*\)/.* brd.*,\1,p' | grep -v ^127. | head -n 1`" \
	>> /srv/www/obs/api/config/options.yml

    sed -i "s,^SOURCE_HOST = .*,SOURCE_HOST = '${OBSBE_SRC}'," \
	/srv/www/obs/api/config/environments/production.rb

## Apache
    sed -i -e 's,^\(APACHE_MODULES=".*\)",\1 passenger xforward headers",' \
	-e 's,^\(APACHE_SERVER_FLAGS=".*\)",\1 SSL",' \
	/etc/sysconfig/apache2
}

createcert_fe() {

    mkdir -p /srv/obs/certs/
    openssl genrsa -out /srv/obs/certs/server.key 2048

    cat << EOF | openssl req -new -x509 -key /srv/obs/certs/server.key -out /srv/obs/certs/server.crt -days 3650
EU
My State or Province
My Locality
My Organization Name
My Organizational Unit Name
${API_FQDN}
test@example.com


EOF
}

setperms_fe() {
    chown -R wwwrun:www /srv/www/obs/webui/log/
    chown -R wwwrun:www /srv/www/obs/api/log/
    mkdir -p /srv/obs/repos
    chown -R wwwrun:www /srv/obs/repos
}

configwww_fe() {

    sed -i -e "s,ServerName api,ServerName ${API_FQDN}," \
	-e "s,ServerName webui,ServerName ${API_FQDN}," \
	/etc/apache2/vhosts.d/obs.conf


    sed -e "s,___WEBUI_URL___,https://${API_FQDN},g" \
	-e "s,___API_URL___,https://${API_FQDN}:444,g" \
	-e "s,___REPO_URL___,http://${API_FQDN}:82,g" \
        /srv/www/obs/overview/overview.html.TEMPLATE \
	> /srv/www/obs/overview/index.html
}

setupmysql_fe() {
## MySQL

    rcmysql start

    (umask 077; dd if=/dev/urandom bs=256 count=1 2>/dev/null |sha256sum| cut -f1 -d" " > /etc/mysql_root.pw)
    (umask 077; dd if=/dev/urandom bs=256 count=1 2>/dev/null |sha256sum| cut -f1 -d" " > /etc/mysql_obs.pw)
    DBROOTPASSWORD=$(cat /etc/mysql_root.pw)
    DBOBSPASSWORD=$(cat /etc/mysql_obs.pw)

    mysqladmin -u root password "$DBROOTPASSWORD"

# The following SQL was taken from /usr/bin/mysql_secure_installation
# remove_anonymous_users, remove_remote_root, remove_test_database
    cat << EOF | mysql -u root -p$DBROOTPASSWORD
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host!='localhost';
DROP DATABASE test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';

create database api_production;
create database webui_production;
GRANT all privileges
     ON api_production.* 
     TO 'obs'@'%', 'obs'@'localhost' IDENTIFIED BY '$DBOBSPASSWORD';
GRANT all privileges
     ON webui_production.* 
     TO 'obs'@'%', 'obs'@'localhost' IDENTIFIED BY '$DBOBSPASSWORD';
FLUSH PRIVILEGES;
EOF

}

rake_fe() {
    cat << EOF > /srv/www/obs/api/config/database.yml
production:
  adapter: mysql
  database: api_production
  username: obs
  password: $DBOBSPASSWORD
EOF

    cat << EOF > /srv/www/obs/webui/config/database.yml
production:
  adapter: mysql
  database: webui_production
  username: obs
  password: $DBOBSPASSWORD
EOF

    cd /srv/www/obs/api/
    RAILS_ENV="production"  rake db:setup
    cd /srv/www/obs/webui/
    RAILS_ENV="production" rake db:setup
}

start_fe() {

    rcmemcached start
    rcobsapidelayed start
    rcapache2 start
}

# We need a local config file

if [[ -f setup-obs.conf ]]; then
    . setup-obs.conf
else 
    cat <<EOF > setup-obs.conf
# This is the internal name of the machine providing the api
OBSFE_INT="obsfe.example.com"

# This is the internal name of the machine providing the bs_srcserver
OBSBE_SRC="obsbe.example.com"
EOF
    echo "You had no setup-obs.conf - one has been created, please edit it"
    exit 1
fi

role=$1

case $role in
    be )
        # This is the internal name of the machine providing the api
	if [[ ${OBSFE_INT} = "" ]] ; then
	    echo "OBSFE_INT must be set for a 'be' role"
	    exit 1
	fi

	echo ________________________________________ $role: add_repos
	add_repos
	echo ________________________________________ $role: install_be
	install_be
	echo ________________________________________ $role: enable_be
	enable_be
	echo ________________________________________ $role: configure_be
	configure_be
	echo ________________________________________ $role: start_be
	start_be
	;;
    worker )
        # This is the internal name of the machine providing the bs_srcserver
	if [[ ${OBSBE_SRC} = "" ]] ; then
	    echo "OBSBE_SRC must be set for a 'be' role"
	    exit 1
	fi
	OBSBE_REPO=${OBSBE_REPO:-${OBSBE_SRC}} # Use OBSBE_SRC unless set

	echo ________________________________________ $role: add_repos
	add_repos
	echo ________________________________________ $role: install_worker
	install_worker
	echo ________________________________________ $role: enable_worker
	enable_worker
	echo ________________________________________ $role: configure_worker
	configure_worker
	echo ________________________________________ $role: wait_for_srcserver
	wait_for_srcserver
	echo ________________________________________ $role: start_worker
	start_worker
	;;
    fe )

        # This is the internal name of the machine providing the bs_srcserver
	if [[ ${OBSBE_SRC} = "" ]] ; then
	    echo "OBSBE_SRC must be set for a 'be' role"
	    exit 1
	fi
	OBSBE_REPO=${OBSBE_REPO:-${OBSBE_SRC}} # Use OBSBE_SRC unless set

        # This is the visible name of the API (and webui) - note that complex
        # setups with reverse proxies etc may need to play with settings
        # hinted at in
        # /srv/www/obs/webui/config/environments/development_base.rb
	API_FQDN=${API_FQDN:-${OBSFE_INT}} # Use OBSBE_SRC unless set
	if [[ ${API_FQDN} = "" ]] ; then
	    echo "API_FQDN or OBSFE_INT must be set for a 'be' role"
	    exit 1
	fi
	
	echo ________________________________________ $role: add_repos
	add_repos
	echo ________________________________________ $role: install_fe
	install_fe
	echo ________________________________________ $role: enable_fe
	enable_fe
	echo ________________________________________ $role: configure_fe
	configure_fe
	echo ________________________________________ $role: createcert_fe
	createcert_fe
	echo ________________________________________ $role: setperms_fe
	setperms_fe
	echo ________________________________________ $role: configwww_fe
	configwww_fe
	echo ________________________________________ $role: setupmysql_fe
	setupmysql_fe
	echo ________________________________________ $role: rake_fe
	rake_fe
	echo ________________________________________ $role: start_fe
	start_fe
	;;
    signer )
	echo ________________________________________ $role: add_repos
	add_repos
	echo ________________________________________ $role: install_sign
	install_sign
	echo ________________________________________ $role: enable_sign
	enable_sign
	echo ________________________________________ $role: start_sign
	start_sign
	;;

    * )
	echo "Unknown role: $role"
	echo "Use : fe, be, signer, worker"
	exit 1
	;;
esac

echo ________________________________________ $role: setup done  ________________________________________
