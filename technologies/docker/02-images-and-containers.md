# Docker — Images, Containers, Volumes & Networking

## Image Build Pipeline

```
Developer writes Dockerfile
         │
         ▼
┌─────────────────────┐
│   docker build .    │  ← BuildKit parses Dockerfile
│   (BuildKit)        │    creates DAG of build stages
└──────────┬──────────┘
           │
           ▼  for each instruction
┌─────────────────────┐
│  Cache lookup        │  ← SHA256 hash of:
│  (content-addressed) │    parent layer + instruction + context
└──────────┬──────────┘
     hit ◄─┤─► miss
     │      │
     │      ▼
     │  ┌─────────────┐
     │  │ Execute RUN │  ← spawn container from previous layer
     │  │ / COPY / ADD│    apply changes
     │  │ → new layer  │    commit new read-only layer
     │  └─────────────┘
     │      │
     └──────┤
            ▼
┌─────────────────────┐
│ Final image manifest │  ← list of layer digests + config JSON
│ (OCI format)         │    tagged and stored in local daemon cache
└─────────────────────┘
           │
           ▼  docker push
┌─────────────────────┐
│  Registry (ECR,      │  ← upload only layers not already present
│  Docker Hub, GCR)    │    (content-addressed dedup)
└─────────────────────┘
```

---

## Dockerfile — Complete Instruction Reference

### Minimal Working Example (Go service)

```dockerfile
# syntax=docker/dockerfile:1

# ── Stage 1: build ─────────────────────────────────────────────────────────
FROM golang:1.22-alpine AS builder

WORKDIR /src

# Copy dependency manifests first (cache deps separately from code)
COPY go.mod go.sum ./
RUN go mod download

# Copy source and build
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /app/server ./cmd/server

# ── Stage 2: runtime ────────────────────────────────────────────────────────
FROM gcr.io/distroless/static-debian12

# Non-root user (distroless provides uid 65532 "nonroot")
USER nonroot:nonroot

COPY --from=builder --chown=nonroot:nonroot /app/server /app/server

EXPOSE 8080

ENTRYPOINT ["/app/server"]
```

### Every Instruction Explained

| Instruction | Purpose | Example | Notes |
|-------------|---------|---------|-------|
| `FROM` | Base image | `FROM ubuntu:22.04` | Always pin a digest or tag; `latest` is mutable |
| `RUN` | Execute command during build | `RUN apt-get install -y curl` | Creates a new layer; chain with `&&` to keep layer count low |
| `COPY` | Copy files from build context | `COPY ./src /app/src` | Preferred over ADD for local files |
| `ADD` | COPY + auto-extract tarballs + URL support | `ADD https://… /tmp/` | Use only when you need tarball extraction; URL ADD is non-deterministic |
| `ENV` | Set environment variable (build + runtime) | `ENV NODE_ENV=production` | Visible in `docker inspect`; don't use for secrets |
| `ARG` | Build-time variable only | `ARG VERSION=1.0` | Not in final image; safe for build-time config |
| `EXPOSE` | Document intended port | `EXPOSE 8080` | Metadata only; does NOT publish the port |
| `ENTRYPOINT` | Process to run (not overridable easily) | `ENTRYPOINT ["/app/server"]` | Exec form preferred (no shell; signals propagated to PID 1) |
| `CMD` | Default args to ENTRYPOINT (or command if no ENTRYPOINT) | `CMD ["--port", "8080"]` | Easily overridden with `docker run … <command>` |
| `USER` | Set UID:GID for subsequent instructions + runtime | `USER 1000:1000` | Critical for security; don't run as root |
| `WORKDIR` | Set working directory | `WORKDIR /app` | Creates dir if absent; use absolute paths |
| `HEALTHCHECK` | Tell Docker how to test container health | `HEALTHCHECK CMD curl -f http://localhost:8080/health` | Enables `docker ps` health status; required for ECS health gates |
| `LABEL` | Attach metadata | `LABEL maintainer="team@company.com"` | OCI annotations; used by image scanners and registries |
| `VOLUME` | Declare mount point | `VOLUME ["/data"]` | Creates anonymous volume; prefer named volumes in Compose |
| `STOPSIGNAL` | Signal Docker sends to stop container | `STOPSIGNAL SIGTERM` | Default SIGTERM; some apps need SIGINT |
| `ONBUILD` | Instruction to run when image is used as base | `ONBUILD RUN npm install` | Useful for base images; confusing in practice — avoid |

---

## Layer Caching Rules (Critical for Fast CI Builds)

