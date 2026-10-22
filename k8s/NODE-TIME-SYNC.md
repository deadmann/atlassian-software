# Node time sync (chrony)

Jira/Confluence stamp everything (audit log, comments, worklogs) with the **node's clock**.
Jira's timezone setting only changes display — a wrong node clock = wrong times in Jira.

## When this is required

| Environment | Required? |
|---|---|
| Suspendable VMs (VirtualBox, VMware Workstation, Hyper-V on a laptop/PC that sleeps) | **Yes** |
| Hypervisor servers (ESXi, Proxmox) / bare metal | Default chrony is fine; only do the *"All setups"* checks |

Why: when the host sleeps, the VM is paused, not suspended — the guest never sees a resume event,
its clock just falls behind. Default chrony (`makestep 1 3`) only steps the clock in the first 3 updates
after start, then **slews** — an 18h gap would take weeks to catch up.

## All setups

```shell
timedatectl status          # System clock synchronized: yes
chronyc tracking            # System time: close to 0
chronyc sources             # one source marked ^*
getent hosts ntp.ubuntu.com # node DNS must resolve, or chrony gets 0 sources
```

## Suspendable VMs

Layout: master syncs from internet, workers sync from master (one upstream, nodes agree with each other).

### Master

Pool servers live in `/etc/chrony/sources.d/ubuntu-ntp-pools.sources` (current default layout) or directly in `/etc/chrony/chrony.conf` (old layout — kept when an upgrade's new config was declined; check for `chrony.conf.dpkg-dist`). Nodes installed the same way can end up with different layouts. Append `maxpoll 6` to each `pool` line.

Override step behaviour and allow workers:

```shell
printf "makestep 1 -1\nallow 192.168.56.0/24\n" | sudo tee /etc/chrony/conf.d/homelab.conf
sudo systemctl restart chrony
sudo chronyc serverstats   # works = master is serving
```

> `conf.d` only works if `chrony.conf` has a `confdir /etc/chrony/conf.d` line. Otherwise edit `chrony.conf` directly.

### Workers

In `/etc/chrony/chrony.conf`: comment out all `pool` lines, then set:

```
server 192.168.56.101 iburst maxpoll 6
makestep 1 -1
```

```shell
sudo systemctl restart chrony
chronyc sources   # ^* 192.168.56.101
```

### What the settings do

- `makestep 1 -1` — step the clock whenever it is >1s off, not only at startup.
- `maxpoll 6` — poll at most every 64s → clock fixed within ~1 min of wakeup (~2 min on workers). 64s is the minimum polite interval for public pools.
- Optional: VirtualBox Guest Additions (`vboxadd-service`) resyncs from host within seconds of resume.

### Fix a node that is already off

```shell
sudo chronyc makestep
```

## Production (long-running servers)

Keep the default `makestep 1 3` — stepping a live server's clock (especially backwards) can upset Postgres, token expiry, k8s leases.
Use internal/cloud-provider NTP servers and alert on offset > 1s (`node_timex_offset_seconds`).

## Shutdown

Use ACPI shutdown for the VMs, not *Save state* — clean stop for Jira/Postgres and no clock jump.
