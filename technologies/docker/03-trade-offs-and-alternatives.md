# Docker — Trade-offs & Alternatives

## VMs vs Containers: The Core Trade-off

This is the most common interview question in the container space. The answer is nuanced: they solve different problems and are often used together (containers inside VMs is the standard production model).

| Dimension | Virtual Machines | Containers |
|-----------|-----------------|------------|
| **Isolation level** | Kernel boundary (strongest) | Process/namespace boundary (weaker) |
| **Attack surface** | Guest kernel + hypervisor | Host kernel shared by all containers |
| **Startup time** | 10–60 seconds (kernel boot) | 50–500 ms (process start) |
| **Memory overhead** | 200MB–2GB+ per VM (OS footprint) | 1–50MB per container (no OS kernel copy) |
| **Density** | 10–50 VMs/host (typical) | 50–1000 containers/host |
| **Portability** | VM image tied to hypervisor (VMware/KVM/Hyper-V) | OCI image runs on any OCI runtime |
| **Immutability** | VM snapshots are mutable state; complex versioning | OCI layers are content-addressed immutable |
| **Dev experience** | Vagrant/Packer; slow feedback loop | `docker build` in seconds; layer caching |
| **State management** | Full disk image (easy to snapshot, hard to diff) | Ephemeral container + separate volume |
| **Kernel version control** | Each VM can pin its kernel | All containers share host kernel version |
| **Windows/Linux mix** | Yes (each VM has its own OS) | No (Linux containers need Linux kernel) |
| **License cost** | Hypervisor licensing (VMware) or free (KVM) | No licensing (runtime is open source) |
| **CI build time** | Minutes to boot a VM runner | Seconds to start a container runner |

### Recommendation

**Use containers** for: application deployment, CI/CD runners, microservices, batch jobs, local dev environments.

**Use VMs** for: multi-tenant isolation with untrusted code, kernel-version-sensitive workloads, mixed OS environments, legacy apps requiring full OS features.

**Use both** (standard production pattern): containers run inside VMs. The VM provides a security boundary between tenants; containers provide density and fast deployment within a trusted tenant boundary.

```
Cloud Provider (AWS / GCP / Azure)
│
├── EC2 Instance (VM) — tenant A
│     ├── container1 (service-auth)
│     ├── container2 (service-api)
│     └── container3 (service-worker)
│
└── EC2 Instance (VM) — tenant B
      ├── container1 (service-auth)
      └── container2 (service-api)
```

---

## Container Runtime Comparison

Docker is not the only container runtime. Understanding the ecosystem matters for principal engineer interviews, especially Kubernetes-adjacent discussions.

| Runtime | Daemon | Root Required | K8s CRI | OCI Compliant | Key Strength | Who Uses It |
|---------|--------|--------------|---------|---------------|-------------|------------|
| **Docker Engine** | Yes (dockerd) | Yes (default) | No (removed in K8s 1.24) | Yes | Dev UX, ecosystem | Developers, Docker Desktop |
| **Podman** | No (fork/exec) | No (rootless default) | Yes (via CRI-O shim) | Yes | Daemonless, rootless, drop-in Docker replacement | Red Hat, RHEL/Fedora shops |
| **containerd** | Yes | Yes | Yes (native) | Yes | Minimal, production-grade, K8s default | Kubernetes (GKE, EKS, AKS default) |
| **CRI-O** | Yes | Yes | Yes (native) | Yes | Purpose-built for K8s; no extra features | OpenShift, K8s purists |
| **nerdctl** | Uses containerd | Yes | No | Yes | Docker-compatible CLI for containerd | K8s-aligned dev environments |
| **LXC / LXD** | Yes | Yes (LXD rootless supported) | No | No (predates OCI) | System containers (full OS init) | Full-OS containers, Canonical |
| **gVisor (runsc)** | No (sandbox) | No | Yes (via shim) | Yes (OCI runtime) | Strong security — userspace kernel | Google Cloud Run, multi-tenant |
| **Kata Containers** | No (VM per container) | Varies | Yes (via shim) | Yes (OCI runtime) | VM-level isolation; OCI interface | OpenStack, telco, high-security |

### Podman vs Docker — Detailed Comparison

| Feature | Docker | Podman |
|---------|--------|--------|
| **Daemon** | dockerd always running | Daemonless (fork/exec per container) |
| **Root default** | Yes (socket owned by root) | No (rootless by default since 3.0) |
| **Rootless** | Yes (Engine ≥ 20.10, complex setup) | Yes (first-class, simple) |
| **Compose** | `docker compose` (V2, built-in) | `podman-compose` or `podman compose` (V4+) |
| **Drop-in replacement** | — | `alias docker=podman` works for most use cases |
| **Pods** | No pod concept | Yes (K8s-compatible pod group) |
| **Systemd integration** | Via restart policies | Native (`podman generate systemd`) |
| **Image signing** | Docker Content Trust (Notary) | Sigstore / cosign native support |
| **Security default** | Privileged daemon, full root | Unprivileged namespaces, no daemon |
| **Fork bomb protection** | Explicit `--pids-limit` | `--pids-limit` default on RHEL |

**When to choose Podman**: RHEL/Fedora production environments, daemonless CI pipelines (no Docker socket exposure), rootless user namespaces required by security policy, Kubernetes-aligned tooling (pod concept).

### containerd vs Docker Engine

**containerd** is what Kubernetes actually uses. It has a minimal API surface:
- Pull images
- Manage image snapshots
- Start/stop containers
- Manage namespaces (containerd namespaces, not Linux namespaces)

