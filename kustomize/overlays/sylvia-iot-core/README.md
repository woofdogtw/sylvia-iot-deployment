Sylvia-IoT Core on Kubernetes
==============================

Deploy Sylvia-IoT core modules (auth, broker, coremgr, data) to any Kubernetes cluster.

### Notes

- `sylvia-router` is not supported in Kubernetes (it manages host network interfaces).
- Storage uses default StorageClass. Override in `storage/*.yaml` if needed.
- Ingress is optional. Uncomment `ingress.yaml` in `kustomization.yaml` to enable.

### Quick Start

**Declarative (recommended for Ansible / CI):**

Edit `settings.env` then apply directly:

```shell
kubectl apply -k .
kubectl wait --for=condition=ready pod -l app=sylvia-iot-gui --timeout=120s
```

**With install.sh:**

```shell
# Basic deploy
./install.sh

# With GUI plugins and custom hostname
./install.sh --with lora-ifroglab,app-demo --host k8s.example.com --port 8080
```

### Configuration

Edit `settings.env` to configure the deployment:

| Key | Default | Description |
|-----|---------|-------------|
| `GUI_HOST` | `localhost` | Hostname for GUI redirect URIs |
| `GUI_PORT` | `80` | Port for GUI redirect URIs |
| `INSTALL_PLUGINS` | (empty) | Plugins to install: `lora-ifroglab`, `app-demo` (comma-separated) |

### install.sh Options

| Option | Default | Description |
|--------|---------|-------------|
| `--with` | -- | Install GUI plugins (writes to `settings.env`) |
| `--host` | `localhost` | Hostname for GUI URLs (writes to `settings.env`) |
| `--port` | `80` | Port for GUI URLs (writes to `settings.env`) |
| `--uninstall` | -- | Remove all resources |

All options write to `settings.env` -- running `install.sh` without options uses the current values.

### Access the GUI

**With Ingress** (k3s Traefik, nginx-ingress, etc.):

Uncomment `ingress.yaml` in `kustomization.yaml`, then re-apply:

```shell
kubectl apply -k .
```

**Without Ingress** (port-forward):

```shell
kubectl port-forward deploy/sylvia-iot-gui --address=0.0.0.0 8080:80
```

Then open `http://localhost:8080/`. Match the port to `GUI_PORT` in `settings.env` for OAuth2 redirect to work.

### Use all-in-one core Pods

Edit `kustomization.yaml` to uncomment `sylvia-iot-core` and comment out individual modules:

```yaml
resources:
    #- ../../base/sylvia-iot-auth
    #- ../../base/sylvia-iot-broker
    - ../../base/sylvia-iot-core
    #- ../../base/sylvia-iot-coremgr
    #- ../../base/sylvia-iot-data
```

### Credentials

- **Admin**: admin / admin
- **OAuth2 client**: `sylvia-iot-gui` (public, no secret)

### Uninstall

```shell
./install.sh --uninstall
```
