Sylvia-IoT Deployment with Kustomize
====================================

Kubernetes deployment for Sylvia-IoT core modules (auth, broker, coremgr, data) using Kustomize.

## Structure

```
kustomize/
├── base/                           # Shared base resources (no volumes)
│   ├── emqx/                       # EMQX MQTT broker
│   ├── mongodb/                    # MongoDB database
│   ├── mongodb-seed/               # MongoDB seed data (Job)
│   ├── platform-init/              # Platform init: demo unit/network/application (Job)
│   ├── rabbitmq/                   # RabbitMQ message broker
│   ├── redis/                      # Redis cache
│   ├── sylvia-iot-auth/            # Auth module
│   ├── sylvia-iot-broker/          # Broker module
│   ├── sylvia-iot-core/            # All-in-one core (auth+broker+coremgr+data)
│   ├── sylvia-iot-coremgr/         # Core manager module
│   ├── sylvia-iot-data/            # Data module
│   └── sylvia-iot-gui/             # Web GUI
└── overlays/
    └── sylvia-iot-core/            # Production-ready overlay
```

## Quick Start

```shell
cd kustomize/overlays/sylvia-iot-core
./install.sh
```

Works with any Kubernetes cluster: k3s, minikube, EKS, GKE, etc.

See [overlays/sylvia-iot-core/README.md](overlays/sylvia-iot-core/README.md) for details.

## Customization

- **Settings**: Edit `settings.env` to configure hostname, port, and plugins.
- **Storage**: Edit `storage/*.yaml` to set a specific `storageClassName` (default: cluster default).
- **Ingress**: Uncomment `ingress.yaml` in `kustomization.yaml` for clusters with an Ingress controller (k3s Traefik, nginx-ingress, etc.).
- **All-in-one**: Uncomment `sylvia-iot-core` and comment out individual modules in `kustomization.yaml`.

## Notes

- `sylvia-router` is **not** suitable for Kubernetes (it manages host network interfaces via nmcli).
- MongoDB seed data and platform init are applied automatically via Kubernetes Jobs.
- For Ansible/CI: edit `settings.env` and run `kubectl apply -k .` directly -- no install.sh needed.

## Credentials

- **Admin user**: admin / admin
- **OAuth2 client**: `sylvia-iot-gui` (public, no secret)
