# Rancher K8s manager

reference URL: https://www.rancher.com/quick-start

## install

```bash
# install rancher (docker, no persistent volume)
docker run -d --name rancher --privileged -p 8980:80 -p 6943:443 rancher/rancher

kubectl get pods --all-namespaces

# the volume mount on Windows caused errors, so it isn't used here:
#   -v c:\k3s-rancher:/var/lib/rancher

docker logs <container-id> 2>&1 | grep "Bootstrap Password:"

# alternate ports
docker run -d --name rancher -p 8090:80 -p 9443:443 rancher/rancher

# install rancher with helm
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
helm repo update
helm install rancher rancher-latest/rancher \
  --namespace cattle-system \
  --create-namespace
```

## manage contexts

```bash
# List available contexts
kubectl config get-contexts

# Switch to specific cluster
kubectl config use-context k3d-cluster1
kubectl config use-context k3d-cluster2
kubectl config use-context k3d-cluster3

kubectl config use-context k3s-cluster1
kubectl config use-context k3s-cluster2

# if new clusters are not in the context list, add them to the kubeconfig file
# on Windows, run this from WSL:
wsl cp /mnt/c/path/to/kubeconfig-cluster1.yaml ~/.kube/config
wsl cp /mnt/c/path/to/kubeconfig-cluster2.yaml ~/.kube/config
```

## register clusters

```bash
# get the kubeconfig file for each cluster and save it to a local file
docker cp k3s-cluster1:/etc/rancher/k3s/k3s.yaml ./kubeconfig-cluster1.yaml
docker cp k3s-cluster2:/etc/rancher/k3s/k3s.yaml ./kubeconfig-cluster2.yaml

# Merge or set individual contexts
kubectl config --kubeconfig=.\kubeconfig-cluster1.yaml config rename-context default cluster1
kubectl config --kubeconfig=.\kubeconfig-cluster2.yaml config rename-context default cluster2

# register the clusters in the Rancher UI, or via the Rancher CLI if installed:
rancher cluster create --name cluster1 --kubeconfig ./kubeconfig-cluster1.yaml
rancher cluster create --name cluster2 --kubeconfig ./kubeconfig-cluster2.yaml

# the Rancher CLI is only available inside WSL on this setup — from Windows, run it via wsl:
wsl rancher cluster create --name cluster1 --kubeconfig /mnt/c/path/to/kubeconfig-cluster1.yaml
wsl rancher cluster create --name cluster2 --kubeconfig /mnt/c/path/to/kubeconfig-cluster2.yaml
```

## uninstall

```bash
helm uninstall rancher -n cattle-system
```
