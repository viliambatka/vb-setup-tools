# Ranger K8s manager

reference URL: https://www.rancher.com/quick-start 

## install

```bash
# install ranger with data persistence

docker run -d --name rancher --privileged -p 8080:80 -p 8443:443 -v G:\rancher-data:/var/lib/rancher rancher/rancher

docker logs container-id 2>&1 | grep "Bootstrap Password:"

docker run -d --name rancher -p 8080:80 -p 8443:443  rancher/rancher

# install ranger with helm
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
helm repo update
helm install ranger rancher-latest/ranger \
  --namespace ranger-system \
  --create-namespace
```

## uninstall

```bash
helm uninstall ranger -n ranger-system
```

