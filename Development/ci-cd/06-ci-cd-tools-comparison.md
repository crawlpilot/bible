# CI/CD Tools — Comparison, Examples & Trade-offs

## Decision Framework

Before picking a tool, answer these questions:
1. **Where does your code live?** (GitHub → GitHub Actions is frictionless; GitLab → GitLab CI)
2. **Where do you deploy?** (AWS-only → CodeDeploy/CodePipeline fits; multi-cloud → Jenkins/GitHub Actions)
3. **Who operates it?** (No ops team → hosted SaaS wins; dedicated platform team → self-hosted gives control)
4. **What's your scale?** (< 50 engineers → managed SaaS; > 500 → cost + control shift toward self-hosted)
5. **How complex are your pipelines?** (Microservices with shared libs → Jenkins; simple service → GitHub Actions)

---

## Tool Landscape Overview

```
                    Hosted / SaaS                    Self-hosted / Open-source
                    ─────────────                    ─────────────────────────
CI-focused:         GitHub Actions                   Jenkins
                    CircleCI                         GitLab CI (self-managed)
                    Buildkite (hybrid)               Buildkite agents

CD-focused:         AWS CodeDeploy / CodePipeline    Spinnaker
                    Google Cloud Deploy              Argo CD
                    Harness                          Flux CD

Build systems:      GitHub Actions                   Bazel, Gradle, Maven
                    (not a build system, wraps them) (tool-level, not pipeline-level)
```

---

## Jenkins

### Overview

Jenkins is the original CI/CD workhorse — open source, self-hosted, infinitely pluggable. It predates cloud-native patterns but remains dominant in enterprises because of its flexibility and plugin ecosystem (1,800+ plugins).

### Architecture

```
                    ┌─────────────────────────┐
                    │     Jenkins Controller   │  ← orchestrates jobs, UI, config
                    └────────────┬────────────┘
                                 │ JNLP / SSH
              ┌──────────────────┼──────────────────┐
              │                  │                  │
       ┌──────▼──────┐   ┌──────▼──────┐   ┌──────▼──────┐
       │   Agent 1   │   │   Agent 2   │   │   Agent N   │  ← run builds
       │ (Java/Maven)│   │ (Docker)    │   │ (K8s pod)   │
       └─────────────┘   └─────────────┘   └─────────────┘
```

**Scaling model**: horizontal — add more agents. Jenkins Kubernetes plugin spins ephemeral pods as agents.

### Declarative Pipeline Example (Jenkinsfile)

```groovy
// Jenkinsfile — Java microservice build → test → deploy
pipeline {
    agent {
        kubernetes {
            yaml """
            apiVersion: v1
            kind: Pod
            spec:
              containers:
              - name: maven
                image: maven:3.9-eclipse-temurin-21
                command: ['sleep', 'infinity']
              - name: kaniko
                image: gcr.io/kaniko-project/executor:debug
                command: ['sleep', 'infinity']
            """
        }
    }

    environment {
        IMAGE_REPO  = "registry.company.com/payment-service"
        GIT_SHA     = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
        IMAGE_TAG   = "${GIT_SHA}-${BUILD_NUMBER}"
    }

    stages {
        stage('Build & Test') {
            steps {
                container('maven') {
                    sh 'mvn -B clean verify'          // compile + unit tests
                    junit 'target/surefire-reports/*.xml'
                    publishCoverage adapters: [jacocoAdapter('target/site/jacoco/jacoco.xml')]
                }
            }
        }

        stage('Build Image') {
            steps {
                container('kaniko') {
                    sh """
                    /kaniko/executor \
                      --context=. \
                      --dockerfile=Dockerfile \
                      --destination=${IMAGE_REPO}:${IMAGE_TAG} \
                      --cache=true \
                      --cache-repo=${IMAGE_REPO}/cache
                    """
                }
            }
        }

        stage('Deploy to Staging') {
            when { branch 'main' }
            steps {
                sh "helm upgrade --install payment-service ./helm --set image.tag=${IMAGE_TAG} -n staging"
            }
        }

        stage('Integration Tests') {
            when { branch 'main' }
            steps {
                container('maven') {
                    sh 'mvn -B verify -Pintegration-tests -Denv=staging'
                }
            }
            post {
                always {
                    junit 'target/failsafe-reports/*.xml'
                }
            }
        }

        stage('Deploy to Production') {
            when { branch 'main' }
            input {
                message "Deploy ${IMAGE_TAG} to production?"
                ok "Deploy"
            }
            steps {
                sh "helm upgrade --install payment-service ./helm --set image.tag=${IMAGE_TAG} -n production"
            }
        }
    }

    post {
        failure { slackSend channel: '#deploys', color: 'danger', message: "FAILED: ${JOB_NAME} #${BUILD_NUMBER}" }
        success { slackSend channel: '#deploys', color: 'good', message: "DEPLOYED: ${JOB_NAME} #${BUILD_NUMBER} → ${IMAGE_TAG}" }
    }
}
```

