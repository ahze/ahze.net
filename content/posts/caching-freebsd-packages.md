---
title: "Speeding Up FreeBSD Hosts & Container Builds with a Local pkg Cache"
date: 2026-07-01T10:00:00-04:00
draft: false
tags: ["freebsd", "daemonless", "containers", "dbuild", "homelab", "nginx"]
categories: ["Daemonless"]
---

When you run FreeBSD in a homelab across multiple servers, VNET jails, or VMs, routine maintenance quickly reveals a hidden inefficiency. Every time you provision a new jail or update your fleet, each instance independently connects to public `pkg.FreeBSD.org` mirrors to download identical packages. If you have a dozen jails running services that need Python, SQLite, or FFmpeg, your WAN connection downloads the exact same binary archives a dozen times.

The problem multiplies exponentially once you start building OCI container images. 

During active development or when running a build pipeline across fleet nodes, container layers are constantly rebuilt. Every automated `podman build` run pulls base operating system packages from scratch. Over an afternoon of testing and debugging Containerfiles, you can easily waste gigabytes of bandwidth and spend significant time just waiting for remote servers to serve up identical packages over and over again.

To solve this for both regular FreeBSD hosts and our container infrastructure, we built **[`daemonless/pkg-cache`](https://daemonless.io/images/pkg-cache/)** — a lightweight, zero-configuration Nginx proxy appliance tailored specifically for FreeBSD repository mirroring.

## How it Works Under the Hood

Not all files on a FreeBSD package mirror can be treated the same way:

1. **Package Binaries (`*.pkg`) are Immutable**: A specific compiled package version never changes its filename or hash. Our cache holds these archives on disk for **30 days**. After the first host or build container fetches a package (MISS), every subsequent request across your LAN downloads it at local network speed (HIT).
2. **Catalog Metadata is Dynamic**: Files like `meta.conf`, `packagesite.pkg`, and `data.pkg` update regularly as port maintainers publish new releases. The proxy caches these catalog files for **only 1 minute**. This ensures `pkg update` always discovers the latest package upgrades without serving stale repository indices.

## Pointing Hosts & Jails at the Cache

Configuring any standard FreeBSD host or jail to use your cache takes a single configuration file. Drop this snippet into `/usr/local/etc/pkg/repos/FreeBSD.conf`:

```ini
FreeBSD: {
  url: "pkg+http://pkg-cache.lan/${ABI}/quarterly",
  mirror_type: "none",
  signature_type: "fingerprints",
  fingerprints: "/usr/share/keys/pkg",
  enabled: yes
}
```

Replace `pkg-cache.lan` with the hostname or IP of your cache instance (and change `quarterly` to `latest` if you track the rolling branch).

### Two Critical Details

#### 1. Why `mirror_type: "none"` is Mandatory
By default, FreeBSD uses SRV or HTTP redirect mirrors (`mirror_type: "srv"`). If left at default, `pkg` queries DNS SRV records and follows redirects straight past your proxy back to external mirrors. Setting `mirror_type: "none"` forces the client to fetch strictly from the URL specified (`http://pkg-cache.lan/...`).

#### 2. End-to-End Cryptographic Security
Even though clients connect to the local cache over plain HTTP on port 80, security is completely preserved. Because `signature_type: "fingerprints"` and `fingerprints: "/usr/share/keys/pkg"` remain active, `pkg` locally verifies the official FreeBSD cryptographic signatures on every downloaded `.pkg` archive before installing it. You get local LAN caching speeds without compromising package integrity.

---

## Seamless OCI Build Acceleration with `dbuild`

If you use our build framework **[`dbuild`](https://github.com/daemonless/dbuild)** to compile FreeBSD container images, you don't need to manually inject configuration files into your Containerfiles. `dbuild` natively supports host-local caching out of the box.

On any build node (such as your dedicated compilation host), create `/usr/local/etc/daemonless.yaml`:

```yaml
pkg_cache_url: "http://pkg-cache.lan"
```

When you run `dbuild`, it automatically detects this host config and injects `PKG_CACHE_URL=http://pkg-cache.lan` as a build argument into every container build. The base image's internal setup hooks intercept this argument and transparently route all `pkg install` commands through your local cache.

Because `/usr/local/etc/daemonless.yaml` lives on the host rather than in git, your source repositories stay clean and portable for users without a local proxy, while your internal build nodes enjoy near-instant package resolution.

---

## Running Your Own Instance

You can deploy `daemonless/pkg-cache` in seconds with Podman Compose:

```yaml
services:
  pkg-cache:
    image: "ghcr.io/daemonless/pkg-cache:latest"
    container_name: pkg-cache
    environment:
      - TZ=UTC
      - PKG_UPSTREAM=pkg.FreeBSD.org
      - PKG_CACHE_SIZE=50g
      - ENABLE_STATS=true
    volumes:
      - "/containers/pkg-cache:/config"
      - "/containers/pkg-cache/cache:/cache"
    ports:
      - "80:80"
      - "7890:7890"
    restart: unless-stopped
```

Check out the [full documentation on daemonless.io](https://daemonless.io/images/pkg-cache/) for AppJail and Ansible deployment examples.
