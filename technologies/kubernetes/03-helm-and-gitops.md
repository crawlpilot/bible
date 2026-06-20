# Helm, GitOps & DevOps Process Improvement

---

## Mental Model (Beginner)

Deploying to Kubernetes means writing a lot of YAML. A small app might need 5–10 YAML files (Deployment, Service, ConfigMap, Ingress, ServiceAccount, HPA...). **Helm** is the package manager for Kubernetes — like `apt` for Ubuntu or `npm` for Node. It bundles all your YAML into a versioned "chart" with configurable parameters, so you can deploy complex apps with one command.

**GitOps** takes this further: your Git repository becomes the single source of truth. Every change to the cluster goes through a pull request. A tool (ArgoCD, FluxCD) continuously syncs the cluster to match what's in Git — automatically, safely, auditably.

---

## Helm

### Chart Structure

```
my-service/
├── Chart.yaml           # Chart metadata (name, version, dependencies)
├── values.yaml          # Default configuration values
├── charts/              # Dependencies (sub-charts)
├── templates/           # Kubernetes manifest templates (Go templates)
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── configmap.yaml
│   ├── hpa.yaml
│   ├── serviceaccount.yaml
│   ├── _helpers.tpl     # Named template definitions (reusable partials)
│   └── NOTES.txt        # Post-install instructions (printed after helm install)
└── .helmignore          # Files to exclude from chart packaging
```

### Chart.yaml

```yaml
apiVersion: v2
name: my-service
description: Payment processing microservice
type: application          # or "library" for helper chart
version: 1.3.0             # Chart version — bump on every change
appVersion: "2.5.1"        # Docker image tag / application version
dependencies:
- name: postgresql
  version: "13.2.0"
  repository: "https://charts.bitnami.com/bitnami"
  condition: postgresql.enabled   # Conditional sub-chart
```

**Chart version vs appVersion**: `version` is the Helm chart version (tracks template changes). `appVersion` is informational — the version of the app being packaged. Decouple them: a typo fix in templates bumps `version` without changing `appVersion`.

### values.yaml — The Configuration Interface

```yaml
# Default values — override per environment
replicaCount: 2

image:
  repository: my-registry/my-service
  tag: ""                    # Default empty — set in CI with --set image.tag=$GIT_SHA
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 80
  targetPort: 8080

ingress:
  enabled: false             # Off by default, on in production values
  host: ""
  tls: true

resources:
  requests:
    cpu: 250m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi

autoscaling:
  enabled: false
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70

postgresql:
  enabled: false             # Disable embedded DB; use external in prod

env: {}                      # Extra environment variables passed in per-deployment
```

### Templates & The Go Template Language

Helm uses Go's `text/template` with Sprig functions. Key patterns:

```yaml
# templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "my-service.fullname" . }}     # Named template from _helpers.tpl
  labels:
    {{- include "my-service.labels" . | nindent 4 }}
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}             # Reference values
  {{- end }}
  selector:
    matchLabels:
      {{- include "my-service.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "my-service.selectorLabels" . | nindent 8 }}
    spec:
      containers:
      - name: {{ .Chart.Name }}
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
        imagePullPolicy: {{ .Values.image.pullPolicy }}
        ports:
        - containerPort: {{ .Values.service.targetPort }}
        resources:
          {{- toYaml .Values.resources | nindent 10 }}   # YAML block from values
        {{- with .Values.env }}
        env:
          {{- range $key, $val := . }}
          - name: {{ $key }}
            value: {{ $val | quote }}
          {{- end }}
        {{- end }}
```

### _helpers.tpl — Reusable Named Templates

```yaml
{{/*
Expand the name of the chart.
*/}}
{{- define "my-service.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Common labels — applied to all resources for consistent querying
*/}}
{{- define "my-service.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
```

### Values Hierarchy (Override Order, Low → High)

```
Chart defaults (values.yaml)
    ↑ overridden by
Parent chart values (if sub-chart)
    ↑ overridden by
-f custom-values.yaml (e.g., values-prod.yaml)
    ↑ overridden by
--set key=value (CLI, used in CI for image tags)
```

**Best practice**: Keep only one `values.yaml` per environment (`values-staging.yaml`, `values-prod.yaml`) rather than separate charts. The chart is the same; the values differ.

### Key Helm Commands

