# ML Systems Observability — Monitoring, Drift Detection, and Production ML Health

**Category**: AI/ML Systems · MLOps · Observability · Production Reliability
**Reference**: *Observability Engineering* (Majors/Fong-Jones/Miranda); Chip Huyen — *Designing Machine Learning Systems*

> "A deployed ML model is a software service. All the observability principles that apply to software services apply to ML models — plus an additional set of challenges unique to statistical models: data drift, concept drift, model staleness, and silent prediction degradation."

---

## Why ML Observability Is Harder Than Software Observability

For a traditional software service, failure is binary: the function either returns the correct result or it doesn't. You can define "correct" in terms of HTTP status codes, response schemas, and unit tests.

For an ML model in production:
- The model always returns a prediction — even when the prediction is wrong
- There is no compile-time check that verifies prediction quality
- Model quality degrades gradually and silently — there is no stack trace
- The root cause of degradation may be upstream (data quality) or model-level (concept drift)
- Retraining is the "hotfix" — but it takes hours to days

**The core challenge**: Silent degradation. A model serving wrong predictions looks exactly like a model serving correct predictions from a traditional service health perspective (HTTP 200, latency < 200ms, no errors). You need ML-specific monitoring to detect it.

---

## The Four Monitoring Layers for ML Systems

### Layer 1: Infrastructure (Operational)

Standard software observability — the four golden signals applied to the model serving layer:

| Signal | Metric | Alert Condition |
|--------|--------|----------------|
| **Latency** | P50/P99/P999 prediction latency | P99 > 2× baseline; p999 > 5× baseline |
| **Traffic** | Predictions per second per model version | Drop > 30% vs 1-week same-period baseline (upstream issue) |
| **Errors** | Prediction request failures (HTTP 5xx) | Error rate > 0.1% |
| **Saturation** | GPU/CPU utilization, memory, queue depth | GPU utilization > 85% for > 5 minutes |

**Why this layer alone is insufficient**: Model serving can show all-green operational metrics while silently returning terrible predictions. Layers 2–4 are what make ML observability meaningful.

### Layer 2: Input Data Quality (Data Validation)

Every prediction request carries an input feature vector. Monitor that input features match the distribution the model was trained on.

**Feature statistics to monitor**:

```
For each input feature:
  Numerical features:
    - Mean, std deviation, min, max (per 1-hour window)
    - Null/missing rate
    - Distribution shape (histogram buckets)
    - Outlier rate (values beyond μ ± 3σ)

  Categorical features:
    - Cardinality (number of distinct values)
    - Frequency distribution of top-N values
    - Unseen category rate (categories not in training vocabulary)
    - Null rate

  Embedding inputs (for NLP/recommendation models):
    - Vocabulary coverage rate (OOV rate for text tokens)
    - Sequence length distribution
    - Zero-vector rate (embedding lookup failures)
```

**Data drift detection** — statistical tests:

| Test | Use Case | Sensitivity |
|------|---------|-------------|
| **KL Divergence** | Detect distribution shift for continuous features | Sensitive to tail changes; requires density estimation |
| **Population Stability Index (PSI)** | Industry standard for feature drift in credit/risk models; PSI > 0.2 = significant drift | Interpretable threshold; good for categorical and bucketed numerical |
| **Kolmogorov-Smirnov (KS) test** | Non-parametric test for continuous distribution shift | Good for detecting shifts without assuming distribution shape |
| **Chi-Square test** | Categorical feature distribution shift | Standard for categorical features |
| **Jensen-Shannon Divergence** | Symmetric version of KL; bounded 0–1 | Better than KL for comparing distributions with disjoint support |

