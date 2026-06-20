# High-Level Design (HLD)

This section covers end-to-end system design at scale. Every design should follow the RESHADED framework and be calibrated to handle FAANG-scale traffic.

## Sub-directories

| Folder | Contents |
|--------|----------|
| `designs/` | Full system designs: URL shortener, Twitter feed, WhatsApp, Uber, Netflix, etc. |
| `case-studies/` | Real-world architecture breakdowns: how Slack built presence, how Discord moved from Mongo, etc. |
| `trade-offs/` | Isolated trade-off analyses: SQL vs NoSQL, push vs pull, sync vs async |
| `cloud-architecture/` | Cloud-native designs: serverless, event-driven, multi-region active-active |
| `blogs/` | Summaries of high-signal engineering blogs (Netflix, Uber, AWS, Cloudflare) |
| `resources/` | **Curated links**: seminal papers, company case studies, cloud patterns, books, practice platforms — [hld-engineering-resources.md](resources/hld-engineering-resources.md) |

## Naming Convention

```
designs/[company-or-system]-[feature].md
# Examples:
designs/twitter-timeline-feed.md
designs/uber-ride-matching.md
designs/distributed-rate-limiter.md
```

## Template

Use `/hld [system name]` with Claude to generate a full design following RESHADED.
