---
title: "Deep Dive: FreeBSD Podman Networking, Custom CNI, and Resource Accounting"
date: 2026-08-09T15:00:00-04:00
draft: false
tags: ["freebsd", "podman", "cni", "vnet", "homelab", "networking", "ansible"]
categories: ["Homelab"]
---

When running native OCI containers on FreeBSD with Podman and `ocijail`, networking is one of the most interesting—and sometimes confusing—parts of the setup. Because Podman translates container commands into FreeBSD `jail(2)` system calls, container interfaces aren't just Linux veth pairs inside network namespaces; they leverage FreeBSD's **VNET (Virtual Network Stack)**, `epair(4)` interface pairs, and standard CNI plugins.

Here is a practical deep dive into how Podman container networking works on FreeBSD, how to build custom CNI bridge networks for VLANs, how to fix `podman stats` metric collection with RACCT, and how to structure multi-container Compose setups.

---

## 1. Enabling Kernel Resource Accounting (RACCT)

If you've ever run `podman stats` on FreeBSD and received an empty output or header-only response, the missing piece is usually kernel resource accounting.

Podman delegates container execution to `ocijail`, which creates FreeBSD jails. To collect CPU, memory, and I/O statistics per jail, Podman queries FreeBSD's kernel `rctl(8)` subsystem. However, RACCT is disabled by default at boot in standard loader configurations.

### The Fix
Add `kern.racct.enable="1"` to `/boot/loader.conf` and reboot:

```sh
echo 'kern.racct.enable="1"' >> /boot/loader.conf
shutdown -r now
```

After rebooting, verify that RACCT is active:

```sh
sysctl kern.racct.enable
# Output: kern.racct.enable: 1
```

Once RACCT is enabled, `podman stats --no-stream` will display live CPU, memory, and time metrics for your running containers.

---

## 2. FreeBSD Podman Network Modes

Podman on FreeBSD supports three primary networking models:

| Mode | Backend Mechanism | Best Used For |
| :--- | :--- | :--- |
| **Bridge (Default CNI)** | VNET jail + `epair` attached to `cni-podman0` bridge (`10.88.0.0/16`) | Standard isolated containers using port mapping (`-p`). |
| **Custom CNI Bridge** | VNET jail + `epair` attached to physical host VLAN (`192.168.5.0/24`) | Services needing real IPs/MACs on your home LAN without NAT. |
| **Host Networking** | Non-VNET jail sharing host network stack directly | Services needing L2 network discovery (e.g. UniFi AP adoption). |

---

## 3. Custom CNI Bridge Networks (VLAN Direct IPs)

On my primary media host (`jupiter`), I don't use port forwarding (`-p 7878:7878`) for services like Radarr or Sonarr. Instead, each container gets its own IP address directly on my service VLAN (`192.168.5.0/24`).

### How Custom CNI Works
We define a CNI network configuration in `/etc/cni/net.d/87-vlan5.conflist` using the official `bridge` and `host-local` plugins from `sysutils/cni-plugins`:

```json
{
  "cniVersion": "1.0.0",
  "name": "vlan5",
  "plugins": [
    {
      "type": "bridge",
      "bridge": "bridge0",
      "isGateway": true,
      "ipMasq": false,
      "ipam": {
        "type": "host-local",
        "subnet": "192.168.5.0/24",
        "routes": [
          { "dst": "0.0.0.0/0" }
        ]
      }
    },
    {
      "type": "dnsname",
      "domainName": "dns.podman"
    }
  ]
}
```

### Static MAC & IP Mapping Scheme
To keep IPs predictable across container recreations without hardcoding DHCP servers, I pass both `--ip` and a structured `--mac-address` scheme to Podman:

```sh
doas podman run -d \
  --name radarr \
  --network vlan5 \
  --ip 192.168.5.10 \
  --mac-address "0e:05:00:00:00:0a" \
  --annotation 'org.freebsd.jail.allow.mlock=true' \
  -e PUID=1000 \
  -e PGID=1000 \
  -v /containers/radarr:/config \
  -v /mars/tide:/tide \
  --restart always \
  ghcr.io/daemonless/radarr:latest
```

* MAC `0e:05:00:00:00:0a`: `05` represents VLAN 5, and `0a` is hex for `.10`.
* OPNsense has a matching DHCP reservation for `0e:05:00:00:00:0a`, guaranteeing that DNS and routing remain rock-solid.

---

## 4. Container-to-Container DNS with `cni-dnsname`

When running multi-container stacks (like Immich or *arr stacks with database backends), services need to talk to each other by container name (`postgres`, `redis`, `sabnzbd`).

On FreeBSD, install the `cni-dnsname` package:

```sh
pkg install cni-plugins cni-dnsname
```

With `dnsname` included in your CNI conflist, Podman runs an embedded `dnsmasq` instance that automatically resolves container names across the bridge network:

```sh
# Inside any container on the bridge network
ping radarr
curl http://prowlarr:9696
```

---

## 5. Compose Best Practices (`podman-compose`)

If you use `podman-compose` to manage stacks, pay attention to `container_name` and `hostname` settings in your `compose.yaml`:

```yaml
services:
  lidarr:
    image: ghcr.io/daemonless/lidarr:latest
    container_name: lidarr
    hostname: lidarr
    networks:
      vlan5:
        ipv4_address: 192.168.5.15
    restart: unless-stopped

networks:
  vlan5:
    external: true
```

### Why `hostname:` Matters
1. **Host Name Leakage:** In non-VNET or default Compose setups, omitting `hostname:` causes `ocijail` to fall back to setting the jail's hostname to the host machine's hostname (e.g. `optiplex`).
2. **Jail Inspection (`jls -Nv`):** Setting `hostname: lidarr` ensures `jls -Nv` outputs clean, recognizable hostnames rather than generic host names.

---

## 6. Inspecting FreeBSD Jails

Because Podman containers are real FreeBSD jails, you can inspect them directly from the host system:

### Viewing Active Jails (`jls -Nv`)
```sh
jls -Nv
```
Output:
```text
   JID  Hostname                      Path
        Name                          State
        CPUSetID
        IP Address(es)
    15  radarr                        /var/db/containers/storage/zfs/graph/3080cd8f5b...
        bd6e12376e5da10907aefd0db2084 ACTIVE
        3
```

* `Name` (`bd6e12376e5da10907aefd0db2084`): The 29-character truncated container ID assigned by `ocijail`.
* `Hostname` (`radarr`): The UTS hostname configured inside the container.

### Direct Kernel Resource Inspection (`rctl`)
To inspect exact kernel resource limits and consumption for any jail:

```sh
doas rctl -u jail:bd6e12376e5da10907aefd0db2084
```

---

## Summary Checklist

1. **Enable RACCT**: Add `kern.racct.enable="1"` in `/boot/loader.conf` and reboot for `podman stats`.
2. **Configure PF**: Add `cni-rdr/*` anchors and `net.pf.filter_local=1` for bridge NAT.
3. **Use CNI Bridge for Custom Subnets**: Create CNI conflists using `cni-plugins` for direct VLAN bridging.
4. **Install `cni-dnsname`**: Enable container name resolution for multi-container stacks.
5. **Set `container_name` and `hostname`**: Prevent host name leakage in `podman-compose`.
