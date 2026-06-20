# Frameworks — Spring Ecosystem Reference

This folder covers the **Spring Framework ecosystem** end-to-end: internals, architecture, production patterns, and interview preparation. Content is calibrated to principal/staff engineer bar at FAANG.

---

## Folder Structure

| Folder | Purpose |
|--------|---------|
| [spring/](spring/) | Deep-dive overviews — how each Spring module works internally |
| [spring-interview/](spring-interview/) | Leveled interview Q&A (L3 → Principal) per module |

---

## Spring Ecosystem Map

```
┌────────────────────────────────────────────────────────────────────┐
│                        Spring Ecosystem                            │
│                                                                    │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │                   Spring Boot (02)                           │ │
│  │          Auto-config · Starters · Actuator · Profiles        │ │
│  └──────────────────────┬───────────────────────────────────────┘ │
│                         │ builds on                               │
│  ┌──────────────────────▼───────────────────────────────────────┐ │
│  │                   Spring Core (01)                           │ │
│  │          IoC · DI · AOP · BeanFactory · SpEL                 │ │
│  └────┬──────────┬──────────┬───────────┬───────────────────────┘ │
│       │          │          │           │                         │
│  ┌────▼──┐  ┌───▼───┐  ┌───▼────┐  ┌──▼──────┐                  │
│  │  MVC  │  │  Data │  │Security│  │WebFlux  │                  │
│  │  (03) │  │  (04) │  │  (05)  │  │  (07)   │                  │
│  └───────┘  └───────┘  └────────┘  └─────────┘                  │
│                                                                    │
│  ┌──────────┐ ┌──────────┐ ┌───────────┐ ┌──────────────────────┐│
│  │  Cloud   │ │  Batch   │ │ Messaging │ │  Cache + Testing     ││
│  │  (06)    │ │  (08)    │ │   (09)    │ │  (10) + (11)         ││
│  └──────────┘ └──────────┘ └───────────┘ └──────────────────────┘│
│                                                                    │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │             Design Patterns (12) — cross-cutting             │ │
│  │   Proxy · Factory · Template · Observer · Strategy · CoR    │ │
│  └──────────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────────┘
```

---

## Module Decision Matrix

| Module | Use When | Avoid When | Alternatives |
|--------|----------|------------|-------------|
| Spring Core | Any Spring app | Greenfield with no DI need | Guice, CDI |
| Spring Boot | Standalone apps, microservices | Library development | Quarkus, Micronaut |
| Spring MVC | REST APIs, server-side rendering | Ultra-low latency streaming | Vert.x, WebFlux |
| Spring Data | JPA/DB access with repositories | Raw JDBC performance critical | jOOQ, JDBI |
| Spring Security | Auth/Authz in any Spring app | Custom minimal auth | Shiro, hand-rolled JWT |
| Spring Cloud | Microservice orchestration | Simple monolith | Kubernetes-native (Istio) |
| Spring WebFlux | High concurrency, streaming | Team unfamiliar with reactive | Akka, Vert.x |
| Spring Batch | ETL, bulk processing, scheduled jobs | Real-time stream processing | Quartz, Apache Spark |
| Spring Messaging | Event-driven, async messaging | Simple REST | Directly with Kafka SDK |
| Spring Cache | Read-heavy, expensive operations | Cache rarely helps writes | Direct Redis/Caffeine |
| Spring Testing | Testing any Spring component | Unit tests with no DI | Plain JUnit + Mockito |

---

## Interview Priority Guide

At **principal/staff engineer** level, interviewers weight these modules:

| Priority | Module | Why It's Asked |
|----------|--------|---------------|
| ★★★★★ | Spring Core | Every Spring question roots here — IoC, AOP, proxies |
| ★★★★★ | Spring Boot | Daily driver; auto-config internals reveal depth |
| ★★★★★ | Spring Security | Auth/Authz architecture is a system design topic |
| ★★★★☆ | Spring MVC | Request lifecycle, filter chain, exception handling |
| ★★★★☆ | Spring Data | N+1, transactions, @Transactional propagation are traps |
| ★★★★☆ | Spring Cloud | Microservices design questions require Cloud knowledge |
| ★★★☆☆ | Spring WebFlux | Reactive is increasingly common; Mono/Flux mechanics |
| ★★★☆☆ | Design Patterns | "What pattern does AOP use?" — fundamental |
| ★★☆☆☆ | Spring Batch | Only for data platform / ETL-focused roles |
| ★★☆☆☆ | Spring Cache | Usually a sub-topic of performance questions |
| ★★☆☆☆ | Spring Messaging | Comes up in event-driven architecture design |
| ★★☆☆☆ | Spring Testing | Testing philosophy matters; specific APIs less so |
