#!/bin/bash

set -e

BROKERS=$(echo $KAFKA_PLAINTEXT_URL | sed -e 's/kafka:\/\///g' | tr ',' ' ')
ZKS=$(echo $KAFKA_ZOOKEEPER_URL | sed -e 's/zookeeper:\/\///g' | tr ',' ' ')
B_JMXS=$(echo $KAFKA_JMX_URL | sed -E 's/kafka\+jmx:\/\///g' | tr ',' ' ')
KAFKA_CONFD_PATH=${KAFKA_CONFD_PATH:-/etc/datadog-agent/conf.d}
KAFKA_CONF=${KAFKA_CONFD_PATH}/kafka.d/kafka.yaml
KAFKA_CONS_CONF=${KAFKA_CONFD_PATH}/kafka_consumer.d/kafka_consumer.yaml
ZK_CONF=${KAFKA_CONFD_PATH}/zk.d/zk.yaml
REDIS_CONF=${KAFKA_CONFD_PATH}/redisdb.d/redis.yaml

TRUST_STORE_PATH=/etc/ssl/certs/java/cacerts
TEMP_CACERT_PATH=/kafka_cluster_ca.crt

# workaround for issue with ca-certificates-java not importing a list of certificates
mkdir /etc/ssl/certs/java
/var/lib/dpkg/info/ca-certificates-java.postinst configure

# debugging info
echo DD_KAFKA_CLUSTER_NAME = ${DD_KAFKA_CLUSTER_NAME} 
echo DD_ENVIRONMENT = ${DD_ENVIRONMENT}
echo Use Brokers: ${BROKERS}
echo Use Brokers JMX: $(echo ${B_JMXS} | sed -e 's/:[a-z0-9]*@/:REDACTED@/g')
echo Use ZKs: ${ZKS}

CONF_FILES=''

if [ -n "${B_JMXS}" ]
then
    echo Prepping Kafka check configuration using Broker JMX connections

    # import the heroku kafka CA cert into the trusted certs list for Java
    echo "${KAFKA_TRUSTED_CERT}" > ${TEMP_CACERT_PATH}
    keytool -import -trustcacerts -noprompt -file ${TEMP_CACERT_PATH} -alias KAFKA_CA -keystore ${TRUST_STORE_PATH} -storepass changeit

    # prep all the config files using values obtained from Heroku configuration
    for JMX in ${B_JMXS}
    do
        # for kafka check
        J_CREDS=$(echo ${JMX} | cut -d '@' -f 1)
        J_NETWK=$(echo ${JMX} | cut -d '@' -f 2)

        J_USER=$(echo ${J_CREDS} | cut -d ':' -f 1)
        J_PASS=$(echo ${J_CREDS} | cut -d ':' -f 2)

        J_HOST=$(echo ${J_NETWK} | cut -d ':' -f 1)
        J_PORT=$(echo ${J_NETWK} | cut -d ':' -f 2)

        sed -i -e "/^instances:/a \  - host: ${J_HOST}\n    port: ${J_PORT}\n    user: ${J_USER}\n    password: ${J_PASS}\n    trust_store_path: ${TRUST_STORE_PATH}\n    tags:\n      - cluster_name:DD_KAFKA_CLUSTER_NAME\n      - environment:DD_ENVIRONMENT" $KAFKA_CONF
    done
    CONF_FILES="${CONF_FILES}\n${KAFKA_CONF}"
else
    # if JMX not enabled here, don't run that check.
    rm -f $KAFKA_CONF
fi

if [ -n "${BROKERS}" ]
then
    echo Prepping Kafka Consumer check configuration using Broker connections
    for B in ${BROKERS}
    do
        # for kafka_consumer check

        # the first instance contains just the kafka_connect_str b/c it monitors broker-stored offsets
        sed -i -e "/^  - kafka_connect_str:/a \    - ${B}" $KAFKA_CONS_CONF
        # the second instance monitors offsets stored in ZK, so requires both kafka_connet_str and zk_connect_str
        sed -i -e "/^    kafka_connect_str:/a \    - ${B}" $KAFKA_CONS_CONF
    done
    CONF_FILES="${CONF_FILES}\n${KAFKA_CONS_CONF}"
fi

if [ -n "${ZKS}" ]
then
    echo Prepping Zookeeper and Kafka Consumer check configuration using Zookeeper connections
    for ZK in ${ZKS}
    do
        # for zk check
        ZK_HOST=$(echo ${ZK} | cut -d ':' -f 1)
        ZK_PORT=$(echo ${ZK} | cut -d ':' -f 2)
        sed -i -e "/^instances:/a \  - host: ${ZK_HOST}\n    port: ${ZK_PORT}\n    tags:\n      - cluster_name:DD_KAFKA_CLUSTER_NAME\n      - environment:DD_ENVIRONMENT" $ZK_CONF

        # for kafka_consumer check, second instance (monitors zk-stored offsets)
        sed -i -e "/^  - zk_connect_str:/a \    - ${ZK}" $KAFKA_CONS_CONF
    done
    CONF_FILES="${CONF_FILES}\n${KAFKA_CONS_CONF}\n${ZK_CONF}"
fi

# REDIS MONITORING
if [ -n "${!REDIS_*}" ]
then
    echo Prepping Redis check configuration using environment variables starting with REDIS_

    echo -e "init_config:\n\ninstances:\n" > $REDIS_CONF

    for REDIS_VAR in ${!REDIS_*}
    do
        REDIS_CONN_STRING=${!REDIS_VAR}
        if echo ${REDIS_CONN_STRING} | grep 'redis://' > /dev/null 2>&1
        then
            REDIS_HOST_PORT=$(echo $REDIS_CONN_STRING | cut -d '@' -f 2)
            REDIS_HOST=$(echo $REDIS_HOST_PORT | cut -d ':' -f 1)
            REDIS_PORT=$(echo $REDIS_HOST_PORT | cut -d ':' -f 2)
            REDIS_PASSWORD=$(echo $REDIS_CONN_STRING | cut -d '@' -f 1 | cut -d ':' -f 3)
            REDIS_INSTANCE_NAME=$(echo $REDIS_VAR | sed -e 's/^REDIS_//' -e 's/_URL//' | tr '[:upper:]' '[:lower:]')
            echo "Redis instance: ${REDIS_CONN_STRING}" | sed -e 's/:[a-z0-9]*@/:REDACTED@/'
            echo -e "  - host: $REDIS_HOST\n    port: $REDIS_PORT\n    password: $REDIS_PASSWORD\n    command_stats: true" >> $REDIS_CONF
            echo -e "    tags:\n      - environment:DD_ENVIRONMENT\n      - redis_instance:${REDIS_INSTANCE_NAME}" >> $REDIS_CONF
        fi
    done
    CONF_FILES="${CONF_FILES}\n${REDIS_CONF}"
fi

for CONF_FILE in $(echo -e "$CONF_FILES" | sort | uniq)
do
    # replace DD_KAFKA_CLUSTER_NAME with the value of the env var
    sed -i -E "s/DD_KAFKA_CLUSTER_NAME/${DD_KAFKA_CLUSTER_NAME}/g" ${CONF_FILE}
    sed -i -E "s/DD_ENVIRONMENT/${DD_ENVIRONMENT}/g" ${CONF_FILE}
    sed -i -E '/^[ ]*\#|^$/d' ${CONF_FILE}
    echo Configuration File ${CONF_FILE}:
    echo ==============================================================================================================
    cat ${CONF_FILE} | sed -e 's/^/> /g' | sed -e 's/password:.*$/password: REDACTED/g'
    echo ==============================================================================================================
    echo
done

/init
