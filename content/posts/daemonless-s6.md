---
title: "The Daemonless Irony: Why We Chose s6 for FreeBSD Containers"
date: 2026-04-04T00:00:00-05:00
draft: false
tags: ["freebsd", "daemonless", "containers", "s6", "podman"]
categories: ["Daemonless"]
---

When the mission is to build native FreeBSD OCI images that run in Jails without a heavy background daemon on the host, the project name basically writes itself: daemonless.io.

The goal is simplicity, transparency, and architectural purity. So, it is only natural that the very first thing we did was install a suite of tools designed specifically to manage, supervise, and run... daemons.

It is a bit like starting a "Car-Free" lifestyle and then immediately buying a fleet of high-end electric scooters. Technically, the name still holds up, but you're still getting around on wheels. We might be "daemonless" on the host, but inside the container, we've hired the most efficient, C-based babysitter in the business.

Here is why s6 is the engine under the hood of our FreeBSD images, and how we use it to bridge the gap between Jails and the modern container workflow. The best place to start is not with theory — it is with what is actually running. Here is the process tree inside a live MariaDB container on my homelab:

```
  PID  PPID USER COMMAND
38492 38490 root s6-svscan /run/s6/services
38706 38492 root s6-supervise mariadb
38707 38492 root s6-supervise mariadb/log
38708 38706 bsd  /usr/local/libexec/mariadbd --datadir=/config/databases --socket=/var/run/mysql/mysql.sock --bind-address=0.0.0.0 --port=3306
38709 38707 bsd  s6-log T n10 s1048576 /config/logs/daemonless/mariadb 1
```

Four processes. That is the entire supervision stack. s6-svscan at the root, two s6-supervise watchdogs (one for the app, one for its logger), MariaDB itself running as `bsd` (UID 1000), and s6-log capturing its output. Nothing else. No bash wrapper hanging around, no zombie processes, no mystery PIDs.

## The Right Tools, Nothing Extra

The s6 ecosystem is a massive collection of small, specialized C programs. In a world where container init systems often try to do everything, we took a surgical approach. We use the sharpest tools in the box and leave the rest on the shelf to keep our images lean.

We install exactly one package: `s6`. Nothing more.

### The Essentials

**`/init` (The Bootstrap):** Our PID 1 is not s6-svscan directly — it is a small, purpose-built shell script that runs first. It configures the loopback interface, saves the container environment for services to consume, and runs any `cont-init.d` scripts (for first-run setup like database initialization). It also auto-registers services: it symlinks each directory under `/etc/services.d/` into `/run/s6/services/` and generates log and finish scripts on the fly if they aren't present. Once that work is done, it hands off with `exec s6-svscan`. This two-phase approach gives us a clean initialization window before supervision begins.

**`s6-svscan` (The Supervisor Root):** Once `/init` hands off, s6-svscan takes over as the supervision root. It watches the service directory and ensures every defined service has an `s6-supervise` process watching over it.

**`s6-supervise` (The Watchdog):** This is the process that actually runs your application. If the app crashes, `s6-supervise` catches it and restarts it. Our `s6-finish-helper` adds crash throttling — a 5-second delay before restart — to prevent a broken service from hammering resources in a tight loop.

**`s6-log` (The Archivist):** We skip the complexity of a full syslog. Instead, we pipe service output into `s6-log` via our `s6-log-helper` wrapper, which handles rotation, file sizing, and optionally mirrors output to stdout so `podman logs` still works. Logs land in `/config/logs/daemonless/<service>/` with configurable size and file count limits via environment variables.

**`s6-setuidgid` (The Identity Layer):** Services never run as root. Every `run` script drops privileges with `s6-setuidgid bsd` before executing the application. The `bsd` user is UID/GID 1000 — consistent across all images, matching the convention for self-hosted setups where the host user is typically UID 1000 as well.

### Log Files and the TAI64N Rabbit Hole

There is one thing that catches every new user off guard. Open the log directory and you will see something like this:

