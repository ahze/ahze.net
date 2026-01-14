---
title: "My Homelab Architecture"
date: 2026-01-12T10:00:00-05:00
draft: false
tags: ["homelab", "infrastructure"]
categories: ["Homelab"]
---

My homelab has evolved significantly over the years. Currently, it's a mix of heavy iron and efficient ARM devices, all orchestrated with Ansible.

## The Fleet

*   **Mars (TrueNAS):** The primary storage engine. Bulk ZFS datasets, backups, and media library.
*   **Saturn (FreeBSD 15):** The CI/CD Core. Runs Gitea, Woodpecker, and DNS.
*   **Jupiter (FreeBSD 15):** The heavy lifter. Runs local storage and media services.
*   **OPNsense:** The perimeter. Handling the network, firewall rules, and VLANs.
*   **Pluto (FreeBSD 14):** My dedicated test box.
*   **Sunshine (Synology DS418):** Secondary backup server to Mars.
*   **Venus (Linux/Fedora):** For the few things that absolutely refuse to run on FreeBSD (yet).
*   **PiAware:** ADS-B flight tracker (built following [this guide](https://www.flightaware.com/adsb/piaware/build/)).
*   **Pibox (Linux/ARM64):** My low-power, always-on utility box.

Everything is managed via **Ansible** stored in a private Gitea repo. Secrets are vaulted. Deployment is a single playbook run.
