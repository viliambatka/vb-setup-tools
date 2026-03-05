# Ranger K8s manager

reference URL: https://www.rancher.com/quick-start 

## install

```bash
# install ranger with data persistence



docker run -d --name rancher --privileged -p 8980:80 -p 6943:443 rancher/rancher

# the volume on windows coused to errors and not whatring "-v c:\k3s-rancher:/var/lib/rancher"


docker logs container-id 2>&1 | grep "Bootstrap Password:"

docker run -d --name rancher -p 8090:80 -p 9443:443  rancher/rancher

# install ranger with helm
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
helm repo update
helm install ranger rancher-latest/ranger \
  --namespace ranger-system \
  --create-namespace
```

```powershell
# First k3s cluster
docker run -d --name k3s-cluster1 `
  --privileged `
  -p 6443:6443 `
  -p 8180:8080 `
  -v C:\k3s-data1:/var/lib/rancher/k3s `
  rancher/k3s:latest server

# Second k3s cluster  
docker run -d --name k3s-cluster2 `
  --privileged `
  -p 6543:6443 `
  -p 8280:8080 `
  -v C:\k3s-data2:/var/lib/rancher/k3s `
  rancher/k3s:latest server

# List available contexts
kubectl config get-contexts

# Switch to specific cluster
kubectl config use-context k3d-mycluster1
kubectl config use-context k3d-mycluster2

```

## uninstall

```bash
helm uninstall ranger -n ranger-system
```