```
[root@jupiter /containers/unifi/logs/daemonless/unifi]# ls -al
-rw-------  1 1000 1000 23294 Jan 22 05:47 @400000006972006d1b50584e.u
-rw-------  1 1000 1000 46557 Jan 25 14:53 @40000000697674db10c36d9c.u
-rw-------  1 1000 1000 45509 Mar  3 17:19 @4000000069a75ebc28848aa6.u
-rw-------  1 1000 1000 22806 Mar 11 17:01 @4000000069b1d86f1471f0a9.u
-rw-------  1 1000 1000 22806 Mar 19 04:44 @4000000069bbb7ad38b6544e.u
-rw-------  1 1000 1000 22703 Mar 19 04:45 current
```

Those filenames are not corruption. They are TAI64N timestamps — strictly monotonic, always sortable, immune to discontinuities like leap seconds or DST changes. Each `@...u` file is a rotated log slice named after the moment it was sealed. Decode one with `s6-tai64nlocal`:

```bash
$ echo "@4000000069bbb7ad38b6544e" | s6-tai64nlocal
2026-03-19 04:44:56.951473230
```

The `daemonless` namespace in the path is intentional — it keeps s6-log output separate from anything the application itself might write. If an app creates its own log directory, there is no collision. For multi-service images like UniFi (which bundles MongoDB), you get a directory per service automatically:

```
[root@jupiter /containers/unifi/logs/daemonless]# ls
mongodb  unifi
```

One log mount, every service separated, no configuration required.

```bash
# Follow the live log (persists across restarts)
tail -f /containers/unifi/logs/daemonless/unifi/current

# Search across rotated files with human-readable timestamps
cat @*.u current | s6-tai64nlocal | grep -i error

# Or podman logs — convenient, but resets on container restart
podman logs -f unifi
```


## Why Not rc.d?

If you are running a `:pkg` or `:pkg-latest` image, the application is installed as a proper FreeBSD package — and every FreeBSD package ships an rc.d script in `/usr/local/etc/rc.d/`. So the question is reasonable: why not just use the FreeBSD service management you already have? rc.d works fine in a Jail.

| Feature | rc.d | s6 |
|---|---|---|
| Foreground logging (`podman logs`) | ⚠️ | ✅ |
| Automatic crash restart | ❌ | ✅ |
| Works without a package (`:latest`) | ❌ | ✅ |
| Signal precision per service | ⚠️ | ✅ |

**rc.d daemonizes by default.** Service scripts fork the process to the background. Whether runtime output reaches `podman logs` depends on how the application handles its file descriptors after forking — some keep stdout open, many redirect to log files. It is per-application, not guaranteed, and not something rc.d controls.

**No crash supervision.** rc.d starts a process and walks away. If it crashes, it stays dead until you intervene. You can add `daemon(8)` for supervision but that is additional moving parts per service. s6-supervise does this automatically for every service with no extra configuration.

**Consistency across the fleet.** Our `:latest` images run upstream binaries that have no rc.d script at all. If `:pkg` images used rc.d and `:latest` images used s6, every image in the fleet would behave differently. One supervision model, regardless of where the binary came from, is simpler to reason about and operate.

**Signal precision.** The FreeBSD postgresql rc.d script actually handles this correctly — its default flags include `-m fast`, which tells `pg_ctl` to use Fast Shutdown. So for postgres specifically, rc.d is not the problem.

The problem is the container runtime. When you run `podman stop`, it sends `SIGTERM` to PID 1 — and PID 1 is not `pg_ctl`, it is whatever is running as your init. A naive shell entrypoint that just `exec postgres` will receive `SIGTERM` directly, bypassing `pg_ctl` entirely and landing in Smart Shutdown. We tested this: with one client holding an open connection, `SIGTERM` sent directly to the postmaster left postgres running for over a minute — client still in `SELECT`, going nowhere.

We then sent `SIGINT` to the same setup. Postgres logged `received fast shutdown request`, terminated the client, flushed a checkpoint, and exited in 11 milliseconds. With s6, a `down-signal` file containing `INT` ensures the right signal reaches postgres regardless of what the container runtime sends to PID 1. The case study below shows exactly how.

The `:pkg` tag describes how the application was installed, not how it should be supervised.

## A Postgres Case Study: Init Phases and Signal Handling

The two-phase `/init` + s6-svscan design pays off most clearly with stateful services like PostgreSQL.

### Structured Initialization

