FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    wget gnupg lsb-release curl nano vim netcat iputils-ping \
    && rm -rf /var/lib/apt/lists/*

# Cài PostgreSQL + repmgr
RUN apt-get update && \
    apt-get install -y postgresql-14 postgresql-client-14 postgresql-server-dev-14 \
    repmgr && \
    rm -rf /var/lib/apt/lists/*

# Tạo thư mục dữ liệu
RUN mkdir -p /var/lib/postgresql/data
VOLUME ["/var/lib/postgresql/data"]

# Copy entrypoint để init node
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["entrypoint.sh"]

