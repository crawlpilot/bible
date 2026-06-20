# Docker — Operations Guide

## Critical Commands Cheatsheet

### Images

```bash
# Pull an image from a registry
docker pull nginx:1.25-alpine
docker pull 123456789.dkr.ecr.us-east-1.amazonaws.com/myapp:v1.2.3

# Build an image from a Dockerfile
docker build -t myapp:latest .
docker build -t myapp:v1.2.3 -f Dockerfile.prod --no-cache .
docker build --platform linux/amd64 -t myapp:latest .   # cross-platform build

# Tag an existing image
docker tag myapp:latest myapp:v1.2.3
docker tag myapp:latest 123456789.dkr.ecr.us-east-1.amazonaws.com/myapp:v1.2.3

# Push to a registry
docker push myapp:v1.2.3
docker push 123456789.dkr.ecr.us-east-1.amazonaws.com/myapp:v1.2.3

# List local images
docker images
docker images --filter "dangling=true"      # untagged images (build cache noise)

# Inspect image layers and metadata
docker inspect nginx:alpine
docker history nginx:alpine                  # show layers + sizes
docker image inspect --format '{{.Config.Env}}' nginx:alpine

# Remove images
docker rmi myapp:latest
docker image prune                           # remove dangling images
docker image prune -a                        # remove all unused images (CAREFUL)

# Save / load (for air-gapped environments)
docker save myapp:v1.2.3 | gzip > myapp.tar.gz
docker load < myapp.tar.gz
```

### Containers

```bash
# Run a container (most common flags)
docker run \
  --name my-nginx \              # name the container
  -d \                           # detached (background)
  -p 8080:80 \                   # host:container port mapping
  -e NGINX_HOST=example.com \    # environment variable
  --memory=256m \                # memory limit
  --cpus=0.5 \                   # CPU limit (0.5 cores)
  --restart=unless-stopped \     # restart policy
  --network myapp-net \          # attach to named network
  -v mydata:/var/data \          # named volume
  nginx:1.25-alpine

# Common run variations
docker run --rm alpine sh -c "echo hello"   # auto-remove on exit (for one-offs)
docker run -it ubuntu:22.04 bash            # interactive + TTY (debugging)
docker run --entrypoint sh nginx:alpine     # override entrypoint

# Execute command in running container
docker exec -it my-nginx sh                 # interactive shell
docker exec my-nginx nginx -t               # non-interactive command
docker exec -u root my-nginx id             # run as different user

# View logs
docker logs my-nginx
docker logs -f my-nginx                     # follow (tail -f style)
docker logs --tail 100 my-nginx             # last 100 lines
docker logs --since 30m my-nginx            # logs from last 30 minutes
docker logs --timestamps my-nginx           # include timestamps

# List containers
docker ps                                   # running
docker ps -a                                # all (including stopped)
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Stop / kill
docker stop my-nginx                        # sends SIGTERM, waits 10s, then SIGKILL
docker stop -t 30 my-nginx                  # wait 30s before SIGKILL
docker kill my-nginx                        # send SIGKILL immediately
docker kill --signal SIGHUP my-nginx        # send specific signal (e.g., reload nginx)

# Remove
docker rm my-nginx                          # remove stopped container
docker rm -f my-nginx                       # force-remove running container
docker container prune                      # remove all stopped containers

# Copy files to/from container
docker cp my-nginx:/etc/nginx/nginx.conf ./nginx.conf    # from container
docker cp ./nginx.conf my-nginx:/etc/nginx/nginx.conf    # to container

# Resource stats (live)
docker stats                                # all containers
docker stats my-nginx --no-stream           # one-shot snapshot

# Inspect container (everything)
docker inspect my-nginx
docker inspect --format '{{.NetworkSettings.IPAddress}}' my-nginx
docker inspect --format '{{json .HostConfig.Memory}}' my-nginx

# Top (processes inside container)
docker top my-nginx

# Diff (files changed vs image)
docker diff my-nginx
```

### Volumes

```bash
# Create and manage
docker volume create pgdata
docker volume ls
docker volume inspect pgdata
docker volume rm pgdata
docker volume prune                         # remove all unused volumes (CAREFUL)

# Use in docker run
docker run -v pgdata:/var/lib/postgresql/data postgres:16
docker run -v $(pwd)/app:/app:ro myapp      # bind mount, read-only

# Backup a volume
docker run --rm \
  -v pgdata:/source:ro \
  -v $(pwd):/backup \
  alpine tar czf /backup/pgdata-$(date +%Y%m%d).tar.gz -C /source .

# Restore a volume
docker run --rm \
  -v pgdata:/target \
  -v $(pwd):/backup \
  alpine tar xzf /backup/pgdata-20240101.tar.gz -C /target
```