On first run, Postgres needs to initialize a data directory, create users, create databases, and potentially run SQL migration files — all before the server starts accepting connections. In our images, this entire sequence lives in `cont-init.d/10-postgres-config`, a shell script that runs during the init phase before s6-svscan starts.

Once initialization is complete, `s6-supervise` takes over with a single clean `run` script:

```sh
exec s6-setuidgid bsd postgres -D "$PGDATA"
```

No init logic, no conditional bootstrapping, no entrypoint sprawl. The service script does exactly one thing. If Postgres crashes, `s6-supervise` restarts it. If the container is stopped, `s6-svscan` handles the shutdown sequence cleanly.

### The Signal Problem

Here is where raw s6 earns its keep. PostgreSQL has three shutdown modes triggered by different signals:

- `SIGTERM` → Smart Shutdown: waits for all clients to disconnect before exiting
- `SIGINT` → Fast Shutdown: forces clients to disconnect, flushes to disk, exits cleanly
- `SIGQUIT` → Immediate Shutdown: no cleanup, risk of corruption

When `podman stop` runs, it sends `SIGTERM` to PID 1. If postgres is running as PID 1 directly — a common pattern with naive entrypoints — that `SIGTERM` triggers Smart Shutdown. With a connected client, postgres waits indefinitely. Eventually the container runtime loses patience and sends `SIGKILL` — and now you have a corrupted database.

> **Note:** The FreeBSD postgresql rc.d script does not have this problem — its default flags include `-m fast`, which routes the stop through `pg_ctl` using Fast Shutdown regardless of what signal initiated the stop. The issue is specific to container entrypoints that run postgres as PID 1 directly.

### The Fix: Two Files

First, we set `STOPSIGNAL SIGINT` in the Containerfile. This tells Podman to send `SIGINT` to PID 1 when you run `podman stop`.

But there is a catch: PID 1 is s6-svscan, not Postgres. s6-svscan catches the signal and initiates its own shutdown sequence — then by default, `s6-supervise` sends `SIGTERM` to the supervised process, accidentally putting us right back into Smart Shutdown.

The fix is a single file: `services.d/postgresql/down-signal` containing just the word `INT`.

This tells s6-supervise: "When it is time to stop, send `SIGINT` — not `SIGTERM`."

Clean. Transparent. No data corruption. This is the level of precision you get from raw s6 that you simply cannot achieve with a naive shell entrypoint.

<div class="mermaid-split">
<pre class="mermaid">
flowchart TD
    A[podman stop] -->|SIGINT| B[s6-svscan\nPID 1]
    B -->|shutdown sequence| C[s6-supervise]
    C -->|reads| D{down-signal\nINT}
    D -->|SIGINT| E[postgres\nFast Shutdown]
    E --> F[✓ Clean exit]
</pre>
<div class="mermaid-steps">

1. **`podman stop`** sends `SIGINT` to PID 1 — not the default `SIGTERM`, because we set `STOPSIGNAL SIGINT` in the Containerfile.
2. **`s6-svscan`** catches the signal and begins its orderly shutdown sequence.
3. **`s6-supervise`** is instructed to stop its supervised process — and before sending anything, it checks for a `down-signal` file.
4. **`down-signal: INT`** overrides the default `SIGTERM`. Without this file, we'd be right back in Smart Shutdown territory.
5. **`postgres`** receives `SIGINT` → Fast Shutdown. Clients are disconnected, data is flushed to disk, process exits cleanly.

</div>
</div>

## The Verdict

By choosing s6, we didn't just build another jail script; we built a professional-grade foundation.

**Performance:** Everything is written in highly optimized C. You won't see s6 taking up more than a fraction of a megabyte in `top`.

**Reliability:** Crash throttling, clean shutdown sequencing, and a structured init phase prevent the common failure modes that plague naive container entrypoints.

**The FreeBSD Way:** It respects the resource constraints of a Jail while providing the "UX layer" that makes containers actually usable for the self-hosting community.

We might be "against" daemons on the host, but as long as they stay inside the Jail and listen to their supervisor, they're more than welcome at daemonless.io.

---

## Change My Mind

> s6 is the right init system for FreeBSD containers.

If you disagree — different init system, cleaner pattern, something I missed — make your case on [GitHub Discussions](https://github.com/orgs/daemonless/discussions). I'm genuinely open to being convinced.