### Jenkins Shared Library (DRY pattern)

For 100+ services, centralize pipeline logic into a shared library:

```groovy
// vars/javaBuild.groovy — callable as javaBuild() from any Jenkinsfile
def call(Map config = [:]) {
    def javaVersion = config.javaVersion ?: '21'
    def runIntegrationTests = config.runIntegrationTests ?: true

    pipeline {
        agent { kubernetes { yaml agentYaml(javaVersion) } }
        stages {
            stage('Build & Test') {
                steps { container('maven') { sh 'mvn -B clean verify' } }
            }
            stage('Integration Tests') {
                when { expression { return runIntegrationTests } }
                steps { container('maven') { sh 'mvn -B verify -Pintegration-tests' } }
            }
        }
    }
}

// Each service Jenkinsfile becomes 3 lines:
// @Library('shared-pipeline') _
// javaBuild javaVersion: '21', runIntegrationTests: true
```

### Advantages

| Advantage | Detail |
|-----------|--------|
| Maximum flexibility | Any language, any tool, any infrastructure — if it can run on Linux, Jenkins can do it |
| Plugin ecosystem | 1,800+ plugins — AWS, GCP, Azure, Slack, JIRA, SonarQube, Artifactory, everything |
| Self-hosted control | Data stays on-prem; no SaaS dependency; audit log under your control |
| Mature at scale | Battle-tested in enterprises with 1,000+ jobs; fine-grained agent management |
| Shared libraries | Cross-team pipeline reuse with Groovy DSL — at 500 teams, this pays off |
| No per-minute pricing | Fixed infrastructure cost, not variable per build-minute |

### Disadvantages

| Disadvantage | Detail |
|--------------|--------|
| High operational burden | You manage the controller, agents, plugins, upgrades, backups |
| Plugin hell | Incompatible plugin versions cause mysterious failures; upgrade paths are painful |
| Controller is a SPOF | Controller outage = 0 builds. HA setup (Active/Standby) is complex |
| Groovy DSL learning curve | Declarative is OK; scripted pipeline is full Groovy — hard to test, easy to abuse |
| No native Git provider UX | No inline PR checks; status posted via API, not native UI |
| Security model is complex | Credential management, agent trust, script approval — footguns everywhere |
| Slow UI | Jenkins UI is notoriously slow for large job lists |

### When to choose Jenkins

- Enterprise with compliance requirements (data must stay on-prem)
- Complex multi-stage pipelines with shared logic across 100+ services
- Heavy custom tooling that doesn't fit GitHub Actions marketplace
- Existing large Jenkins investment not worth migrating

---

## GitHub Actions

### Overview

GitHub Actions is GitHub's native CI/CD platform. YAML-defined workflows triggered by Git events. Runners are hosted (free tier + per-minute billing) or self-hosted. Marketplace has 10,000+ actions.

### Architecture

```
Push to GitHub
      │
      ▼
  GitHub Actions Scheduler
      │
      ├──► GitHub-hosted runner (Ubuntu/macOS/Windows)
      │    Ephemeral VM, provisioned per job
      │
      └──► Self-hosted runner (your infra, registered agent)
           Long-running process, pulls jobs
```

### Complete Workflow Example

