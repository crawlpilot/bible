# Docker & Containers — Overview & Decision Guide

**Type**: Container Runtime / Application Packaging  
**Isolation Model**: OS-level (namespaces + cgroups) — shares host kernel  
**Image Format**: OCI (Open Container Initiative) layered filesystem  
**Default Runtime**: containerd → runc  
**Networking Modes**: bridge, host, none, overlay, macvlan  
**Storage Driver**: overlay2 (default), devicemapper, aufs  
**Origin**: dotCloud (Solomon Hykes), open-sourced March 2013, donated OCI spec to CNCF 2015

---

## What Is Docker?

Docker is an application packaging and runtime platform built on Linux kernel primitives — **namespaces** (process isolation) and **cgroups** (resource limits). A container is not a VM: it is a process (or group of processes) running on the host kernel, isolated from other processes by kernel features. Docker added a developer-friendly workflow on top: a layered image format, a registry ecosystem, and a CLI that made containers accessible without deep kernel knowledge.

The core insight is **"build once, run anywhere"**: an image bundles the application, its runtime, libraries, and config into an immutable artifact. The container runtime then unpacks and executes that artifact identically on a developer laptop, a CI runner, and a production server — eliminating the "works on my machine" class of bugs.

---

## Quick-Reference Card

| Property | Value |
|----------|-------|
| **Isolation unit** | Linux process group (namespace + cgroup) |
| **Startup time** | 50–200 ms (vs 10–60 s for a VM) |
| **Overhead vs bare metal** | < 3% CPU/memory for most workloads |
| **Image layers** | Immutable, content-addressed (SHA256), shared across images |
| **Default network** | Bridge (NAT); containers get private IP 172.17.0.0/16 |
| **Persistent storage** | Named volumes (managed by Docker) or bind mounts |
| **Registry protocol** | OCI Distribution Spec (HTTP REST + chunked blob upload) |
| **Rootless support** | Yes (Docker Engine ≥ 20.10, Podman by default) |
| **Windows containers** | Yes, via Hyper-V isolation or process isolation (Windows Server) |
| **Max containers/host** | ~1,000–3,000 (practical: 50–300 with reasonable workloads) |

---

## Decision Drivers: When to Choose Containers

**Choose containers when ALL of the following are true:**

1. You need **environment parity** across dev / CI / staging / prod
2. Your app is **stateless or externalises state** (database, object store, cache)
3. You want **fast, repeatable deploys** without OS-level provisioning
4. Your team needs to **run multiple isolated services** on shared infrastructure
5. You're building toward Kubernetes, ECS, or any container orchestration platform

**The single most important question**: *Is the application 12-factor-app compatible (stateless process, config via env, logs to stdout)?* If yes, containers are the natural packaging format.

---

## Use Cases

| Use Case | Why Containers Fit | Example Companies |
|----------|-------------------|-------------------|
| **CI/CD pipelines** | Reproducible build environment; ephemeral runners; cache via image layers | GitHub Actions, GitLab CI, CircleCI |
| **Microservices packaging** | One image per service; independent deploy lifecycle | Netflix, Uber, Airbnb |
| **Local dev parity** | `docker compose up` spins entire stack locally in seconds | Any shop running microservices |
| **Batch / cron jobs** | Run-to-completion containers; no long-running process to manage | Data pipelines, report generation |
| **Serverless containers** | AWS Fargate, Cloud Run — no node management, pure container abstraction | Scale-to-zero APIs, event-driven workloads |
| **Legacy app modernisation** | Containerise without rewriting; step toward cloud-native | Enterprise lift-and-shift |
| **Database tooling / dev DBs** | `docker run postgres` instantly; isolated, disposable | Local dev, integration tests |

---

## Anti-Patterns: When NOT to Use Docker Alone

| Situation | Problem | Better Alternative |
|-----------|---------|-------------------|
| GUI-heavy desktop apps | No display server; X11 forwarding is hacky | VM, native install |
| Kernel-version-dependent workloads | Shares host kernel; can't pin kernel version | VM with specific kernel |
| Highly sensitive multi-tenant workloads | Namespace isolation is weaker than VM hypervisor | gVisor, Kata Containers, Firecracker |
| Stateful workloads needing local disk IOPS | Volume I/O adds overhead; no data lifecycle management | VM with dedicated EBS / local NVMe |
| Multi-host production at scale | Docker alone has no scheduling, health checks, rescheduling | Kubernetes, ECS, Nomad |
| Windows-native apps requiring Win32 APIs | Linux containers don't support Win32 | Windows containers or VM |

---

## Key Numbers (Production Reference)

| Metric | Typical | Notes |
|--------|---------|-------|
| Container start time | 50–200 ms | From `docker run` to process PID 1 running |
| VM boot time | 10–60 s | Including kernel boot + init |
| Image pull (1 GB, warm cache) | < 1 s | Layer cache hit — only metadata fetched |
| Image pull (1 GB, cold) | 20–60 s | Network-bound; parallel layer download |
| Overlay2 read overhead | ~2–5% | vs direct filesystem access |
| Container density (4 vCPU, 16 GB) | 50–300 | Depends on per-container resource limits |
| `docker build` layer cache hit | < 100 ms | Cache lookup is hash comparison |
| Bridge network latency | + 0.05–0.2 ms | vs host networking (loopback) |

---

## File Map

| File | What's Inside |
|------|--------------|
| [README.md](README.md) | This file — overview, decision drivers, quick-reference |
| [01-architecture.md](01-architecture.md) | Kernel namespaces, cgroups, OCI spec, Docker daemon stack, Union FS, VMs vs containers |
| [02-images-and-containers.md](02-images-and-containers.md) | Dockerfile, image layers, build cache, multi-stage builds, container lifecycle, volumes, networking |
| [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) | Docker vs VMs, Docker vs Podman/containerd/CRI-O, orchestration decision |
| [04-operations-guide.md](04-operations-guide.md) | Commands cheatsheet, Docker Compose deep-dive, volumes, networking config, anti-patterns |
| [05-production-and-cloud.md](05-production-and-cloud.md) | Local + cloud setup (AWS/GCP/Azure), security hardening, observability, FAANG companies |

---

## FAANG Interview Callout (30-second version)

> "A container packages an application with its dependencies into an OCI image and runs it as an isolated process group on the host kernel using Linux namespaces and cgroups — giving you near-zero overhead and sub-second start times compared to a VM. The trade-off is a weaker security boundary: all containers share the host kernel, so a kernel exploit affects all tenants. For untrusted multi-tenant workloads I'd layer on gVisor or Kata Containers. For everything else — microservices, CI runners, batch jobs — containers are the right unit of deployment because they make environment parity a solved problem."