### Networks

```bash
# Create and manage
docker network create myapp-net
docker network create \
  --driver bridge \
  --subnet 192.168.100.0/24 \
  --gateway 192.168.100.1 \
  myapp-net

docker network ls
docker network inspect myapp-net
docker network rm myapp-net
docker network prune

# Connect / disconnect running containers
docker network connect myapp-net my-nginx
docker network disconnect myapp-net my-nginx

# Diagnose: check what network a container is on
docker inspect my-nginx --format '{{json .NetworkSettings.Networks}}'
```

### System

```bash
# Disk usage (critical for CI runners running out of disk)
docker system df
docker system df -v                         # verbose: per image/container/volume

# Clean everything unused (CAREFUL — use in CI, not prod)
docker system prune                         # stopped containers + dangling images + unused networks
docker system prune -a                      # also removes unused images (not just dangling)
docker system prune -a --volumes            # also removes unused volumes

# Info and version
docker info
docker version

# Daemon config location
cat /etc/docker/daemon.json                 # Linux
# ~/Library/Group Containers/.../settings.json  # Mac Docker Desktop
```

---

## Docker Compose Deep-Dive

Docker Compose defines a multi-container application as a single YAML file. It manages networks, volumes, and service dependencies.

### Compose File Structure

```yaml
# docker-compose.yml

name: myapp                          # project name prefix for container/network/volume names

services:                            # the containers
  <service-name>:
    image: or build:
    ports:
    environment: or env_file:
    volumes:
    networks:
    depends_on:
    healthcheck:
    restart:
    deploy:
      resources:

networks:                            # user-defined networks (optional; Compose creates a default)
  <network-name>:
    driver: bridge

volumes:                             # named volumes
  <volume-name>:
    driver: local
```

### Full 3-Tier Application Example

This example runs: **nginx (reverse proxy) → Node.js API → PostgreSQL database**. Copy and run as-is.

```yaml
# docker-compose.yml
name: myapp

services:

  # ── Database ─────────────────────────────────────────────────────────────
  db:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_DB: myapp
      POSTGRES_USER: myapp
      POSTGRES_PASSWORD: ${DB_PASSWORD:-changeme}    # from .env file or env var
    volumes:
      - pgdata:/var/lib/postgresql/data              # named volume — persists across rm
      - ./db/init.sql:/docker-entrypoint-initdb.d/init.sql:ro  # init script
    networks:
      - backend
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U myapp -d myapp"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s                              # grace period before health checks start

  # ── Application API ───────────────────────────────────────────────────────
  api:
    build:
      context: ./api
      dockerfile: Dockerfile
      target: runtime                                # multi-stage target
    restart: unless-stopped
    env_file:
      - .env                                         # load from .env file
    environment:
      NODE_ENV: production
      DB_HOST: db                                    # DNS resolves via Compose network
      DB_PORT: 5432
      DB_NAME: myapp
      DB_USER: myapp
      DB_PASSWORD: ${DB_PASSWORD:-changeme}
      PORT: 3000
    volumes:
      - ./api/src:/app/src:ro                        # bind mount for local dev (remove in prod)
    networks:
      - backend
      - frontend
    depends_on:
      db:
        condition: service_healthy                   # wait until DB healthcheck passes
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:3000/health"]
      interval: 15s
      timeout: 5s
      retries: 3
      start_period: 20s
    deploy:
      resources:
        limits:
          cpus: "1.0"
          memory: 512M
        reservations:
          cpus: "0.25"
          memory: 128M

  # ── Nginx Reverse Proxy ────────────────────────────────────────────────────
  nginx:
    image: nginx:1.25-alpine
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/certs:/etc/nginx/certs:ro
      - static_files:/var/www/static:ro
    networks:
      - frontend
    depends_on:
      api:
        condition: service_healthy

# ── Networks ──────────────────────────────────────────────────────────────────
networks:
  frontend:
    driver: bridge
    # nginx and api only — DB not exposed to this network
  backend:
    driver: bridge
    # api and db — isolated from nginx

# ── Volumes ───────────────────────────────────────────────────────────────────
volumes:
  pgdata:
    driver: local              # data persists on host at /var/lib/docker/volumes/myapp_pgdata
  static_files:
    driver: local
```

