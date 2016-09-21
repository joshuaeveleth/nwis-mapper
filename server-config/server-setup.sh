#!/bin/sh

#args
USER_HOME=$(getent passwd $SUDO_USER | cut -d: -f6)
USER=$SUDO_USER
LIST_OF_MAIN_APPS="python python-dev python-pip git libgeos-dev libjpeg-dev zlib1g-dev apache2"
LIST_OF_PYTHON_APPS="Mako cherrypy xlwt shapely pillow"

#install cert
wget https://raw.githubusercontent.com/USGS-OWI/nwis-mapper/master/server-config/DOIRootCA2.cer --no-check-certificate
cp DOIRootCA2.cer /usr/local/share/ca-certificates/DOIRootCA2.crt
update-ca-certificates

#install apps
apt-get update  # To get the latest package lists
apt-get install -y $LIST_OF_MAIN_APPS
pip install $LIST_OF_PYTHON_APPS

#get repo from github
GIT_SSL_NO_VERIFY=true git clone https://github.com/USGS-OWI/nwis-mapper.git

#copy bucket info file (should have been placed by cloud formation)
if [ -f /tmp/s3bucket.json ]; then
  cp /tmp/s3bucket.json ${USER_HOME}/nwis-mapper/mapper/s3bucket.json
else
  cp ${USER_HOME}/nwis-mapper/server-config/s3bucket.json ${USER_HOME}/nwis-mapper/mapper/s3bucket.json
fi  

#set proper permissions on nwis mapper folder
chown ${SUDO_USER} -R ${USER_HOME}/nwis-mapper
chgrp ${SUDO_USER} -R ${USER_HOME}/nwis-mapper
chmod +x ${USER_HOME}/nwis-mapper/server-config/chkCherry.sh

#create symbolic link
ln -s ${USER_HOME}/nwis-mapper/mapper /var/www/mapper

#start up cherrypy services
sh ${USER_HOME}/nwis-mapper/server-config/PythonAppServers.sh

#setup up cron jobs
(crontab -u ${USER} -l; echo "*/5 * * * * ${USER_HOME}/nwis-mapper/server-config/chkCherry.sh" ) | crontab -u ${USER} -
(crontab -u ${USER} -l; echo "0 0 * * 0 rm -rf ${USER_HOME}/nwis-mapper/mapper/exporter/temp/*" ) | crontab -u ${USER} -

#add redirect from root and favicon
cp ${USER_HOME}/nwis-mapper/server-config/favicon.ico /var/www/favicon.ico
cp ${USER_HOME}/nwis-mapper/server-config/index.html /var/www/index.html

#cleanup html folder
if [ -d /var/www/html ]; then
  rm -R /var/www/html
fi

#install mod-proxy
a2enmod proxy_http

#add new virtual site
cp ${USER_HOME}/nwis-mapper/server-config/nwis-mapper.conf /etc/apache2/sites-available/nwis-mapper.conf
a2dissite 000-default
a2ensite nwis-mapper
service apache2 restart
