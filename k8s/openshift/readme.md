# OpenShift

## Prerequisites

- download and install the OpenShift CLI (oc) from the official OpenShift website: https://console.redhat.com/openshift/create/local

[https://console.redhat.com/openshift/create/local](https://console.redhat.com/openshift/create/local)

NOTE:

Need to stop the docker desktop on the same machine before starting OpenShift, otherwise, there will be a conflict between the two, because they both use the same port 6443.

## install

```bash
# install OpenShift with data persistence
# for windows, use the following command to start OpenShift with data persistence
crc cleanup
crc setup --enable-experimental-features
crc start --pull-secret-file C:\Users\you\Downloads\pull-secret.txt
crc start -c 16 -m 32000 -d 64

# for linux, use the following command to start OpenShift with data persistence
crc setup
crc start --pull-secret-file path/to/pull-secret.txt
```

## uninstall

```bash
crc stop
crc delete
```

## trouble shooting- failer ot add user to the group

Hyper-V Administrator group is required to run OpenShift on Windows, if you encounter the error "Failed to add user to the group".


in localised versions of Windows, the group name may be different, for example, in Czech/Slovak Windows, the group name is "Správci technologie Hyper-V". You can use the following command to add your user to the Hyper-V Administrator group.

```bash
# open PowerShell as administrator and run the following command to add your user to the Hyper-V Administrator group
# Add user to the Hyper-V Administrator group
# For English Windows:
Add-LocalGroupMember -Group "Hyper-V Administrators" -Member "$env:USERNAME"

# For Czech/Slovak Windows (or other localized versions):
Add-LocalGroupMember -Group "Správci technologie Hyper-V" -Member "$env:USERNAME"

# Rename the group name in the command above according to your localized version of Windows if necessary.

```


