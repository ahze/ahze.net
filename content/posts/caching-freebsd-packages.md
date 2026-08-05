---
title: "Speeding Up FreeBSD Hosts & Container Builds with a Local pkg Cache"
date: 2026-07-01T10:00:00-04:00
draft: false
tags: ["freebsd", "daemonless", "containers", "dbuild", "homelab", "nginx"]
categories: ["Daemonless"]
---

When you run FreeBSD in a homelab across multiple servers, VNET jails, or VMs, routine maintenance quickly reveals a hidden inefficiency. Every time you provision a new jail or update your fleet, each instance independently connects to public `pkg.FreeBSD.org` mirrors to download identical packages. If you have a dozen jails running services that need Python, SQLite, or FFmpeg, your WAN connection downloads the exact same binary archives a dozen times.

To solve this for both regular FreeBSD hosts and container infrastructure, we built **[`daemonless/pkg-cache`](https://daemonless.io/images/pkg-cache/)** — a lightweight, zero-configuration proxy appliance tailored specifically for caching FreeBSD packages.

Here is the quick guide to getting your own cache running in seconds, followed by a deep dive into how it addresses common concerns like CDN hammering and cryptographic validation.

---

## TL;DR: Quick Start Deployment

You can get your own cache running across your network in three simple steps.

**1. Install Podman** (if you haven't already)
```bash
pkg install -y podman
```
*(Note: By using `--network host` in the next step, this works out-of-the-box with zero firewall/NAT configuration. If you prefer isolated bridged networks, see the [Quick Start Guide](https://daemonless.io/guides/quick-start/#2-configure-firewall-pfconf) for the required `pf.conf` setup).*

**2. Run the cache appliance**
```bash
podman run -d --name pkg-cache \
  --restart unless-stopped \
  --network host \
  -v /containers/pkg-cache/cache:/cache \
  -e PKG_UPSTREAM=pkg.FreeBSD.org \
  -e PKG_CACHE_SIZE=50g \
  ghcr.io/daemonless/pkg-cache:latest
```
*(Note: A live traffic dashboard is available at `http://<cache-ip>:7890`. If deploying in a public setting, disable it by passing `-e ENABLE_STATS=false`).*

**3. Point your hosts at the cache**
The cache automatically serves its own configuration file on port `80`. Save this to `/usr/local/etc/pkg/repos/FreeBSD.conf` (or simply visit `http://<cache-ip>:80` in your browser to copy the snippet):

```ini
FreeBSD: {
  url: "pkg+http://<cache-ip>/${ABI}/quarterly",
  mirror_type: "none",
  signature_type: "fingerprints",
  fingerprints: "/usr/share/keys/pkg"
}
```

> **IMPORTANT: Why `mirror_type: "none"` is Mandatory**
> By default, FreeBSD uses SRV or HTTP redirect mirrors (`mirror_type: "srv"`). If left at default, `pkg` queries DNS SRV records and follows redirects straight past your proxy back to external mirrors. Setting `mirror_type: "none"` forces the client to fetch strictly from the URL specified.

*(Prefer Compose, AppJail, or Ansible? Check out the [full documentation on daemonless.io](https://daemonless.io/images/pkg-cache/)).*

---

## How It Works: Cache Logic & Security

During a recent FreeBSD Jail/Zones Production User Call, several great questions were raised about how the cache handles hits/misses, large deployments (like conferences), and package validation. Here is what is happening under the hood.

### The "Conference Use Case" & CDN Protection
If you are at a conference with 50 FreeBSD users on the same network—or you have 50 jails on a single host—and everyone runs `pkg update` simultaneously, you do not want to hammer the upstream FreeBSD CDN.

The proxy differentiates between static and dynamic files to protect the upstream servers:
1. **Catalog Metadata is Dynamic**: Files like `meta.conf`, `packagesite.pkg`, and `data.pkg` are cached for **only 60 seconds**. This ensures `pkg update` always discovers the latest package upgrades without serving stale repository indices, while ensuring the upstream CDN only sees *one* metadata request per minute, no matter how many clients request it.
2. **Package Binaries (`*.pkg`) are Immutable**: A specific compiled package version never changes its hash. Our cache holds these archives on disk for **30 days**. After the first host fetches a package (MISS), every subsequent request across the network downloads it at local LAN speed (HIT).

### Does it Validate on Hit?
A valid concern when using a caching proxy is whether a corrupted file could be served to clients.

The proxy itself is intentionally "dumb" and extremely fast; it does not waste CPU cycles validating hashes on hit. Instead, **End-to-End Cryptographic Security** is preserved locally by the `pkg` client.

Because `signature_type: "fingerprints"` and `fingerprints: "/usr/share/keys/pkg"` remain active in your configuration, `pkg` locally verifies the official FreeBSD cryptographic signatures on every downloaded `.pkg` archive before installing it. If a file is incomplete or corrupted in the cache, `pkg` will instantly reject it. You get local LAN caching speeds without compromising package integrity.

---

## Seamless OCI Build Acceleration with `dbuild`

If you use our build framework **[`dbuild`](https://github.com/daemonless/dbuild)** to compile FreeBSD container images, you don't need to manually inject configuration files into your Containerfiles. `dbuild` natively supports host-local caching out of the box.

On any build node (such as your dedicated compilation host), create `/usr/local/etc/daemonless.yaml`:

```yaml
pkg_cache_url: "http://pkg-cache.lan"
```

When you run `dbuild`, it automatically detects this host config and injects `PKG_CACHE_URL=http://pkg-cache.lan` as a build argument into every container build. The base image's internal setup hooks intercept this argument and transparently route all `pkg install` commands through your local cache.

Because `/usr/local/etc/daemonless.yaml` lives on the host rather than in git, your source repositories stay clean and portable for users without a local proxy, while your internal build nodes enjoy near-instant package resolution.
