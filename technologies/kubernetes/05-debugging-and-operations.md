# Kubernetes Debugging, Operations & kubectl Command Reference

---

## Mental Model (Beginner)

Debugging in Kubernetes is like being a detective. Your three best clues are:
1. **Events** (`kubectl describe`) — what happened to this object recently
2. **Logs** (`kubectl logs`) — what the container printed to stdout
3. **Metrics** (`kubectl top`) — is the node/pod out of CPU or memory

Start with Events → then Logs → then Metrics. That order solves 90% of issues.

---

## kubectl Command Reference

### Setup & Context Management

```bash
# Show current context (which cluster you're talking to)
kubectl config current-context

# List all configured contexts
kubectl config get-contexts

# Switch cluster
kubectl config use-context my-prod-cluster

# Set default namespace for current context (saves typing -n everywhere)
kubectl config set-context --current --namespace=production

# Merge multiple kubeconfigs
KUBECONFIG=~/.kube/config:~/.kube/other-config kubectl config view --flatten > ~/.kube/merged

# Aliases (add to ~/.zshrc)
alias k=kubectl
alias kn='kubectl config set-context --current --namespace'
alias kx='kubectl config use-context'
```

---

### Cluster Inspection

```bash
# Cluster info (API server, CoreDNS)
kubectl cluster-info

# All nodes with status, roles, version
kubectl get nodes -o wide

# Node details: conditions, capacity, allocatable, events
kubectl describe node <node-name>

# Node resource usage (requires metrics-server)
kubectl top nodes

# All resources across all namespaces (broad view)
kubectl get all -A

# API resources available (including CRDs)
kubectl api-resources

# Check your permissions
kubectl auth can-i create deployments --namespace production
kubectl auth can-i "*" "*" --namespace kube-system    # Are you cluster-admin?
```

---

### Pod Operations

```bash
# List pods with node, IP, status
kubectl get pods -o wide -n production

# List pods with labels shown
kubectl get pods --show-labels -n production

# Filter pods by label
kubectl get pods -l app=my-service,env=prod -n production

# Watch pods in real-time (refreshes on changes)
kubectl get pods -w -n production

# Sort pods by restart count (find crashlooping)
kubectl get pods --sort-by='.status.containerStatuses[0].restartCount' -n production

# Get pod YAML (including scheduler-added fields, status)
kubectl get pod <pod-name> -o yaml -n production

# Full pod details: events, probes, conditions, resource limits
kubectl describe pod <pod-name> -n production

# Execute command in running container
kubectl exec -it <pod-name> -n production -- /bin/sh

# Execute in specific container (multi-container pod)
kubectl exec -it <pod-name> -c <container-name> -n production -- bash

# Copy file from pod to local
kubectl cp production/<pod-name>:/app/logs/app.log ./app.log

# Copy file to pod
kubectl cp ./config.yaml production/<pod-name>:/tmp/config.yaml

# Pod resource usage (requires metrics-server)
kubectl top pods -n production --sort-by=memory
```

---

### Log Viewing

```bash
# Current logs (last 100 lines)
kubectl logs <pod-name> -n production --tail=100

# Stream logs in real-time
kubectl logs <pod-name> -n production -f

# Logs from a previous (crashed) container instance
kubectl logs <pod-name> -n production --previous

# Logs from a specific container in a multi-container pod
kubectl logs <pod-name> -c <container-name> -n production

# Logs from ALL pods matching a label selector (aggregated)
kubectl logs -l app=my-service -n production --tail=50

# Logs with timestamps
kubectl logs <pod-name> -n production --timestamps=true

# Logs since a duration
kubectl logs <pod-name> -n production --since=1h
kubectl logs <pod-name> -n production --since-time="2024-01-15T10:00:00Z"

# Get logs from all containers in a pod
kubectl logs <pod-name> -n production --all-containers=true
```

**Multi-pod log aggregation tools**:
```bash
# stern — tail logs from multiple pods matching a pattern
stern my-service -n production

# stern with container filter
stern my-service -n production -c app

# k9s — interactive TUI, select pod, press 'l' for logs
k9s -n production
```

---

### Events — First Stop for Debugging

```bash
# Events for a specific object (pod, deployment, node)
kubectl describe pod <pod-name> -n production
# Events section at the bottom shows: Scheduled, Pulled, Created, Started, Killing, etc.

# All events in a namespace, sorted by time
kubectl get events -n production --sort-by='.lastTimestamp'

# Watch events as they happen
kubectl get events -n production -w

# Filter events to just warnings
kubectl get events -n production --field-selector type=Warning

# Events for a specific object via field selector
kubectl get events -n production --field-selector involvedObject.name=<pod-name>
```

