# RBAC, ABAC, ReBAC, and OPA

> **Principal Engineer Reference** — covers all major authorization models from simple role-based access control through Google's Zanzibar relationship-based model, to policy-as-code with OPA/Rego. Includes database schemas, decision performance, and FAANG-scale authorization architecture.

---

## Part A: RBAC (Role-Based Access Control)

### Core Concept

Users are assigned roles; roles grant permissions. Access decisions: "does the user have role X which grants permission Y?"

```
User ──── (assigned) ──── Role ──── (grants) ──── Permission
alice                   admin                   delete:records
bob                     viewer                  read:records
```

### Flat RBAC

**Database schema:**

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY,
    username VARCHAR(255) NOT NULL UNIQUE
);

CREATE TABLE roles (
    id UUID PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,   -- 'admin', 'viewer', 'editor'
    description TEXT
);

CREATE TABLE permissions (
    id UUID PRIMARY KEY,
    resource VARCHAR(100) NOT NULL,      -- 'records', 'users', 'reports'
    action VARCHAR(50) NOT NULL,         -- 'read', 'write', 'delete'
    UNIQUE(resource, action)
);

CREATE TABLE user_roles (
    user_id UUID REFERENCES users(id),
    role_id UUID REFERENCES roles(id),
    PRIMARY KEY(user_id, role_id),
    granted_by UUID REFERENCES users(id),
    granted_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE role_permissions (
    role_id UUID REFERENCES roles(id),
    permission_id UUID REFERENCES permissions(id),
    PRIMARY KEY(role_id, permission_id)
);
```

**Authorization query:**
```sql
SELECT EXISTS(
    SELECT 1
    FROM user_roles ur
    JOIN role_permissions rp ON ur.role_id = rp.role_id
    JOIN permissions p ON rp.permission_id = p.id
    WHERE ur.user_id = $1
      AND p.resource = $2
      AND p.action = $3
) AS has_permission;
```

**Performance:** Cache user roles in Redis after authentication. Invalidate on role change.

---

### Hierarchical RBAC

Roles inherit from parent roles. A Senior Engineer inherits all Engineer permissions.

```
SuperAdmin
  └── Admin (inherits: SuperAdmin permissions)
        └── Editor (inherits: Admin permissions)
              └── Viewer (inherits: Editor permissions)
```

```sql
ALTER TABLE roles ADD COLUMN parent_role_id UUID REFERENCES roles(id);

-- Recursive CTE to get all inherited permissions
WITH RECURSIVE role_hierarchy AS (
    SELECT id, name, parent_role_id FROM roles WHERE id = $role_id
    UNION ALL
    SELECT r.id, r.name, r.parent_role_id
    FROM roles r
    JOIN role_hierarchy rh ON r.id = rh.parent_role_id
)
SELECT DISTINCT p.resource, p.action
FROM role_hierarchy rh
JOIN role_permissions rp ON rh.id = rp.role_id
JOIN permissions p ON rp.permission_id = p.id;
```

---

### Constrained RBAC: Separation of Duty (SoD)

User cannot simultaneously hold conflicting roles. Classic example: the Requester of a payment cannot also be the Approver.

```sql
CREATE TABLE role_conflicts (
    role_id_a UUID REFERENCES roles(id),
    role_id_b UUID REFERENCES roles(id),
    PRIMARY KEY(role_id_a, role_id_b)
);

-- Check before assigning role
INSERT INTO user_roles (user_id, role_id)
SELECT $user_id, $new_role_id
WHERE NOT EXISTS (
    SELECT 1
    FROM user_roles ur
    JOIN role_conflicts rc ON ur.role_id IN (rc.role_id_a, rc.role_id_b)
    WHERE ur.user_id = $user_id
      AND $new_role_id IN (rc.role_id_a, rc.role_id_b)
      AND ur.role_id != $new_role_id
);
```

---

### RBAC Limitations

| Limitation | Description |
|---|---|
| **Role explosion** | Every unique permission set needs a new role → 1000+ roles in large orgs |
| **Context-insensitive** | Cannot express "can only edit their own records" |
| **No resource-level control** | Role grants access to class of resources, not specific instances |
| **Temporal constraints difficult** | "Access valid only during business hours" requires custom logic |

---

## Part B: ABAC (Attribute-Based Access Control)

### Core Concept

Policy engine evaluates a set of attributes at decision time:
- **Subject attributes:** user.department, user.clearance, user.location
- **Resource attributes:** resource.classification, resource.owner, resource.region
- **Action:** read, write, delete
- **Environment:** current time, request IP, device trust level

```
IF user.department == resource.department
AND user.clearance >= resource.classification
AND environment.time BETWEEN '09:00' AND '17:00'
THEN PERMIT
```

---

### XACML Standard Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Request Flow                                 │
│                                                                  │
│  User ──► PEP (Policy Enforcement Point)  ──► Resource          │
│           │ (intercepts request)                                 │
│           │                                                      │
│           └──► PDP (Policy Decision Point) ──► PAP (policies)   │
│                │ (evaluates policy)          (Policy Admin Point)│
│                │                                                  │
│                └──► PIP (Policy Information Point)               │
│                     (fetches subject/resource attributes)        │
└─────────────────────────────────────────────────────────────────┘
```

- **PEP:** Gateway/middleware; receives permit/deny from PDP; enforces it
- **PDP:** Pure decision function: (request + policies + attributes) → permit/deny
- **PAP:** Admin interface where policies are written and stored
- **PIP:** Attribute store — LDAP for user attrs, database for resource attrs

**Example rule (pseudocode):**
```python
def evaluate(subject, resource, action, environment):
    # Rule 1: Owners can do anything to their resources
    if subject.user_id == resource.owner_id:
        return PERMIT

    # Rule 2: Department members can read same-dept resources
    if (action == "read"
        and subject.department == resource.department
        and subject.clearance >= resource.classification):
        return PERMIT

    # Rule 3: Admins can do anything within their region
    if ("admin" in subject.roles
        and subject.region == resource.region):
        return PERMIT

    return DENY
```

---

### ABAC Strengths and Weaknesses

| Strengths | Weaknesses |
|---|---|
| Handles complex, context-sensitive policies | Policies are hard to audit ("who has access to X?") |
| No role explosion — policy replaces role matrix | Performance: attribute fetch + policy evaluation per request |
| Temporal and environmental constraints natural | Complex policies lead to emergent behavior |
| Fine-grained instance-level control | Harder to reason about than RBAC |

**Performance:** Cache attribute lookups. PDP evaluation: 0.5-5ms without network calls. OPA (below) caches policies in memory and evaluates at ~1ms.

---

## Part C: ReBAC (Relationship-Based Access Control)

### The Google Zanzibar Paper (2019)

Google Zanzibar is the authorization system powering Google Drive, Docs, Photos, YouTube, Maps, and Cloud. It models authorization as a **relationship graph** between users and objects.

**Paper reference:** Zanzibar: Google's Consistent, Global Authorization System (USENIX ATC 2019)
- **Scale:** 10^13 ACL tuples, 10^6 QPS, 95th-percentile latency: 10ms, globally distributed

---

### Tuple Model

Authorization state is stored as tuples: `(object, relation, user)`

```
document:123#owner@user:alice
document:123#editor@user:bob
document:123#viewer@group:engineering#member
folder:projects#owner@user:alice
folder:projects#viewer@group:all-employees#member
```

**Tuple syntax:**
- `object`: `type:id` (e.g., `document:123`, `folder:projects`)
- `relation`: `owner`, `editor`, `viewer`, `member`, `parent`
- `user`: `user:id` OR `object#relation` (userset — any member of that set)

---

### Userset Rewrites (Policy Definition)

```
type document {
  relation owner: user
  relation editor: user | document#owner  ← owners are also editors
  relation viewer: user | document#editor ← editors are also viewers
}

type folder {
  relation parent: folder
  relation owner: user
  relation viewer: user | folder#owner | folder#parent#viewer  ← inherit from parent
}
```

**Check API:** "Is alice a viewer of document:123?"

```
1. Look up direct viewer tuples: document:123#viewer@user:alice → not found
2. Expand via userset rewrite: viewer includes editor
3. Check: document:123#editor@user:alice → not found
4. Expand: editor includes owner
5. Check: document:123#owner@user:alice → FOUND → PERMIT
```

---

### ReBAC Tuple Store Implementation

```sql
CREATE TABLE relation_tuples (
    namespace VARCHAR(100) NOT NULL,  -- 'document', 'folder', 'repo'
    object_id VARCHAR(255) NOT NULL,
    relation VARCHAR(100) NOT NULL,
    subject_type VARCHAR(100) NOT NULL,  -- 'user' or namespace
    subject_id VARCHAR(255) NOT NULL,
    subject_relation VARCHAR(100),       -- NULL for direct user, else userset relation
    created_at TIMESTAMPTZ DEFAULT now(),

    PRIMARY KEY(namespace, object_id, relation, subject_type, subject_id, subject_relation)
);

CREATE INDEX idx_tuples_lookup ON relation_tuples(namespace, object_id, relation);
CREATE INDEX idx_tuples_user ON relation_tuples(subject_type, subject_id);
```

**Check query (simplified):**
```python
def check(obj_ns: str, obj_id: str, relation: str, user_id: str) -> bool:
    # Direct check
    if direct_tuple_exists(obj_ns, obj_id, relation, "user", user_id):
        return True

    # Userset check (e.g., document:123#viewer@group:engineering#member)
    userset_tuples = get_userset_tuples(obj_ns, obj_id, relation)
    for t in userset_tuples:
        if check(t.subject_ns, t.subject_id, t.subject_relation, user_id):
            return True

    # Userset rewrites (owner ⊇ editor ⊇ viewer)
    for implied_relation in schema.expand(obj_ns, relation):
        if check(obj_ns, obj_id, implied_relation, user_id):
            return True

    return False
```

---

### Open-Source Zanzibar Implementations

| System | Maintainer | Notes |
|---|---|---|
| **OpenFGA** | Auth0 (Okta) | Cloud-native; supports OpenFGA schema |
| **SpiceDB** | Authzed | Zanzibar-inspired; Zed language for schema |
| **Ory Keto** | Ory | Simple REST API; Zanzibar-compatible |
| **Google Zanzibar** | Google | Internal only |

---

### When to Use ReBAC

- **Google Docs-style sharing:** "Share this file with Alice (editor), Bob (viewer), everyone in Marketing (viewer)"
- **GitHub-style:** repo → org → team → member hierarchy
- **Hierarchical resources:** folders contain files; access flows down

---

## Part D: OPA (Open Policy Agent)

### Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  Application / Kubernetes / API Gateway                       │
│                                                              │
│  ┌────────────────────────┐      ┌──────────────────────┐   │
│  │       PEP              │─────►│   OPA (PDP)          │   │
│  │  (intercepts request)  │      │   Rego policies in   │   │
│  │                        │◄─────│   memory             │   │
│  └────────────────────────┘      │   data bundle loaded │   │
│                                  └──────────────────────┘   │
│  Input:                                                      │
│    { "user": "alice", "action": "read",                     │
│      "resource": "document:123" }                            │
│  Output: { "allow": true }                                   │
└──────────────────────────────────────────────────────────────┘
```

**OPA deployment patterns:**
1. **In-process library** (Go): lowest latency, no network hop, policies loaded at startup
2. **Sidecar container:** separate process; ~1ms over localhost socket; language-agnostic
3. **Standalone service:** shared OPA for multiple services; ~5ms over network; centralized

---

### Rego Policy Language

```rego
package authz.api

import future.keywords.if
import future.keywords.in

default allow = false

# Rule: allow read if user has the right role
allow if {
    input.method == "GET"
    "viewer" in data.roles[input.user]
}

# Rule: allow write if user is owner
allow if {
    input.method in {"POST", "PUT", "PATCH"}
    input.resource.owner == input.user
}

# Rule: admins can do anything
allow if {
    "admin" in data.roles[input.user]
}

# Rule: deny if user is suspended
deny if {
    data.users[input.user].status == "suspended"
}

# Final decision: allow unless explicitly denied
final_allow if {
    allow
    not deny
}
```

**OPA data model:**
- `input`: the request being evaluated (provided by PEP)
- `data`: policies + context loaded from bundle API or files (role assignments, user attributes)
- Rules are **partial evaluation** — all matching rules contribute to the result

---

### Kubernetes Integration (OPA Gatekeeper)

```yaml
# ConstraintTemplate: custom admission rule
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequiredlabels
spec:
  crd:
    spec:
      names: { kind: K8sRequiredLabels }
      validation:
        openAPIV3Schema:
          properties:
            labels:
              type: array
              items: { type: string }
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequiredlabels
        violation[{"msg": msg}] {
          provided := {label | input.review.object.metadata.labels[label]}
          required := {label | label := input.parameters.labels[_]}
          missing := required - provided
          count(missing) > 0
          msg := sprintf("Missing required labels: %v", [missing])
        }
```

---

### OPA Performance Characteristics

| Metric | Value | Notes |
|---|---|---|
| Policy evaluation latency | 0.5–2ms | Policies in memory |
| Bundle reload | < 1s (incremental) | Policies updated without restart |
| Decision log throughput | >100K decisions/sec | Async logging |
| Memory per policy set | 10–100MB | Depends on data bundles |

**Caching:** OPA caches all data bundles in memory. Partial evaluation pre-computes policy decisions for common query shapes → sub-millisecond for cached queries.

---

## Comparison: Which Model to Use?

| Criterion | RBAC | ABAC | ReBAC | OPA/Rego |
|---|---|---|---|---|
| **Complexity** | Low | High | Medium | Medium |
| **Expressiveness** | Low | High | High (for relationships) | Very High |
| **Performance** | Fast (DB query) | Medium (attribute fetch) | Medium (graph traversal) | Fast (in-memory) |
| **Auditability** | Easy ("who has admin?") | Hard | Medium | Medium |
| **Scale** | Simple orgs | Complex enterprises | Internet-scale (Google) | Any |
| **Best for** | Simple apps, APIs | Enterprise with complex policies | Sharing / collaboration systems | Kubernetes, policy-as-code |

---

## FAANG Interview Callout

**Q: "Design the authorization system for a Google Docs-like product at 100M users."**
→ ReBAC (Zanzibar model). Tuple store: `(document:X, editor, user:alice)`. Userset rewrites: editor ⊇ viewer. Folder inheritance: `(folder:Y, parent, folder:Z)` → viewer access flows down. OpenFGA or SpiceDB as implementation. Check API: sub-millisecond for direct tuples, 10-50ms for deep graph traversal (cache intermediate results). Zookeeper-like consensus for global consistency with bounded staleness (Zanzibar uses "zookies" — consistency tokens).

**Q: "RBAC has role explosion at your 5000-person company. What do you do?"**
→ Three options: (1) ABAC — replace role matrix with policy rules (user.dept = resource.dept); reduces roles from O(teams × permissions) to O(policy rules). (2) Hierarchical RBAC — roles inherit; reduces redundant assignments. (3) Hybrid: RBAC for coarse-grained access (authenticated users vs admins), ABAC for fine-grained instance-level decisions. At FAANG scale: use ABAC with OPA for policy decisions, RBAC for broad access gates.

**Q: "How does OPA differ from writing authorization logic in application code?"**
→ OPA: policies as data (versioned, testable, auditable, deployable separately from application code). Enables: policy changes without code deployments; centralized policy management across services; unit tests for access control; decision logging for audit. Application code: policies scattered across services, hard to audit "who can do X across all services?", policy changes require coordinated deployments.
