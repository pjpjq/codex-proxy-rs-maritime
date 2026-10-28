#!/bin/sh
# Starts Redis (127.0.0.1 only, AOF in /data/redis), writes deploy/config.yaml from env, then execs CPR.
set -eu

: "${CPR_DATABASE_URL:?CPR_DATABASE_URL secret is required}"
: "${CPR_DATABASE_PASSWORD:?CPR_DATABASE_PASSWORD secret is required}"
: "${CPR_REDIS_PASSWORD:?CPR_REDIS_PASSWORD secret is required}"
: "${CPR_ADMIN_PASSWORD:?CPR_ADMIN_PASSWORD secret is required}"
export CPR_SERVER_PORT="${PORT:-${CPR_SERVER_PORT:-8080}}"

# Drop to the image's cpr user when started as root (volume may be root-owned).
if [ "$(id -u)" = "0" ]; then
  mkdir -p /data
  chown cpr:cpr /data
  exec setpriv --reuid=cpr --regid=cpr --init-groups "$0" "$@"
fi

mkdir -p /data/redis /data/cpr /data/logs /data/config

# Single-quoted YAML scalars: escape embedded single quotes.
q() { printf "'%s'" "$(printf %s "$1" | sed "s/'/''/g")"; }

cat > /data/config/config.yaml <<YAML
schema_version: 1
host:
  timezone: $(q "${CPR_TIMEZONE:-Asia/Shanghai}")
  listen:
    host: '0.0.0.0'
    port: ${CPR_SERVER_PORT}
  runtime_data_dir: '/data/cpr'
  logging:
    level: 'info'
    stdout: true
    file:
      enabled: true
      directory: '/data/logs'
      retention_days: 3
      max_file_size_mb: 10
store:
  database:
    url: $(q "$CPR_DATABASE_URL")
    password: $(q "$CPR_DATABASE_PASSWORD")
  redis:
    url: 'redis://127.0.0.1:6379/'
    password: $(q "$CPR_REDIS_PASSWORD")
  pool:
    max_connections: ${CPR_DB_MAX_CONNECTIONS:-8}
admin:
  default_username: $(q "${CPR_ADMIN_USERNAME:-admin@cpr.local}")
  default_password: $(q "$CPR_ADMIN_PASSWORD")
YAML
chmod 600 /data/config/config.yaml
ln -sfn /data/config/config.yaml /app/deploy/config.yaml

# Redis: localhost only, AOF persisted to /data/redis, capped memory for the 2 GB box.
cat > /data/redis/redis.conf <<CONF
bind 127.0.0.1
port 6379
protected-mode yes
dir /data/redis
appendonly yes
appendfsync everysec
save ""
maxmemory ${REDIS_MAXMEMORY:-256mb}
maxmemory-policy noeviction
daemonize yes
logfile /data/logs/redis.log
requirepass $CPR_REDIS_PASSWORD
CONF
chmod 600 /data/redis/redis.conf
redis-server /data/redis/redis.conf

i=0
until REDISCLI_AUTH="$CPR_REDIS_PASSWORD" redis-cli -h 127.0.0.1 ping 2>/dev/null | grep -q PONG; do
  i=$((i + 1))
  [ "$i" -gt 60 ] && { echo "redis did not start" >&2; tail -n 50 /data/logs/redis.log >&2; exit 1; }
  sleep 0.5
done
echo "[cpr-entrypoint] redis ready; starting codex-proxy-rs on :${CPR_SERVER_PORT}"

# Passwords are in config.yaml; keep the URL override pointed at localhost Redis.
unset CPR_DATABASE_PASSWORD CPR_REDIS_PASSWORD CPR_ADMIN_PASSWORD
cd /app
exec /app/bin/codex-proxy-rs "$@"
