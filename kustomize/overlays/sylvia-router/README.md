Sylvia-IoT Core in Minikube
===========================

This documents describes how to run Sylvia-IoT core modules (auth, broker, coremgr, data) in Minikube.

### Notes

- This deployment is workable but is not tuned.
- Currently not support `sylvia-router`.

### Install kubectl, kustomize, minikube

```shell
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"  | bash
sudo install kubectl kustomize minikube /usr/local/bin/
kubectl completion bash | sudo dd of=/etc/bash_completion.d/kubectl
kustomize completion bash | sudo dd of=/etc/bash_completion.d/kustomize
minikube completion bash | sudo dd of=/etc/bash_completion.d/minikube
```

### Run minikube

In this document we use a directory as the storage for MongoDB and RabbitMQ (EMQX has some problems).

```shell
minikube start \
    --driver=docker \
    --kubernetes-version="v1.35.0" \
    --mount \
    --mount-string="$HOME/minikube:/db" \
    --network=host
```

### Deploy Sylvia-IoT

Go to the kustomize directory and run the following command to deploy Sylvia-IoT:

```shell
kustomize build overlays/sylvia-router | kubectl apply -f -
```

### Use all-in-one core Pods

You can modify `kustomization.yaml` as following to use `sylvia-iot-core`:

```yaml
resources:
    - ./emqx
    - ./mongodb
    - ./rabbitmq
    - ./redis
    #- ../../base/sylvia-iot-auth
    #- ../../base/sylvia-iot-broker
    - ../../base/sylvia-iot-core
    #- ../../base/sylvia-iot-coremgr
    #- ../../base/sylvia-iot-data
    - ../../base/sylvia-iot-simple-ui
```

And then modify `sylvia-iot-simple-ui/nginx.conf`:

```
#location /auth {
#    proxy_pass  http://sylvia-iot-auth:1080;
#}
#
#location /broker {
#    proxy_pass  http://sylvia-iot-broker:1080;
#}
#
#location /coremgr {
#    proxy_pass  http://sylvia-iot-coremgr:1080;
#}
#
#location /data {
#    proxy_pass  http://sylvia-iot-data:1080;
#}

location /auth {
    proxy_pass  http://sylvia-iot-core:1080;
}

location /broker {
    proxy_pass  http://sylvia-iot-core:1080;
}

location /coremgr {
    proxy_pass  http://sylvia-iot-core:1080;
}

location /data {
    proxy_pass  http://sylvia-iot-core:1080;
}
```

Apply the all-in-one overlay:

```shell
kustomize build overlays/sylvia-router | kubectl apply -f -
```

### Add users and clients to operate the Sylvia-IoT core

Entering MongoDB and use mongosh to add users and clients:

```shell
kubectl exec -it mongodb-0 -- mongosh
```

In the MongoDB shell, enter the following commands:

```
use sylvia-iot-auth

db.user.insertOne({
    userId: 'admin',
    account: 'admin',
    email: 'admin',
    createdAt: new Date(),
    modifiedAt: new Date(),
    verifiedAt: new Date(),
    expiredAt: null,
    disabledAt: null,
    roles: {"admin":true,"dev":false},
    password: '27258772d876ffcef7ca2c75d6f4e6bcd81c203bd3e93c0791c736e5a2df4afa',
    salt: 'YsBsou2O',
    name: 'Admin',
    info: {}
})
db.client.insertOne({
    clientId: 'sylvia-iot-simple-ui',
    createdAt: new Date(),
    modifiedAt: new Date(),
    clientSecret: null,
    redirectUris: ['http://localhost/#/sylvia-core/redirect'],
    scopes: [],
    userId: 'admin',
    name: 'SimpleUI',
    imageUrl: null
})
```

Back to the host, enter kubectl to forward port 80:

```shell
sudo cp -r ~/.kube /root/
sudo kubectl port-forward deploy/sylvia-iot-simple-ui --address=0.0.0.0 80:80 > /dev/null
```

Use the browser to open `http://localhost`, then use **admin** and **admin** as user name and password to log-in the Sylvia-IoT simple UI.

You may receive 404 warning messages because currently we don't support **sylvia-router** for Kubernetes.