---

### Deployments & Rollouts

```bash
# Rollout status (blocks until complete or fails)
kubectl rollout status deployment/my-service -n production

# Rollout history
kubectl rollout history deployment/my-service -n production

# Rollout history for a specific revision
kubectl rollout history deployment/my-service -n production --revision=3

# Rollback to previous version
kubectl rollout undo deployment/my-service -n production

# Rollback to specific revision
kubectl rollout undo deployment/my-service -n production --to-revision=2

# Pause rollout (useful to stop a bad deploy mid-way)
kubectl rollout pause deployment/my-service -n production

# Resume paused rollout
kubectl rollout resume deployment/my-service -n production

# Restart pods (triggers rolling restart without changing the spec)
kubectl rollout restart deployment/my-service -n production

# Scale manually
kubectl scale deployment/my-service --replicas=5 -n production
```

---

### Services & Networking

```bash
# List services
kubectl get services -n production -o wide

# Check service endpoints (are pods registering?)
kubectl get endpoints my-service -n production
# If ENDPOINTS column is empty — pods aren't passing readiness probes

# Port-forward local traffic to a pod (for quick testing)
kubectl port-forward pod/<pod-name> 8080:8080 -n production
kubectl port-forward service/my-service 8080:80 -n production

# DNS debugging — launch a debug pod
kubectl run debug-dns --image=busybox:1.35 --rm -it --restart=Never -- nslookup my-service.production.svc.cluster.local

# Test connectivity between services
kubectl exec -it <pod-name> -n production -- curl -v http://other-service.other-ns.svc.cluster.local/health

# Network policy testing — check if egress is blocked
kubectl exec -it <pod-name> -n production -- nc -zv postgres-service 5432

# Trace a request through ingress
kubectl get ingress -n production -o wide
kubectl describe ingress my-ingress -n production
```

---

### ConfigMaps & Secrets

```bash
# View configmap (decoded)
kubectl get configmap app-config -n production -o yaml

# View secret (base64 — pipe to decode)
kubectl get secret db-credentials -n production -o jsonpath='{.data.password}' | base64 -d

# All secrets in namespace (names only — don't print values in logs)
kubectl get secrets -n production

# Edit configmap in-place (use with care in prod)
kubectl edit configmap app-config -n production

# Create configmap from file
kubectl create configmap app-config --from-file=config.yaml -n production

# Create secret from literal
kubectl create secret generic db-creds --from-literal=password=mysecret -n production
```

---

### Apply, Diff & Dry-Run

```bash
# Apply manifest
kubectl apply -f deployment.yaml -n production

# Server-side dry run (validates against live API, checks admission webhooks)
kubectl apply -f deployment.yaml --dry-run=server -n production

# Client-side dry run (no server call, just schema check)
kubectl apply -f deployment.yaml --dry-run=client -n production

# Diff between local manifest and live cluster state
kubectl diff -f deployment.yaml -n production

# Apply all files in a directory
kubectl apply -f ./k8s/ -n production --recursive

# Force delete a stuck pod (last resort)
kubectl delete pod <pod-name> -n production --force --grace-period=0
```

---

### RBAC Inspection

```bash
# What can my current user do?
kubectl auth can-i --list -n production

# What can a specific service account do?
kubectl auth can-i --list --as=system:serviceaccount:production:my-service -n production

# All role bindings in a namespace
kubectl get rolebindings -n production -o wide

# All cluster role bindings
kubectl get clusterrolebindings -o wide

# Who has cluster-admin?
kubectl get clusterrolebindings -o json | jq '.items[] | select(.roleRef.name=="cluster-admin") | .subjects'
```

---

### Node Operations

```bash
# Mark node unschedulable (no new pods land here)
kubectl cordon node-1

# Drain node (evict all pods, respects PDB)
kubectl drain node-1 --ignore-daemonsets --delete-emptydir-data

# Drain with timeout
kubectl drain node-1 --ignore-daemonsets --delete-emptydir-data --timeout=300s

# Mark node schedulable again
kubectl uncordon node-1

# Add taint to node (e.g., dedicated GPU node)
kubectl taint nodes gpu-node-1 gpu=true:NoSchedule

# Remove taint
kubectl taint nodes gpu-node-1 gpu=true:NoSchedule-

# Label a node
kubectl label node node-1 disktype=ssd
```

---

## Debugging Runbooks

### CrashLoopBackOff

