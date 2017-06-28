# !/bin/bash

echo step1:
echo docker pull image of jre containing keytool: openjdk contains keytool
docker pull openjdk:8-jre-alpine
echo docker pull image for openssl: just alpine + openssl
docker pull frapsoft/openssl

echo step2:
echo Generate a CA certificate:
docker run -it -v $PWD/keystore:/work:Z frapsoft/openssl req -new -newkey rsa:4096 -x509 -keyout /work/xpaas.key  -days 365 -subj "/CN=xpaas-sso-demo.ca" -out /work/xpaas.crt

echo step3:
echo Generate a Certificate for the SSL keystore:
docker run --rm -ti -v $PWD/keystore:/work:Z openjdk:8-jre-alpine keytool -genkeypair -alias sso-https-key -keyalg RSA -keystore /work/sso-https.jks -storepass admin123 --dname "CN=qujinping,OU=CloudPlatform,O=xiaomi.com,L=QingHe6Qi,S=BJ,C=CN"

echo step4:
echo Generate a Certificate Sign Request for the SSL keystore:
docker run --rm -ti -v $PWD/keystore:/work:Z openjdk:8-jre-alpine keytool -certreq -keyalg rsa -alias sso-https-key -keystore /work/sso-https.jks -file /work/sso.csr

echo step5:
echo  Sign the Certificate Sign Request with the CA certificate:
docker run -it -v $PWD/keystore:/work:Z frapsoft/openssl  x509 -req -CA /work/xpaas.crt -CAkey /work/xpaas.key -in /work/sso.csr -out /work/sso.crt -days 365 -CAcreateserial

echo step6:
echo  Import the CA into the SSL keystore:
docker run --rm -ti -v $PWD/keystore:/work:Z openjdk:8-jre-alpine keytool -import -file /work/xpaas.crt -alias xpaas.ca -keystore /work/sso-https.jks

echo step7:
echo  Import the signed Certificate Sign Request into the SSL keystore:
docker run --rm -ti -v $PWD/keystore:/work:Z openjdk:8-jre-alpine keytool -import -file /work/sso.crt -alias sso-https-key -keystore /work/sso-https.jks

echo step8:
echo  Create the keystore secrets with the SSL keystore, link the secrets to the service account created earlier:
oc secret new sso-ssl-secret keystore/sso-https.jks
oc create serviceaccount sso-service-account
oc secrets link sso-service-account sso-ssl-secret
oc policy add-role-to-user view system:serviceaccount:keycloak:sso-service-account -n keycloak
