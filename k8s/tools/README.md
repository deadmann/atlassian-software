# Node Tools

Helpers that run **on the Kubernetes nodes** (not on Windows).

| Tool | What it does |
|------|--------------|
| [`pull-progress.sh`](pull-progress.sh) | Shows image downloads in progress: image name, MiB done / total, %, speed, ETA, stalled detection |

---

## pull-progress.sh

On a slow connection a big image (e.g. `atlassian/confluence` ~1.1 GiB, one layer alone ~965 MiB) can take hours.
Kubernetes only shows `ContainerCreating` / `ImagePullBackOff`; this script shows the actual bytes.

### Install on a node (once)

From the repo root on Windows:

```powershell
scp k8s/tools/pull-progress.sh vboxuser@192.168.56.102:~
```

On the node:

```bash
sudo install -m 755 ~/pull-progress.sh /usr/local/bin/pull-progress
```

Repeat for every node that pulls images (`192.168.56.101` for the control plane).

> If the script fails with `$'\r': command not found`, it was copied with Windows line endings.
> Fix on the node: `sed -i 's/\r$//' ~/pull-progress.sh` and install again.
> (`.gitattributes` in the repo root keeps `*.sh` as LF in git to prevent this.)

### Usage

One snapshot (measures speed over 3 seconds):

```bash
sudo pull-progress
```

Live view, refresh every 10 seconds (Ctrl+C to stop):

```bash
sudo pull-progress -w 10
```

More accurate speed on a jumpy connection (measure over 10 seconds):

```bash
sudo pull-progress -s 10
```

### Example output

```text
2026-10-11 17:00:28  2 layer(s) downloading

IMAGE                        LAYER          PROGRESS                                           %      SPEED      ETA  STATUS
atlassian/confluence         5c4a62dc1487   818.3 MiB / 965.5 MiB  [################----]    84%   2.9MiB/s      51s  downloading
redis                        a1b2c3d4e5f6   1.0 MiB / 28.6 MiB     [--------------------]     3%   0.0MiB/s        -  STALLED 5m02s

In-flight total: 819.3 MiB / 994.1 MiB
```

| Column | Meaning |
|--------|---------|
| IMAGE | Image the layer belongs to. `unknown` until containerd has fetched that image's manifest (first seconds of a pull) |
| LAYER | First 12 characters of the layer digest |
| PROGRESS / % | Bytes received for this layer / layer size (compressed) |
| SPEED / ETA | Measured during the sample window; `-` when nothing arrived |
| STATUS | `downloading`, `waiting` (no bytes this sample), `STALLED <time>` (no bytes for 60s+) |

When nothing is downloading, the script says so and lists what that can mean:

```text
2026-10-11 17:30:02  Nothing is downloading on this node right now.

  This means one of:
    - all pulls FINISHED      -> pod shows Running / ContainerCreating briefly
    - a pull FAILED, retrying -> pod shows ErrImagePull / ImagePullBackOff (retries within 5 min)
    - no pull was started     -> image already on the node, or pod scheduled elsewhere
```

The script never prints a per-layer "done" list. `ctr content ls | grep <digest>` is **not** a reliable
"downloaded" check, because image manifests reference layer digests in their labels and match even when the
layer itself is still missing. To confirm an image is complete, use `sudo crictl images` or the pod events.

### Notes

* Only **in-flight** layers are listed. Finished layers are moved out of `ingest/` and no longer shown.
* If the connection resets, containerd **discards the partial layer** and the next retry starts that layer from 0.
  Finished layers are kept.
* `In-flight total` covers only the layers currently downloading, not the whole image.
  Get an image's full size from Docker Hub: `https://hub.docker.com/r/<repo>/tags`.

---

## Related commands

From Windows, which pods are waiting on images:

```powershell
kubectl get pods -A | Select-String "ContainerCreating|ImagePull|ErrImage"
```

Why a pull failed (DNS, connection reset, not found, ...):

```powershell
kubectl describe pod <pod-name> -n atlassian
```

Images already on the node:

```bash
sudo crictl images
```

Pre-pull an image on the node before deploying (same progress shows up in `pull-progress`):

```bash
sudo crictl pull redis:7
```

Restart a pull right away instead of waiting for the back-off (only the pod, the Deployment recreates it):

```powershell
kubectl delete pod <pod-name> -n atlassian
```

For connections too unstable to ever finish a large layer, use the offline route
(`docker pull` + `docker save` on Windows, `scp`, `ctr -n k8s.io images import`) described in
[jira/README.md](../jira/README.md#optional-offline-image-preparation).
