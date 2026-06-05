Check jira version:
```bash
kubectl exec -it jira-7fc6fd7964-c2ln2 -n atlassian -- sh -c "cat /opt/atlassian/jira/atlassian-jira/WEB-INF/classes/
```

```
META-INF/maven/com.atlassian.jira/jira-core/pom.properties"
Defaulted container "jira" out of: jira, jira-agent-init (init)
artifactId=jira-core
groupId=com.atlassian.jira
version=11.3.7
```

## Fixing Jira Certificate Error

Jira 11.3.7 validates Marketplace app signatures using certificates stored in Jira Home. Currently: [Atlassian Page](https://confluence.atlassian.com/upm/updating-atlassian-certificates-bundles-1489470540.html)

Download the Atlassian CA bundle from Atlassian documentation.

Extract the archive locally. The extracted files should include:

```text
atlassian_mpac_root_ca_v1.crt
atlassian_mpac_intermediate_ca_v2.crt
```

Copy the certificates into Jira's UPM truststore.

Using `kubectl cp`:

```powershell
kubectl cp atlassian_mpac_root_ca_v1.crt atlassian/<jira-pod>:/var/atlassian/application-data/jira/upmconfig/truststore/
kubectl cp atlassian_mpac_intermediate_ca_v2.crt atlassian/<jira-pod>:/var/atlassian/application-data/jira/upmconfig/truststore/
```

If `kubectl cp` fails, stream the files directly:

```powershell
kubectl exec -i -n atlassian <jira-pod> -- sh -c "cat > /var/atlassian/application-data/jira/upmconfig/truststore/atlassian_mpac_root_ca_v1.crt" < atlassian_mpac_root_ca_v1.crt

kubectl exec -i -n atlassian <jira-pod> -- sh -c "cat > /var/atlassian/application-data/jira/upmconfig/truststore/atlassian_mpac_intermediate_ca_v2.crt" < atlassian_mpac_intermediate_ca_v2.crt
```

Verify:

```powershell
kubectl exec -it -n atlassian <jira-pod> -- sh
ls -la /var/atlassian/application-data/jira/upmconfig/truststore
```

Restart Jira:

```powershell
kubectl rollout restart deployment/jira -n atlassian
```

---

## Allowing Installation of Unsigned Apps

Add the following environment variable to the Jira deployment:

```yaml
- name: JVM_SUPPORT_RECOMMENDED_ARGS
  value: -Datlassian.upm.signature.check.disabled=true
```

Example:

```yaml
spec:
  containers:
    env:
    - name: JVM_SUPPORT_RECOMMENDED_ARGS
        value: -Datlassian.upm.signature.check.disabled=true
```

Other singature check flags:
- -Datlassian.upm.signature.check.disabled=true
- -Datlassian.upm.signature.check.upload.disabled=true 
- -Datlassian.upm.signature.check.marketplace.disabled=true

NOTE: When disabling signature.check, the third-party app `Upload` button will also disappear and it should manually be reactivated... to do this also add the following flag:

```
-Dupm.plugin.upload.enabled=true
```

Example:

```yaml
- name: JVM_SUPPORT_RECOMMENDED_ARGS
        value: -Datlassian.upm.signature.check.disabled=true -Dupm.plugin.upload.enabled=true
```yaml

Apply the deployment changes:

```powershell
helm upgrade jira . -n atlassian
kubectl rollout restart deployment/jira -n atlassian
```

Verify the deployment:

```powershell
kubectl get pods -n atlassian
```

---

## Important YAML Formatting Note

For JVM arguments, use a single-line string:

```yaml
- name: JAVA_OPTS
  value: -javaagent:/agent/atlassian-agent.jar
```

Do not use folded YAML syntax:

```yaml
- name: JAVA_OPTS
  value: >
    -javaagent:/agent/atlassian-agent.jar
```

Using folded syntax caused Jira startup failures and resulted in immediate container crashes.

The same recommendation applies to:

```yaml
JVM_SUPPORT_RECOMMENDED_ARGS
```

Use:

```yaml
- name: JVM_SUPPORT_RECOMMENDED_ARGS
  value: "-Datlassian.upm.signature.check.disabled=true"
```

instead of multiline folded YAML.

---

## Jira Home Locked After Restart

After restarting or rolling out Jira, the following message may appear:

```text
The jira.home directory is locked by another running instance of Jira.
```

Verify that no Jira pod is currently running:

```powershell
kubectl get pods -n atlassian -l app=jira
```

Scale Jira down:

```powershell
kubectl scale deployment jira --replicas=0 -n atlassian
```

Remove the lock file from the Jira Home volume:

```bash
rm /var/atlassian/application-data/jira/.jira-home.lock
```

If present, also remove:

```bash
rm /var/atlassian/application-data/jira/docker-app.pid
```

Scale Jira back up:

```powershell
kubectl scale deployment jira --replicas=1 -n atlassian
```

Verify startup:

```powershell
kubectl get pods -n atlassian
kubectl logs -f -n atlassian <jira-pod>
```
