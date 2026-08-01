---
title: "Transparent Supply Chains: First-Class SBOMs in Daemonless & dbuild"
date: 2026-08-01T15:00:00-04:00
draft: false
tags: ["freebsd", "daemonless", "sbom", "dbuild", "security"]
categories: ["Daemonless", "Security"]
cover:
  image: "https://daemonless.io/assets/daemonless-logo.svg"
  alt: "Daemonless Logo"
---

Supply chain security in modern container ecosystems is often treated as a post-build afterthought: a secondary scanner runs against a finished image and tries to infer what packages are inside. 

When building native FreeBSD OCI images at [Daemonless](https://daemonless.io), we decided to make supply chain transparency a first-class citizen from day one. With recent updates to our custom build system ([`dbuild`](https://github.com/daemonless/dbuild)), every container image generated across our entire fleet now produces multi-format **Software Bill of Materials (SBOM)** artifacts directly at build time.

## Multi-Format Standard Compliance

Rather than forcing users into a single vendor format, `dbuild` queries package manifests directly from the FreeBSD package manager (`pkg`) during container assembly and outputs three distinct SBOM representations:

1. **CycloneDX (v1.5 JSON):** The OWASP industry standard designed specifically for application security, dependency analysis, and automated vulnerability scanning.
2. **SPDX (2.3 JSON):** The ISO/IEC 5962:2021 standard format tailored for license compliance and enterprise auditing.
3. **Daemonless Native JSON:** A lightweight, human-readable manifest optimized for fast local inspection.

## Dual-Delivery: Embedded & Attested

An SBOM is only useful if it's accessible when and where you need it. We deliver SBOM metadata through two distinct channels for every image:

* **Embedded inside the image:** During build execution, `dbuild` bakes the SBOM manifests directly into `/usr/share/sbom/` inside the container filesystem using `buildah`. Even if you run an image completely offline or detached from a registry, its complete bill of materials travels with it.
* **Attested & Published on the Web:** During CI execution, SBOMs are attested to GitHub Container Registry (GHCR) and published to our interactive online viewer at **[daemonless.io/sbom/](https://daemonless.io/sbom/?h=sbom)**.

## Interactive Inspection

You can inspect the full package manifest, upstream origins, license breakdown, and build metadata for any Daemonless image directly from your browser. Whether you are running `radarr`, `sonarr`, `traefik`, or `adguardhome`, you can verify every single package and dependency present in the container before deploying it to your FreeBSD host.

Check out the live SBOM browser at **[daemonless.io/sbom/](https://daemonless.io/sbom/?h=sbom)** or browse our build toolchain in the [`daemonless/dbuild`](https://github.com/daemonless/dbuild) repository.
