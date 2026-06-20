# RFC-001: Standardize Service Telemetry on OpenTelemetry

**Status**: Draft
**Author(s)**: [Principal Engineer]
**Reviewers**: [SRE Lead], [Platform Engineering Lead], [Security Lead]
**Deciders**: [VP Engineering]
**Target Date**: 2026-07-01

## Problem

Our services emit telemetry through a mix of vendor-specific agents, bespoke logging libraries, and incomplete trace instrumentation. The result is inconsistent signal quality across the platform:

- Some services emit structured logs but no spans
- Some services emit spans but do not propagate trace context across boundaries
- Alerting is inconsistent because metric names and labels vary by team
- Incident response takes longer because the on-call engineer must translate between several telemetry tools

At the current scale, this creates an operational tax every time we debug a production issue or onboard a new service.

## Motivation

We need a standard telemetry model that reduces vendor lock-in, improves debuggability, and makes it possible to reuse dashboards, alerts, and runbooks across teams.

Without standardization, we keep paying the cost of one-off observability integration work for each new service and each new vendor decision.

## Goals

- Standardize all new services on OpenTelemetry for metrics, logs, and traces
- Ensure trace context propagates across HTTP and messaging boundaries
- Make dashboards and alerts portable across backends
- Reduce service-specific observability setup work for platform and product teams

## Non-Goals

- Replacing every existing observability backend immediately
- Redesigning service-specific business metrics
- Changing incident management process in this RFC

## Detailed Design

### Architecture

Each service will use OpenTelemetry SDKs or auto-instrumentation where appropriate. Telemetry will flow through a Collector layer before being exported to backend systems.

```
Service SDK / Auto-instrumentation
        │
        ▼
OpenTelemetry Collector
        │
   ┌─────┼───────────┐
   ▼     ▼           ▼
Metrics  Logs      Traces
```

### Data Flow

1. Services emit spans, metrics, and structured logs using OpenTelemetry APIs.
2. The Collector enriches telemetry with resource attributes and redacts sensitive fields.
3. Metrics are exported to the metrics backend.
4. Logs are exported to the log backend with shared correlation identifiers.
5. Traces are exported to the trace backend, preserving traceparent headers across services.

### Interfaces / APIs

- HTTP services must forward `traceparent` and `tracestate`
- Messaging producers must inject trace context into message headers
- Consumers must extract trace context before processing work
- Shared libraries should expose one default telemetry configuration per language runtime

### Operational Considerations

- The Collector must be deployed redundantly so it does not become a single point of failure
- Sampling rules must preserve error and slow traces
- Sensitive fields must be stripped before export outside approved environments
- Dashboards should be labeled consistently so teams can reuse them without local rewrites

## Trade-offs

| Dimension | Benefit | Cost |
|-----------|---------|------|
| Standardization | Shared conventions across teams and services | Requires migration work in existing services |
| Vendor neutrality | Easier backend replacement later | Some vendor-specific features become less accessible |
| Better incident response | Consistent trace and metric correlation | Collector and SDK configuration adds operational surface area |
| Security | Sensitive field redaction can be centralized | Misconfiguration in the pipeline can still leak data if not reviewed |

## Alternatives Considered

### Option A: Keep Vendor-Specific Agents

This preserves current investments, but it keeps telemetry fragmented and makes long-term migration expensive.

### Option B: Rebuild the Observability Stack Around a Single Vendor

This simplifies short-term adoption but increases lock-in and makes future backend changes expensive.

## Rollout Plan

1. Pilot OTel in one customer-facing service and validate trace propagation end to end.
2. Add shared libraries and configuration for the rest of the Java and Python services.
3. Migrate dashboards and alerts for the highest-traffic services first.
4. Decommission legacy agents only after validation metrics are met for at least two release cycles.

## Success Metrics

- 100% of new services use OpenTelemetry by default
- 90% of production incidents have a directly linked trace within 5 minutes
- Platform teams spend less time creating one-off observability setup per service

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Collector misconfiguration drops telemetry | Run collectors redundantly and monitor export error rate |
| Migration work slows product delivery | Roll out by service tier and phase migrations across releases |
| Teams adopt OTel inconsistently | Provide shared starter libraries and review checklists |
