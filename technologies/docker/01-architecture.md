# Docker — Architecture

## Origins

Docker was created by Solomon Hykes at dotCloud in 2013 as an internal tool to manage their PaaS infrastructure. The key insight was that Linux had had all the necessary isolation primitives for years (namespaces since 2002, cgroups since 2007) but using them directly required deep kernel expertise. Docker built a developer-friendly abstraction — the Dockerfile, image registry, and CLI — on top of those primitives.

The 2015 donation of the image format to the Open Container Initiative (OCI) under the Linux Foundation decoupled the runtime from Docker, enabling containerd, CRI-O, and other runtimes to emerge. Today, Kubernetes uses containerd (not Docker) as its container runtime — Docker is primarily a developer toolchain, not a production runtime.

---

## VMs vs Containers — The Fundamental Difference

```
┌─────────────────────────────────┐   ┌───────────────────────────────────────┐
│          VIRTUAL MACHINE        │   │              CONTAINER                │
│                                 │   │                                       │
│  ┌──────┐ ┌──────┐ ┌──────┐    │   │  ┌──────┐  ┌──────┐  ┌──────┐       │
│  │ App A│ │ App B│ │ App C│    │   │  │App A │  │App B │  │App C │       │
│  ├──────┤ ├──────┤ ├──────┤    │   │  ├──────┤  ├──────┤  ├──────┤       │
│  │Libs  │ │Libs  │ │Libs  │    │   │  │Libs  │  │Libs  │  │Libs  │       │
│  ├──────┤ ├──────┤ ├──────┤    │   │  └──────┘  └──────┘  └──────┘       │
│  │Guest │ │Guest │ │Guest │    │   │  ┌─────────────────────────────────┐ │
│  │  OS  │ │  OS  │ │  OS  │    │   │  │      Container Runtime (runc)   │ │
│  └──────┘ └──────┘ └──────┘    │   │  └─────────────────────────────────┘ │
│  ┌─────────────────────────┐   │   │  ┌─────────────────────────────────┐ │
│  │      Hypervisor         │   │   │  │         HOST OS KERNEL          │ │
│  │  (VMware/KVM/Hyper-V)   │   │   │  │   (namespaces + cgroups)        │ │
│  └─────────────────────────┘   │   │  └─────────────────────────────────┘ │
│  ┌─────────────────────────┐   │   │  ┌─────────────────────────────────┐ │
│  │       Host Hardware     │   │   │  │         Host Hardware           │ │
│  └─────────────────────────┘   │   │  └─────────────────────────────────┘ │
└─────────────────────────────────┘   └───────────────────────────────────────┘

  Each VM boots its own full OS kernel.           All containers share the host kernel.
  Strong isolation (separate kernel).             Process-level isolation (namespaces).
  10–60s boot. 500MB–2GB overhead/VM.            50–200ms start. <5MB overhead/container.
```

**Key implication**: A vulnerability in the host kernel can affect all containers simultaneously. A VM's guest kernel acts as a second isolation layer that containers do not have.

---

## Linux Kernel Primitives

### Namespaces — What a Process Can See

Namespaces control which system resources a process can observe. Each container gets its own set:

| Namespace | What It Isolates | Practical Effect |
|-----------|-----------------|-----------------|
| **pid** | Process IDs | Container sees its own PID 1; can't see host processes |
| **net** | Network interfaces, routes, ports | Container has its own `eth0`, IP address, port space |
| **mnt** | Mount points, filesystem tree | Container has its own `/`, `/proc`, `/sys` |
| **uts** | Hostname, domain name | Container can have its own hostname |
| **ipc** | System V IPC, POSIX message queues | Containers can't signal each other's processes |
| **user** | UIDs and GIDs | UID 0 inside container ≠ UID 0 on host (rootless) |
| **cgroup** | cgroup hierarchy (Linux 4.6+) | Container sees only its own cgroup subtree |
| **time** (Linux 5.6+) | System clock offsets | Experimental; rarely used in practice |