```
Symptom: Pod restarts repeatedly, status shows CrashLoopBackOff

Step 1: Get logs from the crashed container (--previous = last run)
  kubectl logs <pod> -n <ns> --previous

Step 2: Look for:
  - OOMKilled: exit code 137 → increase memory limit
  - Application startup error → fix the app, check env vars / config
  - Missing file / wrong path → check volumeMounts and ConfigMap
  - Permission denied → check runAsUser, file ownership in image

Step 3: Describe pod for events
  kubectl describe pod <pod> -n <ns>
  Look for: OOMKilled in lastState.terminated.reason

Step 4: Check if resource limits are too tight
  kubectl top pods <pod> -n <ns>

Step 5: Temporarily override command for diagnosis
  kubectl run debug --image=<same-image> --rm -it --restart=Never -- /bin/sh
```

### Pending Pod (Never Schedules)

```
Symptom: Pod stuck in Pending state, no node assigned

Step 1: Describe pod — look at Events section
  kubectl describe pod <pod> -n <ns>

Common reasons in Events:
  "0/5 nodes are available: 5 Insufficient cpu"
    → Nodes don't have enough CPU request headroom
    → Solution: add nodes, reduce requests, or wait for scale-up

  "0/5 nodes are available: 5 node(s) had taint..."
    → Pod doesn't tolerate required node taint
    → Solution: add toleration to pod spec

  "0/5 nodes are available: pod has unbound PersistentVolumeClaims"
    → PVC not bound (StorageClass issue, quota exhausted)
    → kubectl get pvc -n <ns> → check status

  "0/5 nodes are available: 5 node(s) didn't match pod affinity"
    → Affinity/anti-affinity unsatisfiable
    → Review affinity rules, check node labels

Step 2: Check node capacity
  kubectl describe nodes | grep -A5 "Allocated resources"
```

### Service Not Reachable

```
Symptom: Cannot connect to a service from another pod or externally

Step 1: Verify service exists and has correct selector
  kubectl get service my-service -n <ns> -o yaml
  Check: spec.selector matches pod labels

Step 2: Check endpoints — are pods registered?
  kubectl get endpoints my-service -n <ns>
  If EMPTY: pods failing readiness probe OR labels don't match

Step 3: Verify pods are ready
  kubectl get pods -l app=my-service -n <ns>
  Look for: READY column shows 0/1 or 0/2

Step 4: Check readiness probe failures
  kubectl describe pod <pod> -n <ns>
  Look for: Readiness probe failed in Events

Step 5: DNS resolution test
  kubectl run tmp --image=busybox --rm -it --restart=Never \
    -- nslookup my-service.production.svc.cluster.local

Step 6: Direct connectivity test (bypassing service)
  Get pod IP: kubectl get pods -o wide
  kubectl run tmp --image=busybox --rm -it --restart=Never \
    -- wget -qO- http://<pod-ip>:8080/health

Step 7: Check NetworkPolicy
  kubectl get networkpolicy -n <ns>
  If policies exist, verify ingress allows traffic from source pod
```

### ImagePullBackOff

```
Symptom: Pod stuck in ImagePullBackOff or ErrImagePull

Step 1: Describe pod — exact error in Events
  kubectl describe pod <pod> -n <ns>

Common errors:
  "unauthorized: authentication required"
    → Registry credentials missing or wrong
    → kubectl get secret regcred -n <ns>
    → Check imagePullSecrets in pod spec

  "not found" / "manifest unknown"
    → Wrong image tag (check CI pushed the right tag)
    → kubectl get deployment <name> -o jsonpath='{.spec.template.spec.containers[0].image}'

  Timeout pulling
    → Nodes can't reach the registry (check VPC, security groups)
    → Try: kubectl run test --image=<image> --rm -it --restart=Never

Step 2: Test registry access from a node
  kubectl debug node/<node-name> -it --image=ubuntu -- crictl pull <image>
```

### OOMKilled

```
Symptom: Container exits with OOMKilled

Step 1: Confirm OOM
  kubectl describe pod <pod> -n <ns>
  Look for: lastState.terminated.reason: OOMKilled
            lastState.terminated.exitCode: 137

Step 2: Check current memory usage
  kubectl top pods -n <ns>

Step 3: Check memory limit
  kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.containers[0].resources}'

Step 4: Decision
  a) Memory leak in app → profile and fix
  b) Limit too low for legitimate workload → increase limits
  c) Sudden spike (batch job, GC pressure) → add JVM/runtime tuning
     For JVM: -XX:MaxRAMPercentage=75.0 instead of -Xmx (respects container limit)
```

---

## Useful Tools

