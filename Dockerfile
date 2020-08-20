FROM alpine:latest
MAINTAINER Julien Francoz <julien-postgresqltuner@francoz.net>
RUN apk add perl-dbd-pg openssh-client
ADD postgresqltuner.pl /usr/bin/
ENTRYPOINT ["/usr/bin/postgresqltuner.pl"]
