# codex-proxy-rs on Maritime: CPR + localhost-only Redis (AOF) in one container, state under /data.
FROM ghcr.io/zyycn/codex-proxy-rs:3.34.0

USER root
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends redis-server \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /data /app/deploy \
    && chown -R cpr:cpr /data /app/deploy

COPY --chmod=0755 entrypoint.sh /usr/local/bin/cpr-entrypoint

ENV HOME=/app \
    CPR_SERVER_HOST=0.0.0.0 \
    CPR_DEPLOYMENT_MODE=docker \
    CPR_WEB_DIST_DIR=/app/web/dist \
    CPR_REDIS_URL=redis://127.0.0.1:6379/ \
    GLIBC_TUNABLES=glibc.malloc.mmap_threshold=131072:glibc.malloc.trim_threshold=131072

VOLUME ["/data"]
EXPOSE 8080
# Migrations can take a while on first boot.
HEALTHCHECK --interval=30s --timeout=5s --start-period=5m --retries=3 \
    CMD curl -fsS "http://127.0.0.1:${PORT:-8080}/healthz" || exit 1

ENTRYPOINT ["/usr/local/bin/cpr-entrypoint"]
