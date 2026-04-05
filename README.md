Sylvia-IoT Deployments
======================

Deployment toolkit for the [Sylvia-IoT](https://github.com/woofdogtw/sylvia-iot-core) IoT platform. Four deployment methods for different environments:

| Method | Use Case | Config |
|--------|----------|--------|
| [scripts/](scripts/) | Local dev/test with native binaries (SQLite or MongoDB) | CLI options |
| [systemd/](systemd/) | Production on Ubuntu/Debian with systemd (supports `sylvia-router`) | CLI options |
| [compose/](compose/) | Docker Compose for NAS, Portainer, or any Docker host | `.env` file |
| [kustomize/](kustomize/) | Kubernetes with Kustomize (k3s, minikube, EKS, GKE, etc.) | `settings.env` file |

### Notes

- **`sylvia-router`** manages host network interfaces and is only supported in `scripts/` and `systemd/`.
- `compose/` and `kustomize/` deploy `sylvia-iot-core` (auth + broker + coremgr + data as one process).
- All methods automatically initialize platform data (admin user, OAuth2 clients, demo unit/network/application).

### Default Credentials

- **Admin**: admin / admin
- **RabbitMQ management**: guest / guest
- **EMQX dashboard**: admin / public
