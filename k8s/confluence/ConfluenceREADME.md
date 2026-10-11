Check confluence version:
```bash
kubectl exec -it <confluence-pod> -n atlassian -- sh -c "cat /opt/atlassian/confluence/confluence/META-INF/maven/com.atlassian.confluence/confluence-webapp/pom.properties"
```

If the path differs between versions, find it with:
```bash
kubectl exec -it <confluence-pod> -n atlassian -- sh -c "find /opt/atlassian/confluence -name pom.properties -path '*confluence-webapp*'"
```

## Fixing Confluence Certificate Error

Like Jira, recent Confluence versions validate Marketplace app signatures using certificates stored in Confluence Home. Currently: [Atlassian Page](https://confluence.atlassian.com/upm/updating-atlassian-certificates-bundles-1489470540.html)

Download the Atlassian CA bundle from Atlassian documentation.

Extract the archive locally. The extracted files should include:

```text
atlassian_mpac_root_ca_v1.crt
atlassian_mpac_intermediate_ca_v2.crt
```

Copy the certificates into Confluence's UPM truststore.

Using `kubectl cp`:

```powershell
kubectl cp atlassian_mpac_root_ca_v1.crt atlassian/<confluence-pod>:/var/atlassian/application-data/confluence/upmconfig/truststore/
kubectl cp atlassian_mpac_intermediate_ca_v2.crt atlassian/<confluence-pod>:/var/atlassian/application-data/confluence/upmconfig/truststore/
```

If `kubectl cp` fails, stream the files directly:

```powershell
kubectl exec -i -n atlassian <confluence-pod> -- sh -c "cat > /var/atlassian/application-data/confluence/upmconfig/truststore/atlassian_mpac_root_ca_v1.crt" < atlassian_mpac_root_ca_v1.crt

kubectl exec -i -n atlassian <confluence-pod> -- sh -c "cat > /var/atlassian/application-data/confluence/upmconfig/truststore/atlassian_mpac_intermediate_ca_v2.crt" < atlassian_mpac_intermediate_ca_v2.crt
```

Verify:

```powershell
kubectl exec -it -n atlassian <confluence-pod> -- sh
ls -la /var/atlassian/application-data/confluence/upmconfig/truststore
```

Restart Confluence:

```powershell
kubectl rollout restart deployment/confluence -n atlassian
```

---

## Allowing Installation of Unsigned Apps

Already set in `templates/confluence-deployment.yaml`:

```yaml
- name: JVM_SUPPORT_RECOMMENDED_ARGS
  value: -Datlassian.upm.signature.check.disabled=true -Dupm.plugin.upload.enabled=true
```

Same flags as Jira (see [JiraREADME.md](../jira/JiraREADME.md#allowing-installation-of-unsigned-apps)).
Disabling `signature.check` hides the app `Upload` button, which `-Dupm.plugin.upload.enabled=true` brings back.

Apply the deployment changes:

```powershell
helm upgrade confluence . -n atlassian
kubectl rollout restart deployment/confluence -n atlassian
```

---

## Important YAML Formatting Note

Same as Jira: use single-line strings for `JAVA_OPTS` / `JVM_SUPPORT_RECOMMENDED_ARGS`, not folded YAML (`>`).

---

## Confluence Home Locked After Restart

After restarting or rolling out Confluence, the following message may appear:

```text
Confluence home directory is locked by another running instance of Confluence.
```

Verify that no Confluence pod is currently running:

```powershell
kubectl get pods -n atlassian -l app=confluence
```

Scale Confluence down:

```powershell
kubectl scale deployment confluence --replicas=0 -n atlassian
```

Remove the lock file from the Confluence Home volume (on the bound worker: `/data/k8s/confluence-data`):

```bash
rm /var/atlassian/application-data/confluence/lock
```

Scale Confluence back up:

```powershell
kubectl scale deployment confluence --replicas=1 -n atlassian
```

Verify startup:

```powershell
kubectl get pods -n atlassian
kubectl logs -f -n atlassian <confluence-pod>
```
