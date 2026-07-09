# Docker Desktop

## Prerequisites

- download and install Docker Desktop from the official Docker website:
[https://www.docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop)

## install

```bash
# install docker desktop with data persistence
# for windows, use the following command to start docker desktop with data persistence
docker run -d --name docker-desktop --privileged -p 2375:2375 -v C:\docker-desktop-data:/var/lib/docker docker:latest   
# for linux, use the following command to start docker desktop with data persistence
docker run -d --name docker-desktop --privileged -p 2375:2375 -v /var/lib/docker:/var/lib/docker docker:latest
```

## uninstall

```bash
docker stop docker-desktop
docker rm docker-desktop
```