```bash
# Install a chart
helm install my-release ./my-service -f values-prod.yaml --set image.tag=abc123

# Upgrade (create or update)
helm upgrade --install my-release ./my-service -f values-prod.yaml --set image.tag=abc123

# Preview rendered YAML (dry run, server-side validation)
helm upgrade --install my-release ./my-service --dry-run --debug

# Rollback to previous release
helm rollback my-release 2

# List all releases in a namespace
helm list -n production

# Show computed values for a running release
helm get values my-release -n production

# Show rendered manifests of a running release
helm get manifest my-release -n production

# Add and update a chart repository
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Package chart for distribution
helm package ./my-service

# Lint for common errors
helm lint ./my-service
```

### Helm Best Practices

| Practice | Why |
|----------|-----|
| Never store secrets in `values.yaml` | Checked into git; use External Secrets Operator or sealed-secrets |
| Pin chart dependencies by exact version | `^1.0.0` can pull breaking updates; use `1.2.3` |
| Set `image.tag` at deploy time, not in values.yaml | Allows CI to inject the exact built SHA |
| Use `--atomic` in CI | Rolls back automatically if any resource fails to become healthy |
| Enable `--wait` with a timeout | Helm waits for Deployment rollout to complete before exiting successfully |
| Use `helm test` for smoke testing | Define a Job in `templates/tests/` that runs post-install validation |
| Use library charts for shared templates | Avoids copy-paste of identical `_helpers.tpl` across 50 service charts |

### Sub-Charts vs Umbrella Chart

**Sub-chart**: A dependency declared in `Chart.yaml`. Values prefixed by chart name: `postgresql.password`.

**Umbrella chart**: A parent chart with no templates of its own — just dependencies. Used to deploy a full application stack (service + DB + cache) as one unit.

```
platform-stack/           # Umbrella chart
├── Chart.yaml            # Lists my-service, redis, postgres as dependencies
├── values.yaml           # Configures all three sub-charts in one file
└── charts/               # Downloaded sub-charts (or symlinks)
```

**Trade-off**: Umbrella charts give atomic deploys but can create circular dependency problems and slow down individual service deploys. Prefer per-service charts with independent ArgoCD Applications for large orgs.

---

## GitOps

### The Push vs Pull Model

**Traditional (Push) CD**:
```
CI pipeline ──► kubectl apply / helm upgrade ──► Cluster
```
- CI needs cluster credentials (high blast radius if compromised)
- Cluster state can drift (manual kubectl changes not tracked)
- No audit trail of who changed what

**GitOps (Pull)**:
```
Developer ──► Git PR ──► merge ──► Git repo (desired state)
                                        ▲
                                        │ watches
                                  ArgoCD/FluxCD
                                        │ syncs
                                        ▼
                                    Cluster (actual state)
```
- Cluster credentials never leave the cluster
- Git is the audit trail (who approved, when, what changed)
- Drift detection: operator alerts if actual state != git state
- Rollback = `git revert`

### ArgoCD vs FluxCD

| Feature | ArgoCD | FluxCD |
|---------|--------|--------|
| UI | Rich web UI | CLI + Grafana dashboard |
| Multi-cluster | Yes, hub-spoke model | Yes, with Cluster API integration |
| Helm support | Native Helm Application | Native HelmRelease CRD |
| Kustomize support | Native | Native |
| App of Apps pattern | Application sets, App-of-Apps | Kustomization nesting |
| Progressive delivery | Integrates with Argo Rollouts | Integrates with Flagger |
| RBAC | Built-in RBAC with SSO (OIDC) | Kubernetes RBAC only |
| Notification | Slack/PagerDuty via ArgoCD Notifications | AlertManager or Notification Controller |
| Maturity | CNCF Graduated | CNCF Graduated |
| Best for | Teams wanting a control plane UI | Teams preferring pure GitOps, Flux operator model |

### ArgoCD Application Pattern

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-service-prod
  namespace: argocd
spec:
  project: production
  source:
    repoURL: https://github.com/myorg/k8s-config
    targetRevision: main
    path: apps/my-service/production     # Folder with values-prod.yaml
    helm:
      valueFiles:
      - values-prod.yaml
      parameters:
      - name: image.tag
        value: "abc1234"                  # Overridden by CI
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    automated:
      prune: true          # Delete K8s resources removed from git
      selfHeal: true       # Re-apply if someone does manual kubectl change
    syncOptions:
    - CreateNamespace=true
    - PrunePropagationPolicy=foreground
