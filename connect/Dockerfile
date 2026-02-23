# =============================================================================
# Custom Kafka Connect image for the AB Bank CDC demo.
#
# Extends the official Confluent Server Connect image with:
#   1. Oracle Instant Client (needed for XStream native library)
#   2. Oracle XStream CDC Source Connector (place in confluent-hub-components/)
#   3. JMX Prometheus Exporter agent
#
# Build context: ./connect/
# =============================================================================

ARG CONFLUENT_PLATFORM_VERSION=7.9.0
FROM confluentinc/cp-server-connect:${CONFLUENT_PLATFORM_VERSION}

USER root

# ── 1. Oracle Instant Client ─────────────────────────────────────────────────
# You must place the unzipped Instant Client directory at:
#   connect/instantclient/
# Download from:
#   https://www.oracle.com/database/technologies/instant-client/downloads.html
#
# x86-64 : instantclient-basic-linux.x64-19.26.0.0.0dbru.zip
# ARM64   : instantclient-basic-linux.arm64-19.26.0.0.0dbru.zip
#
COPY instantclient/ /opt/oracle/instantclient/
RUN chmod 755 /opt/oracle/instantclient/*.so* 2>/dev/null || true && \
    echo /opt/oracle/instantclient > /etc/ld.so.conf.d/oracle-instantclient.conf && \
    ldconfig

ENV LD_LIBRARY_PATH=/opt/oracle/instantclient:${LD_LIBRARY_PATH}
ENV ORACLE_HOME=/opt/oracle/instantclient
ENV PATH=${ORACLE_HOME}:${PATH}

# ── 2. Required OS packages ───────────────────────────────────────────────────
RUN microdnf install -y libaio && microdnf clean all

# ── 3. Connector plugins ──────────────────────────────────────────────────────
# Copy Oracle XStream CDC connector (you must download and place it at
#   connect/confluent-hub-components/confluentinc-kafka-connect-oracle-xstream-cdc/
# then copy ojdbc8.jar + xstreams.jar into its lib/ directory)
COPY confluent-hub-components/ /usr/share/confluent-hub-components/

# Ensure Oracle JDBC and XStream JARs are in the connector's classpath
RUN cp /opt/oracle/instantclient/ojdbc8.jar /usr/share/confluent-hub-components/confluentinc-kafka-connect-oracle-xstream-cdc/lib/ && \
    cp /opt/oracle/instantclient/xstreams.jar /usr/share/confluent-hub-components/confluentinc-kafka-connect-oracle-xstream-cdc/lib/ && \
    chmod 644 /usr/share/confluent-hub-components/confluentinc-kafka-connect-oracle-xstream-cdc/lib/*.jar

# ── 4. JMX Prometheus Exporter ────────────────────────────────────────────────
RUN mkdir -p /usr/share/jmx-exporter && \
    curl -fsSL \
      "https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/1.0.1/jmx_prometheus_javaagent-1.0.1.jar" \
      -o /usr/share/jmx-exporter/jmx_prometheus_javaagent.jar

USER appuser
