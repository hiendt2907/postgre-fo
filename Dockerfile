FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    wget ca-certificates gnupg lsb-release \
    software-properties-common

# Add PostgreSQL APT repo (PG 14 example)
RUN wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
 && echo "deb http://apt.postgresql.org/pub/repos/apt/ jammy-pgdg main" > /etc/apt/sources.list.d/pgdg.list

RUN apt-get update && apt-get install -y \
    postgresql-14 postgresql-client-14 postgresql-server-dev-14 \
    repmgr postgresql-14-repmgr \
    iputils-ping procps vim less \
 && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/lib/postgresql/data
RUN chown -R postgres:postgres /var/lib/postgresql/data

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 5432

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

