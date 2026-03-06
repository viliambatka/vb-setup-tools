[CmdletBinding()]
param(
    [switch]$cleanup,
	[switch]$force
)

# download k3d windows binary if does not exists  from https://github.com/k3d-io/k3d/releases/download/v5.8.3/k3d-windows-amd64.exe
if (-not (Test-Path -Path ~/Downloads/k3d-windows-amd64.exe)) {
    Write-Host "Downloading k3d windows binary..." -ForegroundColor Green
    Invoke-WebRequest -Uri "https://github.com/k3d-io/k3d/releases/download/v5.8.3/k3d-windows-amd64.exe" -OutFile ~/Downloads/k3d-windows-amd64.exe
}

~/Downloads/k3d-windows-amd64.exe  cluster create cluster1 --volume C:\k3d-data1:/var/lib/rancher/k3s/storage --api-port 16443

# Create second cluster on different port
~/Downloads/k3d-windows-amd64.exe  cluster create cluster2 --volume C:\k3d-data2:/var/lib/rancher/k3s/storage --api-port 16543

# Create third cluster
~/Downloads/k3d-windows-amd64.exe  cluster create cluster3 --volume C:\k3d-data3:/var/lib/rancher/k3s/storage --api-port 16643 --servers 1 --agents 3

# cluster config files are in windows path 
docker network ls
docker container ls

kubectl --context k3d-cluster1 get pods -A
kubectl --context k3d-cluster2 get pods -A
kubectl --context k3d-cluster3 get pods -A
