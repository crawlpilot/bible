# Docker — Production, Cloud & Security

## Local Setup

### Mac — Docker Desktop (Recommended for Developers)

Docker Desktop runs a lightweight Linux VM (via Apple Hypervisor Framework / HVF) because macOS does not have Linux namespaces natively.

```bash
# Install via Homebrew (preferred)
brew install --cask docker

# Or download from: https://www.docker.com/products/docker-desktop/

# Start Docker Desktop from Applications, then verify:
docker info
docker run --rm hello-world

# Check resources (configure in Docker Desktop → Settings → Resources)
# Recommended for dev: 4 vCPU, 8 GB RAM, 64 GB disk
```

**Key Mac-specific behaviour**:
- Bind mounts use a file sync layer (gRPC FUSE or VirtioFS) — I/O is slower than Linux native
- `host.docker.internal` resolves to the host's IP from inside containers (built-in)
- Docker socket is at `~/.docker/run/docker.sock` (symlinked to `/var/run/docker.sock`)
- Use **VirtioFS** (Docker Desktop ≥ 4.6) for bind mount performance

### Windows — Docker Desktop with WSL2

```powershell
# 1. Enable WSL2 (PowerShell as Admin)
wsl --install
wsl --set-default-version 2

# 2. Install Docker Desktop from https://www.docker.com/products/docker-desktop/
# Enable WSL2 backend in Settings → General

# Verify
docker version
docker run --rm hello-world
```

### Linux — Docker Engine (Production / CI)

```bash
# Ubuntu / Debian — official install script (simplest)
curl -fsSL https://get.docker.com | sh

# Or manual (Ubuntu 22.04)
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add user to docker group (avoid sudo on every command)
sudo usermod -aG docker $USER
newgrp docker

# Start and enable daemon
sudo systemctl enable --now docker

# Verify
docker run --rm hello-world
```

**Rootless Docker** (Linux — no daemon running as root):

```bash
# Install rootless Docker
dockerd-rootless-setuptool.sh install

# Add to ~/.bashrc
export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock

# Start
systemctl --user start docker
```

### Docker Engine Configuration (`/etc/docker/daemon.json`)

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "default-ulimits": {
    "nofile": { "Name": "nofile", "Hard": 64000, "Soft": 64000 }
  },
  "storage-driver": "overlay2",
  "registry-mirrors": ["https://mirror.gcr.io"],
  "live-restore": true,
  "userland-proxy": false
}
```

---

## AWS Setup

### ECR (Elastic Container Registry)

ECR is AWS's managed private OCI registry. It integrates natively with ECS, EKS, and Lambda.

```bash
# 1. Authenticate Docker to ECR (token valid 12 hours)
AWS_ACCOUNT=123456789012
AWS_REGION=us-east-1

aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin \
  $AWS_ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com

# 2. Create a repository
aws ecr create-repository \
  --repository-name myapp \
  --image-scanning-configuration scanOnPush=true \
  --encryption-configuration encryptionType=AES256 \
  --region $AWS_REGION

# 3. Build, tag, and push
docker build -t myapp:v1.2.3 .
docker tag myapp:v1.2.3 $AWS_ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com/myapp:v1.2.3
docker push $AWS_ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com/myapp:v1.2.3

# 4. Pull
docker pull $AWS_ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com/myapp:v1.2.3

# 5. Set lifecycle policy (keep last 10 tagged; delete untagged after 1 day)
aws ecr put-lifecycle-policy \
  --repository-name myapp \
  --lifecycle-policy-text '{
    "rules": [
      {
        "rulePriority": 1,
        "description": "Keep last 10 tagged images",
        "selection": {"tagStatus": "tagged", "tagPrefixList": ["v"], "countType": "imageCountMoreThan", "countNumber": 10},
        "action": {"type": "expire"}
      },
      {
        "rulePriority": 2,
        "description": "Expire untagged after 1 day",
        "selection": {"tagStatus": "untagged", "countType": "sinceImagePushed", "countUnit": "days", "countNumber": 1},
        "action": {"type": "expire"}
      }
    ]
  }'