```yaml
# .github/workflows/ci-cd.yml
name: CI/CD Pipeline

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  # ── Stage 1: Fast feedback ────────────────────────────────
  build-and-test:
    name: Build & Unit Test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up JDK 21
        uses: actions/setup-java@v4
        with:
          java-version: '21'
          distribution: 'temurin'
          cache: maven          # cache ~/.m2 automatically

      - name: Build and test
        run: mvn -B clean verify

      - name: Upload test results
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: test-results
          path: target/surefire-reports/

      - name: Code coverage report
        uses: codecov/codecov-action@v4
        with:
          token: ${{ secrets.CODECOV_TOKEN }}

  # ── Stage 2: Security scanning ───────────────────────────
  security-scan:
    name: SAST & Dependency Scan
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run OWASP Dependency Check
        uses: dependency-check/Dependency-Check_Action@main
        with:
          project: 'payment-service'
          path: '.'
          format: 'SARIF'
          out: 'reports'

      - name: Upload SARIF to GitHub Security
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: reports/dependency-check-report.sarif

  # ── Stage 3: Build & push image ──────────────────────────
  build-image:
    name: Build Docker Image
    runs-on: ubuntu-latest
    needs: [build-and-test, security-scan]   # gate on both stages
    if: github.ref == 'refs/heads/main'
    outputs:
      image-digest: ${{ steps.build.outputs.digest }}
      image-tag: ${{ steps.meta.outputs.tags }}

    permissions:
      contents: read
      packages: write
      id-token: write      # for OIDC signing

    steps:
      - uses: actions/checkout@v4

      - name: Docker metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=sha,prefix=sha-
            type=ref,event=branch

      - name: Log in to registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push
        id: build
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Sign image with Sigstore
        run: cosign sign --yes ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}@${{ steps.build.outputs.digest }}

  # ── Stage 4: Deploy to staging ───────────────────────────
  deploy-staging:
    name: Deploy → Staging
    runs-on: ubuntu-latest
    needs: build-image
    environment: staging     # GitHub environment with protection rules

    steps:
      - uses: actions/checkout@v4

      - name: Deploy to EKS staging
        uses: aws-actions/amazon-eks-deploy@v1
        with:
          cluster-name: my-cluster-staging
          namespace: payment-staging
          image: ${{ needs.build-image.outputs.image-tag }}

      - name: Run smoke tests
        run: ./scripts/smoke-test.sh https://staging.payment.company.com

  # ── Stage 5: Deploy to production (manual gate) ──────────
  deploy-production:
    name: Deploy → Production
    runs-on: ubuntu-latest
    needs: deploy-staging
    environment:
      name: production        # requires reviewer approval in GitHub UI
      url: https://payment.company.com

    steps:
      - uses: actions/checkout@v4

      - name: Deploy to EKS production
        uses: aws-actions/amazon-eks-deploy@v1
        with:
          cluster-name: my-cluster-prod
          namespace: payment-prod
          image: ${{ needs.build-image.outputs.image-tag }}
```

### Reusable Workflows (DRY pattern)

```yaml
# .github/workflows/java-build-template.yml  (in shared repo)
on:
  workflow_call:
    inputs:
      java-version:
        type: string
        default: '21'
      run-integration-tests:
        type: boolean
        default: true
    secrets:
      CODECOV_TOKEN:
        required: true

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          java-version: ${{ inputs.java-version }}
          cache: maven
      - run: mvn -B clean verify
      - if: inputs.run-integration-tests
        run: mvn -B verify -Pintegration-tests

# ─── Consuming repo's workflow (3 lines) ───
# jobs:
#   build:
#     uses: org/shared-workflows/.github/workflows/java-build-template.yml@main
#     with:
#       java-version: '21'
#     secrets: inherit
```

### Advantages

| Advantage | Detail |
|-----------|--------|
| Zero infrastructure to manage | GitHub-hosted runners: fully managed, auto-scaled, patched |
| Native GitHub integration | PR status checks, environment protection rules, OIDC identity, secrets |
| YAML is simple | No Groovy DSL; declarative syntax; reviewable like code |
| Marketplace | 10,000+ pre-built actions — AWS deploy, Docker, Helm, Terraform, Slack |
| OIDC for cloud auth | Keyless cloud auth (no long-lived credentials stored as secrets) |
| Parallel jobs natively | `needs` graph — fan-out/fan-in with dependency ordering |
| Cost model for small teams | Free tier (2,000 min/month) covers many small projects |