```bash
# Verify container namespaces
docker run --rm alpine sh -c "ls -la /proc/1/ns/"
# lrwxrwxrwx cgroup -> cgroup:[4026532.....]
# lrwxrwxrwx ipc    -> ipc:[4026532.....]
# lrwxrwxrwx mnt    -> mnt:[4026532.....]   ← different from host
# lrwxrwxrwx net    -> net:[4026532.....]   ← different from host
# lrwxrwxrwx pid    -> pid:[4026532.....]   ← different from host
# lrwxrwxrwx uts    -> uts:[4026532.....]
```

### cgroups — What a Process Can Use

Control Groups limit and account for resource usage. Docker maps each container to a cgroup:

| cgroup Subsystem | What It Controls | Docker Flag |
|-----------------|-----------------|-------------|
| **cpu** | CPU time allocation (shares/quota) | `--cpus`, `--cpu-shares` |
| **cpuset** | Which CPU cores a process may use | `--cpuset-cpus` |
| **memory** | RAM + swap limits | `--memory`, `--memory-swap` |
| **blkio** | Block I/O bandwidth and IOPS | `--blkio-weight`, `--device-read-bps` |
| **pids** | Maximum number of processes | `--pids-limit` |
| **net_cls** | Tag packets with class ID (for tc rules) | via network policy |

```bash
# Limit container to 512MB RAM and 1 CPU
docker run --memory=512m --cpus=1.0 nginx

# Check live resource usage
docker stats my-container
# CONTAINER    CPU %    MEM USAGE / LIMIT     MEM %    NET I/O    BLOCK I/O
# my-container 0.02%    45.3MiB / 512MiB      8.85%    1.2kB/1kB  0B/0B
```

---

## The Docker Component Stack

```
Developer CLI
     │
     │  docker build / run / push
     ▼
┌──────────────────────────────────────────┐
│            Docker CLI (client)           │  ← unix socket or TCP to daemon
└─────────────────┬────────────────────────┘
                  │  REST API (/var/run/docker.sock)
                  ▼
┌──────────────────────────────────────────┐
│          Docker Daemon (dockerd)         │  ← image management, volumes,
│          /usr/bin/dockerd                │    networking, build (BuildKit)
└─────────────────┬────────────────────────┘
                  │  gRPC
                  ▼
┌──────────────────────────────────────────┐
│           containerd                     │  ← CNCF project; used by K8s
│   Container lifecycle management         │    pull images, manage snapshots,
│   (start/stop/pause/delete)              │    execute containers
└─────────────────┬────────────────────────┘
                  │  fork/exec per container
                  ▼
┌──────────────────────────────────────────┐
│        containerd-shim-runc-v2           │  ← one shim process per container;
│                                          │    keeps container running if
│                                          │    containerd restarts
└─────────────────┬────────────────────────┘
                  │
                  ▼
┌──────────────────────────────────────────┐
│              runc                        │  ← OCI runtime spec implementation
│   (libcontainer / Go)                    │    sets up namespaces + cgroups,
│                                          │    then exec()s PID 1
└──────────────────────────────────────────┘
                  │
                  ▼
         Container Process (PID 1)
```

**Key insight for interviews**: Kubernetes removed Docker as its runtime in 1.24 (`dockershim` deprecation). K8s talks to containerd directly via the Container Runtime Interface (CRI). `docker build` and `docker push` still work; Docker is just no longer in the K8s runtime path.

---

## Union Filesystem (Overlay2)

Docker images are built from **immutable layers** stacked via a Union filesystem. The default storage driver is **overlay2** on modern Linux kernels.

### How Layers Work

```
┌────────────────────────────────────────────────────┐
│  Container Layer (read-write)                      │  ← writes go here (copy-on-write)
├────────────────────────────────────────────────────┤
│  Layer 4: COPY ./app /app  (your code — 2MB)       │  ← image layers (read-only)
├────────────────────────────────────────────────────┤
│  Layer 3: RUN pip install -r requirements.txt      │  ← cached if requirements.txt
│           (dependencies — 150MB)                   │    hasn't changed
├────────────────────────────────────────────────────┤
│  Layer 2: RUN apt-get install python3 (45MB)       │
├────────────────────────────────────────────────────┤
│  Layer 1: FROM ubuntu:22.04 (base — 77MB)          │  ← shared with other images
└────────────────────────────────────────────────────┘
```

