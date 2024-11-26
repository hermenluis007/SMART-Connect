
sudo apt -y update
sudo apt -y upgrade

sudo apt install net-tools

sudo apt-get -y install postgresql-12
sudo apt-get -y install postgis
sudo apt-get -y install postgresql-contrib-12

sudo cp /home/smart/postgresql.conf /etc/postgresql/12/main/postgresql.conf
sudo cp /home/smart/pg_hba.conf /etc/postgresql/12/main/pg_hba.conf

sudo service postgresql restart
sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'smart1234';"
sudo -u postgres psql -c "CREATE USER smartconnect PASSWORD 'smart1234';"
sudo -i -u postgres createdb connectsmart
sudo -i -u postgres psql connectsmart -b -f /home/smart/connect-7_5_4.sql


sudo apt-get -y install openjdk-11-jre
sudo apt-get -y install tomcat9
sudo apt-get -y install tomcat9-admin
sudo apt-get -y install tomcat9-common

sudo cp /home/smart/*.jar /var/lib/tomcat9/lib/


sudo mkdir /datadrive/
sudo chown tomcat:tomcat /datadrive
sudo chmod 755 /datadrive

sudo mkdir /datadrive/filestore
sudo mkdir /datadrive/filestore/uploads
sudo mkdir /datadrive/filestore/dataqueue
sudo mkdir /datadrive/filestore/caexport

sudo chown tomcat:tomcat /datadrive/filestore
sudo chown tomcat:tomcat /datadrive/filestore/uploads
sudo chown tomcat:tomcat /datadrive/filestore/dataqueue
sudo chown tomcat:tomcat /datadrive/filestore/caexport

sudo chmod 755 /datadrive/filestore
sudo chmod 755 /datadrive/filestore/uploads
sudo chmod 755 /datadrive/filestore/dataqueue
sudo chmod 755 /datadrive/filestore/caexport


sudo cp /home/smart/tomcat9.service /lib/systemd/system/tomcat9.service


sudo keytool -genkey -alias tomcat -keyalg RSA -validity 3650 -keysize 2048 -keypass 1234smart -dname "CN=LOCALHOST" -keystore /var/lib/tomcat9/conf/tomcat.jks -storepass 1234smart -deststoretype pkcs12 -ext SAN=ip:127.0.0.1,dns:localhost
sudo keytool -list -alias tomcat -keystore /var/lib/tomcat9/conf/tomcat.jks -storepass 1234smart -v

sudo cp /home/smart/server.xml /var/lib/tomcat9/conf
sudo cp /home/smart/server.war /var/lib/tomcat9/webapps

sudo systemctl daemon-reload
sudo service postgresql restart
sudo service tomcat9 restart
