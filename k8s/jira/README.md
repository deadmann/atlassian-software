# Deployment Guide

## Prerequisites

The following tools are required:

* Kubernetes cluster
* kubectl
* Helm 3
* Docker (or compatible container runtime)
* SSH access to cluster nodes (only required for local-path storage and offline image workflows)

Verify access:

```bash
kubectl get nodes
helm version
docker version
```

---

## Configure Values

Edit `values.yaml`.

Example:

```yaml
namespace: atlassian

# Node that owns the persistent storage.
# Replace with your own worker or control-plane node name.
k8s:
  boundWorker: my-worker-node

jira:
  image: atlassian/jira-software:latest

  service:
    type: NodePort
    port: 8080
    nodePort: 30081

  persistence:
    size: 20Gi

  jvm:
    minMemory: 512m
    maxMemory: 2048m

postgres:
  image: postgres

  persistence:
    size: 20Gi

secret:
  postgresUser: jira
  postgresPassword: ChangeMe
```

To find a valid node name:

```bash
kubectl get nodes
```

Example output:

```text
NAME
controlplane
worker1
worker2
```

Use one of those names as `boundWorker`.

---

## Create Storage Directories

Persistent storage must exist on the node specified by `k8s.boundWorker`.

SSH to that node:

```bash
ssh user@worker-node
```

Create storage directories:

```bash
sudo mkdir -p /data/jira
sudo mkdir -p /data/postgres
sudo mkdir -p /data/jira-agent

sudo chmod -R 777 /data
```

Adjust paths if your chart uses different storage locations.

---

## Build Jira Agent Bootstrap Image

Build the bootstrap image locally:

```bash
docker build -t jira-agent-bootstrap:1.0 .
```

Verify:

```bash
docker images
```

---

## Transfer Bootstrap Image to Kubernetes Nodes

Export image:

```bash
docker save jira-agent-bootstrap:1.0 -o jira-agent-bootstrap.tar
```

Copy to node:

```bash
scp jira-agent-bootstrap.tar user@worker-node:/tmp/
```

SSH into node:

```bash
ssh user@worker-node
```

Import image into containerd:

```bash
sudo ctr -n k8s.io images import /tmp/jira-agent-bootstrap.tar
```

Verify:

```bash
sudo crictl images | grep jira-agent-bootstrap
```

Expected:

```text
jira-agent-bootstrap    1.0
```

---

## Optional: Offline Image Preparation

If internet access is unreliable, preload images.

Pull locally:

```bash
docker pull atlassian/jira-software:latest
docker pull postgres:latest
```

Export:

```bash
docker save atlassian/jira-software:latest -o jira.tar
docker save postgres:latest -o postgres.tar
```

Copy:

```bash
scp jira.tar user@worker-node:/tmp/
scp postgres.tar user@worker-node:/tmp/
```

Import:

```bash
sudo ctr -n k8s.io images import /tmp/jira.tar
sudo ctr -n k8s.io images import /tmp/postgres.tar
```

Verify:

```bash
sudo crictl images
```

---

## IPv6 Considerations

Some environments experience image pull failures caused by broken IPv6 connectivity.

Symptoms include:

```text
connect: connection refused
```

against IPv6 addresses.

Disable IPv6 if necessary:

```bash
sudo tee /etc/sysctl.d/99-disable-ipv6.conf <<EOF
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
EOF
```

Apply:

```bash
sudo sysctl --system
```

Verify:

```bash
cat /proc/sys/net/ipv6/conf/all/disable_ipv6
```

Expected:

```text
1
```

Reboot if required.

---

## Deploy Helm Chart

Initial installation:

```bash
helm install jira . \
  --namespace atlassian \
  --create-namespace
```
OR (Since we add namespace to the config)
```bash
kubectl create namespace atlassian
helm install jira .
```

Verify:

```bash
helm list -n atlassian
```

---

## Upgrade Existing Installation

Whenever templates or values change:

```bash
helm upgrade jira . \
  --namespace atlassian
```

Force recreation if required:

```bash
helm upgrade jira . \
  --namespace atlassian \
  --force
```

---

## Monitor Deployment

Check pods:

```bash
kubectl get pods -n atlassian
```

Expected:

```text
jira-xxxxx             Running
postgres-jira-xxxxx    Running
```

Check services:

```bash
kubectl get svc -n atlassian
```

Example:

```text
jira      NodePort   8080:30081/TCP
db-jira   ClusterIP  5432/TCP
```

---

## Troubleshooting Image Pull Failures

Check pod status:

```bash
kubectl describe pod <pod-name> -n atlassian
```

Common errors:

```text
ImagePullBackOff
ErrImagePull
```

Check image availability:

```bash
sudo crictl images
```

Check logs:

```bash
kubectl logs <pod-name> -n atlassian
```

Check events:

```bash
kubectl get events -n atlassian \
  --sort-by=.metadata.creationTimestamp
```

---

## Verify Jira Startup

Monitor Jira logs:

```bash
kubectl logs -f deployment/jira -n atlassian
```

Successful startup contains:

```text
Startup is complete. Jira is ready to serve.
```

Example:

```text
INFO [LauncherContextListener]
Startup is complete. Jira is ready to serve.
```

---

## Access Jira

Determine node IP:

```bash
kubectl get nodes -o wide
```

Example:

```text
192.168.56.102
```

Open:

```text
http://<node-ip>:30081
```

Example:

```text
http://192.168.56.102:30081
```

You should see the Jira setup wizard.

---

## Useful Commands

List pods:

```bash
kubectl get pods -n atlassian
```

Describe pod:

```bash
kubectl describe pod <pod-name> -n atlassian
```

View logs:

```bash
kubectl logs -f <pod-name> -n atlassian
```

List PVCs:

```bash
kubectl get pvc -n atlassian
```

List services:

```bash
kubectl get svc -n atlassian
```

Uninstall:

```bash
helm uninstall jira -n atlassian
```


# Execute Command In a Pod

When Pods get ready:

```bash
kubectl get pods -n atlassian
NAME                             READY   STATUS    RESTARTS      AGE
jira-5ffcf85d98-dxgkq            1/1     Running   3 (93s ago)   15h
postgres-jira-557bb875bc-ndn6c   1/1     Running   4 (93s ago)   15h
```

run following command:
```bash
kubectl exec <pod-name> -n atlassian -- <Command>
# Example:
kubectl exec jira-5ffcf85d98-dxgkq -n atlassian -- java -jar example.jar ...
```






<!-- # Jira Helm chart

## HELM Result
```shell
helm template jira . > output.yaml
```


## Switch context
```shell
kubectl config use-context homelab
```


## Validate chart changes:

```shell
helm lint .

helm template jira .
```

## Create namespace

- First create the namespace
```shell
kubectl create namespace atlassian

kubectl get ns
```

> NAME                 STATUS   AGE
> atlassian            Active   28s

## Install

```shell
helm install jira . -n atlassian
```

## Upgrade

```shell
helm upgrade jira . -n atlassian
```

## Debug rendered output size

to view the template result and get file size:
```shell
helm template jira . > output.yaml
(Get-Item .\output.yaml).Length
```


-------------------------

We mount the file using Helm .Files.Get (THIS is the Helm-native solution)
 -->