```

### ECS Fargate — Serverless Containers on AWS

ECS Fargate runs containers without managing EC2 instances. AWS allocates compute per task.

```json
// ECS Task Definition (simplified)
{
  "family": "myapp",
  "networkMode": "awsvpc",               // required for Fargate
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",                          // 0.5 vCPU
  "memory": "1024",                      // 1 GB
  "executionRoleArn": "arn:aws:iam::123456789012:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::123456789012:role/ecsTaskRole",
  "containerDefinitions": [
    {
      "name": "api",
      "image": "123456789012.dkr.ecr.us-east-1.amazonaws.com/myapp:v1.2.3",
      "portMappings": [{ "containerPort": 8080, "protocol": "tcp" }],
      "environment": [
        { "name": "NODE_ENV", "value": "production" }
      ],
      "secrets": [
        {
          "name": "DB_PASSWORD",
          "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789012:secret:myapp/db-password"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/myapp",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "wget -qO- http://localhost:8080/health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
```

### ECS EC2 vs Fargate Trade-off

| Dimension | ECS EC2 | ECS Fargate |
|-----------|---------|-------------|
| **Node management** | You manage EC2 instances | AWS manages compute |
| **Cost** | Lower (EC2 pricing); Reserved Instances available | Higher (~15–25% premium vs EC2 On-Demand); no RI |
| **Startup time** | Fast (container on running node) | 30–90s cold start (provision compute + pull image) |
| **Density control** | Fine-grained placement strategies | None (AWS decides) |
| **Privileged containers** | Yes | No |
| **GPU support** | Yes | No |
| **Custom AMI / kernel** | Yes | No |
| **Use case** | High-density, cost-sensitive, GPU/privileged needs | Default for new services; scale-to-zero; no ops |

---

## GCP Setup

### Artifact Registry

Replaced Container Registry (GCR). Multi-format (Docker, Maven, npm, Python).

```bash
# Authenticate
gcloud auth configure-docker us-central1-docker.pkg.dev

# Create repository
gcloud artifacts repositories create myapp \
  --repository-format=docker \
  --location=us-central1 \
  --description="My app images"

# Build, tag, push
docker build -t myapp:v1.2.3 .
docker tag myapp:v1.2.3 us-central1-docker.pkg.dev/my-project/myapp/api:v1.2.3
docker push us-central1-docker.pkg.dev/my-project/myapp/api:v1.2.3
```

### Cloud Run — Serverless Containers

Cloud Run is the most seamless "container to production" path:

```bash
# Deploy a container directly from source (Cloud Build + Artifact Registry + Cloud Run)
gcloud run deploy myapp \
  --source . \                          # builds image automatically
  --region us-central1 \
  --allow-unauthenticated \
  --memory 512Mi \
  --cpu 1 \
  --min-instances 0 \                   # scale to zero
  --max-instances 100 \
  --set-env-vars NODE_ENV=production \
  --set-secrets DB_PASSWORD=myapp-db-password:latest

# Deploy from existing image
gcloud run deploy myapp \
  --image us-central1-docker.pkg.dev/my-project/myapp/api:v1.2.3 \
  --region us-central1

# Get URL
gcloud run services describe myapp --region us-central1 --format 'value(status.url)'
```

**Cloud Run limits**: 60-minute request timeout max; 32GB memory, 8 vCPU max; no persistent disk (use Cloud SQL or GCS); cold start 100ms–2s (depends on image size and language).

---

## Azure Setup

### Azure Container Registry (ACR)

```bash
# Create ACR
az acr create \
  --resource-group myapp-rg \
  --name myappregistry \
  --sku Basic

# Authenticate
az acr login --name myappregistry

# Build and push
docker build -t myappregistry.azurecr.io/myapp:v1.2.3 .
docker push myappregistry.azurecr.io/myapp:v1.2.3

# Azure Container Instances (ACI) — simplest serverless container on Azure
az container create \
  --resource-group myapp-rg \
  --name myapp \
  --image myappregistry.azurecr.io/myapp:v1.2.3 \
  --registry-login-server myappregistry.azurecr.io \
  --registry-username $(az acr credential show --name myappregistry --query username -o tsv) \
  --registry-password $(az acr credential show --name myappregistry --query passwords[0].value -o tsv) \
  --cpu 1 \
  --memory 1.5 \
  --ports 8080
```

---

## Security Hardening

### Non-Root User (Most Important)

```dockerfile
# Create a dedicated user (don't use uid 0)
RUN addgroup -S appgroup && adduser -S appuser -G appgroup -u 1001
USER appuser:appgroup

# Or with distroless (uid 65532 "nonroot" built-in)
FROM gcr.io/distroless/java17-debian12
USER nonroot
```

### Read-Only Root Filesystem

```bash
# Runtime: prevent any writes to the container filesystem
docker run --read-only \
  --tmpfs /tmp \              # allow writes to /tmp (in RAM)
  --tmpfs /var/run \
  myapp

# Compose:
services:
  api:
    read_only: true
    tmpfs:
      - /tmp
      - /var/run
```

### Capability Dropping

By default Docker containers run with ~14 Linux capabilities (subset of root's 38+). Drop all, then add only what's needed:

```bash
docker run \
  --cap-drop ALL \
  --cap-add NET_BIND_SERVICE \      # only if binding to port < 1024
  myapp

# Most application containers need ZERO capabilities
docker run --cap-drop ALL myapp     # runs fine for most web services
```

### Seccomp Profile

Docker applies a default seccomp profile blocking ~44 syscalls. For stricter control:

```bash
docker run \
  --security-opt seccomp=/path/to/custom-seccomp.json \
  myapp

# Verify which syscalls a container uses (for profile building)
docker run --security-opt seccomp=unconfined strace -f myapp
```

### No New Privileges

```bash
# Prevent container processes from gaining privileges via setuid binaries
docker run --security-opt=no-new-privileges myapp
```

### Image Scanning

```bash
# Trivy (open source, fast)
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image myapp:v1.2.3

# Grype
grype myapp:v1.2.3

# ECR native scanning (configured at push time)
aws ecr describe-image-scan-findings \
  --repository-name myapp \
  --image-id imageTag=v1.2.3

# In CI (fail build on HIGH+ CVEs)
trivy image --exit-code 1 --severity HIGH,CRITICAL myapp:v1.2.3
```

### Secrets Management (Never in ENV)

```bash
# Docker Swarm secrets (file-based, tmpfs mount in container)
echo "supersecret" | docker secret create db_password -
docker service create \
  --secret db_password \               # available at /run/secrets/db_password
  myapp

# AWS Secrets Manager (ECS)
# Reference in task definition "secrets" array (see ECS section above)
# Secret injected as env var at task start; never stored in image

# Vault (any environment)
docker run \
  -e VAULT_ADDR=http://vault:8200 \
  -e VAULT_TOKEN=$(vault login -token-only ...) \
  myapp
# App reads secrets from Vault API at startup

# tmpfs for in-memory secrets (local dev)
docker run --tmpfs /run/secrets:rw,noexec,nosuid,size=65536k myapp
```

### Security Summary Checklist

```
✓ USER <non-root uid> in Dockerfile
✓ --read-only with --tmpfs for writable paths
✓ --cap-drop ALL (add back only what's needed)
✓ --security-opt=no-new-privileges
✓ Secrets via Secrets Manager / Vault, not ENV
✓ Image scanning in CI pipeline (Trivy/Grype)
✓ Pinned base image tags (sha256 digest)
✓ No SSH daemon in container
✓ Minimal base image (distroless / alpine)
✓ .dockerignore excludes .git, .env, credentials
```

---

## Observability

### Log Drivers

```json
// daemon.json — set default log driver for all containers
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
```

| Log Driver | Where Logs Go | When to Use |
|-----------|--------------|------------|
| `json-file` (default) | `/var/lib/docker/containers/<id>/<id>-json.log` | Local dev; use `docker logs` |
| `awslogs` | AWS CloudWatch Logs | ECS / EC2 on AWS |
| `fluentd` | Fluentd collector → any backend | Central log aggregation |
| `gelf` | Graylog / Logstash via UDP | ELK stack |
| `syslog` | Local syslog | Linux host integration |
| `none` | Discard all logs | Security-sensitive or high-volume apps with app-level logging |

### Prometheus + cAdvisor for Container Metrics

```yaml
# docker-compose.yml addition for monitoring
services:
  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
    ports:
      - "8080:8080"

  prometheus:
    image: prom/prometheus:latest
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
    ports:
      - "9090:9090"

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    volumes:
      - grafana_data:/var/lib/grafana
```

Key cAdvisor metrics: `container_cpu_usage_seconds_total`, `container_memory_working_set_bytes`, `container_network_receive_bytes_total`, `container_fs_reads_bytes_total`.

---

## Companies & How They Use Docker / Containers

| Company | How They Use Containers | Key Detail |
|---------|------------------------|------------|
| **Netflix** | Titus (internal container platform on AWS); all 700+ microservices containerised | Titus scheduler handles 3M+ container launches/week; uses cgroup v2, Fenzo scheduler |
| **Uber** | Docker + Kubernetes on bare metal and AWS; ~4,000 microservices | Moved from Mesos to K8s; heavy use of multi-stage builds for Go services |
| **Airbnb** | Kubernetes on AWS; containerised data pipelines | SmartStack → Consul → service mesh for container-to-container discovery |
| **Google** | Borg (internal; predates Docker) → Kubernetes open-sourced 2014 | Every Google service runs in a container; ~2 billion containers launched per week |
| **Stripe** | Docker for local dev; custom CI; AWS for prod | Emphasis on reproducible builds; internal tooling around Dockerfile standards |
| **GitHub Actions** | Ephemeral Docker containers as CI runners | Each job gets a fresh container; Docker-in-Docker for building images in CI |

---

## FAANG Interview Framing

### Container as Unit of Deployment (12-Factor App)

Containers are the natural runtime for 12-factor applications:

| 12-Factor Principle | Container Implementation |
|--------------------|------------------------|
| Codebase | One image per service, version-tagged |
| Dependencies | Bundled in image layers |
| Config | Environment variables at `docker run` / ECS task definition |
| Backing services | External (DB, cache) — not in the same container |
| Build/release/run | Image = build artifact; deploy = run with config |
| Processes | Stateless; horizontal scaling via replicas |
| Port binding | EXPOSE + port mapping |
| Concurrency | `docker run --scale` or K8s HPA |
| Disposability | Fast start/stop; graceful SIGTERM handling |
| Dev/prod parity | Same image in all environments |
| Logs | Write to stdout → log driver ships to aggregator |
| Admin processes | `docker exec` or one-off task containers |

### Immutable Infrastructure Pattern

```
Old way:                          Container way:
  Server → SSH → apt install →      Build new image (v2) →
  modify config → service restart   Deploy new containers →
  (mutable, drift over time)        Remove old containers
                                    (immutable, no drift)
```

### FAANG Interview Callout

> **What the interviewer is testing**: Can you reason about containers in a production system? Do you understand where containers fit in a cloud architecture vs what they don't solve?
>
> **What to say**: "At Google/Netflix scale, every service runs in a container — it's the standard deployment unit. The container image is the release artifact: built once, promoted through dev/staging/prod unchanged. Secrets are never in the image — they're injected at runtime via the secret manager. For the cloud runtime, I'd choose ECS Fargate for new AWS services because it removes node management entirely; I'd choose EKS when I need pod-level scheduling control, custom resource definitions, or a service mesh. The security model I apply in production is: non-root user, read-only filesystem, no capabilities, image scanning in CI, and secrets from Secrets Manager. The thing containers don't solve is data — stateful workloads need a managed database (RDS, CloudSQL) or a distributed system (Cassandra, DynamoDB) backed by persistent storage outside the container lifecycle."

---

## Related Files

| File | Relationship |
|------|-------------|
| [README.md](README.md) | Overview and quick-reference card |
| [01-architecture.md](01-architecture.md) | Kernel architecture that the security hardening (capabilities, namespaces, seccomp) maps to |
| [02-images-and-containers.md](02-images-and-containers.md) | Dockerfile patterns (USER, HEALTHCHECK, multi-stage) used in hardening |
| [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) | ECS vs K8s vs Fargate — orchestration decision expanded |
| [04-operations-guide.md](04-operations-guide.md) | Local commands; Docker Compose examples referenced in cloud context |