**Implementation**:
```python
# Example: PSI computation for a numerical feature
def compute_psi(expected: np.ndarray, actual: np.ndarray, buckets: int = 10) -> float:
    """
    Population Stability Index. PSI < 0.1: stable. 0.1–0.2: monitor. > 0.2: significant drift.
    """
    expected_pct = np.histogram(expected, bins=buckets)[0] / len(expected)
    actual_pct = np.histogram(actual, bins=buckets)[0] / len(actual)
    # Avoid log(0)
    expected_pct = np.clip(expected_pct, 1e-6, None)
    actual_pct = np.clip(actual_pct, 1e-6, None)
    psi = np.sum((actual_pct - expected_pct) * np.log(actual_pct / expected_pct))
    return psi
```

**Alerting on data drift**:
```
Alert: feature_drift_detected
Condition: PSI(feature_X, window=1h) > 0.2
Action: investigate upstream data pipeline; check for schema change, null rate increase, 
        or feature engineering bug in serving path
```

### Layer 3: Prediction Distribution (Output Monitoring)

Even if inputs look healthy, the model may produce systematically different predictions than expected.

**Prediction distribution metrics**:

```
For classification models:
  - Class probability distribution (softmax outputs) per hour
  - Predicted class distribution — alert if class proportion shifts significantly
    (e.g., "fraud" predictions suddenly drop from 2% to 0.1% of requests)
  - Confidence distribution — alert if model becomes systematically uncertain
    (mean confidence drops from 0.87 to 0.63)
  - Entropy distribution — high entropy = model is uncertain across classes

For regression models:
  - Prediction value distribution (mean, std, min, max, percentiles)
  - Alert if prediction mean shifts > 2σ from training distribution
  - Alert if prediction variance collapses (model stuck on one value)

For ranking / recommendation models:
  - Diversity of top-K items served (are we recommending the same items to everyone?)
  - Novelty: fraction of recommendations from new (unseen during training) items
  - Position bias: are the same items consistently ranked #1?
```

**Why prediction monitoring catches what data monitoring misses**: Even if input features are in-distribution, the model may have learned a spurious correlation that is no longer valid (concept drift). Prediction distribution monitoring detects the output symptom of concept drift.

### Layer 4: Outcome Monitoring (Ground Truth)

