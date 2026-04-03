# Ranger K8s manager

reference URL: https://www.rancher.com/quick-start 

## install

```bash
# install ranger with data persistence



docker run -d --name rancher --privileged -p 8980:80 -p 6943:443 rancher/rancher


 kubectl get pods --all-namespaces


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


# List available contexts
kubectl config get-contexts

# Switch to specific cluster
kubectl config use-context k3d-cluster1
kubectl config use-context k3d-cluster2
kubectl config use-context k3d-cluster3

kubectl config use-context k3s-cluster1
kubectl config use-context k3s-cluster2


# if new clusters are not in context list, you can use the following command to add the clusters to the kubeconfig file
# for windows, use the following command to add the clusters to the kubeconfig file 
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


# register the clusters to ranger
ranger cluster create --name cluster1 --kubeconfig ./kubeconfig-cluster1.yaml
ranger cluster create --name cluster2 --kubeconfig ./kubeconfig-cluster2.yaml

# on windows where is no ranger it is only in WSL you can use the following command to register the clusters to ranger  
wsl ranger cluster create --name cluster1 --kubeconfig /mnt/c/path/to/kubeconfig-cluster1.yaml
wsl ranger cluster create --name cluster2 --kubeconfig /mnt/c/path/to/kubeconfig-cluster2.yaml

```





## uninstall

```bash
helm uninstall ranger -n ranger-system
```



