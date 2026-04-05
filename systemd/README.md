Sylvia-IoT Deployment with systemd
===================================

Deploy Sylvia-IoT as systemd services on Ubuntu/Debian. Infrastructure (MongoDB, Redis, RabbitMQ, EMQX) runs in Docker containers; Sylvia-IoT binaries run natively.

This is the recommended approach for `sylvia-router`, which manages host network interfaces via nmcli and cannot run inside containers.

## Quick Start

```shell
# Install core (auth + broker + coremgr + data)
sudo ./install.sh

# Install router (core + network management)
sudo ./install.sh --bin router

# With optional services and GUI
sudo ./install.sh --bin router --with lora-ifroglab,app-demo --gui

# Custom hostname for GUI (e.g. access from other devices)
sudo ./install.sh --bin router --gui --host router.sylvia-iot

# Install dev-demo independently (e.g. on Raspberry Pi)
sudo ./install-dev-demo.sh
```

## install.sh Options

| Option | Default | Description |
|--------|---------|-------------|
| `--bin` | `core` | Main binary (`sylvia-iot-core` or `sylvia-router`) |
| `--with` | — | Comma-separated optional services: `lora-ifroglab`, `app-demo` |
| `--gui` | — | Install GUI and plugins |
| `--host` | `localhost` | Hostname for GUI `config.js` URLs (e.g. `router.sylvia-iot`) |
| `--uninstall` | — | Remove all installed components |

## File Locations

| Path | Content |
|------|---------|
| `/usr/local/bin/` | Binaries (sylvia-iot-core, sylvia-router, etc.) |
| `/etc/sylvia-iot/` | Config files (config.json5, docker-compose.yaml, certificates/) |
| `/usr/local/share/sylvia-iot/static/` | GUI web app |
| `/var/lib/sylvia-iot/` | Runtime data |

## Services

| Service | Description |
|---------|-------------|
| `sylvia-iot-infra` | Docker infra (MongoDB, Redis, RabbitMQ, EMQX) |
| `sylvia-iot-core` | Core service (auth+broker+coremgr+data) |
| `sylvia-router` | Router service (core + network management) |
| `lora-ifroglab` | LoRa iFrogLab gateway (optional) |
| `app-demo` | Application demo (optional) |
| `dev-demo` | IoT device demo — standalone, install via `install-dev-demo.sh` |

## Management

```shell
# Check service status
systemctl status sylvia-iot-core
systemctl status sylvia-iot-infra

# View logs
journalctl -u sylvia-iot-core -f
journalctl -u sylvia-router -f

# Restart
sudo systemctl restart sylvia-iot-core

# Stop all
sudo systemctl stop sylvia-iot-core sylvia-iot-infra
```

## Credentials

- **Admin**: admin / admin
- **RabbitMQ management**: guest / guest (port 15672)
- **EMQX dashboard**: admin / public (port 18083)

## Uninstall

```shell
sudo ./install.sh --uninstall
```

This removes binaries, config, services, and data. Docker volumes are not removed — run `docker volume prune` if needed.