Cache is **invalidated** from the changed instruction onward. Order instructions from **least frequently changing** to **most frequently changing**:

```dockerfile
# ✗ SLOW — code change invalidates dependency install cache
COPY . .
RUN npm install

# ✓ FAST — package.json rarely changes; src changes every commit
COPY package.json package-lock.json ./
RUN npm install          # cached unless package files change
COPY src/ ./src/         # only this layer changes on code commits
```

**Cache invalidation triggers**:
- `FROM`: new base image digest
- `RUN`: instruction text change OR any `--mount` content change
- `COPY`/`ADD`: any file in the source path changes (mtime + content hash)
- `ENV`/`ARG`: value changes
- Any previous layer was invalidated (cascading)

**BuildKit cache mounts** (avoid re-downloading in CI):
```dockerfile
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt
```

---

## Multi-Stage Builds

Multi-stage builds eliminate build tools from runtime images. The final image contains only what the app needs to run.

### Python Example

```dockerfile
FROM python:3.12-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --prefix=/install -r requirements.txt

FROM python:3.12-slim
COPY --from=builder /install /usr/local
COPY app/ /app/
USER 1000
CMD ["python", "/app/main.py"]
```

| Stage | Size | Contents |
|-------|------|----------|
| Builder | ~800MB | Python + pip + gcc + headers + wheels |
| Runtime | ~180MB | Python + installed packages only |

---

## Container Lifecycle

```
docker create         docker start        (process running)
     │                     │
     ▼                     ▼
  CREATED  ──────────►  RUNNING  ◄──────── docker unpause
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
           PAUSED       STOPPED      (OOM killed)
        docker pause  docker stop      │
              │        SIGTERM         │
              │        → SIGKILL 10s   │
              │            │           │
              └────────────▼───────────┘
                        EXITED
                           │
                      docker rm
                           │
                           ▼
                        (gone)
```

**Key states**:
- `RUNNING`: PID 1 is alive in the container namespace
- `PAUSED`: cgroup freezer suspends all processes; memory retained
- `EXITED`: PID 1 has exited; writable layer still on disk until `docker rm`
- `DEAD`: container couldn't be removed; resources partially cleaned

---

## Volumes — Persistent and Shared Data

Containers are ephemeral: the writable layer is destroyed with `docker rm`. Volumes survive container removal.

### Three Types Compared

| Type | Syntax | Managed By | Data Persists After `rm`? | Use Case |
|------|--------|-----------|--------------------------|---------|
| **Named volume** | `-v mydata:/data` | Docker daemon | Yes | DB data, app state |
| **Bind mount** | `-v /host/path:/container/path` | Host OS | Yes (host file) | Local dev, config injection |
| **tmpfs mount** | `--tmpfs /run` | Kernel RAM | No (in-memory only) | Secrets, temp files, perf |

### Named Volumes

```bash
# Create
docker volume create pgdata

# Use
docker run -v pgdata:/var/lib/postgresql/data postgres:16

# Inspect (find actual path on host)
docker volume inspect pgdata
# "Mountpoint": "/var/lib/docker/volumes/pgdata/_data"

# Backup
docker run --rm \
  -v pgdata:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/pgdata-backup.tar.gz /data

# Remove (DESTRUCTIVE — data gone)
docker volume rm pgdata
```

### Bind Mounts

```bash
# Mount local code into container for live reloading
docker run \
  -v $(pwd)/src:/app/src \
  -p 3000:3000 \
  node:20-alpine npm run dev

# Mount read-only config
docker run \
  -v $(pwd)/nginx.conf:/etc/nginx/nginx.conf:ro \
  nginx
```

**Bind mount trade-off**: Breaks environment parity — different host paths, permission mismatches on Linux vs Mac. Use only for local dev, never in production images.

### Volume Drivers for Production

| Driver | Backend | Use Case |
|--------|---------|---------|
| `local` | Host disk | Default; single host |
| `nfs` | NFS mount | Shared across hosts |
| `rexray/ebs` | AWS EBS | EBS volume per container |
| `cloudstor:aws` | EFS / S3 | Multi-host shared storage |
| `csi-*` | Kubernetes CSI | K8s-native volume lifecycle |

---

## Networking

### Five Network Drivers

| Driver | Topology | When to Use |
|--------|----------|------------|
| **bridge** (default) | Private subnet (172.17.0.0/16), NAT to host | Single-host container-to-container communication |
| **host** | Container uses host network namespace | Max performance; removes network isolation |
| **none** | No networking | Security-critical containers; add your own network interface |
| **overlay** | Multi-host VXLAN tunnel | Docker Swarm, multi-host container networking |
| **macvlan** | Container gets MAC + IP on LAN | Legacy apps requiring L2 visibility on the physical network |

