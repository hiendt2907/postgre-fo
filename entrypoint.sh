#!/bin/bash
set -euo pipefail

NODE_ID=${NODE_ID:-1}
CLUSTER_NAME=${CLUSTER_NAME:-pg_cluster}
REPMGR_USER=${REPMGR_USER:-repmgr}
REPMGR_DB=${REPMGR_DB:-repmgr}
PRIMARY_HOST=${PRIMARY_HOST:-pg-0}
PGDATA=/var/lib/postgresql/data
LOGFILE=$PGDATA/startup.log

mkdir -p "$PGDATA"
mkdir -p "$(dirname $LOGFILE)"

# === Function tiện ích ===
pg_ctl_bin="/usr/lib/postgresql/14/bin/pg_ctl"
initdb_bin="/usr/lib/postgresql/14/bin/initdb"
psql_bin="/usr/bin/psql"
pg_basebackup_bin="/usr/lib/postgresql/14/bin/pg_basebackup"
repmgr_bin="/usr/bin/repmgr"

start_postgres() {
  $pg_ctl_bin -D "$PGDATA" -o "-c listen_addresses='*'" -w start >>"$LOGFILE" 2>&1
}

# === Primary Node ===
if [ "$NODE_ID" -eq 1 ]; then
  if [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo "[PRIMARY] Initializing primary node..." | tee -a "$LOGFILE"
    $initdb_bin -D "$PGDATA" >>"$LOGFILE" 2>&1
    echo "listen_addresses='*'" >> "$PGDATA/postgresql.conf"
    echo "wal_level=replica" >> "$PGDATA/postgresql.conf"
    echo "archive_mode=on" >> "$PGDATA/postgresql.conf"
    echo "max_wal_senders=20" >> "$PGDATA/postgresql.conf"
    echo "max_replication_slots=20" >> "$PGDATA/postgresql.conf"
    echo "host replication all all trust" >> "$PGDATA/pg_hba.conf"
    echo "host all all all trust" >> "$PGDATA/pg_hba.conf"
  fi

  start_postgres

  # Tạo user và database cho repmgr
  $psql_bin -U postgres -tc "SELECT 1 FROM pg_roles WHERE rolname='$REPMGR_USER'" | grep -q 1 || \
    $psql_bin -U postgres -c "CREATE USER $REPMGR_USER REPLICATION LOGIN SUPERUSER;"
  $psql_bin -U postgres -tc "SELECT 1 FROM pg_database WHERE datname='$REPMGR_DB'" | grep -q 1 || \
    $psql_bin -U postgres -c "CREATE DATABASE $REPMGR_DB OWNER $REPMGR_USER;"

  ROLE="primary"
  REGISTER_CMD="$repmgr_bin -f /etc/repmgr.conf primary register || true"

# === Standby Node ===
else
  if [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo "[STANDBY] Cloning from primary ($PRIMARY_HOST)..." | tee -a "$LOGFILE"
    $pg_basebackup_bin -h "$PRIMARY_HOST" -D "$PGDATA" -U "$REPMGR_USER" -Fp -Xs -P -R >>"$LOGFILE" 2>&1
  fi

  start_postgres

  ROLE="standby"
  REGISTER_CMD="$repmgr_bin -f /etc/repmgr.conf standby register || true"
fi

# === repmgr.conf ===
cat > /etc/repmgr.conf <<EOF
node_id=$NODE_ID
node_name=pg$NODE_ID
conninfo='host=$HOSTNAME user=$REPMGR_USER dbname=$REPMGR_DB connect_timeout=2'
data_directory='$PGDATA'
failover=automatic
promote_command='$repmgr_bin standby promote -f /etc/repmgr.conf --log-to-file'
follow_command='$repmgr_bin standby follow -f /etc/repmgr.conf --log-to-file --upstream-node-id=%n'
monitor_interval_secs=5
EOF

# === Register node ===
echo "[INFO] Registering node $NODE_ID as $ROLE..." | tee -a "$LOGFILE"
eval $REGISTER_CMD >>"$LOGFILE" 2>&1

# === Start repmgrd (auto failover) ===
echo "[INFO] Starting repmgrd on $ROLE node..." | tee -a "$LOGFILE"
exec $repmgr_bin -f /etc/repmgr.conf -d --verbose --log-to-file

