Sylvia-IoT Deployment with Docker Compose
==========================================

Deploy Sylvia-IoT using Docker Compose. Suitable for NAS (Synology/QNAP), Portainer, or any Docker host.

All configuration is contained in `docker-compose.yaml` and `.env` -- no external files required.

## Services

| Service | Image | Ports |
|---------|-------|-------|
| MongoDB | `mongo` | 27017 |
| Redis | `redis` | 6379 |
| RabbitMQ | `rabbitmq` | 5671, 5672, 15672 |
| EMQX | `emqx/emqx` | 1883, 8883, 18083 |
| sylvia-iot-core | `woofdogtw/sylvia-iot-core` | 1080, 1443 |
| sylvia-iot-gui | `woofdogtw/sylvia-iot-gui` | configurable (default 80) |

## Quick Start

```shell
# Basic
./setup.sh

# With GUI plugins and custom hostname/port
./setup.sh --with lora-ifroglab,app-demo --host nas.local --port 8080

# Stop / remove
./setup.sh --down
./setup.sh --down-v    # also remove volumes (data)
```

## setup.sh Options

| Option | Default | Description |
|--------|---------|-------------|
| `--with` | -- | Install GUI plugins: `lora-ifroglab`, `app-demo` (comma-separated) |
| `--host` | `localhost` | Hostname for GUI redirect URIs |
| `--port` | `80` | GUI listen port |
| `--down` | -- | Stop and remove containers |
| `--down-v` | -- | Stop and remove containers and volumes |

All options write to `.env` -- running `setup.sh` without options uses the current `.env` values.

## Configuration

Edit `.env` to configure:

| Key | Default | Description |
|-----|---------|-------------|
| `MONGODB_VERSION` | `8.2.6` | MongoDB image tag |
| `REDIS_VERSION` | `8.6.1` | Redis image tag |
| `RABBITMQ_VERSION` | `4.2.5` | RabbitMQ image tag |
| `EMQX_VERSION` | `6.2.0` | EMQX image tag |
| `SYLVIA_IOT_CORE_VERSION` | `0.4.5` | sylvia-iot-core image tag |
| `SYLVIA_IOT_GUI_VERSION` | `0.1.2` | sylvia-iot-gui image tag |
| `GUI_HOST` | `localhost` | Hostname for GUI redirect URIs |
| `GUI_PORT` | `80` | GUI listen port |
| `INSTALL_PLUGINS` | (empty) | Plugins: `lora-ifroglab`, `app-demo` (comma-separated) |

## Portainer / NAS

1. Create a new **Stack**
2. Upload `docker-compose.yaml`
3. Set environment variables (or upload `.env` via **Advanced mode**)
4. Deploy

No external files or scripts needed -- certificates are auto-generated, config files are embedded in the compose file.

## Credentials

- **Admin**: admin / admin
- **OAuth2 client**: `sylvia-iot-gui` (public, no secret)
- **RabbitMQ management**: guest / guest (port 15672)
- **EMQX dashboard**: admin / public (port 18083)

## Stop / Remove

```shell
./setup.sh --down       # stop and remove containers
./setup.sh --down-v     # also remove volumes (data)

# Or directly:
docker compose down
docker compose down -v
```
