# Deployment Guide

## Prerequisites

The following tools are required:

* Kubernetes cluster
* kubectl
* Helm 3
* Docker (or compatible container runtime)
* SSH access to cluster nodes (only required for local-path storage and offline image workflows)
* Synced node clocks — see [NODE-TIME-SYNC.md](../NODE-TIME-SYNC.md). Wrong node time = wrong times in Confluence (page history, comments), regardless of Confluence's timezone setting.

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

# Jira chart already creates the "atlassian" namespace; set true only when installing Confluence alone
createNamespace: false

# Node that owns the persistent storage.
# Replace with your own worker or control-plane node name.
k8s:
  boundWorker: my-worker-node

confluence:
  image: atlassian/confluence:latest

  service:
    type: NodePort
    port: 8090
    nodePort: 30082

  persistence:
    size: 20Gi

  jvm:
    minMemory: 1024m
    maxMemory: 2048m

postgres:
  image: postgres:16

  persistence:
    size: 20Gi

secret:
  postgresUser: confluence
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
sudo mkdir -p /data/k8s/confluence-data
sudo mkdir -p /data/k8s/postgres-confluence-data
sudo mkdir -p /data/confluence-agent

sudo chmod -R 777 /data
```

Adjust paths if your chart uses different storage locations.

---

## Build Confluence Agent Bootstrap Image

Build the bootstrap image locally:

```bash
docker build -f Dockerfile.agent -t confluence-agent-bootstrap:1.0 .
```

Verify:

```bash
docker images
```

---

## Transfer Bootstrap Image to Kubernetes Nodes

Export image:

```bash
docker save confluence-agent-bootstrap:1.0 -o confluence-agent-bootstrap.tar
```

Copy to node:

```bash
scp confluence-agent-bootstrap.tar user@worker-node:/tmp/
```

SSH into node:

```bash
ssh user@worker-node
```

Import image into containerd:

```bash
sudo ctr -n k8s.io images import /tmp/confluence-agent-bootstrap.tar
```

Verify:

```bash
sudo crictl images | grep confluence-agent-bootstrap
```

Expected:

```text
confluence-agent-bootstrap    1.0
```

---

## Optional: Offline Image Preparation

If internet access is unreliable, preload images.

Pull locally:

```bash
docker pull atlassian/confluence:latest
docker pull postgres:16
```

Export:

```bash
docker save atlassian/confluence:latest -o confluence.tar
docker save postgres:16 -o postgres16.tar
```

Copy:

```bash
scp confluence.tar user@worker-node:/tmp/
scp postgres16.tar user@worker-node:/tmp/
```

Import:

```bash
sudo ctr -n k8s.io images import /tmp/confluence.tar
sudo ctr -n k8s.io images import /tmp/postgres16.tar
```

Verify:

```bash
sudo crictl images
```

---

## IPv6 Considerations

See [Jira guide - IPv6 Considerations](../jira/README.md#ipv6-considerations).

---

## VirtualBox NAT Port Forwarding

When the cluster runs on VirtualBox VMs and NodePorts are reached through `127.0.0.1`,
add a forward for the Confluence NodePort on the same VM that forwards Jira (`30081`):

```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" controlvm "Ubuntu Server - K8s" natpf1 "k8s-confluence-30082,tcp,,30082,,30082"
```

Verify:

```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" showvminfo "Ubuntu Server - K8s" --machinereadable | findstr Forwarding
```

Expected:

```text
Forwarding(0)="k8s-jira-30081,tcp,,30081,,30081"
Forwarding(1)="k8s-confluence-30082,tcp,,30082,,30082"
```

---

## Deploy Helm Chart

Initial installation (Jira already created the `atlassian` namespace):

```bash
helm install confluence . \
  --namespace atlassian
```
OR (Standalone, without Jira)
```bash
helm install confluence . \
  --namespace atlassian \
  --set createNamespace=true
```

Verify:

```bash
helm list -n atlassian
```

---

## Upgrade Existing Installation

Whenever templates or values change:

```bash
helm upgrade confluence . \
  --namespace atlassian
```

Force recreation if required:

```bash
helm upgrade confluence . \
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
confluence-xxxxx             Running
postgres-confluence-xxxxx    Running
```

Check services:

```bash
kubectl get svc -n atlassian
```

Example:

```text
confluence      NodePort   8090:30082/TCP
db-confluence   ClusterIP  5432/TCP
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

## Verify Confluence Startup

Monitor Confluence logs:

```bash
kubectl logs -f deployment/confluence -n atlassian
```

Successful startup contains:

```text
org.apache.catalina.startup.Catalina.start Server startup in [xxxxx] milliseconds
```

---

## Access Confluence

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
http://<node-ip>:30082
```

Example:

```text
http://192.168.56.102:30082
OR (VirtualBox NAT forward)
http://127.0.0.1:30082
```

You should see the Confluence setup wizard.

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
helm uninstall confluence -n atlassian
```


# Execute Command In a Pod

When Pods get ready:

```bash
kubectl get pods -n atlassian
NAME                                   READY   STATUS    RESTARTS   AGE
confluence-6d9f8c7b5d-x2k4p            1/1     Running   0          5m
postgres-confluence-7b8c9d6f4-q9w8e    1/1     Running   0          5m
```

run following command:
```bash
kubectl exec <pod-name> -n atlassian -- <Command>
# Example:
kubectl exec confluence-6d9f8c7b5d-x2k4p -n atlassian -- java -jar example.jar ...
```
