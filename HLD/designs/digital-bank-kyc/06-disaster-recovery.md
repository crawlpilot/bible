# 06 — Disaster Recovery & Cross-DC Failover

## 1. RTO / RPO Targets & Regulatory Compliance

### 1.1 Regulatory Mandate

| Regulation | Body | DR Obligation |
|---|---|---|
| RBI BCDR Guidelines (2019 circular) | RBI | Payment systems: RTO ≤ 2 hr, RPO = 0 for critical flows |
| RBI IT Framework for Banks (2011, updated 2021) | RBI | Annual DR drill; documented evidence submitted |
| CERT-In Guidelines for Financial Entities | MeiTY/CERT-In | Incident reporting within 6 hours of major outage |
| SEBI Circular on Business Continuity | SEBI | Market-infrastructure entities: RTO ≤ 30 min |
| NPCI Operational Guidelines | NPCI | UPI/IMPS participating banks: RPO ≤ 15 min |
| PCI-DSS v4.0 Req 12.3 | PCI SSC | Documented BCP tested annually; cardholder-data environment included |

### 1.2 Service Tier Classification & Targets

| Service / Data Store | Tier | RTO Target | RPO Target | Justification |
|---|---|---|---|---|
| Onboarding Orchestrator | Tier-1 Critical | 15 min | 0 (stateless) | Stateless pods; no data loss possible |
| KYC Engine | Tier-1 Critical | 15 min | 0 (stateless) | Stateless; adapters re-called on retry |
| Fraud Screening Service | Tier-1 Critical | 15 min | 0 (stateless) | Stateless; synchronous, fail-closed |
| **PostgreSQL** (leads, KYC records) | Tier-1 Critical | **30 min** | **< 5 min** | Core transactional data; async WAL replication |
| **Kafka** (event bus, ECA, audit) | Tier-1 Critical | **30 min** | **< 60 s** | MirrorMaker 2 near-real-time replication |
| Account Factory + Account DB | Tier-1 Critical | 30 min | < 5 min | Account creation is idempotent; saga replay safe |
| **Elasticsearch** (lead/KYC search) | Tier-2 Supporting | **1 hr** | **< 15 min** | CCR lag; reads degrade gracefully to DB |
| **RabbitMQ** (async commands) | Tier-2 Supporting | **1 hr** | **≈ 0 with outbox** | Outbox pattern ensures no in-flight loss |
| **Redis** (session, rate-limit, idempotency) | Tier-3 Recoverable | **30 min** | **0 (reconstructible)** | Cache — all data reconstructable from PostgreSQL |
| Document Blob Store (S3-compatible) | Tier-2 Supporting | 2 hr | 1 hr | Hourly cross-DC sync; documents not on critical path |
| Vault / CloudHSM (key management) | Tier-1 Critical | 30 min | 0 | Secondary HSM pre-provisioned with replicated keys |
| Audit Log (Kafka → Iceberg) | Tier-2 Supporting | 2 hr | < 15 min | Append-only; Kafka MM2 replication covers this |

**Hard rule**: RTO and RPO targets above represent the maximum. The onboarding path must remain operational even if Elasticsearch and RabbitMQ are degraded — they are not on the synchronous critical path for account creation.

### 1.3 Annual DR Drill Requirements

```
Frequency:   Annual full-stack drill (RBI mandate) + quarterly component drills
Evidence:    Signed DR test report (CTO + CISO + Compliance Officer)
Submission:  Included in Annual IT Audit Report submitted to RBI
Metrics:
  - Actual RTO achieved (detection timestamp → smoke tests passing)
  - Actual RPO achieved (last confirmed write in Primary → first write in Secondary)
  - Data loss count (records, if any)
  - Rollback time (Secondary → Primary failback)
```

---

## 2. Multi-DC Topology

