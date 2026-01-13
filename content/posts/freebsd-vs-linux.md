---
title: "FreeBSD vs Linux: My Take"
date: 2026-01-11T09:00:00-05:00
draft: false
tags: ["opinion", "os"]
categories: ["Opinion"]
---

I use both. I like both. But they feel very different.

**Linux** feels like a bazaar. You grab a kernel here, a package manager there, a init system from over there (usually systemd these days), and stitch it together. It's powerful, chaotic, and moves fast.

**FreeBSD** feels like a cathedral (to borrow the classic metaphor). The OS is a complete, cohesive unit. The kernel and userland are developed together. `ifconfig` works the same way it did 20 years ago. ZFS is a first-class citizen, not an external module.

For servers, I prefer the cathedral. I want my storage system to be boring. I want my network stack to be predictable. That's why I stick with FreeBSD for the core of my infrastructure.
