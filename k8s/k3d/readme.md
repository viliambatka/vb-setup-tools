# k3d

draft - VIP (work in progress)

https://github.com/k3d-io/k3d/releases

for windows, use the following command to start k3d with data persistence

https://github.com/k3d-io/k3d/releases/download/v5.8.3/k3d-windows-amd64.exe

C:\Users\<username>\Downloads\k3d-windows-amd64.exe

```powershell
# Create first cluster on port 16443 (as you have documented)
k3d cluster create mycluster1 --volume C:\k3d-data1:/var/lib/rancher/k3s/storage --api-port 16443

# Create second cluster on different port
k3d cluster create mycluster2 --volume C:\k3d-data2:/var/lib/rancher/k3s/storage --api-port 16543

# Create third cluster
k3d cluster create mycluster3 --volume C:\k3d-data3:/var/lib/rancher/k3s/storage --api-port 16643 --servers 1 --agents 3

```

## uninstall

```bash
k3d cluster delete mycluster1
k3d cluster delete mycluster2   
k3d cluster delete mycluster3
```
