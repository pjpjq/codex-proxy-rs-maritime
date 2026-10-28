# codex-proxy-rs on Maritime

Wrapper image: `ghcr.io/zyycn/codex-proxy-rs:3.34.0` + localhost Redis (AOF) in one container. State lives under `/data`.

Required secrets: `CPR_DATABASE_URL`, `CPR_DATABASE_PASSWORD`, `CPR_REDIS_PASSWORD`, `CPR_ADMIN_PASSWORD`.