### Copy-on-Write (CoW) Mechanics

- **Read**: resolved from the topmost layer that contains the file
- **Write**: file is **copied** from the image layer into the container's writable layer first, then modified
- **Delete**: a "whiteout" file is created in the writable layer masking the lower file
- **Result**: the original image layer is never modified; every container starts from the same clean base

```
overlay2 directory layout on disk:
/var/lib/docker/overlay2/<layer-id>/
  ├── diff/       ← files changed in this layer
  ├── link        ← short name symlink for this layer
  ├── lower       ← colon-separated list of parent layer links
  └── work/       ← overlay2 internal work directory
```

### Layer Sharing Benefit

Multiple containers from the same image share all read-only layers in memory (page cache). 100 nginx containers cost 1× base image in RAM for layers, not 100×.

---

## OCI Specification

The Open Container Initiative defines two specs:

| Spec | What It Defines | Who Implements |
|------|----------------|---------------|
| **OCI Image Spec** | Image manifest, config, layer format (tar.gz), content-addressable registry | Docker, Podman, Buildah, Kaniko |
| **OCI Runtime Spec** | `config.json` format describing how to run a container (rootfs + process + namespaces) | runc, crun, Kata, gVisor |

```json
// Simplified OCI config.json (what runc receives)
{
  "ociVersion": "1.0.2",
  "process": {
    "terminal": false,
    "user": { "uid": 1000, "gid": 1000 },
    "args": ["/app/server", "--port", "8080"],
    "env": ["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"]
  },
  "root": { "path": "rootfs", "readonly": false },
  "linux": {
    "namespaces": [
      {"type": "pid"}, {"type": "network"}, {"type": "mount"},
      {"type": "uts"}, {"type": "ipc"}
    ],
    "resources": {
      "memory": { "limit": 536870912 },
      "cpu": { "quota": 100000, "period": 100000 }
    }
  }
}
```

---

## Windows Containers

Docker on Windows supports two isolation modes:

| Mode | How It Works | Isolation Level | Use Case |
|------|-------------|-----------------|----------|
| **Process isolation** | Shared Windows kernel (like Linux containers) | Moderate | Same Windows Server version host/container |
| **Hyper-V isolation** | Each container gets a lightweight Hyper-V VM | Strong (VM boundary) | Mixed Windows version, untrusted workloads |

**Limitation**: Windows containers can only run Windows workloads. Linux containers on Windows Docker Desktop run inside a lightweight Linux VM (WSL2 or Hyper-V VM) — the host kernel is not actually shared on Windows.

---

## FAANG Interview Callout

> **What the interviewer is testing**: Do you understand that containers are a kernel feature, not a hypervisor? Can you articulate the security trade-off?
>
> **What to say**: "A container is a process group isolated via Linux namespaces — which control what the process can see — and cgroups — which control what it can consume. The runtime (runc) sets these up by calling kernel syscalls, then exec()s PID 1 inside the container. Because all containers share the host kernel, the security boundary is weaker than a VM: a kernel exploit affects all containers. For true multi-tenant isolation at the kernel level, you'd add gVisor (intercepts syscalls via a Go userspace kernel) or Kata Containers (lightweight VM per container). The overlay2 Union filesystem gives you layer sharing and copy-on-write so 100 containers from the same image consume 1× base image in the page cache, not 100×."

---

## Related Files

| File | Relationship |
|------|-------------|
| [02-images-and-containers.md](02-images-and-containers.md) | Dockerfile, build pipeline, volumes, networking — the developer workflow on top of this architecture |
| [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) | VMs vs containers comparison table; Docker vs Podman vs containerd |
| [04-operations-guide.md](04-operations-guide.md) | Commands that expose the architectural concepts: `docker inspect`, `docker stats`, namespace flags |
| [05-production-and-cloud.md](05-production-and-cloud.md) | Security hardening that maps to the namespace/cgroup layer: `--cap-drop`, `--read-only`, seccomp |