**Docker Engine** wraps containerd and adds:
- `docker build` (BuildKit)
- `docker push` / `docker pull` (with credential helpers)
- Volume management
- Network management (`docker network`)
- Docker Compose
- The developer UX

In a K8s cluster, containerd handles the runtime path; Docker is not present. But Docker CLI is still used on developer machines to build and push images.

---

## Orchestration: When Docker Alone Is Not Enough

A single host running Docker is not production. At scale you need scheduling, health checking, rescheduling on failure, rolling deploys, and service discovery. These orchestrators solve that problem:

| Orchestrator | Complexity | Strengths | When to Use |
|-------------|------------|-----------|-------------|
| **Docker Compose** | Low | Single-host, local dev, simple deploys | 1–2 hosts, dev/staging, < 20 services |
| **Docker Swarm** | Low-Medium | Built into Docker, simple clustering, overlay networking | Small teams, don't want K8s complexity, < 50 nodes |
| **Kubernetes (K8s)** | High | Industry standard, huge ecosystem, fine-grained control | Production, 10+ services, multi-team, cloud provider managed (EKS/GKE/AKS) |
| **Amazon ECS** | Medium | AWS-native, simpler than K8s, Fargate option | AWS shops that don't want K8s operational burden |
| **HashiCorp Nomad** | Medium | Multi-workload (containers + VMs + binaries), simpler than K8s | Mixed workload environments, HashiCorp ecosystem |
| **Fly.io / Railway** | Low | Opinionated PaaS on top of containers | Startups, simple global deploy without K8s expertise |

### Decision Flowchart

```
How many hosts?
│
├─ 1 host
│   └─ Docker Compose (dev) or docker run (simple prod)
│
├─ 2–10 hosts, small team, no K8s expertise
│   └─ Docker Swarm or Amazon ECS (Fargate)
│
├─ 10+ hosts OR multiple teams OR need pod scheduling / HPA / RBAC
│   └─ Kubernetes
│       ├─ AWS?  → EKS
│       ├─ GCP?  → GKE (Autopilot for minimal ops)
│       └─ Azure? → AKS
│
└─ Serverless containers (no node management, scale to zero)
    ├─ AWS → ECS Fargate
    ├─ GCP → Cloud Run
    └─ Azure → Azure Container Instances
```

---

## Image Build Alternative: Buildpacks

**Cloud Native Buildpacks (CNB)** — build container images without a Dockerfile:

```bash
pack build my-app --builder gcr.io/buildpacks/builder:v1
# Detects language (Java/Node/Python/Go), installs deps, creates optimised image
# No Dockerfile required
```

| Tool | How | Best For |
|------|-----|---------|
| **Dockerfile** | Explicit instruction-by-instruction | Full control, multi-stage, custom base images |
| **Buildpacks** | Convention-based auto-detection | Heroku-style platforms, dev speed, security patching (rebase base layer) |
| **Jib (Java)** | Layered image from Maven/Gradle, no Docker daemon | Java microservices; direct push to registry |
| **Bazel rules_docker** | Hermetic builds, content-addressed layers | Monorepos with strict build reproducibility |
| **ko (Go)** | Go → OCI image without Dockerfile | Go services; zero-config |

---

## Security Isolation: Container Runtimes for Untrusted Workloads

Standard containers share the host kernel. For SaaS multi-tenancy or code execution platforms (Repl.it, GitHub Actions, Fly.io), stronger isolation is needed:

| Technology | Mechanism | Overhead | Use Case |
|-----------|----------|---------|---------|
| **gVisor (runsc)** | Userspace kernel in Go; intercepts syscalls | ~10–30% CPU overhead vs runc | Google Cloud Run, App Engine, Anthos |
| **Kata Containers** | Lightweight VM (QEMU/Firecracker) per container | ~100–200ms cold start | OpenStack, Alibaba Cloud ECI |
| **Firecracker** | MicroVM optimised for serverless | ~125ms cold start, 5MB overhead | AWS Lambda, AWS Fargate (underlying tech) |
| **Wasm (Wasmtime)** | WebAssembly sandbox, no OS calls | Near-native, ~1ms cold start | Edge functions, untrusted plugins, WASI |

---

## FAANG Interview Callout

> **What the interviewer is testing**: Awareness of the container ecosystem; ability to make runtime and orchestration decisions based on requirements.
>
> **What to say**: "For production at Google-scale, you wouldn't use Docker Engine on individual hosts — Kubernetes uses containerd directly via CRI. Docker as a CLI is still the developer toolchain for building and pushing images, but it's not in the runtime path. The VM vs container decision comes down to isolation requirements: containers inside VMs is the standard (e.g., EC2 nodes running K8s pods) because the VM gives you tenant isolation at the cloud level, and containers give you density and fast deploys within a trusted boundary. For untrusted multi-tenant workloads — like a code execution platform — I'd use Firecracker MicroVMs or gVisor, not standard runc, because a shared kernel is too weak a boundary when the code being run is adversarial."

---

## Related Files

| File | Relationship |
|------|-------------|
| [01-architecture.md](01-architecture.md) | Namespace/cgroup architecture that explains WHY containers have weaker isolation than VMs |
| [02-images-and-containers.md](02-images-and-containers.md) | Podman/Buildah as Docker CLI alternatives for image building |
| [04-operations-guide.md](04-operations-guide.md) | Docker Compose vs Swarm operational commands |
| [05-production-and-cloud.md](05-production-and-cloud.md) | ECS Fargate and Cloud Run — the managed orchestration options described here |