### Disadvantages

| Disadvantage | Detail |
|--------------|--------|
| Variable per-minute cost | At 50,000 builds/month, GitHub-hosted runners get expensive fast |
| GitHub lock-in | Workflows are GitHub-specific YAML — not portable to GitLab or Bitbucket |
| Runner cold start | GitHub-hosted runners: ~30–60s provisioning. Self-hosted runners: persistent but you manage them |
| Limited pipeline visualization | No native DAG view like Jenkins Blue Ocean or Spinnaker |
| Secret rotation UX | Rotating secrets across 500 repos is painful (Actions doesn't have org-level dynamic secrets) |
| Job timeout: 6 hours max | Long-running jobs (large builds, ML training) hit ceiling |
| No built-in canary/progressive delivery | Need external tool (Argo Rollouts, Spinnaker) for deployment strategies |

### When to choose GitHub Actions

- Code is on GitHub (or migrating to it)
- Small to mid-size team (< 200 engineers) wanting zero infra overhead
- Cloud-native services deploying to AWS/GCP/Azure (OIDC works beautifully)
- Need fast setup — first pipeline in < 30 minutes

---

## AWS CodeDeploy + CodePipeline

### Overview

AWS CodeDeploy is an EC2/ECS/Lambda deployment service. CodePipeline is the orchestration layer that chains Source → Build (CodeBuild) → Test → Deploy (CodeDeploy). Together they form AWS's native CI/CD suite.

### Architecture

```
GitHub / S3                CodeBuild               CodeDeploy
────────────────           ─────────────           ─────────────────────────
Source stage:              Build stage:            Deploy stage:
  poll or webhook     →    compile, test,   →      rolling, blue-green,
  from GitHub             build artifact,          canary on:
  CodeCommit,             push to S3 /             - EC2 instances
  S3 bucket              ECR                       - ECS services
                                                   - Lambda functions
        └──────────────────────────────────────────────────────────────────────────┘
                                 CodePipeline orchestrates the above
```

### CodePipeline Example (CloudFormation)

```yaml
# codepipeline.yaml — AWS CloudFormation
AWSTemplateFormatVersion: '2010-09-09'

Resources:
  PaymentServicePipeline:
    Type: AWS::CodePipeline::Pipeline
    Properties:
      Name: payment-service-pipeline
      RoleArn: !GetAtt PipelineRole.Arn
      ArtifactStore:
        Type: S3
        Location: !Ref ArtifactBucket

      Stages:
        # Stage 1: Source
        - Name: Source
          Actions:
            - Name: GitHubSource
              ActionTypeId:
                Category: Source
                Owner: AWS
                Provider: CodeStarSourceConnection
                Version: '1'
              Configuration:
                ConnectionArn: !Ref GitHubConnection
                FullRepositoryId: company/payment-service
                BranchName: main
                DetectChanges: true
              OutputArtifacts:
                - Name: SourceCode

        # Stage 2: Build & Test
        - Name: Build
          Actions:
            - Name: BuildAndTest
              ActionTypeId:
                Category: Build
                Owner: AWS
                Provider: CodeBuild
                Version: '1'
              Configuration:
                ProjectName: !Ref BuildProject
              InputArtifacts:
                - Name: SourceCode
              OutputArtifacts:
                - Name: BuildOutput

        # Stage 3: Deploy to staging
        - Name: DeployStaging
          Actions:
            - Name: DeployToECSStaging
              ActionTypeId:
                Category: Deploy
                Owner: AWS
                Provider: CodeDeployToECS
                Version: '1'
              Configuration:
                ApplicationName: !Ref CodeDeployApp
                DeploymentGroupName: staging-deployment-group
                TaskDefinitionTemplateArtifact: BuildOutput
                AppSpecTemplateArtifact: BuildOutput

        # Stage 4: Manual approval gate
        - Name: ProductionApproval
          Actions:
            - Name: ManualApproval
              ActionTypeId:
                Category: Approval
                Owner: AWS
                Provider: Manual
                Version: '1'
              Configuration:
                NotificationArn: !Ref ApprovalSNSTopic
                CustomData: "Review staging metrics before approving production deploy"

        # Stage 5: Deploy to production
        - Name: DeployProduction
          Actions:
            - Name: DeployToECSProduction
              ActionTypeId:
                Category: Deploy
                Owner: AWS
                Provider: CodeDeployToECS
                Version: '1'
              Configuration:
                ApplicationName: !Ref CodeDeployApp
                DeploymentGroupName: production-deployment-group
                TaskDefinitionTemplateArtifact: BuildOutput
                AppSpecTemplateArtifact: BuildOutput
```

### CodeBuild buildspec.yml

```yaml
# buildspec.yml — runs inside CodeBuild
version: 0.2

phases:
  install:
    runtime-versions:
      java: corretto21

  pre_build:
    commands:
      - echo Logging in to Amazon ECR...
      - aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
      - COMMIT_HASH=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)
      - IMAGE_TAG=${COMMIT_HASH:-latest}

  build:
    commands:
      - echo Build started
      - mvn -B clean verify
      - docker build -t $ECR_REGISTRY/$IMAGE_REPO:$IMAGE_TAG .
      - docker push $ECR_REGISTRY/$IMAGE_REPO:$IMAGE_TAG

  post_build:
    commands:
      - echo Writing image definitions file...
      - printf '[{"name":"payment-service","imageUri":"%s"}]' $ECR_REGISTRY/$IMAGE_REPO:$IMAGE_TAG > imagedefinitions.json
      - cat imagedefinitions.json

reports:
  UnitTestResults:
    files:
      - 'target/surefire-reports/*.xml'
    file-format: JUNITXML

artifacts:
  files:
    - imagedefinitions.json
    - appspec.yaml
    - taskdef.json
```

### CodeDeploy appspec.yaml (ECS blue-green)

```yaml
# appspec.yaml — CodeDeploy deployment spec
version: 0.0
Resources:
  - TargetService:
      Type: AWS::ECS::Service
      Properties:
        TaskDefinition: <TASK_DEFINITION>          # replaced by pipeline
        LoadBalancerInfo:
          ContainerName: payment-service
          ContainerPort: 8080
        PlatformVersion: LATEST

Hooks:
  - BeforeAllowTraffic: ValidateStagingFunction    # Lambda for smoke test
  - AfterAllowTraffic:  NotifyDeployFunction        # Lambda for Slack notify
```

### CodeDeploy Deployment Configurations

| Config | Behavior | Use case |
|--------|----------|----------|
| `CodeDeployDefault.ECSAllAtOnce` | Replace all traffic at once | Dev/staging |
| `CodeDeployDefault.ECSLinear10PercentEvery1Minutes` | 10% per minute over 10 min | Medium-risk |
| `CodeDeployDefault.ECSCanary10Percent5Minutes` | 10% for 5 min, then 90% | Production |
| Custom: e.g., `Canary10Percent30Minutes` | 10% for 30 min (manual-ish) | High-risk |

### Advantages

| Advantage | Detail |
|-----------|--------|
| Native AWS integration | IAM roles, CloudWatch, ECR, ECS, Lambda — no glue code needed |
| Blue-green built-in | ECS + CodeDeploy: blue-green with ALB traffic shift is first-class |
| No servers to manage | Fully managed — CodeBuild auto-scales, CodeDeploy is serverless |
| Rollback on CloudWatch alarm | Tie CloudWatch alarm to automatic rollback — SLO-gated deploy |
| Audit via CloudTrail | Every pipeline action is logged in CloudTrail — compliance-ready |
| Cost model | Pay per active pipeline + CodeBuild minutes. No fixed infra cost |

### Disadvantages

| Disadvantage | Detail |
|--------------|--------|
| AWS lock-in | 100% tied to AWS. Migrating to GCP/Azure means rewriting everything |
| Limited pipeline logic | CodePipeline lacks the scripting power of Jenkins or GitHub Actions |
| CodeCommit deprecated | AWS deprecated CodeCommit (2024) — GitHub source connection works but adds friction |
| UI is dated | CodePipeline UI is functional but not developer-friendly vs. GitHub Actions |
| Multi-region complexity | Separate pipelines per region — no native multi-region orchestration |
| Cold start on CodeBuild | 2–3 min to provision build environment (can use custom image to mitigate) |
| Limited language in pipeline logic | No shared library equivalent — repeated configuration across pipelines |

### When to choose AWS CodeDeploy/CodePipeline

- AWS-only infrastructure, compliance requires all tooling in your AWS account
- ECS/EC2/Lambda deployments — CodeDeploy's blue-green for ECS is genuinely excellent
- Team wants zero CI/CD infra management and is already deep in AWS
- Need CloudWatch alarm → auto-rollback without building it yourself

---

## GitLab CI

### Overview

GitLab CI is fully integrated into GitLab (SCM + CI + CD + security scanning). Best-in-class if your company uses GitLab.

### .gitlab-ci.yml Example

```yaml
stages:
  - build
  - test
  - security
  - package
  - deploy-staging
  - deploy-production

variables:
  IMAGE: $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA
  MAVEN_OPTS: "-Dmaven.repo.local=$CI_PROJECT_DIR/.m2/repository"

cache:
  paths:
    - .m2/repository/

build:
  stage: build
  image: maven:3.9-eclipse-temurin-21
  script:
    - mvn -B compile
  artifacts:
    paths:
      - target/

unit-test:
  stage: test
  image: maven:3.9-eclipse-temurin-21
  script:
    - mvn -B test
  artifacts:
    reports:
      junit: target/surefire-reports/*.xml

sast:
  stage: security
  include:
    - template: Security/SAST.gitlab-ci.yml   # built-in SAST template

container-scan:
  stage: security
  include:
    - template: Security/Container-Scanning.gitlab-ci.yml

build-image:
  stage: package
  image: docker:24
  services:
    - docker:24-dind
  before_script:
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY
  script:
    - docker build -t $IMAGE .
    - docker push $IMAGE
  only:
    - main

deploy-staging:
  stage: deploy-staging
  environment:
    name: staging
    url: https://staging.payment.company.com
  script:
    - helm upgrade --install payment ./helm --set image.tag=$CI_COMMIT_SHORT_SHA -n staging
  only:
    - main

deploy-production:
  stage: deploy-production
  environment:
    name: production
    url: https://payment.company.com
  when: manual            # requires human click in GitLab UI
  script:
    - helm upgrade --install payment ./helm --set image.tag=$CI_COMMIT_SHORT_SHA -n production
  only:
    - main
```

### Advantages vs. Disadvantages (GitLab CI)

| Advantage | Disadvantage |
|-----------|--------------|
| All-in-one: SCM + CI + CD + security | Requires GitLab (not GitHub/Bitbucket) |
| Built-in SAST, DAST, container scanning | Self-managed GitLab is complex to operate |
| Auto DevOps — zero-config pipelines | YAML is verbose for complex pipelines |
| GitLab environments + deployment board | Limited marketplace vs. GitHub Actions |
| Kubernetes integration built-in | Expensive at scale (per-seat licensing) |

---

## ArgoCD (GitOps CD)

### Overview

ArgoCD is a Kubernetes-native CD tool implementing GitOps: the desired state lives in Git; ArgoCD continuously reconciles cluster state to match.

### How it differs from push-based CD

```
Push-based (Jenkins/GitHub Actions/CodeDeploy):
  Pipeline PUSHES to cluster:   pipeline runs → kubectl apply → cluster

Pull-based / GitOps (ArgoCD):
  ArgoCD PULLS from Git:         cluster ← ArgoCD watches Git → reconcile
                                           │
                                           ▼
                                   Cluster state always
                                   matches Git state
                                   (or ArgoCD alerts)
```

### Application manifest

```yaml
# argocd-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: payment-service
  namespace: argocd
spec:
  project: default

  source:
    repoURL: https://github.com/company/k8s-manifests
    targetRevision: HEAD
    path: services/payment-service/overlays/production

  destination:
    server: https://kubernetes.default.svc
    namespace: payment-production

  syncPolicy:
    automated:
      prune: true        # delete resources removed from Git
      selfHeal: true     # re-apply if cluster state drifts
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

### Advantages vs. Disadvantages (ArgoCD)

| Advantage | Disadvantage |
|-----------|--------------|
| Declarative, auditable — Git IS the source of truth | Kubernetes-only (not for EC2, Lambda, ECS non-K8s) |
| Drift detection — alerts if cluster diverges from Git | Learning curve for teams new to GitOps |
| Multi-cluster management | Pull model means new deploys require a Git commit |
| Automatic rollback via Git revert | Not a full CI tool — needs upstream CI (GitHub Actions, Jenkins) |
| RBAC + SSO built-in | Secrets in Git is an anti-pattern — need Sealed Secrets or Vault |

---

## Tool Selection Matrix

| Criteria | Jenkins | GitHub Actions | AWS CodeDeploy | GitLab CI | ArgoCD |
|----------|---------|----------------|----------------|-----------|--------|
| **Setup time** | Days | Minutes | Hours | Minutes | Hours |
| **Infra to manage** | High (controller + agents) | None (hosted) or Low (self-hosted) | None | None or High (self-managed) | Low (K8s operator) |
| **Pipeline complexity ceiling** | Very high | Medium-high | Low-medium | High | N/A (CD only) |
| **Deployment strategies** | Plugin-based | Via external tools | Blue-green, canary native | Manual or via tools | Via Argo Rollouts |
| **AWS native** | Plugins | OIDC + actions | Native | Possible | Possible |
| **Cost at 500 engineers** | Fixed (infra) | Variable (per min) | Usage-based | Per-seat license | Low (open source) |
| **Audit / compliance** | Extensive (self-hosted) | GitHub audit log | CloudTrail | GitLab audit | Git history |
| **Best for** | Enterprise, complex pipelines | Cloud-native, GitHub orgs | AWS-only shops | GitLab shops | K8s GitOps |

---

## Common Hybrid Architecture

Most FAANG-scale companies don't use one tool — they compose:

```
Developer pushes → GitHub (source of truth)
         │
         ▼
GitHub Actions (CI: build, test, security scan, push image)
         │
         ▼
Artifact in ECR / GCR (immutable, signed)
         │
         ▼
ArgoCD (CD: watches image tag promotion in Git, reconciles K8s cluster)
    +
Argo Rollouts (progressive delivery: canary analysis, blue-green)
    +
Feature Flags (LaunchDarkly / in-house: decouple deploy from release)
```

**Why this split?**
- GitHub Actions excels at CI (fast, zero config, close to code)
- ArgoCD excels at K8s CD (GitOps, drift detection, multi-cluster)
- Neither tool does the other's job as well

---

## FAANG Interview Callouts

**Q: You're joining a team using Jenkins with a 45-minute pipeline. How do you modernize it?**

Don't rewrite first — diagnose:
1. Profile time: `stage timing` in Blue Ocean. Where is the 45 minutes?
2. If test-heavy: parallelize with `parallel {}` blocks + agent fan-out
3. If build-heavy: Gradle incremental, Docker layer cache, persistent agent cache volumes
4. If sequential by design: can acceptance tests run async? Non-blocking trunk = higher velocity

Then evaluate migration:
- If team is on GitHub → GitHub Actions for CI, keep Jenkins for complex CD orchestration
- Never do a big-bang migration; run old and new pipelines in parallel, migrate service by service

**Q: GitHub Actions vs. Jenkins — which would you choose for a greenfield 50-engineer startup?**

GitHub Actions. The zero-ops advantage is decisive at 50 engineers — nobody should be managing Jenkins agents. The per-minute cost is irrelevant at that scale. When you grow past 300 engineers and costs escalate, move to self-hosted GitHub Actions runners (not Jenkins) — you keep the workflow syntax, just swap the compute.

**Q: CodeDeploy blue-green vs. Kubernetes rolling update — when does each win?**

| Scenario | Recommendation |
|----------|----------------|
| ECS on AWS, no Kubernetes | CodeDeploy blue-green — native, zero extra tooling |
| Kubernetes cluster | Argo Rollouts (canary) > rolling update — more control, automated analysis |
| Lambda functions | CodeDeploy traffic shifting — only tool with native Lambda % routing |
| Multi-cloud | Spinnaker or Argo Rollouts — cloud-agnostic |

CodeDeploy wins on simplicity inside AWS. Argo Rollouts wins on observability and automated analysis.