**Companion `.env` file** (never commit this with real passwords):

```bash
# .env
DB_PASSWORD=supersecret123
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
```

### Essential Compose Commands

```bash
# Start (build if needed, create and start containers, detached)
docker compose up -d

# Start specific services only
docker compose up -d db api

# Rebuild images (ignores cache)
docker compose up -d --build

# Force recreate containers (even if config unchanged)
docker compose up -d --force-recreate

# Stop and remove containers (volumes KEPT)
docker compose down

# Stop and remove containers + volumes (DESTRUCTIVE — deletes DB data)
docker compose down -v

# Stop and remove containers + images
docker compose down --rmi all

# View logs
docker compose logs
docker compose logs -f api                  # follow specific service
docker compose logs --tail 50 api           # last 50 lines

# Run a one-off command in a service container
docker compose run --rm api node --version
docker compose run --rm api sh              # get a shell

# Execute in running container
docker compose exec db psql -U myapp myapp
docker compose exec api sh

# List running services
docker compose ps

# Check resource usage
docker compose stats

# Scale a service (multiple replicas — requires no port binding or use 0 port)
docker compose up -d --scale api=3

# Pull latest images for all services
docker compose pull

# Validate compose file syntax
docker compose config
```

### Compose Profiles (Dev vs Test vs Prod)

```yaml
services:
  api:
    # always runs
    build: ./api

  db:
    # always runs
    image: postgres:16-alpine

  pgadmin:
    image: dpage/pgadmin4
    profiles: ["debug"]                      # only starts with --profile debug

  test-runner:
    build:
      context: ./api
      target: test
    profiles: ["test"]
    depends_on: [db]
    command: npm test

  mailhog:
    image: mailhog/mailhog
    profiles: ["dev", "debug"]
```

```bash
# Start with debug tools
docker compose --profile debug up -d

# Run tests
docker compose --profile test run --rm test-runner
```

---

## Volumes — Detailed Patterns

### Named Volume Lifecycle

```
docker volume create pgdata          Created (empty)
         │
         ▼
docker run -v pgdata:/data ...       Mounted into container; data written
         │
         ▼
docker stop / docker rm <container>  Container gone; volume SURVIVES
         │
         ▼
docker run -v pgdata:/data ...       New container mounts same data
         │
         ▼
docker volume rm pgdata              Volume destroyed — DATA PERMANENTLY LOST
```

### Volume for Database (Production Pattern)

```bash
# Separate volume for WAL and data (PostgreSQL performance pattern)
docker run \
  -v pg_data:/var/lib/postgresql/data \
  -v pg_wal:/var/lib/postgresql/wal \     # separate device for WAL = better IOPS
  postgres:16

# In Compose, map to specific host paths on SSD:
volumes:
  pg_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /mnt/ssd/pgdata             # bind to specific host path
```

---

## Networking — Deep Dive

### Custom Bridge DNS Resolution

```
myapp_frontend network (172.20.0.0/16)
├── nginx  → 172.20.0.2
└── api    → 172.20.0.3

myapp_backend network (172.21.0.0/16)
├── api    → 172.21.0.2   ← api is on BOTH networks
└── db     → 172.21.0.3

Docker embedded DNS (127.0.0.11):
  "db"    → 172.21.0.3   (resolved from api's perspective)
  "api"   → 172.21.0.2   (resolved from nginx's perspective)
  "nginx" → NOT resolvable from db (different network — isolated)
```

This network segmentation is the equivalent of a security group rule: `db` can't be reached from `nginx` because they share no common network.

### Host Networking Trade-offs

```bash
# Use host networking (bypasses NAT, maximum performance)
docker run --network host nginx
# nginx listens on host port 80 directly — no port mapping needed
# Pros: lower latency, no NAT overhead (~0.05-0.2ms saved)
# Cons: no port isolation; container and host share port space; Linux only
```

Use host networking when: latency is critical (high-frequency trading, low-latency proxies), container processes need to bind to specific host ports without mapping, or you're running network diagnostic tools.

### Inter-Container Communication Patterns

```
Pattern 1: Same Compose project (automatic shared network)
  api → db via hostname "db" (automatic)

Pattern 2: Different Compose projects (need external network)
  # Create a shared network manually
  docker network create shared-net

  # In project A's docker-compose.yml:
  networks:
    shared-net:
      external: true       # don't manage this network; it already exists

  # In project B's docker-compose.yml:
  networks:
    shared-net:
      external: true

Pattern 3: Container → host service
  # From inside container, reach host machine services
  docker run --add-host=host.docker.internal:host-gateway myapp
  # Now "host.docker.internal" resolves to host IP
  # (Docker Desktop auto-adds this; Linux needs explicit --add-host)
```