### 2.1 Physical Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     India — Two Data Centers                        │
│                                                                     │
│  ┌──────────────────────────────┐   ┌──────────────────────────┐   │
│  │   Primary DC — Mumbai        │   │  Secondary DC — Hyderabad │   │
│  │   Tier-IV, 2N+1 power/cooling│   │  Tier-III+, N+1           │   │
│  │                              │   │                           │   │
│  │  K8s Cluster: k8s-primary    │   │  K8s Cluster: k8s-secondary   │
│  │  (prod, 100% capacity)       │   │  (warm standby, 50% capacity) │
│  │                              │   │                           │   │
│  │  ● Kafka Cluster (3 brokers) │◄──┤  ● Kafka Cluster (MirrorMaker2│
│  │  ● PostgreSQL primary        │──►│  ● PostgreSQL cross-DC replica│
│  │  ● Elasticsearch leader      │──►│  ● Elasticsearch CCR follower │
│  │  ● RabbitMQ 3-node cluster   │──►│  ● RabbitMQ federation node  │
│  │  ● Redis primary + replica   │──►│  ● Redis cross-DC replica     │
│  │  ● Vault primary             │──►│  ● Vault standby              │
│  │                              │   │                           │   │
│  │  Ingress: HAProxy (BGP VIP)  │   │  Ingress: HAProxy (BGP VIP)   │
│  └──────────────────────────────┘   └──────────────────────────┘   │
│                  │                                │                 │
│                  └───── 10 Gbps dedicated WAN ────┘                 │
│                         (encrypted, MPLS)                           │
│                                                                     │
│  DNS / Traffic:  Single Anycast VIP → Primary DC normally           │
│                  On failover: BGP route withdrawn at Primary;        │
│                  Secondary DC advertises same prefix                 │
│                                                                     │
│  RBI constraint: ALL data remains within India (DPDPA + RBI 2018)   │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 Active-Passive, Not Active-Active

**Decision**: Active-Passive with warm standby.

| Factor | Active-Active | Active-Passive (chosen) |
|---|---|---|
| Write conflicts | Both DCs write simultaneously → KYC record conflicts; requires distributed CRDT or conflict resolution impossible for financial data | Primary is sole writer; no conflict possible |
| Complexity | Extremely high; every service must handle concurrent updates | Lower; standby is read-only until promoted |
| RTO | Near-zero (already live) | 30 min (promotion + DNS propagation) |
| RPO | Near-zero | < 5 min (async lag) |
| Regulatory clarity | Dual-write audit trail complicates PMLA compliance | Single audit trail, clear write origin |
| Split-brain risk | Very high — both DCs may diverge | Fencing via Consul lock prevents dual-primary |

**Verdict**: For a regulated KYC/payments system, active-passive is the safer, auditable choice. Active-active reserved for truly stateless services (API gateway, BFF layer — these run in both DCs behind the Anycast VIP at all times).

### 2.3 Kubernetes Cluster Strategy

```
Two independent clusters — never a stretched multi-DC cluster:
  k8s-primary    (Mumbai)     — all production workloads, full capacity
  k8s-secondary  (Hyderabad)  — warm standby, 50% replica count

Why NOT a stretched cluster:
  - etcd consensus across WAN requires < 10ms RTT; Mumbai–Hyderabad ≈ 8-20ms
    → unreliable; any WAN blip triggers etcd election storm
  - K8s scheduler cannot reason about DC affinity reliably in stretched setups
  - Istio service mesh control plane splits-brain across DCs

GitOps with ArgoCD:
  - Single Git repo source of truth for both clusters
  - Two ArgoCD Application sets: one targeting k8s-primary, one k8s-secondary
  - ConfigMaps differ only in: Kafka bootstrap servers, DB host, S3 endpoints
  - Secrets: Vault agent injector per cluster; each cluster has Vault AppRole credentials
  - ArgoCD sync: automated (k8s-secondary tracks HEAD); k8s-primary uses manual gate for prod safety

Capacity:
  k8s-primary:   30 worker nodes (production load)
  k8s-secondary: 15 worker nodes (warm standby; auto-scales to 30 on failover via Cluster Autoscaler)
```

---

## 3. Per-Technology Replication & Failover

### 3.1 Kafka — MirrorMaker 2

```
Topology:
  Primary DC:   3 Kafka brokers (ZooKeeper-less, KRaft mode)
  Secondary DC: 3 Kafka brokers + MirrorMaker 2 cluster (3 MM2 workers)

MM2 is deployed in Secondary DC — it pulls from Primary:
  Source cluster:      kafka-primary.internal:9092
  Target cluster:      kafka-secondary.internal:9092
  Topics replicated:   onboarding.events.*, kyc.events.*, audit.*, eca.*
  Topic naming:        secondary.onboarding.events.lead_created (prefixed)
  Replication factor:  2 in Secondary (cost vs. durability trade-off on standby)
```

**MM2 Configuration**:
```properties
# mirrormaker2.properties
clusters = primary, secondary
primary.bootstrap.servers = kafka-primary.internal:9092
secondary.bootstrap.servers = kafka-secondary.internal:9092

primary->secondary.enabled = true
primary->secondary.topics = onboarding\.events\..*, kyc\.events\..*, eca\..*, audit\..*
primary->secondary.replication.factor = 2

# Offset sync — consumers in secondary resume from translated offsets
primary->secondary.sync.group.offsets.enabled = true
primary->secondary.sync.group.offsets.interval.seconds = 10

# Heartbeat + checkpoint topics for offset tracking
checkpoints.topic.replication.factor = 2
heartbeats.topic.replication.factor = 2
```

**Replication Lag Monitoring**:
```
Prometheus metric: kafka_mirrormaker_replication_latency_ms_p99
Alert rule:
  WARN  > 5,000 ms  (5 seconds) — approaching SLA boundary
  CRIT  > 60,000 ms (60 seconds) — RPO breach imminent

Consumer group lag (per topic per partition):
  kafka_consumer_group_lag > 1000 (records) for > 2 minutes → WARN
```

**Failover Procedure (Kafka)**:
```
1. MM2 in Secondary already has all topic data up to last replicated offset
2. Declare Secondary Kafka as primary
3. Update all consumer/producer bootstrap.servers in Secondary K8s ConfigMaps
   (ArgoCD applies new ConfigMap; rolling pod restart — < 5 min)
4. After Primary DC recovery:
   Reverse MM2: deploy new MM2 in restored Primary, pull from Secondary
   (secondary.* topic prefix → primary.* topic via offset sync)
5. Perform offset reconciliation: verify no duplicate events via idempotency keys in DB
```

**Split-brain prevention**: producers use `acks=all` + `enable.idempotence=true`; consumers use EOS (exactly-once semantics) with transactional IDs. Duplicate events detected and discarded by ECA engine's Redis dedup store.

---

### 3.2 PostgreSQL — Patroni + Streaming Replication

```
Primary DC topology:
  patroni-primary-1  (leader)
  patroni-primary-2  (synchronous replica — same DC, same AZ different rack)

Cross-DC:
  patroni-secondary-1 (asynchronous streaming replica in Secondary DC)
  — configured as a Patroni standby cluster (Patroni 2.x feature)
  — lags behind primary by async WAL; target lag < 5 minutes

Why async (not synchronous) for cross-DC:
  Synchronous replication requires Primary to wait for Secondary ACK before confirming write.
  Mumbai → Hyderabad RTT ≈ 8-20ms. Every write would incur this penalty.
  At 30 QPS onboarding writes, P99 write latency would increase from < 5ms to > 20ms.
  For a KYC onboarding system, this is acceptable — but for ledger/payment writes it would not be.
  Decision: async cross-DC; synchronous within-DC for zero data loss on single-DC failures.
```

**Patroni Configuration (standby cluster)**:
```yaml
# patroni-secondary.yaml
bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 900  # 15 minutes — hard RPO boundary
                                   # if lag > 15 min, do NOT auto-promote

standby_cluster:
  host: patroni-primary-1.mumbai.internal
  port: 5432
  primary_slot_name: secondary_dc_slot  # replication slot prevents WAL removal

postgresql:
  parameters:
    max_replication_slots: 10
    wal_level: replica
    max_wal_senders: 10
    hot_standby: "on"
    recovery_min_apply_delay: 0  # no intentional delay; minimize RPO
```

**WAL Lag Monitoring**:
```sql
-- Run on replica to check lag
SELECT
    pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn()) AS replay_lag_bytes,
    now() - pg_last_xact_replay_timestamp() AS replay_lag_time;

-- Prometheus via postgres_exporter:
pg_replication_lag_seconds > 300  (5 min) → WARN
pg_replication_lag_seconds > 900  (15 min) → CRIT + page on-call + block failover
```

**Failover Procedure (PostgreSQL)**:
```bash
# Step 1: Verify Secondary DC replica is reachable and lag < 900s
patronictl -c patroni-secondary.yaml list

# Step 2: Check lag (must be below maximum_lag_on_failover)
# If lag > 900s: wait for replay to catch up, or accept data loss with compliance sign-off

# Step 3: Promote standby cluster to standalone cluster
patronictl -c patroni-secondary.yaml edit-config
  # Remove standby_cluster section → triggers promotion

# Step 4: Patroni elects new primary within the Secondary DC cluster
# patroni-secondary-1 becomes writable primary

# Step 5: Update PgBouncer connection pool (via Consul service discovery)
consul kv put postgres/primary "patroni-secondary-1.hyderabad.internal:5432"
# PgBouncer auto-reconfigures via consul-template; zero application code change

# Step 6: Verify with smoke test
psql -h pgbouncer.hyderabad.internal -c "SELECT count(*) FROM leads WHERE created_at > NOW() - INTERVAL '1h';"

# Step 7: pg_rewind for Primary DC recovery (when Primary comes back)
pg_rewind --target-pgdata=/var/lib/postgresql/data \
          --source-server="host=patroni-secondary-1.hyderabad.internal dbname=postgres"
# This re-syncs diverged WAL; prevents having to re-copy full base backup
```

**Idempotency guarantee**: Every saga step in the Onboarding Orchestrator uses a DB-persisted idempotency key (`lead_id + step_name`). On replay after failover, duplicate steps are no-ops. No duplicate accounts can be created.

---

### 3.3 Elasticsearch — Cross-Cluster Replication (CCR)

```
Primary DC:   ES cluster (3 master nodes, 3 data nodes) — kyc-es-primary
Secondary DC: ES cluster (3 master nodes, 3 data nodes) — kyc-es-secondary
              CCR follower indices mirror all leader indices from Primary
```

**CCR Auto-Follow Pattern**:
```json
PUT /_ccr/auto_follow/kyc_follow_pattern
{
  "remote_cluster": "kyc-es-primary",
  "leader_index_patterns": ["kyc_*", "leads_*", "fraud_*"],
  "follow_index_pattern": "{{leader_index}}",
  "settings": {
    "number_of_replicas": 1
  },
  "max_read_request_operation_count": 5120,
  "max_outstanding_read_requests": 12,
  "max_read_request_size": "32mb",
  "max_write_request_operation_count": 5120,
  "max_write_buffer_count": 512,
  "max_retry_delay": "500ms",
  "read_poll_timeout": "1m"
}
```

**CCR Lag Monitoring**:
```
Metric: elasticsearch_ccr_follower_operations_behind (per index)
WARN  > 1000 ops behind  → replication slow
CRIT  > 10000 ops behind → potential RPO breach
```

**Failover Procedure (Elasticsearch)**:
```bash
# Step 1: Pause CCR to freeze follower at consistent point
POST /kyc_leads/_ccr/pause_follow
POST /kyc_documents/_ccr/pause_follow

# Step 2: Close follower indices (required before unfollow)
POST /kyc_leads/_close
POST /kyc_documents/_close

# Step 3: Promote followers to standalone writable indices
POST /kyc_leads/_ccr/unfollow
POST /kyc_documents/_ccr/unfollow

# Step 4: Re-open indices; now writable in Secondary DC
POST /kyc_leads/_open
POST /kyc_documents/_open

# Step 5: Update application ES endpoint via K8s ConfigMap
kubectl patch configmap app-config -n kyc-system \
  --patch '{"data": {"ES_HOST": "kyc-es-secondary.hyderabad.internal:9200"}}'
# Rolling restart of KYC Engine pods (~3 min)

# Recovery: re-establish CCR from Secondary → Primary (reverse direction)
```

**Snapshot fallback** (if CCR lag is unacceptable at time of failure):
```
Hourly snapshots: registered repository on shared MinIO cluster accessible from both DCs
  PUT /_snapshot/shared_repo
  {
    "type": "s3",
    "settings": { "bucket": "es-snapshots", "endpoint": "minio-shared.internal" }
  }

Restore in Secondary: last snapshot = max 1 hour old → RPO = 1 hr (acceptable for ES search tier)
```

---

### 3.4 RabbitMQ — Federation + Quorum Queues

```
Primary DC:   3-node RabbitMQ cluster with Quorum Queues (Raft consensus, RF=3)
Secondary DC: 3-node RabbitMQ cluster with Quorum Queues (RF=3)
              Federation link: Primary is upstream, Secondary is downstream
```

**Within-DC durability (Quorum Queues)**:
```
Quorum queues use Raft — a write is only ACKed after majority (2/3) of queue members confirm.
No message loss on single-node failure within a DC.
Classic mirrored queues deprecated — quorum queues are mandatory for all critical queues.

Queue declaration:
  x-queue-type: quorum
  x-quorum-initial-group-size: 3
```

**Cross-DC Federation**:
```
Federation does NOT create a synchronous replica — it forwards messages.
Primary DC publishes to exchange `kyc.events`. Federation link forwards to Secondary DC exchange.
Consumer in Secondary DC sees messages with small additional latency (typically < 100ms for WAN).

rabbitmq.conf (Secondary DC):
  federation-upstream.primary-dc.uri = amqp://rmq-primary.mumbai.internal
  federation-upstream.primary-dc.prefetch-count = 1000
  federation-upstream.primary-dc.reconnect-delay = 5

Federation Policy:
  Pattern: ^kyc\.|^onboarding\.  (all KYC and onboarding exchanges)
  Definition: {"federation-upstream-set": "all"}
  Priority: 10
```

**Critical gap — in-flight messages at failure**:
```
Problem: messages published to Primary DC but not yet forwarded to Secondary will be lost
         if Primary fails before federation forwards them.

Solution: Outbox Pattern (mandatory for all producers sending to RabbitMQ):

  Outbox table (PostgreSQL):
    id, exchange, routing_key, payload, status (PENDING/SENT), created_at

  Transactional publish:
    BEGIN;
      INSERT INTO leads VALUES (...);
      INSERT INTO outbox (exchange, routing_key, payload) VALUES ('kyc.events', 'kyc.step_completed', '...');
    COMMIT;

  Outbox relay (async):
    SELECT * FROM outbox WHERE status = 'PENDING' ORDER BY created_at LIMIT 100;
    → Publish to RabbitMQ with publisher confirms
    → On confirm: UPDATE outbox SET status = 'SENT'
    → Retry on NACK with exponential backoff

  After failover: outbox relay reads from PostgreSQL (now on Secondary DC) → publishes to Secondary RMQ
  RPO for RabbitMQ: effectively 0 (bounded by PostgreSQL RPO of < 5 min)
```

**Failover Procedure (RabbitMQ)**:
```bash
# Secondary DC already has federated copy of all messages
# Step 1: Consumers in Secondary DC already connected to local RMQ cluster (no change needed)
# Step 2: Producers updated via K8s ConfigMap to point to Secondary DC RMQ
kubectl patch configmap app-config -n kyc-system \
  --patch '{"data": {"RABBITMQ_HOST": "rmq-secondary.hyderabad.internal"}}'
# Step 3: Outbox relay re-publishes any PENDING outbox entries to Secondary DC RMQ
# Step 4: Validate no duplicate processing via message idempotency header (message_id = outbox.id)
```

---

### 3.5 Redis — Sentinel + Cross-DC Async Replica

```
Primary DC:   Redis primary + 2 replicas; 3 Sentinel nodes
Secondary DC: Redis replica (async, cross-DC) + 1 local Sentinel
              On failover: local replica promoted to primary by Sentinel
```

**Configuration**:
```conf
# redis.conf (cross-DC replica in Secondary)
replicaof redis-primary.mumbai.internal 6379
replica-read-only yes
replica-lazy-flush yes   # non-blocking flush during failover
```

**Sentinel quorum**:
```conf
# sentinel.conf (Secondary DC Sentinel)
sentinel monitor mymaster redis-primary.mumbai.internal 6379 2
sentinel down-after-milliseconds mymaster 5000
sentinel failover-timeout mymaster 30000
sentinel parallel-syncs mymaster 1
```

With 3 Primary DC Sentinels + 1 Secondary DC Sentinel → quorum = 2; cross-DC Sentinel participates in leader election.

**Thundering herd on failover**:
```
Problem: cache is cold after failover (replica may lag by minutes);
         all cache misses hit PostgreSQL simultaneously.

Solution: Probabilistic early expiry + pre-warm job
  1. Before declaring failover complete, run cache warm-up job:
       SELECT id, state, account_type FROM leads WHERE updated_at > NOW() - INTERVAL '1h';
       → SET lead:{id}:state {state} EX 3600  (bulk MSET pipeline)
  2. App uses circuit breaker on cache misses: if miss rate > 50% for 30s,
     throttle requests to 25% of normal and queue the rest (jitter)
  3. Cache TTLs staggered: no two top-1000 keys expire at the same second
     (achieved by adding random jitter: TTL = base_ttl + rand(0, base_ttl * 0.1))

RPO: Redis is a cache layer. ALL authoritative data lives in PostgreSQL.
     Redis RPO = 0 by definition — data loss in Redis has no compliance impact.
     RTO = 30 min (Sentinel promotion < 30s; cache warm-up takes the rest).
```

---

## 4. Kubernetes Cross-DC Deployment

### 4.1 GitOps with ArgoCD

```
Git Repo: github.com/internal/kyc-platform-infra (single source of truth)
  /base/           — shared Deployment, Service, PodDisruptionBudget specs
  /overlays/
    /primary/      — Kustomize overlay: Mumbai-specific ConfigMaps, resource limits (100%)
    /secondary/    — Kustomize overlay: Hyderabad-specific ConfigMaps, resource limits (50%)

ArgoCD Application (Primary DC):
  project: kyc-production
  source: overlays/primary
  destination: k8s-primary cluster, namespace kyc-system
  syncPolicy: manual (production safeguard; requires PR approval)

ArgoCD Application (Secondary DC):
  project: kyc-standby
  source: overlays/secondary
  destination: k8s-secondary cluster, namespace kyc-system
  syncPolicy: automated (self-heal enabled; always tracks HEAD)
```

### 4.2 Capacity & Pod Distribution

```yaml
# base/deployment.yaml (representative — Onboarding Orchestrator)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: onboarding-orchestrator
spec:
  replicas: 10        # Primary DC: 10 pods
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 2
  template:
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchLabels:
                  app: onboarding-orchestrator
              topologyKey: kubernetes.io/hostname  # one pod per node

# overlays/secondary/patch-replicas.yaml
- op: replace
  path: /spec/replicas
  value: 5              # Secondary DC: 50% warm standby

---
# PodDisruptionBudget — in base
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: onboarding-orchestrator-pdb
spec:
  minAvailable: 3       # never fewer than 3 pods during drains
  selector:
    matchLabels:
      app: onboarding-orchestrator
```

### 4.3 Failover Traffic Scaling

```
On DR failover declaration, Secondary DC scales to 100%:
  kubectl scale deployment --all -n kyc-system --replicas=<primary_count> \
    --context=k8s-secondary

Or: HPA triggers automatically if CPU/RPS thresholds are met.

Cluster Autoscaler (Secondary DC) pre-configured:
  min nodes: 15 (warm standby)
  max nodes: 30 (full primary capacity)
  scale-up stabilization: 0 seconds (immediate on failover)
```

### 4.4 Health Checks & Readiness Gates

```yaml
# All services must pass DB + Kafka connectivity before receiving traffic
livenessProbe:
  httpGet:
    path: /health/live
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /health/ready   # checks: DB connection, Kafka connectivity, Vault reachability
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 5
  failureThreshold: 2     # strict: remove from LB after 2 failures (10s)

# /health/ready response:
{
  "status": "UP",
  "components": {
    "db":    {"status": "UP", "lag_ms": 3},
    "kafka": {"status": "UP", "lag_records": 12},
    "vault": {"status": "UP"}
  }
}
```

---

## 5. Cross-DC Failover Runbook

```
┌──────────────────────────────────────────────────────────────────────┐
│                     DR FAILOVER RUNBOOK                              │
│          Primary (Mumbai) → Secondary (Hyderabad)                    │
│                                                                      │
│  TOTAL TARGET RTO: 30 minutes from detection to smoke tests passing  │
└──────────────────────────────────────────────────────────────────────┘

T+0:00 — DETECTION
  Prometheus alert: PrimaryDCHealthCheckFailed for > 2 minutes
  PagerDuty: pages on-call SRE + backup SRE + SRE lead
  Automated: Incident created in incident management system

T+0:05 — INCIDENT DECLARATION
  On-call SRE joins war room (Slack/Meet)
  SRE lead declares: DR event YES/NO
    - If network blip (<5 min): wait; do not failover
    - If DC confirmed down: proceed
  Compliance officer notified (mandatory for CERT-In reporting clock)

T+0:07 — DATA CONSISTENCY CHECK (parallel, 3 minutes max)
  Check Kafka MM2 lag:    kubectl exec -n kafka mm2-pod -- ./check_lag.sh
  Check PostgreSQL lag:   patronictl -c patroni-secondary.yaml list
  Check ES CCR lag:       GET /_ccr/stats (follower_operations_behind)
  Decision gate:
    PostgreSQL lag > 900s (15 min): STOP — accept data loss only with Compliance Officer sign-off
    Otherwise: proceed

T+0:10 — DNS / TRAFFIC CUTOVER
  HAProxy admin: withdraw Primary DC BGP prefix
    ip route del 10.0.1.0/24 via <primary-upstream>  (or via BGP community tag)
  Secondary DC HAProxy: advertise prefix
  DNS TTL was pre-lowered to 60s during maintenance window (done weekly)
  Traffic flows to Secondary within 60-90 seconds

T+0:12 — DATABASE PROMOTION
  patronictl -c patroni-secondary.yaml edit-config
    # Remove standby_cluster block
  Patroni auto-promotes secondary-1 as new primary (< 30 seconds)
  PgBouncer reconfigures via consul-template (< 10 seconds)
  Verify: psql -c "SELECT pg_is_in_recovery();"  → must return 'f' (false)

T+0:14 — KAFKA PROMOTION
  Update Secondary K8s ConfigMap: KAFKA_BOOTSTRAP=kafka-secondary.internal:9092
  kubectl rollout restart deployment -n kyc-system  (rolling restart, 3-5 min)
  MM2 reverse: deploy MM2 configuration pulling from old Primary (for recovery sync later)

T+0:16 — ELASTICSEARCH PROMOTION
  POST /kyc_leads/_ccr/pause_follow
  POST /kyc_leads/_close
  POST /kyc_leads/_ccr/unfollow
  POST /kyc_leads/_open
  (repeat for all follower indices)
  Update K8s ConfigMap: ES_HOST=kyc-es-secondary.internal:9200
  kubectl rollout restart deployment kyc-engine -n kyc-system

T+0:18 — RABBITMQ (no action required)
  Consumers already connected to local Secondary DC RMQ
  Update K8s ConfigMap: RABBITMQ_HOST=rmq-secondary.internal
  Outbox relay will re-publish any PENDING entries to Secondary RMQ

T+0:20 — REDIS (auto-recovered via Sentinel)
  Sentinel has already promoted cross-DC replica (< 30s automatic)
  Verify: redis-cli -h redis-secondary.internal ping → PONG
  Run cache warm-up: kubectl create job cache-warmup --image=kyc-cache-warmer -n kyc-system

T+0:25 — VAULT FAILOVER
  Vault standby in Secondary DC unseals from auto-unseal (CloudHSM secondary)
  Health check: vault status → initialized: true, sealed: false
  Update K8s: VAULT_ADDR=https://vault-secondary.internal:8200

T+0:28 — SMOKE TESTS
  ./scripts/dr-smoke-tests.sh --dc=secondary
    ✓ POST /v1/onboarding/leads → 201 Created
    ✓ GET  /v1/onboarding/leads/{id} → 200 with correct state
    ✓ Fraud screening health check → {"status": "UP"}
    ✓ KYC Engine health check → {"status": "UP"}
    ✓ PostgreSQL write → INSERT succeeds
    ✓ Kafka produce + consume → message round-trip < 1s
    ✓ CKYC lookup (mock) → 200 < 200ms

T+0:30 — DECLARE SECONDARY ACTIVE
  Incident status: ACTIVE → MITIGATED
  Notify: RBI incident report initiated (must submit within 6 hours)
  All-hands: communicate status to engineering + business teams

─────────────────────────────────────────────────────────────────────
FAILBACK (after Primary DC recovery — minimum 24 hours stability):
─────────────────────────────────────────────────────────────────────
  1. Restore Primary DC infrastructure
  2. Re-establish replication: Secondary → Primary
     - PostgreSQL: pg_rewind + streaming replication from current primary (Secondary DC)
     - Kafka: MM2 reverse replication (already deployed at T+0:14)
     - ES: CCR with Secondary as leader, Primary as follower
     - Redis: REPLICAOF secondary-primary from Primary DC Redis
  3. Allow sync to complete: PostgreSQL lag = 0, Kafka MM2 lag < 5s
  4. Planned maintenance window failback:
     - Reverse traffic: Secondary BGP withdrawn; Primary re-advertised
     - Promote Primary DB: same runbook steps in reverse
  5. Update ConfigMaps: all services point back to Primary DC
  6. Post-incident review within 5 business days (RBI mandate)
```

---

## 6. Data Consistency Guarantees Across DCs

### 6.1 Replication Lag Budget

| Component | Normal Lag | Alert Threshold | Hard RPO Limit | Action at Hard Limit |
|---|---|---|---|---|
| PostgreSQL WAL | < 30s | 5 min | 15 min | Block failover; require compliance sign-off |
| Kafka MM2 | < 1s | 30s | 60s | Alert; consumers will replay from last committed offset |
| Elasticsearch CCR | < 30s | 2 min | 15 min | Accept reads from stale index; fall back to DB query |
| RabbitMQ federation | < 100ms | 5s | N/A (outbox pattern ensures 0 loss) | Outbox relay on DB |
| Redis async replica | < 1s | 30s | N/A (cache, reconstructible) | Pre-warm from DB |

### 6.2 Exactly-Once Semantics

```
Layer 1 — Kafka:
  Producers:  transactional.id per service instance; enable.idempotence=true
  Consumers:  isolation.level=read_committed (only see committed transaction messages)
  ECA Engine: dedup key = (lead_id, rule_id, event_id) in Redis; TTL 5 min

Layer 2 — PostgreSQL sagas:
  Idempotency table:
    CREATE TABLE idempotency_keys (
      key     VARCHAR(128) PRIMARY KEY,  -- lead_id + step_name
      result  JSONB,
      created_at TIMESTAMPTZ DEFAULT NOW()
    );
  On replay: SELECT result FROM idempotency_keys WHERE key = ?
    → if found: return cached result (no re-execution)
    → if not found: execute + INSERT

Layer 3 — API:
  Every mutation API accepts X-Idempotency-Key header
  Key stored in Redis (TTL 24h) → duplicate requests return 200 with original response
```

### 6.3 Split-Brain Prevention

```
PostgreSQL split-brain:
  Patroni uses DCS (etcd in Consul) as single-writer lock.
  Only one node holds the Patroni leader key at a time.
  If cross-DC network partition: Secondary DC cannot acquire lock while Primary DC etcd is reachable.
  If Primary DC etcd lost: Secondary acquires lock → promotes.
  Fencing: old Primary receives SIGTERM to pg_ctl; Patroni uses pg_rewind before rejoining as replica.

Kafka split-brain:
  KRaft (no ZooKeeper) — single active controller per cluster.
  MM2 is unidirectional — only one cluster is writable at a time.
  Producer idempotency: duplicate records in both clusters identified by Kafka record headers
    (producer_id + sequence_number) and discarded on merge.

Application split-brain:
  BGP ensures only one DC receives traffic at a time (Anycast VIP).
  If somehow both DCs are live (misconfiguration): DB transactions will fail at the
  serialization isolation level (REPEATABLE READ) for conflicting lead state updates.
  Conflict detected → rejected → user retries → correct DC handles.
```

---

## 7. DR Testing & Compliance

### 7.1 Test Schedule

| Test Type | Frequency | Scope | Pass Criteria |
|---|---|---|---|
| Full DR drill | Annual | Complete Primary DC outage simulation | RTO ≤ 30 min, RPO ≤ 5 min, zero data loss measured |
| Component failover drill | Quarterly | One component at a time (DB, Kafka, ES, Redis) | Per-component RTO from §1.2 |
| Chaos engineering | Weekly | Random pod failures, network latency injection | No user-visible errors during steady-state chaos |
| Backup restoration test | Monthly | Restore PostgreSQL from WAL backup + S3 snapshot | Full restore completes in < 2 hours |
| Runbook rehearsal | Bi-annual | Tabletop exercise (no actual failover) | All team members can execute each runbook step without guidance |

### 7.2 DR Metrics Captured During Drill

```
MTTD (Mean Time to Detect):    time from Primary failure → Prometheus alert
MTTI (Mean Time to Isolate):   time from alert → failover decision
MTTF (Mean Time to Failover):  time from decision → Secondary DC traffic live
MTTV (Mean Time to Validate):  time from traffic live → smoke tests passing
Total RTO:                     MTTD + MTTI + MTTF + MTTV

RPO Measurement:
  1. Record timestamp of last successful write in Primary before failure
  2. After failover, find earliest timestamp of that write in Secondary
  3. RPO = failover_timestamp - last_primary_write_timestamp

Data Loss Count:
  SELECT count(*) FROM leads WHERE created_at BETWEEN :last_primary_write AND :failover_timestamp
  AND id NOT IN (SELECT id FROM secondary_leads_snapshot);
```

### 7.3 Chaos Engineering (Chaos Mesh)

```yaml
# Kafka broker failure
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata: { name: kafka-pod-kill }
spec:
  action: pod-kill
  selector:
    namespaces: [kafka]
    labelSelectors:
      "app.kubernetes.io/name": kafka
  mode: one   # kill 1 of 3 brokers

---
# Network partition between DCs (simulated within k8s-secondary)
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata: { name: dc-partition-sim }
spec:
  action: partition
  selector:
    namespaces: [kyc-system]
  direction: both
  target:
    selector:
      namespaces: [kafka]
  duration: "5m"
```

### 7.4 RBI BCDR Report Checklist

```
Annual submission to RBI includes:
  ☐ DR test date and test scenario description
  ☐ Actual RTO achieved (with timestamp evidence)
  ☐ Actual RPO achieved (with data loss count)
  ☐ List of systems tested (all Tier-1 Critical services)
  ☐ Issues found during drill + remediation actions + completion dates
  ☐ Signed by: CTO, CISO, Compliance Officer
  ☐ Next drill scheduled date
  ☐ Any changes to DR architecture since last submission
```

---

## FAANG Interview Callout

> "Your Kafka MirrorMaker 2 is replicating events to the secondary DC. At the moment of Primary DC failure, there are 5,000 events in Kafka that have been published but NOT yet replicated. After failover, how do you ensure those events are not lost AND not processed twice?"

**Answer**:
1. **Not lost**: The outbox pattern ensures every Kafka-bound event is first written transactionally to PostgreSQL (`outbox` table). After failover, the outbox relay service (now running in Secondary DC, reading from the promoted PostgreSQL) re-publishes all `PENDING` outbox entries to Secondary Kafka. The 5,000 events were in `PENDING` state in the DB → they will be re-published.

2. **Not processed twice**: Each Kafka message carries the `outbox.id` as its `message_id` header. The ECA engine's dedup store (Redis) checks `(lead_id, rule_id, message_id)` — if already processed, it's a no-op. Kafka producer uses `transactional.id` — if the same outbox entry is published twice (crash during relay), Kafka deduplication rejects the second write at the broker level.

3. **What about events that were replicated but not yet consumed in Secondary?** MM2 offset translation means consumers in Secondary resume from the translated offset of the last committed Primary offset. Events replicated before failure are consumed exactly once.