```

### CI/CD Integration Pattern

```
┌─────────────────────────────────────────────────────────────────┐
│                     Full GitOps Pipeline                         │
│                                                                  │
│  1. Developer pushes code to app repo (feature branch)          │
│           │                                                      │
│  2. CI builds & tests                                            │
│     ├── docker build -t my-service:$GIT_SHA .                   │
│     ├── docker push my-registry/my-service:$GIT_SHA             │
│     └── Run unit + integration tests                             │
│           │                                                      │
│  3. CI opens PR to config repo (separate from app repo)         │
│     └── Updates image.tag: $GIT_SHA in values-prod.yaml         │
│           │                                                      │
│  4. Human approves PR (or auto-merge for staging)               │
│           │                                                      │
│  5. ArgoCD detects change in config repo                        │
│     └── helm upgrade my-service (with new image tag)            │
│           │                                                      │
│  6. ArgoCD monitors rollout health (readiness probes)           │
│     ├── Success: marks Application Healthy                       │
│     └── Failure: alerts Slack, optionally auto-rollback          │
└─────────────────────────────────────────────────────────────────┘
```

**Why separate app repo and config repo**: App repo changes trigger CI (build, test, push). Config repo changes trigger CD (deploy). This separation means:
- You can deploy a previously-built image without rebuilding
- Git history of the config repo is purely deployment history
- Easier to audit: "when did this image reach production?"

### Kustomize (Alternative to Helm)

Kustomize uses **overlays** — a base directory for shared config, and per-environment overlays that patch it.

```
k8s/
├── base/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── kustomization.yaml
└── overlays/
    ├── staging/
    │   ├── kustomization.yaml   # patches: replica count, image tag
    │   └── replica-patch.yaml
    └── production/
        ├── kustomization.yaml
        └── resource-patch.yaml
```

```yaml
# overlays/production/kustomization.yaml
bases:
- ../../base
images:
- name: my-service
  newTag: abc1234
patches:
- path: resource-patch.yaml
  target:
    kind: Deployment
    name: my-service
```

**Helm vs Kustomize**:
| | Helm | Kustomize |
|--|------|-----------|
| Config approach | Parameterised templates | Strategic merge patches on YAML |
| Learning curve | Higher (Go templates, Helm concepts) | Lower (pure YAML patching) |
| Package ecosystem | Rich (ArtifactHub: 10k+ charts) | None (you own all the YAML) |
| Complex logic | Yes (conditionals, loops, functions) | Limited (patches only) |
| Secret management | External Secrets / Sealed Secrets | Same |
| Best for | Third-party software deployment (Prometheus, Kafka) | First-party service config management |

---

## Process Improvements from GitOps

| Old World | GitOps World | Benefit |
|-----------|-------------|---------|
| SSH into server and change config | PR + review + merge | Audit trail, peer review, rollback via revert |
| "It works on staging, why not prod?" | Identical manifests with env-specific values | Reproducible environments |
| "Who changed the replica count?" | `git log` on config repo | Full history with author and timestamp |
| Manual rollback (kubectl set image) | `git revert <commit>` | Safe, reviewed, tracked rollback |
| Snowflake clusters (config drift) | Self-healing sync (ArgoCD selfHeal) | Drift is automatically corrected |
| Secrets in CI environment variables | External Secrets Operator, Vault | Centralised secret rotation, no secret sprawl |

---

## FAANG Interview Callouts

**Q: "How do you manage configuration differences between 50 microservices across 3 environments?"**
> Use a **monorepo config structure** with one Helm chart per service, environment-specific values files, and an ArgoCD ApplicationSet that generates one ArgoCD Application per service × environment combination. The ApplicationSet uses a Git generator pointing at a directory structure — adding a new service is a PR to add a folder. Secret injection comes from External Secrets Operator pulling from AWS Secrets Manager, keyed by `<env>/<service>/<secret>`. Drift detection catches any out-of-band changes. This is the pattern used at Airbnb (their Kubernetes GitOps migration circa 2020).

**Q: "What happens if someone does a manual `kubectl edit` on a production Deployment?"**
> With ArgoCD `selfHeal: true`, the operator detects the out-of-sync state within ~3 seconds (it watches the API Server) and re-applies the desired state from Git. The manual change is reverted. This is the primary value proposition of GitOps — the cluster's actual state converges to Git state automatically, eliminating snowflake configuration drift.
