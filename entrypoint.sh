#!/bin/bash
set -e

NODE_ID=${NODE_ID:-1}
CLUSTER_NAME=${CLUSTER_NAME:-pg_cluster}
REPMGR_USER=${REPMGR_USER:-repmgr}
REPMGR_DB=${REPMGR_DB:-repmgr}
PRIMARY_HOST=${PRIMARY_HOST:-pg-0}   # primary mặc định
PGDATA=/var/lib/postgresql/data

mkdir -p $PGDATA/log

if [ "$NODE_ID" -eq 1 ]; then
  # === PRIMARY NODE ===
  if [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo "Initializing primary node..."
    pg_ctl initdb -D $PGDATA
    echo "listen_addresses='*'" >> $PGDATA/postgresql.conf
    echo "wal_level=replica" >> $PGDATA/postgresql.conf
    echo "archive_mode=on" >> $PGDATA/postgresql.conf
    echo "max_wal_senders=20" >> $PGDATA/postgresql.conf
    echo "max_replication_slots=20" >> $PGDATA/postgresql.conf
    echo "host replication all all trust" >> $PGDATA/pg_hba.conf
    echo "host all all all trust" >> $PGDATA/pg_hba.conf
  fi

  pg_ctl -D $PGDATA -o "-c listen_addresses='*'" -w start

  # Create repmgr user/db
  psql -U postgres -tc "SELECT 1 FROM pg_roles WHERE rolname='$REPMGR_USER'" | grep -q 1 || \
    psql -U postgres -c "CREATE USER $REPMGR_USER REPLICATION LOGIN SUPERUSER;"
  psql -U postgres -tc "SELECT 1 FROM pg_database WHERE datname='$REPMGR_DB'" | grep -q 1 || \
    psql -U postgres -c "CREATE DATABASE $REPMGR_DB OWNER $REPMGR_USER;"

  ROLE="primary"
  REGISTER_CMD="repmgr -f /etc/repmgr.conf primary register || true"

else
  # === STANDBY NODE ===
  if [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo "Cloning data from primary ($PRIMARY_HOST)..."
    pg_basebackup -h $PRIMARY_HOST -D $PGDATA -U $REPMGR_USER -Fp -Xs -P -R
  fi

  pg_ctl -D $PGDATA -o "-c listen_addresses='*'" -w start

  ROLE="standby"
  REGISTER_CMD="repmgr -f /etc/repmgr.conf standby register || true"
fi

# Common repmgr.conf
cat > /etc/repmgr.conf <<EOF
node_id=$NODE_ID
node_name=pg$NODE_ID
conninfo='host=$HOSTNAME user=$REPMGR_USER dbname=$REPMGR_DB connect_timeout=2'
data_directory='$PGDATA'
failover=automatic
promote_command='repmgr standby promote -f /etc/repmgr.conf --log-to-file'
follow_command='repmgr standby follow -f /etc/repmgr.conf --log-to-file --upstream-node-id=%n'
monitor_interval_secs=5
EOF

# Register node
eval $REGISTER_CMD

# Start repmgrd (daemon mode, auto failover)
echo "Starting repmgrd on $ROLE node..."
exec repmgrd -f /etc/repmgr.conf -d --verbose --log-to-file

