[CmdletBinding()]
param(
    [switch]$cleanup,
	[switch]$force
)

# Get kubeconfig files from containers (Windows paths)
function add-cluster-to-kubeconfig {
    param (
        [int]$clusterId,
        [switch]$cleanup
    )

    $clustername = "k3s-cluster$clusterId"
    $subnet = "172.2$clusterId.0.0/16"

    # check if bin folder exists, if not create it
    if (-not (Test-Path -Path .\bin)) {
        New-Item -ItemType Directory -Path .\bin
    }

    # check if network exists with the name k3s-net$clusterId
    $networkExists = docker network ls | Select-String -Pattern "k3s-net$clusterId"
    if (-not $cleanup) {

        if ($networkExists) {
            Write-Debug "Network k3s-net$clusterId already exists."
        } else {
            docker network create k3s-net$clusterId --subnet=$subnet
        }

        # Calculate unique ports for each cluster
        $apiPort = 16000 + ($clusterId * 100) + 43  # 16143 for cluster1, 16243 for cluster2
        $webPort = 16000 + ($clusterId * 100) + 80  # 16180 for cluster1, 16280 for cluster2

        # check if container exists with the name $clustername
        $containerExists = docker ps -a | Select-String -Pattern $clustername
        if (-not $containerExists) {
            
            docker run -d --name $clustername `
                --privileged `
                --network "k3s-net$clusterId" `
                -p "${apiPort}:6443" `
                -p "${webPort}:8080" `
                -v "C:\${clustername}:/var/lib/rancher/k3s" `
                rancher/k3s:latest server
            
            Start-Sleep -Seconds 10 # wait for cluster to start up
        }

        $kubeconfigPath = ".\bin\kubeconfig-$clustername.yaml"
        docker cp ${clustername}:/etc/rancher/k3s/k3s.yaml $kubeconfigPath

        # overwrite current context config  
        $kubeconfigPath = ".\bin\kubeconfig-$clustername.yaml"
        $user = "admin@$clustername"
        $ctx = $clustername

        # Extract client cert/key and cluster CA from the existing kubeconfig
        $crt = kubectl config --kubeconfig=$kubeconfigPath view --raw -o jsonpath="{.users[0].user.client-certificate-data}"
        $key = kubectl config --kubeconfig=$kubeconfigPath view --raw -o jsonpath="{.users[0].user.client-key-data}"
        $ca = kubectl config --kubeconfig=$kubeconfigPath view --raw -o jsonpath="{.clusters[0].cluster.certificate-authority-data}"

        # update default ~/.kube/config file to include the new cluster context (optional)
        $defaultKube = "$env:USERPROFILE\.kube\config"
        $crtPath = Join-Path $env:USERPROFILE ".kube\$clustername-client.crt"
        $keyPath = Join-Path $env:USERPROFILE ".kube\$clustername-client.key"
        $caPath = Join-Path $env:USERPROFILE ".kube\$clustername-ca.crt"

        [IO.File]::WriteAllBytes($crtPath, [Convert]::FromBase64String($crt))
        [IO.File]::WriteAllBytes($keyPath, [Convert]::FromBase64String($key))
        [IO.File]::WriteAllBytes($caPath, [Convert]::FromBase64String($ca))

        kubectl config --kubeconfig $defaultKube set-cluster $clustername --server="https://localhost:${apiPort}" --certificate-authority=$caPath --embed-certs=true
        kubectl config --kubeconfig $defaultKube set-credentials $user --client-certificate=$crtPath --client-key=$keyPath --embed-certs=true
        kubectl config --kubeconfig $defaultKube set-context $clustername --cluster=$clustername --user=$user

        # remove the temporary exported certs
        Remove-Item -Path $crtPath, $keyPath, $caPath -Force

        # remove exported cluster kubeconfig file
        Remove-Item -Path $kubeconfigPath -Force

    } else {       
            Write-Host "Cleaning up existing container $clustername and network k3s-net$clusterId" -ForegroundColor Yellow
            docker rm -f $clustername
            docker network rm k3s-net$clusterId

            # remove cluster context from default kubeconfig
            $defaultKube = "$env:USERPROFILE\.kube\config"  
            kubectl config --kubeconfig $defaultKube delete-context $clustername
            kubectl config --kubeconfig $defaultKube delete-cluster $clustername
            kubectl config --kubeconfig $defaultKube unset users.admin@$clustername
    }
}

# add the clusters to kubeconfig file (Windows paths) 
add-cluster-to-kubeconfig -clusterId 1 -cleanup:$cleanup
add-cluster-to-kubeconfig -clusterId 2 -cleanup:$cleanup

# cluster config files are in windows path 
docker network ls
docker container ls

kubectl --context k3s-cluster1 get pods -A
kubectl --context k3s-cluster2 get pods -A
