---
title: "Why I Built Daemonless"
date: 2026-01-13T16:00:00-05:00
draft: false
tags: ["daemonless", "freebsd", "projects"]
categories: ["Technical", "Daemonless"]
---

I've been a FreeBSD user since the late 90s. From 2002 to 2010, I was a ports committer working on the GNOME and Multimedia teams. **I have always felt more "at home" with FreeBSD.** There is a logic and cohesiveness to the Base System + Ports approach that just clicks for me in a way Linux distros often don't.

But the world changed. The OCI (Docker) container workflow took over, and for good reason: immutable infrastructure and easy updates are incredible for sanity.

For a long time, I was stuck in a dilemma:
1.  **Run Linux:** Get the great container workflow, but lose the OS I love (ZFS, Jails, consistency).
2.  **Run FreeBSD:** Keep the OS, but go back to "sysadmin drudgery"—manually maintaining dependencies inside 15 different Jails like it's 2005.
3.  **Run a Linux VM on FreeBSD:** The worst of both worlds. Overhead + complexity.

### The Solution

With `podman` and `ocijail` stabilizing on FreeBSD, I realized we could finally bridge this gap.

I built **[Daemonless](https://daemonless.io)** to provide a polished, "Docker-like" experience that runs **natively** on FreeBSD.

*   **No Linux VM.**
*   **Native Performance.**
*   **Real FreeBSD Jails under the hood.**

It isn't just a tech demo; it's a full fleet of high-quality images (Radarr, Sonarr, Traefik, etc.) built with `s6-overlay` for supervision and proper user mapping (`PUID`/`PGID`).

My goal is simple: **Make "Docker on FreeBSD" as boring and reliable as it is on Linux.**

Check out the project at [daemonless.io](https://daemonless.io) or browse the [images](https://daemonless.io/images/).
