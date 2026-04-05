Sylvia-IoT Development Scripts
===============================

Scripts for quickly setting up a **Sylvia-IoT** development/test environment on a local machine.

### Prerequisites

- Docker
- `curl`
- `sqlite3` (SQLite mode only): `sudo apt-get install sqlite3`

---

### Quick Start

```bash
# 1. Install components
./update.sh core               # or: ./update.sh router
./update.sh gui                # optional: web GUI (served at http://localhost:1080)
./update.sh lora-ifroglab      # optional: LoRa service
./update.sh app-demo           # optional: app-demo service
./update.sh plugin-lora        # optional: GUI plugin

# 2. Start services (also initializes platform data automatically)
./start.sh                     # SQLite + sylvia-iot-core (defaults)
./start.sh --db mongodb --bin router --with lora-ifroglab --gui

# 3. Stop services
./stop.sh
```

---

### Scripts

| Script | Description |
|--------|-------------|
| `update.sh` | Install or upgrade components to latest versions |
| `start.sh` | Start all services |
| `stop.sh` | Stop all services |
| `status.sh` | Show status of all services and installed components |
| `reset-db.sh` | Reset database to initial state |
| `init-api.sh` | Initialize platform data via REST API (also run by start.sh) |

---

### update.sh

Downloads the latest release from GitHub. Uses the `VERSION` file in each release to skip unnecessary downloads.

```bash
./update.sh <COMPONENT...>
```

| Component | Description |
|-----------|-------------|
| `core` | sylvia-iot-core (auth + broker + coremgr + data) |
| `router` | sylvia-router (core + router functionality) |
| `router-cli` | sylvia-router CLI tool |
| `coremgr-cli` | sylvia-iot-coremgr CLI tool |
| `lora-ifroglab` | LoRa iFrogLab gateway service |
| `app-demo` | Application demo service |
| `gui` | Sylvia-IoT web GUI — extracted to `static/`, served by the main binary at `http://localhost:1080` |
| `plugin-lora` | GUI shell plugin: LoRa iFrogLab — extracted to `static/js/plugins/` |
| `plugin-app` | GUI shell plugin: App Demo — extracted to `static/js/plugins/` |

Version records are stored in `.versions/`. Supports `x86_64` and `arm64`.

---

### start.sh

```
./start.sh [--db sqlite|mongodb] [--bin core|router] [--with SERVICE,...] [--gui] [--host HOSTNAME]
```

| Option | Default | Description |
|--------|---------|-------------|
| `--db` | `sqlite` | Database backend |
| `--bin` | `core` | Main binary (`sylvia-iot-core` or `sylvia-router`) |
| `--with` | — | Comma-separated optional services: `lora-ifroglab`, `app-demo` |
| `--gui` | — | Serve installed GUI via `staticPath` (requires `./update.sh gui`) |
| `--host` | `localhost` | Hostname for GUI `config.js` URLs (e.g. `router.sylvia-iot`) |

**SQLite mode** starts: EMQX + RabbitMQ + sylvia-iot-core/router

**MongoDB mode** starts: EMQX + RabbitMQ + MongoDB + Redis + sylvia-iot-core/router

---

### reset-db.sh

```
./reset-db.sh [--db sqlite|mongodb]
```

- **SQLite**: deletes `test.db` and recreates it from `test.db.sql`
- **MongoDB**: drops `sylvia-iot-auth`, `sylvia-iot-broker`, `sylvia-iot-data` and re-runs `init-mongodb.js`

---

### Configuration Files

| File | Description |
|------|-------------|
| `versions.env` | Docker image and component versions |
| `config.json5` | sylvia-iot-core/router config (includes both SQLite and MongoDB settings, switched by `engine`) |
| `config-lora-ifroglab.json5` | LoRa iFrogLab service config |
| `config-app-demo.json5` | App Demo service config |
| `emqx.conf` | EMQX broker configuration |
| `test.db.sql` | SQLite schema + seed data |
| `init-mongodb.js` | MongoDB seed data (idempotent mongosh script) |

`config.runtime.json5` is generated at startup with EMQX credentials and the selected `engine` injected — do not edit manually.

---

### Default Credentials

| Service | URL | Credentials |
|---------|-----|-------------|
| Sylvia-IoT + GUI | http://localhost:1080 | admin / admin |
| RabbitMQ | http://localhost:15672 | guest / guest |
| EMQX Dashboard | http://localhost:18083 | admin / public |

### Default OAuth2 Clients

| Client ID | Secret | Redirect URI |
|-----------|--------|--------------|
| `public` | — | `http://localhost:1080/auth/oauth2/redirect`, `http://localhost:1080/#/auth/callback` |
| `private` | `secret` | `http://localhost:1080/auth/oauth2/redirect` |
| `sylvia-iot-gui` | — | `http://localhost:1080/#/auth/callback` |

---

### Docker Containers

| Container | Image | Ports |
|-----------|-------|-------|
| `sylvia-rabbitmq` | `rabbitmq` | 5671, 5672, 15672 |
| `sylvia-emqx` | `emqx/emqx` | 1883, 8883, 18083 |
| `sylvia-mongodb` | `mongo` | 27017 |
| `sylvia-redis` | `redis` | 6379 |

Image versions are defined in [`versions.env`](versions.env).

RabbitMQ, MongoDB, and Redis containers are stopped but not removed.