### Default Bridge Network

```
Host (192.168.1.10)
│
├── docker0 bridge (172.17.0.1)
│     ├── container1 veth → eth0 (172.17.0.2)
│     ├── container2 veth → eth0 (172.17.0.3)
│     └── container3 veth → eth0 (172.17.0.4)
│
└── iptables NAT rules
      MASQUERADE: 172.17.0.0/16 → host IP for outbound
      DNAT: host:8080 → 172.17.0.2:80 for -p 8080:80
```

**Default bridge limitation**: Containers communicate by IP only — no DNS. Use a **user-defined bridge** for DNS by container name.

### User-Defined Bridge (Recommended)

```bash
# Create custom network
docker network create --driver bridge myapp-net

# Containers on same network resolve each other by name
docker run -d --network myapp-net --name db postgres:16
docker run -d --network myapp-net --name app \
  -e DB_HOST=db \          # ← "db" resolves to container IP via Docker DNS
  myapp:latest
```

### Port Mapping

```bash
# Syntax: -p [host_ip:]host_port:container_port[/protocol]
docker run -p 8080:80 nginx          # host:8080 → container:80
docker run -p 127.0.0.1:8080:80 nginx  # bind to localhost only
docker run -p 8080:80/udp nginx      # UDP
docker run -P nginx                  # auto-assign ephemeral port for all EXPOSE'd ports
```

### DNS Inside Containers

```bash
# Default DNS: /etc/resolv.conf inside container
docker run --rm alpine cat /etc/resolv.conf
# nameserver 127.0.0.11        ← Docker's embedded DNS server
# options ndots:0

# Container name resolution works only on user-defined networks
# On default bridge: only --link (deprecated) or IP addresses
```

---

## Docker Client Tools

| Tool | Who Makes It | Key Difference | When to Use |
|------|-------------|----------------|-------------|
| **Docker CLI** (`docker`) | Docker Inc | Talks to dockerd via socket | Default for Docker Desktop users |
| **Docker Desktop** | Docker Inc | GUI + VM for Mac/Windows; includes BuildKit, Compose, Dev Environments | Dev machines |
| **Podman CLI** (`podman`) | Red Hat | Daemonless; rootless by default; OCI-compatible; `alias docker=podman` works | RHEL/Fedora, rootless requirement, CI without daemon |
| **nerdctl** | containerd | containerd-native; same UX as docker CLI; supports Lazy Pulling (eStargz) | K8s-aligned environments; when you want to bypass Docker daemon |
| **Buildah** | Red Hat | Builds OCI images without daemon or Dockerfile; scriptable | CI image builds, integration with Podman |
| **Kaniko** | Google | Builds images inside containers (no privileged mode) | K8s-native CI builds (Tekton, Argo, GCB) |
| **BuildKit** | Docker Inc | Next-gen build engine (parallel builds, cache mounts, secrets) | Already the default in `docker build`; expose via `buildctl` for advanced use |

---

## FAANG Interview Callout

> **What the interviewer is testing**: Can you design a safe, efficient container packaging pipeline? Do you know the footgun of storing secrets in ENV, running as root, or using mutable image tags?
>
> **What to say**: "For a production image, I'd use a multi-stage build — compile in a fat builder image, copy only the binary to a distroless runtime image. This shrinks attack surface and image size. I'd COPY dependency manifests before source code to maximise layer cache hits in CI — a cache miss on a 200MB npm install per commit is a real CI cost. For volumes, I'd use named volumes for DB data (Docker manages the lifecycle) and bind mounts only for local dev. For networking, always use user-defined bridge networks, not the default bridge, because you get DNS by container name — which is how you avoid hardcoding IPs. Never store secrets in ENV variables — they appear in `docker inspect`, container logs, and any image layer. Inject secrets at runtime via Docker secrets, AWS Secrets Manager, or tmpfs mounts."

---

## Related Files

| File | Relationship |
|------|-------------|
| [01-architecture.md](01-architecture.md) | Kernel layer that makes images and containers work (overlay2, namespaces) |
| [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) | Docker vs Podman/Buildah for daemonless builds; VM vs container trade-offs |
| [04-operations-guide.md](04-operations-guide.md) | Hands-on commands for all concepts in this file; Docker Compose full example |
| [05-production-and-cloud.md](05-production-and-cloud.md) | Registry setup (ECR, GCR), security hardening on top of USER/HEALTHCHECK |
