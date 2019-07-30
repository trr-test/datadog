datadog
====================

Monitoring of infrastructure at TRR.

Set up to use DataDog with DataDog-provided checks for:

* Kafka cluster monitoring via JMX (requires exposure of JMX on Heroku Kafka)
* Kafka consumer monitoring via Broker and Zookeeper interfaces (requires exposure of Zookeeper on Heroku Kafka)
* Zookeeper cluster monitoring (requires exposure of Zookeeper on Heroku Kafka)

This is implemented in a Docker container for easy deployment to Heroku as a `worker`-only app.

## Design

### JMX Capabilities

This inherits the `datadog/agent:6.11.2-jmx` container provided by DataDog. It was the latest agent at the time of building, and includes a JRE with the necessary JMX JARs.

**Note:** there is a workaround in place for a problem with the debian package `ca-certificates-java` where it has not imported a default list of CA certificates into `/etc/ssl/certs/java/cacerts`. The workaround reruns a postinstall script to pull down certs and make `cacerts`.

### Kafka Monitoring

There are 3 main config files that get added - one for each of the DataDog-provided checks. These must be updated with the correct information for connecting to the Kafka infrastructure in Heroku. Heroku provides all of the information via config vars, so we parse those and update the following things:

* CA certificate for the Kafka cluster, imported into the Java keystore at `/etc/ssl/certs/java/cacerts`
* JMX endpoint, username, password for connecting to Kafka brokers via JMX
* Kafka and Zookeeper endpoint information (we use plaintext to connect to these) for consumer group and zookeeper monitoring

Finally, comments are removed and configuration files are echoed to logs (with passwords redacted) before the DataDog agent is started up.

### Redis Monitoring

Mulitple Heroku Redis instances can be monitored by this Docker container. We use the DataDog Redis monitoring with `command_stats` turned on, in order to get pre-command call rates and response times.

Heroku Redis instances should be attached as a descriptive name. For instance:

> heroku addons:attach -a trr-datadog-staging --as REDIS_WEB_CACHE trr-web-staging-redis-cache

This will result in a redis instance being tracked as `web_cache`. The Environment is also marked using the `environment` tag, which corresponds to the `DD_ENVIRONMENT` environment variable as passed to this Docker container.

## Usage

Create a Heroku app in the same private space as the Heroku Kafka instance.

Attach the Heroku Kafka addon to this app using the attachment name `KAFKA`. You will need to have enabled zookeeper access, plaintext authentication, and JMX. This is normally done at provisioning time with the flags `--enable-zookeeper`, `--plaintext` and `--enable-jmx`. If this is aproduction or non-disposable instance, you may have to ask Heroku support to enable this for you - and depending on the feature, your brokers may need to be restarted.

Set the following config vars in the Heroku App:

| config var name | config var value |
| --- | --- |
| DD_API_KEY | your DataDog API key |
| DD_KAFKA_CLUSTER_NAME | the name of the Kafka cluster to be monitored (i.e. `production` or `staging`) |
| DD_ENVIRONMENT | the environment that we're running in (i.e. `production` or `staging`). Used to tag all metrics. |

Ensure that you're logged in to the Heroku CLI and container registry

> heroku login && heroku container:login

From within this repo directory, build and deploy this image as the `worker` portion of the app. There will be no `web` portion.

> docker build -t worker . && heroku container:push -a trr-datadog-staging worker && heroku container:release -a trr-datadog-staging worker