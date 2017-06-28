FROM centos:7

RUN yum install -y epel-release && yum update -y && yum install -y java-1.8.0-openjdk-devel jq xmlstarlet saxon augeas bsdtar unzip && yum clean all

# Set the JAVA_HOME variable to make it clear where Java is located
ENV JAVA_HOME /usr/lib/jvm/java
ENV KEYCLOAK_VERSION 3.1.0.Final
# Enables signals getting passed from startup script to JVM
# ensuring clean shutdown when container is stopped.
ENV LAUNCH_JBOSS_IN_BACKGROUND 1
ENV PROXY_ADDRESS_FORWARDING false

ENV JBOSS_BASE /opt/jboss
ENV JBOSS_HOME /opt/jboss/keycloak

RUN  useradd -u 1001 -r -g 0 -d ${JBOSS_BASE} -s /sbin/nologin \
     -c "JBoss User" default && \
     mkdir -p $JBOSS_BASE && \
     chown -R 1001:0 $JBOSS_BASE

USER 1001

#COPY keycloak-3.1.0.Final.tar.gz /opt/jboss/
#RUN cd /opt/jboss/ && tar -zxvf keycloak-3.1.0.Final.tar.gz && mv /opt/jboss/keycloak-$KEYCLOAK_VERSION /opt/jboss/keycloak 
RUN cd $JBOSS_BASE && curl http://downloads.jboss.org/keycloak/$KEYCLOAK_VERSION/keycloak-$KEYCLOAK_VERSION.tar.gz | tar zx && mv $JBOSS_BASE/keycloak-$KEYCLOAK_VERSION $JBOSS_HOME

ADD docker-entrypoint.sh $JBOSS_BASE

# switch to run in standalone mode
ADD setLogLevel.xsl $JBOSS_HOME
RUN java -jar /usr/share/java/saxon.jar -s:$JBOSS_HOME/standalone/configuration/standalone.xml -xsl:$JBOSS_HOME/setLogLevel.xsl -o:$JBOSS_HOME/standalone/configuration/standalone.xml


#Enabling Proxy address forwarding so we can correctly handle SSL termination in front ends
#such as an OpenShift Router or Apache Proxy
RUN sed -i -e 's/<http-listener /& proxy-address-forwarding="${env.PROXY_ADDRESS_FORWARDING}" /' $JBOSS_HOME/standalone/configuration/standalone.xml

# setup mysql database instead of h2
ADD changeDatabase.xsl $JBOSS_HOME
RUN java -jar /usr/share/java/saxon.jar -s:$JBOSS_HOME/standalone/configuration/standalone.xml -xsl:$JBOSS_HOME/changeDatabase.xsl -o:$JBOSS_HOME/standalone/configuration/standalone.xml; rm $JBOSS_HOME/changeDatabase.xsl 
RUN mkdir -p $JBOSS_HOME/modules/system/layers/base/com/mysql/jdbc/main; cd $JBOSS_HOME/modules/system/layers/base/com/mysql/jdbc/main && curl -O http://central.maven.org/maven2/mysql/mysql-connector-java/5.1.42/mysql-connector-java-5.1.42.jar
ADD module.xml $JBOSS_HOME/modules/system/layers/base/com/mysql/jdbc/main/

#Give correct permissions when used in an OpenShift environment.
USER root
RUN chown -R 1001:0 $JBOSS_HOME/standalone && \
    chmod -R g+rwx $JBOSS_HOME/standalone

USER 1001
RUN sed -i -e 's/<security-realms>/&\n            <security-realm name="UndertowRealm">\n                <server-identities>\n                    <ssl>\n                        <keystore path="keystore\/sso-https.jks" relative-to="jboss.server.config.dir" keystore-password="${env.HTTPS_PASSWORD:secret}" alias="${env.HTTPS_NAME:secret}" key-password="${env.HTTPS_PASSWORD:secret}" \/>\n                    <\/ssl>\n                <\/server-identities>\n            <\/security-realm>/' $JBOSS_HOME/standalone/configuration/standalone.xml
RUN sed -i -e 's/<server name="default-server">/&\n                <https-listener name="https" socket-binding="https" security-realm="UndertowRealm"\/>/' $JBOSS_HOME/standalone/configuration/standalone.xml

#VOLUME $JBOSS_HOME/standalone/configuration/keystore

WORKDIR $JBOSS_HOME

EXPOSE 8080

ENTRYPOINT [ "/opt/jboss/docker-entrypoint.sh" ]

CMD ["-b", "0.0.0.0"]
