> **Prerequisite:** node clocks must be synced — see [NODE-TIME-SYNC.md](NODE-TIME-SYNC.md) (required for VMs on a PC/laptop that sleeps).

switch kubectl context:
```shell
kubectl config use-context docker-desktop
```

- On changes:

```shell
helm lint .

helm template jira .
```


-----

- First create the namespace
```shell
kubectl create namespace atlassian

kubectl get ns
```

> NAME                 STATUS   AGE
> atlassian            Active   28s

- Install the config

```shell
helm install jira . -n atlassian
```

-----

Helpers:

to view the template result and get file size:
```shell
helm template jira . > output.yaml
(Get-Item .\output.yaml).Length
```