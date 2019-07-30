FROM datadog/agent:6.11.2-jmx

ENV KAFKA_CONFD_PATH /etc/datadog-agent/conf.d

ADD kafka.yml ${KAFKA_CONFD_PATH}/kafka.d/kafka.yaml
ADD kafka_consumer.yml ${KAFKA_CONFD_PATH}/kafka_consumer.d/kafka_consumer.yaml
ADD zk.yml ${KAFKA_CONFD_PATH}/zk.d/zk.yaml

# don't monitor disks - blank out this default file or it'll throw errors
ADD conf.yaml.default ${KAFKA_CONFD_PATH}/disk.d/conf.yaml.default

ADD entrypoint.sh /entrypoint.sh
RUN chmod 0750 entrypoint.sh

ADD custom_checks/salesforce_limits/custom_salesforce_limits.py /etc/datadog-agent/checks.d/
ADD custom_checks/salesforce_limits/custom_salesforce_limits.yaml /etc/datadog-agent/conf.d/

ADD custom_checks/review_envs/custom_review_envs.py /etc/datadog-agent/checks.d/
ADD custom_checks/review_envs/custom_review_envs.yaml /etc/datadog-agent/conf.d/

CMD [ "/entrypoint.sh" ]