| Tool | Purpose | Install |
|------|---------|---------|
| **k9s** | Interactive terminal UI — browse cluster, logs, exec, describe | `brew install k9s` |
| **kubectx + kubens** | Fast context and namespace switching | `brew install kubectx` |
| **stern** | Multi-pod log tail with colour and filtering | `brew install stern` |
| **kube-ps1** | Show current context/namespace in shell prompt | `brew install kube-ps1` |
| **Lens** | Desktop GUI for Kubernetes | lens.app |
| **Telepresence** | Run local service as if it's inside the cluster (for dev) | `brew install telepresence` |
| **kubectl-neat** | Remove noise from `kubectl get -o yaml` output | `kubectl krew install neat` |
| **krew** | kubectl plugin manager | `https://krew.sigs.k8s.io` |
| **Popeye** | Cluster linter — finds misconfigurations | `kubectl krew install popeye` |
| **Trivy** | Vulnerability scanner for images and K8s configs | `brew install trivy` |

### k9s Keyboard Shortcuts (Most Used)

```
:              → Command mode (type resource name: pods, nodes, svc, deploy)
/              → Filter by name
l              → View logs for selected pod
e              → Edit resource YAML
d              → Describe resource
ctrl+d         → Delete resource
s              → Shell exec into pod
f              → Port-forward
ctrl+k         → Kill pod
0-9            → Switch namespace (0 = all namespaces)
?              → Help / all shortcuts
```

---

## Log Aggregation Patterns

### ELK Stack vs Loki

| | ELK (Elasticsearch + Logstash + Kibana) | Loki + Grafana |
|--|----------------------------------------|----------------|
| Storage model | Full-text index (high storage cost) | Label-indexed + raw chunks (10x cheaper) |
| Query language | Lucene / KQL | LogQL (similar to PromQL) |
| Latency to query | Near real-time | Near real-time |
| Setup complexity | High (Elasticsearch tuning) | Low (Loki is lightweight) |
| Best for | Compliance, full-text search, parsed JSON logs | Cost-effective log storage with metric correlation |
| Used at | Many enterprises | Grafana OSS stack, cloud-native shops |

### Fluentd / Fluent Bit for Log Collection

Both run as DaemonSets, tailing `/var/log/containers/*.log` on every node:

```
Fluent Bit (lightweight, C) → forward to Fluentd (heavy, Ruby, plugin-rich)
                            → OR directly to Loki / Elasticsearch / S3
```

**Production pattern**: Fluent Bit as DaemonSet (low memory, fast) → Loki / Elasticsearch. Use structured logging (JSON) in apps so log parsers can extract fields without regex.

---

## Observability Stack Overview

```
Metrics:    Prometheus → Grafana
Logs:       Fluent Bit → Loki → Grafana (or ELK)
Traces:     OpenTelemetry Collector → Tempo/Jaeger/X-Ray → Grafana
Events:     kubectl get events / Kubernetes Event Exporter → Loki

Grafana becomes the single pane of glass — correlate metrics, logs, traces by time and labels.
```

**kube-state-metrics** vs **metrics-server**:
- `metrics-server`: real-time CPU/memory for `kubectl top` and HPA
- `kube-state-metrics`: exports object state as Prometheus metrics (replica counts, pod phases, deployment conditions) — used for alerting ("Deployment has 0 ready pods")

---

## FAANG Interview Callouts

**Q: "Walk me through debugging a service that's returning 500s in production."**
> 1. **Start with metrics**: Grafana dashboard — which pods are erroring, when did it start, did a deploy happen?
> 2. **Events**: `kubectl get events -n production --sort-by=lastTimestamp` — any pod restarts, OOMKills, or probe failures around the incident time?
> 3. **Logs**: `stern my-service -n production --since 30m` — look for error stack traces, timeout messages
> 4. **Pod health**: `kubectl get pods -n production` — any pods in CrashLoop or not Ready?
> 5. **Endpoints**: `kubectl get endpoints my-service` — is any pod not registered (readiness failing)?
> 6. **Trace correlation**: If distributed tracing is set up, pull the trace ID from error logs, find the slow span in Jaeger/Tempo
> 7. **Rollback if needed**: `kubectl rollout undo deployment/my-service -n production`

**Q: "How do you debug a pod that starts and immediately crashes before you can exec into it?"**
> The pod is in `CrashLoopBackOff` — you can't exec because it's not running long enough. Two approaches:
> 1. `kubectl logs <pod> --previous` — logs from the last crash. This usually reveals the startup error.
> 2. Override the container command to sleep: `kubectl debug <pod> --copy-to=debug-pod --container=app -- sleep 3600` — creates a copy of the pod with the same spec but overrides the entrypoint to sleep, letting you exec in and investigate the filesystem, env vars, and run the binary manually.