---

## Anti-Patterns and How to Fix Them

| Anti-Pattern | Problem | Fix |
|-------------|---------|-----|
| **Running as root** | Privilege escalation risk; files created as root | `USER 1000:1000` in Dockerfile; verify with `docker run --rm myapp whoami` |
| **Storing secrets in ENV** | Visible in `docker inspect`, container env, image manifest | Docker secrets, tmpfs mount, runtime secret injection (Vault, AWS SSM) |
| **`FROM ubuntu:latest` or `:latest` tag** | Non-deterministic; breaks caching; surprises on rebuild | Pin to digest: `FROM ubuntu:22.04@sha256:abc123…` |
| **No `.dockerignore`** | Sends `node_modules`, `.git`, test data in build context → slow builds | Add `.dockerignore` with `node_modules`, `.git`, `*.md`, `tests/`, `.env` |
| **One `RUN` per command** | Each command = one layer; image bloat | Chain with `&&`, clean up in same `RUN`: `apt-get install … && rm -rf /var/lib/apt/lists/*` |
| **Copying source before deps** | Cache miss on every code change re-runs `npm install` | COPY package files → install → COPY source (see layer caching rules) |
| **No HEALTHCHECK** | Docker/Compose/ECS can't detect app crashes vs container running | Add `HEALTHCHECK CMD curl -f http://localhost:8080/health || exit 1` |
| **Fat images** | Large images = slow pulls, large attack surface | Multi-stage builds; use `distroless` or `alpine` base for runtime stage |
| **Storing state in writable layer** | Data lost on `docker rm`; performance overhead (copy-on-write) | Named volumes for all persistent data |
| **Port binding to `0.0.0.0` in prod** | Container port exposed on all interfaces | Bind to specific interface: `-p 127.0.0.1:8080:80` |

### Before/After Dockerfile

```dockerfile
# ✗ BEFORE — anti-pattern riddled
FROM ubuntu:latest
RUN apt-get update
RUN apt-get install -y python3 python3-pip
COPY . /app
RUN pip install -r /app/requirements.txt
CMD python3 /app/main.py

# Problems: ubuntu:latest; 3 RUN layers that could be 1; COPY before pip install
# (invalidates cache on every code change); running as root; no HEALTHCHECK;
# no cleanup of apt cache; no .dockerignore = slow build context
```

```dockerfile
# ✓ AFTER — production-ready
FROM python:3.12-slim AS builder
WORKDIR /build

# Dependencies first (cache-stable layer)
COPY requirements.txt .
RUN pip install --prefix=/install --no-cache-dir -r requirements.txt

FROM python:3.12-slim
WORKDIR /app

# Non-root user
RUN useradd -r -u 1001 appuser
USER appuser

COPY --from=builder --chown=appuser /install /usr/local
COPY --chown=appuser . .

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')"

EXPOSE 8080
ENTRYPOINT ["python3", "main.py"]
```

---

## FAANG Interview Callout

> **What the interviewer is testing**: Operational discipline — do you know the commands that matter in an incident? Can you design a Docker Compose setup that resembles production? Do you know the security footguns?
>
> **What to say**: "In an incident I'd start with `docker logs -f` and `docker stats` to see what's happening, then `docker exec -it <container> sh` to investigate internals. For networking issues, `docker network inspect` shows the subnet and which containers are connected. For the Compose setup, I always segment networks — the reverse proxy has no direct path to the database; they communicate through the app tier. Named volumes with `depends_on` and `condition: service_healthy` prevents the app from starting before the database accepts connections, which eliminates the race condition that causes 'connection refused' on startup. In production I'd move the secrets from `.env` to AWS Secrets Manager and inject them at task startup, never baking them into the image or Compose file."

---

## Related Files

| File | Relationship |
|------|-------------|
| [01-architecture.md](01-architecture.md) | Internals behind `docker stats` (cgroups), `docker inspect` (namespaces), overlay2 (docker diff) |
| [02-images-and-containers.md](02-images-and-containers.md) | Dockerfile best practices behind the before/after example; volume types; network drivers |
| [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) | Orchestration options when Compose is not enough |
| [05-production-and-cloud.md](05-production-and-cloud.md) | Cloud registry commands (ECR push/pull); ECS task definitions; security hardening commands |