The most reliable but slowest signal. When ground truth labels become available (after the prediction's consequence plays out), compare model predictions against actuals.

| Model Type | Prediction | Ground Truth Availability | Lag |
|-----------|-----------|--------------------------|-----|
| Fraud detection | "This transaction is fraudulent" | Chargeback confirmed/denied | Days–weeks |
| Recommendation | "User will click this item" | Click event (or lack of) | Minutes–hours |
| Demand forecast | "Store X will sell N units tomorrow" | Actual units sold | 24 hours |
| Credit scoring | "Applicant will default" | Default event | Months–years |
| Content moderation | "This post violates policy" | Human moderator review | Hours–days |

**Outcome metrics**:
```
Binary classification:
  - Precision, Recall, F1 per time window (compare against training benchmark)
  - AUC-ROC per time window
  - Calibration: does P(fraud) = 0.7 actually mean 70% of flagged cases are fraud?

Regression:
  - MAE, RMSE, MAPE per time window
  - Residual distribution (systematic bias = model under/over-predicting)

Ranking:
  - CTR (click-through rate), NDCG, MAP per time window
  - A/B holdout group comparison
```

**Practical challenge**: Ground truth lag means you detect model degradation days or weeks after it started. Layers 2 and 3 (data and prediction monitoring) provide leading indicators that correlation with future outcome degradation.

---

## Concept Drift vs Data Drift

| Type | Definition | Example | Detection | Fix |
|------|-----------|---------|-----------|-----|
| **Data drift** (covariate shift) | Input feature distribution changes; the relationship X→Y is unchanged | Traffic prediction model: traffic patterns change seasonally (more WFH after COVID) | Layer 2: PSI on input features | Retrain on recent data; or recalibrate |
| **Concept drift** | The relationship X→Y changes; input distribution may be the same | Fraud detection: fraudsters adopt new tactics not in training data | Layer 4: degrading precision/recall; Layer 3: confidence collapse | Retrain with recent labeled data; online learning |
| **Upstream schema change** | Feature engineering bug; schema migration introduces null values or wrong data types | After a DB migration, `user_age` becomes NULL for new users | Layer 2: null rate spike; layer 1: potential NaN-based errors | Fix the upstream pipeline; patch the serving path |
| **Label shift** | Output distribution changes; class proportions in production differ from training | Fraud rate drops from 3% to 0.5% due to new KYC controls; model calibrated to 3% | Layer 3: predicted fraud rate remains at 3% while actual drops | Recalibrate model thresholds; retrain with recent labels |
| **Feedback loop drift** | Model predictions influence the data used to train the next model | Recommendation model's outputs become next month's training data; popularity bias amplifies | Emerging pattern in outcome metrics; diversity drops over time | Inject diversity; use counterfactual logging; break feedback loop |

---

## SLOs for ML Systems

Define ML-specific SLIs that capture model health, not just service health.

```
SLI-1: Prediction freshness (for recommendation / personalization)
  Good event: prediction served from a model trained within the last 7 days
  Total event: all prediction requests
  SLO: 99.9% of predictions served from a model < 7 days old, 30-day rolling

SLI-2: Feature freshness (for real-time feature pipelines)
  Good event: prediction uses feature values updated within the last 5 minutes
  Total event: all prediction requests
  SLO: 99% of predictions use features updated within 5 minutes, 7-day rolling

SLI-3: Data quality (for batch feature pipelines)
  Good event: feature pipeline completed without data validation failure
  Total event: each scheduled pipeline run
  SLO: 99.5% of pipeline runs complete without data quality failure, 30-day rolling

SLI-4: Model accuracy (when ground truth is available within 24h)
  Good event: prediction within acceptable error bound (regression: |predicted - actual| / actual < 10%)
  Total event: all predictions with available ground truth
  SLO: 95% of predictions within error bound, 7-day rolling
  [Note: this SLO has a 24-hour lag — use prediction and data SLOs for real-time alerting]
```

---

## ML Observability Architecture

### Reference Architecture

```
Prediction Request
    │
    ▼
Feature Store (real-time feature retrieval)
    │ Feature values + metadata (freshness timestamp, version)
    ▼
Model Serving Layer (TF Serving / TorchServe / Triton)
    │ Input features → Model → Prediction
    │
    ├──→ Prediction Log (Kafka topic: model-predictions)
    │     Fields: request_id, model_version, input_features, 
    │             prediction, confidence, latency_ms, timestamp
    │
    └──→ Response to client
    
    Later (when ground truth available):
    Ground Truth Event (Kafka topic: ground-truth-labels)
        │ request_id, ground_truth_label, label_timestamp
        ▼
    Outcome Joiner (Flink stream-stream join, 48h window)
        │ Joins prediction + ground truth by request_id
        ▼
    Metrics Store (Prometheus + Grafana)
        │ Computes: accuracy, precision, recall, PSI, calibration
        ▼
    Alerting (Grafana Alerting → PagerDuty)
```

### Key Design Principles

**1. Log everything at prediction time** (not just errors):
```
Every prediction must be logged with:
  - request_id (for joining with ground truth later)
  - model_version (to correlate quality issues with specific model versions)
  - input_feature_values (for data drift computation offline)
  - raw prediction (probability scores, not just the label)
  - serving latency
  - feature freshness timestamps (how old were the features used?)
```

**2. Prediction log is the source of truth for ML monitoring**:
The prediction log in Kafka is the equivalent of the WAL for a database. All monitoring (data drift, prediction distribution, outcome metrics) is derived from this log. Do not derive ML health from the model serving layer's internal state.

**3. Use shadow deployments for model validation**:
```
Production request
    ├──→ Model A (production): prediction served to user
    └──→ Model B (shadow): prediction computed but NOT served; logged for comparison

Shadow evaluation metrics:
  - Agreement rate between A and B predictions
  - Distribution comparison of A vs B predictions
  - If B shows significantly different prediction distribution → investigate before promoting
```

**4. Canary deployment for model promotion**:
```
Traffic split during canary (first 24 hours after promoting Model B):
  5% → Model B (new version)
  95% → Model A (production)

Monitor:
  - Outcome metrics (if ground truth available within 24h)
  - Prediction distribution shift (hours)
  - Data drift on Model B's inputs vs baseline
  - Latency and error rate

Promotion criteria:
  □ Outcome metrics ≥ baseline (or within -5% tolerance during 24h canary)
  □ Prediction distribution stable (PSI < 0.1 vs production distribution)
  □ Latency P99 ≤ baseline + 20%
  □ No data validation failures
```

---

## Alerting for ML Systems

### Alert Priority Matrix

| Alert | Condition | Severity | Response |
|-------|----------|----------|---------|
| Feature pipeline failure | Pipeline failed to run; features are stale | SEV-1 | Auto-fallback to last valid features; page on-call |
| Data drift detected | PSI > 0.25 for any top-10 feature | SEV-2 | Ticket + Slack notification; investigate data pipeline |
| Prediction distribution shift | Predicted positive rate drops/spikes > 3σ from baseline | SEV-2 | Investigate within 2 hours; may signal concept drift |
| Accuracy degradation | Rolling accuracy drops > 5% below benchmark | SEV-1 | Page on-call; trigger retraining pipeline |
| Model serving latency spike | P99 > 2× baseline for > 5 minutes | SEV-1 | Page on-call; check GPU saturation, model version |
| Feature freshness violation | >1% of predictions using features > SLO threshold | SEV-2 | Page on-call if freshness SLO burn rate > 6× |
| Model staleness | Model version > 7 days old (if retraining SLO = 7 days) | SEV-2 | Page MLOps on-call; trigger manual retraining |
| OOV (out-of-vocabulary) rate spike | >10% of categorical features encountering unseen values | SEV-3 | Ticket; schema or vocabulary expansion needed |

---

## Debugging ML Incidents — Investigation Framework

When an alert fires on model quality degradation, apply this sequence:

```
Step 1: Is this a serving layer issue or a model quality issue?
  Check: HTTP error rate, latency, feature store errors
  If serving layer is unhealthy → infrastructure incident (handle as SEV-1 service incident)
  If serving layer is healthy → model quality investigation

Step 2: Check feature freshness
  Check: feature freshness timestamps in prediction logs
  "Are we serving predictions with stale features?"
  Common cause: feature pipeline failure; cache invalidation bug

Step 3: Check for data drift in input features
  Check: PSI scores for all features over the last 24h vs training distribution
  "Which features have drifted? When did the drift start?"
  Common cause: upstream data schema change; new user behavior; seasonal shift

Step 4: Check prediction distribution
  Check: predicted positive rate, confidence distribution, entropy
  "Has the model's output distribution changed?"
  If inputs are in-distribution but outputs shifted → potential concept drift

Step 5: Check outcome metrics (if ground truth available)
  Check: accuracy/precision/recall/RMSE for the last N labeled predictions
  "Is model quality degraded relative to benchmark?"
  If yes: trigger retraining; check if training data needs refreshing

Step 6: Correlate with model version
  Check: when was the current model trained? What data was it trained on?
  "Did a recent model promotion introduce regression?"
  If new model version correlates with degradation: rollback to previous model version

Mitigation order:
  1. Rollback to previous model version (if promotion correlates with issue)
  2. Fall back to simpler/safer model (rule-based fallback, previous stable model)
  3. Trigger emergency retraining (if concept drift is confirmed)
  4. Degrade gracefully (disable ML feature; use heuristic/default)
```

---

## ML Observability Tooling

| Tool | Category | Use Case |
|------|----------|---------|
| **Evidently AI** | Open-source | Data drift, model performance reports; Prometheus-compatible metrics |
| **WhyLogs / WhyLabs** | Open-source SDK + SaaS | Profile logging for feature distributions; integrates with ML pipelines |
| **Arize AI** | SaaS | Production ML monitoring; slice-based performance analysis; data drift |
| **Fiddler AI** | SaaS | Explainability + monitoring; bias detection; root cause analysis |
| **Grafana + Prometheus** | Open-source | Custom ML metrics; SLO burn rate for ML SLIs; operationally familiar |
| **MLflow** | Open-source | Experiment tracking; model registry with version history |
| **Weights & Biases (W&B)** | SaaS | Training observability; sweep analysis; model comparison |
| **Seldon Core** | Open-source | Model serving on Kubernetes; built-in drift detection and outlier detection |
| **Feast** | Open-source | Feature store; point-in-time correct feature retrieval; feature freshness tracking |

---

## FAANG Interview Application

### System Design — Including ML Observability

When designing an ML system, always include:

```
"For observability, I'd define three classes of SLIs:

1. Infrastructure SLIs: P99 prediction latency < 200ms; error rate < 0.1%; 
   feature freshness SLO (99% of predictions use features < 5 minutes old)

2. Data quality SLIs: PSI < 0.1 for all top-20 features, computed hourly
   against training distribution; alert on PSI > 0.2 (significant drift)
   Alert on unseen category rate > 5% for categorical features

3. Model quality SLIs: for fraud detection (24h ground truth lag) — 
   precision > 85%, recall > 90%, 7-day rolling window;
   alert on >3% drop in either metric vs 30-day rolling benchmark

Every prediction is logged to Kafka (request_id, model_version, features, prediction, confidence).
Ground truth is joined via Flink stream-stream join (48h window) and materialized to Prometheus.

Canary deployment: every model promotion goes to 5% traffic for 24 hours; 
auto-promote if metrics are stable; auto-rollback if quality degrades."
```

### "How Would You Detect if Your Recommendation Model Started Performing Poorly?"

```
"I'd monitor at four layers:

Layer 1 (immediate, seconds): serving metrics — latency, errors, throughput. 
These tell me if the serving infrastructure is broken.

Layer 2 (immediate, minutes): prediction distribution monitoring — 
has the distribution of recommendation scores, item diversity, or confidence changed?
A sudden drop in item diversity or a collapse in confidence scores indicates a problem.

Layer 3 (hours): data drift on input features — 
has user behavior feature distribution shifted significantly?
PSI > 0.2 on key behavioral features triggers an investigation.

Layer 4 (hours to days): outcome metrics — 
CTR, engagement rate, conversion rate for served recommendations vs holdout baseline.
A drop in CTR > 5% relative to the A/B holdout triggers a model review.

For fast ground truth (CTR), I'd get signal within hours.
For slow ground truth (purchase conversion), I'd rely on layers 2 and 3 as leading indicators.

Mitigation if quality degrades: shadow the new model version; 
rollback to previous version while investigating;
trigger retraining pipeline with recent data if concept drift is confirmed."
```

---

## Connections to Other Topics

| Topic | File | Connection |
|-------|------|-----------|
| Observability Engineering foundations | [Books/summaries/observability-engineering-majors-fong-jones-miranda.md](../../Books/summaries/observability-engineering-majors-fong-jones-miranda.md) | Core observability principles apply to ML serving layer |
| SLO Design Guide | [HLD/designs/slo-design-guide.md](../../HLD/designs/slo-design-guide.md) | ML-specific SLIs and burn rate alerting |
| Incident Response | [Development/processes/incident-response-playbook.md](../../Development/processes/incident-response-playbook.md) | ML model degradation as a production incident |
| Feature Store Design | [AI/ml-systems/](../../AI/ml-systems/) | Feature freshness is a prerequisite for ML observability |
| Stream Processing (DDIA Ch.11) | [Books/summaries/designing-data-intensive-applications-kleppmann.md](../../Books/summaries/designing-data-intensive-applications-kleppmann.md) | Ground truth joining uses stream-stream join patterns |
| Kafka | [HLD/designs/](../../HLD/designs/) | Prediction log and ground truth log use Kafka as event backbone |
