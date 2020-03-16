#!/bin/bash
(( ${#JAVA_HOME} == 0 )) && echo Error: missing JAVA_HOME environment variable. && exit
stuff=`ls`
if (( ${#stuff} != 0 )); then
  echo Current folder is not empty. Press Ctrl-C to cancel or ENTER to continue.
  read
fi
from=${0%/*} && (( $# > 0 )) && from="$1"
for f in apache_tomcat alfresco_content alfresco_search; do
  for found in $from/${f/_/-}-*.zip; do break; done
  (( ${#found} == 0 )) && echo Error: cannot find $from/${f/_/-}-*.zip && exit
  echo Found $found
  eval ${f}="$found"
done
mkdir -p modules/platform modules/share tmp
unzip -q $apache_tomcat -d tmp
mv tmp/* tomcat
unzip -q $alfresco_search -d tmp
mv tmp/* search-services
unzip -q $alfresco_content -d tmp
cd tmp/*; mv * ../..; cd ../..; rmdir tmp/*
mv tmp logs

chmod +x bin/*.sh tomcat/bin/*.sh
cd tomcat/conf
ln -s ../../web-server/conf/Catalina .
sed -i.bak -e 's|connectionTimeout=|URIEncoding="UTF-8" connectionTimeout=|' server.xml
sed -i.bak -e 's|shared.loader=|shared.loader=${catalina.base}/shared/classes|' catalina.properties
cd ..
rm -rf webapps
ln -s ../web-server/webapps .
ln -s ../web-server/shared .
cat > bin/setenv.sh <<-'END'
	JAVA_OPTS="-XX:+DisableExplicitGC -XX:+UseConcMarkSweepGC -XX:+UseParNewGC -Djava.awt.headless=true -XX:ReservedCodeCacheSize=128m $JAVA_OPTS "
	JAVA_OPTS="-Xms512M -Xmx8192M -Djgroups.bind_addr=127.0.0.1 $JAVA_OPTS "
	export JAVA_OPTS
END
cd ..
sed -e "s|JAVA_HOME=|JAVA_HOME=${JAVA_HOME}|" > alfresco.sh <<-'END'
	#!/bin/bash

	cd `dirname $0`
	catalina=tomcat/bin/catalina.sh

	export JAVA_HOME=
	export LC_ALL="en_US.UTF-8"
	export JAVA_OPTS="-Duser.timezone=PST -Dalfresco.home=$PWD"
	export CATALINA_PID=tomcat/temp/catalina.pid

	if [ -f $catalina ]; then
	  if [ "$*" == "stop" ]; then $catalina stop 20 -force; else $catalina "$@"; fi
	else
	  echo ERROR: $PWD/$catalina not found.
	fi
END
chmod +x alfresco.sh

bin/apply_amps.sh
rm web-server/webapps/alfresco.war-*.bak

mv alfresco-pdf-renderer pdf-renderers; cd pdf-renderers
if [[ $OSTYPE == darwin* ]]; then
  # Get the missing PDF Renderer for Mac
  wget --no-check-certificate https://artifacts.alfresco.com/nexus/content/repositories/public/org/alfresco/alfresco-pdf-renderer/1.1/alfresco-pdf-renderer-1.1-osx.tgz
  tar xzf alfresco-pdf-renderer-*-osx.tgz
else
  tar xzf alfresco-pdf-renderer-*-linux.tgz
fi
mv alfresco-pdf-renderer ../bin/
cd ../tomcat/lib
wget --no-check-certificate https://repo1.maven.org/maven2/mysql/mysql-connector-java/5.1.48/mysql-connector-java-5.1.48.jar
cd ../..

# First time Solr startup
search-services/solr/bin/solr start -a "-Dcreate.alfresco.defaults=alfresco,archive"

# Bare minimum properties
cat > web-server/shared/classes/alfresco-global.properties <<END
dir.root=$PWD/alf_data
dir.keystore=\${dir.root}/keystore

db.driver=org.gjt.mm.mysql.Driver
db.url=jdbc:mysql://localhost/alf612ce?useUnicode=yes&characterEncoding=UTF-8
db.username=alfresco
db.password=alfresco

jodconverter.officeHome=/Applications/LibreOffice.app/Contents
jodconverter.portNumbers=8101
jodconverter.enabled=false

alfresco.context=alfresco
alfresco.host=\${localname}
alfresco.port=8080
alfresco.protocol=http

share.context=share
share.host=\${localname}
share.port=8080
share.protocol=http

index.subsystem.name=solr6
solr.secureComms=none
solr.port=8983
solr.host=localhost
solr.base.url=/solr

alfresco-pdf-renderer.exe=bin/alfresco-pdf-renderer
alfresco.rmi.services.host=0.0.0.0
messaging.broker.url=vm://localhost?broker.persistent=false

smart.folders.enabled=true
smart.folders.model=alfresco/model/smartfolder-model.xml
smart.folders.model.labels=alfresco/messages/smartfolder-model
END
