# LLD: Production-Ready In-House Job Scheduler

> **Problem Statement:** Automate jobs currently running on Jenkins by building an in-house scheduler that supports time-based (cron), interval-based, and ad-hoc (on-demand) execution — feature-parity with Quartz Scheduler, deployed as a clustered, persistent service.

---

## 0. Context, Motivation & Use Cases

### 0.1 Why We Were Running Jobs on Jenkins — and Why That Broke Down

The platform started using Jenkins purely as a CI/CD tool. Over time, teams began scheduling business-logic jobs on Jenkins because it was already there: cron-triggered pipeline jobs, Groovy scripts for data reconciliation, shell steps for report generation. By the time the problem was surfaced, Jenkins was carrying two entirely different concerns — build/deploy automation and business-job orchestration — and it was failing at the second one.

**Pain points that drove the in-house build:**

| Problem | Jenkins reality | Impact |
|---|---|---|
| **No programmatic API for job management** | Jobs are XML on disk; creating or updating one requires either UI clicks or calling the Jenkins Remote API with raw XML blobs | Teams can't onboard jobs without an ops ticket; no self-service |
| **No execution isolation** | All jobs share the Jenkins executor pool; a runaway report job starves deployments | SLA misses on CI pipelines during month-end batch windows |
| **No job-level audit trail** | Jenkins build history is per-pipeline, not per-business-event; history expires with Jenkins log rotation | Can't answer "was this settlement job run on 2024-12-31?" without trawling raw logs |
| **Misfire handling is absent** | If Jenkins is restarted at trigger time, the job is silently skipped | Missed financial reconciliation jobs discovered hours later |
| **No concurrency control across runs** | Nothing prevents the same job from running twice simultaneously; Jenkins has no `DisallowConcurrentExecution` concept for scheduled jobs | Data corruption in ETL pipelines when a slow run overlaps the next scheduled window |
| **Coupling between CI availability and business ops** | A failed Jenkins upgrade blocks both deployments and nightly batch jobs | Operational blast radius is too wide |
| **No dynamic scheduling** | Cron expression changes require a commit + pipeline edit; no runtime rescheduling | Inflexible for event-driven or on-call-driven ad-hoc runs |

### 0.2 Why Not Use an Existing Scheduler?

Before committing to an in-house build, three alternatives were evaluated:

**Quartz Scheduler (embedded library)**
- Quartz itself is the design inspiration here. The decision to not just use Quartz as-is came down to deployment model: Quartz is a library, not a service. Every team that needed to schedule jobs would embed their own Quartz instance. No shared visibility, no central audit, no unified admin UI. We needed Quartz's scheduling semantics but exposed as a shared platform service.

**AWS EventBridge / Cloud Scheduler**
- Viable for purely cloud-native workloads, but the jobs being migrated ran on internal infra with internal network access (databases, internal APIs, SFTP endpoints). Bridging those into a cloud-native trigger would require VPC plumbing for every job. Also, no support for stateful job data, priority-based execution, or DisallowConcurrentExecution.

**Apache Airflow**
- Excellent for DAG-based data pipelines with complex dependencies. Overhead is significant for simple scheduled jobs (separate webserver, scheduler, workers, metadata DB). The target workloads were mostly independent, single-step jobs — Airflow's DAG model was more complexity than the problem needed.

**Decision: Build a thin service layer on top of Quartz's persistence model.** Reuse the DB schema and the scheduling math; own the service boundary, the API, and the operational experience.

### 0.3 Use Cases This System Solves

#### UC-1: Recurring Business Jobs (Time-Driven)
*"Run the daily settlement report at 2:00 AM every business day."*

- Trigger type: `CronTrigger` with expression `0 0 2 ? * MON-FRI`
- Misfire policy: `FIRE_NOW` (if we missed the 2 AM window because of a deploy, run immediately on startup)
- `requestsRecovery = true` so a mid-run node crash causes re-fire on another node
- `DisallowConcurrentExecution = true` to prevent double-settlement if a run is slow

#### UC-2: Ad-Hoc / On-Demand Execution
*"Re-run the failed reconciliation job for 2024-12-15 right now."*

- Trigger type: `OneTimeTrigger` (fires 5ms after `POST /jobs/{key}/trigger`)
- Job receives the target date via `JobDataMap` in the request body
- Appears in audit log identically to a scheduled run — no special-casing downstream

#### UC-3: High-Frequency Polling Jobs (Interval-Driven)
*"Check the inbound FTP directory every 60 seconds for new files."*

- Trigger type: `SimpleTrigger` with `repeatInterval = 60_000`, `repeatCount = INDEFINITELY`
- `DisallowConcurrentExecution = true` — if the previous poll is still processing a large file, the next tick waits rather than starting a parallel poll
- Misfire policy: `DO_NOTHING` — if a node restarts, skip missed ticks; the next 60s poll will catch whatever the missed ones would have

#### UC-4: Job Chaining / Pipeline
*"After the data-extract job succeeds, kick off the transform job, then the load job."*

- `JobChainingListener` maps `extract.job → transform.job → load.job`
- Each step is a separate `Job` implementation with its own retry logic
- Failure at any step halts the chain (exception prevents `jobWasExecuted` from forwarding)
- Compared to Airflow: no DAG overhead; suitable for linear pipelines of 2–5 steps

#### UC-5: Cluster-Safe One-Time Migration Jobs
*"Backfill historical order statuses — but only run once across all nodes, not once per node."*

- `SimpleTrigger` with `repeatCount = 0` (fires exactly once)
- `SELECT FOR UPDATE SKIP LOCKED` ensures only one cluster node acquires the trigger
- `durable = false` so both the trigger and job are deleted from the store after completion
- Migration team can verify execution in the audit log before decommissioning the job definition

#### UC-6: Replacing Jenkins Parametrized Builds
*"Jenkins job 'GenerateInvoices' runs every Sunday at midnight with parameter REGION=US. Same job with REGION=EU at 01:00."*

- Two `JobDetail` instances sharing the same `Job` class (`InvoiceGenerationJob`)
- Each has a separate `CronTrigger` and a `JobDataMap` carrying `REGION=US` / `REGION=EU`
- Job reads `context.getMergedJobDataMap().getString("REGION")` — no conditional branching in code
- Onboarding new regions is an API call, not a Jenkins config file change

#### UC-7: Priority-Based Execution Under Load
*"Month-end batch jobs must not be starved by low-priority housekeeping jobs."*

- Month-end triggers set `priority = 9` (max); housekeeping triggers default to `5`
- When the thread pool is saturated, `acquireNextTriggers` orders by `priority DESC, next_fire_time ASC`
- High-priority triggers are always dispatched first regardless of submission order

### 0.4 Design Principles

1. **Scheduling logic is in the library, operational concerns are in the service.** The system is a thin HTTP + persistence wrapper around proven Quartz scheduling math — no custom cron parser, no custom cluster consensus.

2. **The DB is the single source of truth for cluster state.** No in-memory shared state between nodes. Any node can go down at any time; survivors reconstruct full state from the DB on their next heartbeat cycle.

3. **Jobs are self-describing.** A `JobDetail` carries everything needed to execute the job: the handler class, the input data map, and the recovery/concurrency flags. The scheduler doesn't need to know what the job does.

4. **Execution is auditable by default.** Every execution — scheduled or ad-hoc — writes a record to the audit log via `AuditLogListener`. Answering "did this job run, and did it succeed?" is a DB query, not a log search.

5. **Self-service, not ops tickets.** The REST API lets application teams register, modify, pause, and trigger their own jobs. The platform team owns the scheduler service; product teams own their job definitions.

---

## 1. Requirements

### Functional
- Define jobs with metadata (name, group, class/handler, data map)
- Three trigger types: **CronTrigger**, **SimpleTrigger** (repeat N times every X ms), **OneTimeTrigger** (ad-hoc immediate or delayed)
- Pause, resume, delete, and manually fire jobs at runtime
- Misfire handling policies (do-nothing, fire-now, fire-and-proceed, ignore)
- Prevent concurrent execution of the same job instance (`DisallowConcurrentExecution`)
- Job chaining: trigger job B on successful completion of job A
- Priority-based execution when thread pool is saturated
- Job listeners and trigger listeners (before/after/on-veto hooks)
- Persistent job store (survives restarts)
- REST API for all operations

### Non-Functional
- Clustered HA: any node can fire any job (no SPOF)
- At-least-once execution guarantee (exactly-once with idempotent jobs)
- Sub-second scheduling precision
- Support 10,000+ scheduled jobs
- Horizontal scaling of executor nodes

---

## 2. Core Abstractions

### 2.1 Interface Contracts

```java
// The unit of work — pure logic, no scheduling concern
public interface Job {
    void execute(JobExecutionContext context) throws JobExecutionException;
}

// Every trigger type implements this
public interface Trigger {
    String getKey();          // triggerGroup.triggerName
    String getJobKey();       // job this trigger is bound to
    Date getNextFireTime();
    Date getPreviousFireTime();
    int getPriority();
    MisfireInstruction getMisfireInstruction();
    Date computeNextFireTime(Calendar cal);  // called by scheduler after each fire
    TriggerState getState();  // NORMAL | PAUSED | BLOCKED | ERROR | COMPLETE
}

// Encapsulates everything a job sees at runtime
public interface JobExecutionContext {
    JobDetail getJobDetail();
    Trigger getTrigger();
    JobDataMap getMergedJobDataMap();  // job data + trigger data, trigger wins on conflict
    Date getFireTime();
    Date getScheduledFireTime();
    long getJobRunTime();              // -1 until job completes
    Scheduler getScheduler();
    void setResult(Object result);
    Object getResult();
}

// Primary entry point for all scheduling operations
public interface Scheduler {
    void scheduleJob(JobDetail job, Trigger trigger) throws SchedulerException;
    Date rescheduleJob(String triggerKey, Trigger newTrigger) throws SchedulerException;
    void deleteJob(String jobKey) throws SchedulerException;
    void pauseJob(String jobKey) throws SchedulerException;
    void resumeJob(String jobKey) throws SchedulerException;
    void triggerJob(String jobKey, JobDataMap data) throws SchedulerException; // ad-hoc
    void pauseAll() throws SchedulerException;
    void resumeAll() throws SchedulerException;
    List<String> getJobKeys(GroupMatcher matcher) throws SchedulerException;
    JobDetail getJobDetail(String jobKey) throws SchedulerException;
    List<? extends Trigger> getTriggersOfJob(String jobKey) throws SchedulerException;
    boolean checkExists(String jobKey) throws SchedulerException;
    void start() throws SchedulerException;
    void shutdown(boolean waitForJobsToComplete) throws SchedulerException;
    SchedulerMetaData getMetaData();
}

// Pluggable persistence layer
public interface JobStore {
    void storeJob(JobDetail job, boolean replaceExisting) throws ObjectAlreadyExistsException;
    void storeTrigger(Trigger trigger, boolean replaceExisting) throws ObjectAlreadyExistsException;
    boolean removeJob(String jobKey);
    boolean removeTrigger(String triggerKey);
    JobDetail retrieveJob(String jobKey);
    Trigger retrieveTrigger(String triggerKey);
    List<OperableTrigger> acquireNextTriggers(long noLaterThan, int maxCount, long timeWindow);
    void triggersFired(List<TriggerFiredBundle> triggers);
    void triggeredJobComplete(OperableTrigger trigger, JobDetail job, Trigger.CompletedExecutionInstruction instruction);
    void pauseTrigger(String triggerKey);
    void resumeTrigger(String triggerKey);
    Set<String> getPausedTriggerGroups();
}

// Thread pool abstraction — decouple scheduling from execution
public interface ThreadPool {
    boolean runInThread(Runnable runnable);
    int blockForAvailableThreads();
    void setInstanceId(String schedInstId);
    void initialize() throws SchedulerConfigException;
    void shutdown(boolean waitForJobsToComplete);
    int getPoolSize();
}
```

### 2.2 Value Objects

```java
// Immutable descriptor — what to run and with what data
@Value  // Lombok
public class JobDetail {
    String key;                   // group.name unique within scheduler
    Class<? extends Job> jobClass;
    JobDataMap jobDataMap;        // arbitrary KV passed to job at runtime
    String description;
    boolean durable;              // persist even with no triggers
    boolean requestsRecovery;     // re-fire if node crashes mid-execution
    boolean concurrentExecutionDisallowed;
}

@Value
public class JobDataMap extends HashMap<String, Object> {
    // type-safe accessors
    public String getString(String key) { ... }
    public int getInt(String key) { ... }
    // etc.
}

@Value
public class TriggerFiredBundle {
    JobDetail jobDetail;
    OperableTrigger trigger;
    boolean jobIsRecovering;
    Date fireTime;
    Date scheduledFireTime;
    Date prevFireTime;
    Date nextFireTime;
}
```

---

## 3. Trigger Implementations

### 3.1 CronTrigger

```java
public class CronTrigger extends AbstractTrigger {
    private CronExpression cronExpression;  // parsed cron
    private TimeZone timeZone;

    @Override
    public Date computeNextFireTime(Calendar afterTime) {
        return cronExpression.getNextValidTimeAfter(afterTime.getTime());
    }

    @Override
    public boolean mayFireAgain() {
        return getNextFireTime() != null;
    }
}

// Cron expression parser — handles standard 6/7-field cron + special chars
public class CronExpression {
    // Fields: seconds minutes hours day-of-month month day-of-week [year]
    // Supports: * / , - L W # ?
    private final Set<Integer> seconds, minutes, hours, daysOfMonth, months, daysOfWeek, years;

    public Date getNextValidTimeAfter(Date date) {
        Calendar cal = Calendar.getInstance(timeZone);
        cal.setTime(date);
        cal.add(Calendar.SECOND, 1);  // exclusive — next time AFTER given
        // iterate calendar forward satisfying each field constraint
        // O(1) amortized — worst case a few calendar iterations
        return findNextTime(cal);
    }
}
```

### 3.2 SimpleTrigger

```java
public class SimpleTrigger extends AbstractTrigger {
    private long startTime;
    private long endTime;           // 0 = no end
    private int repeatCount;        // REPEAT_INDEFINITELY = -1
    private long repeatInterval;    // millis
    private int timesTriggered;

    @Override
    public Date computeNextFireTime(Calendar afterTime) {
        if (repeatCount != REPEAT_INDEFINITELY && timesTriggered >= repeatCount + 1) {
            return null;  // exhausted
        }
        long fireTime = startTime + (timesTriggered * repeatInterval);
        if (endTime > 0 && fireTime > endTime) return null;
        return new Date(fireTime);
    }
}
```

### 3.3 AbstractTrigger (Template Method)

```java
public abstract class AbstractTrigger implements OperableTrigger {
    protected String key;
    protected String jobKey;
    protected int priority = DEFAULT_PRIORITY;  // 5
    protected MisfireInstruction misfireInstruction;
    protected Date nextFireTime;
    protected Date previousFireTime;
    protected TriggerState state = TriggerState.NORMAL;

    // Template method — subclasses implement computeNextFireTime
    public final void triggered(Calendar calendar) {
        previousFireTime = nextFireTime;
        nextFireTime = computeNextFireTime(calendar);
    }

    public abstract Date computeNextFireTime(Calendar afterTime);

    // Misfire: scheduled fire time was missed (node down, pool saturated, etc.)
    public void updateAfterMisfire(Calendar cal) {
        MisfireInstruction instruction = getMisfireInstruction();
        switch (instruction) {
            case FIRE_NOW:
                setNextFireTime(new Date());
                break;
            case DO_NOTHING:
                setNextFireTime(computeNextFireTime(cal));
                break;
            case IGNORE_MISFIRE_POLICY:
                // fire immediately for every missed firing
                break;
        }
    }
}
```

---

## 4. Scheduler Engine

```java
public class StdScheduler implements Scheduler {
    private final QuartzSchedulerThread schedThread;  // main loop
    private final ThreadPool threadPool;
    private final JobStore jobStore;
    private final JobFactory jobFactory;
    private final List<SchedulerListener> schedulerListeners;
    private final List<JobListener> globalJobListeners;
    private final List<TriggerListener> globalTriggerListeners;
    private volatile SchedulerState state = SchedulerState.STANDBY;

    @Override
    public void start() {
        state = SchedulerState.STARTED;
        schedThread.togglePause(false);
    }

    @Override
    public void scheduleJob(JobDetail job, Trigger trigger) throws SchedulerException {
        validateState();
        jobStore.storeJob(job, false);
        jobStore.storeTrigger((OperableTrigger) trigger, false);
        notifySchedulerListenersJobAdded(job);
        notifySchedulerThread(trigger.getNextFireTime());
    }

    @Override
    public void triggerJob(String jobKey, JobDataMap data) throws SchedulerException {
        // ad-hoc: create a one-shot trigger firing 5ms from now
        Trigger trigger = TriggerBuilder.newTrigger()
            .forJob(jobKey)
            .withSchedule(SimpleScheduleBuilder.simpleSchedule())
            .startAt(new Date(System.currentTimeMillis() + 5))
            .usingJobData(data)
            .build();
        scheduleJob(trigger);
    }
}
```

### 4.1 Scheduler Main Loop

```java
public class QuartzSchedulerThread extends Thread {
    private final StdScheduler scheduler;
    private final JobStore jobStore;
    private final ThreadPool threadPool;
    private volatile boolean paused;
    private volatile boolean halted;
    private static final long IDLE_WAIT_TIME = 30_000L;  // 30s when no jobs
    private static final int MAX_BATCH_SIZE = 1;         // tunable

    @Override
    public void run() {
        while (!halted) {
            try {
                // 1. Wait until pool has threads available
                int availThreads = threadPool.blockForAvailableThreads();
                if (availThreads <= 0) continue;

                // 2. Acquire next triggers firing within next 30ms window
                long now = System.currentTimeMillis();
                long noLaterThan = now + idleWaitTime;
                List<OperableTrigger> triggers = jobStore.acquireNextTriggers(
                    noLaterThan, Math.min(availThreads, MAX_BATCH_SIZE), 0L);

                if (triggers.isEmpty()) {
                    // 3. No triggers: sleep until next fire time or idleWaitTime
                    long sleepTime = computeSleepTime();
                    waitOnLock(sleepTime);
                    continue;
                }

                // 4. For each trigger: build fire bundle and dispatch
                long triggerTime = triggers.get(0).getNextFireTime().getTime();
                long timeUntilTrigger = triggerTime - now;
                if (timeUntilTrigger > 2) {
                    // release acquired lock early, sleep until fire time
                    jobStore.releaseAcquiredTrigger(triggers.get(0));
                    waitOnLock(Math.min(timeUntilTrigger, idleWaitTime));
                    continue;
                }

                // 5. Fire!
                List<TriggerFiredBundle> bundles = jobStore.triggersFired(triggers);
                for (TriggerFiredBundle bundle : bundles) {
                    JobRunShell shell = jobRunShellFactory.createJobRunShell(bundle);
                    threadPool.runInThread(shell);
                }
            } catch (Exception e) {
                // log, backoff, continue — never crash the loop
            }
        }
    }
}
```

---

## 5. Job Execution: JobRunShell

```java
// Wraps a single job execution — runs on a worker thread
public class JobRunShell implements Runnable {
    private final TriggerFiredBundle bundle;
    private final Scheduler scheduler;

    @Override
    public void run() {
        JobExecutionContext context = new JobExecutionContextImpl(scheduler, bundle);
        Job job = scheduler.getJobFactory().newJob(bundle);

        // Notify listeners: beforeExecution (veto check)
        if (!notifyListenersBefore(context)) {
            // vetoed by a TriggerListener — update store and exit
            jobStore.triggeredJobComplete(trigger, jobDetail,
                CompletedExecutionInstruction.SET_TRIGGER_COMPLETE);
            return;
        }

        Throwable jobException = null;
        boolean doConcurrencyCheck = jobDetail.isConcurrentExecutionDisallowed();

        try {
            long startTime = System.currentTimeMillis();
            job.execute(context);
            context.setJobRunTime(System.currentTimeMillis() - startTime);
        } catch (JobExecutionException e) {
            jobException = e;
            if (e.refireImmediately()) {
                // refire once, then move on
                run();
                return;
            }
            if (e.unscheduleFiringTrigger()) {
                instruction = CompletedExecutionInstruction.SET_TRIGGER_COMPLETE;
            }
        } finally {
            notifyListenersComplete(context, jobException);
            jobStore.triggeredJobComplete(trigger, jobDetail, instruction);
            // releases BLOCKED state if DisallowConcurrentExecution was set
        }
    }
}
```

---

## 6. Listener Framework (Observer Pattern)

```java
public interface JobListener {
    String getName();
    void jobToBeExecuted(JobExecutionContext context);
    void jobExecutionVetoed(JobExecutionContext context);      // called if TriggerListener vetoed
    void jobWasExecuted(JobExecutionContext context, JobExecutionException e);
}

public interface TriggerListener {
    String getName();
    void triggerFired(Trigger trigger, JobExecutionContext context);
    boolean vetoJobExecution(Trigger trigger, JobExecutionContext context); // true = veto
    void triggerMisfired(Trigger trigger);
    void triggerComplete(Trigger trigger, JobExecutionContext context,
                         CompletedExecutionInstruction instruction);
}

public interface SchedulerListener {
    void jobScheduled(Trigger trigger);
    void jobUnscheduled(String triggerKey);
    void triggerPaused(String triggerKey);
    void triggerResumed(String triggerKey);
    void schedulerStarted();
    void schedulerShuttingdown();
    void schedulingDataCleared();
}

// Built-in listeners
public class JobChainingListener implements JobListener {
    private final Map<String, String> chainLinks = new LinkedHashMap<>(); // jobA -> jobB

    public void addJobChainLink(String firstJobKey, String secondJobKey) {
        chainLinks.put(firstJobKey, secondJobKey);
    }

    @Override
    public void jobWasExecuted(JobExecutionContext ctx, JobExecutionException ex) {
        if (ex != null) return;  // don't chain on failure
        String followUp = chainLinks.get(ctx.getJobDetail().getKey());
        if (followUp != null) {
            ctx.getScheduler().triggerJob(followUp, null);
        }
    }
}

public class AuditLogListener implements JobListener {
    private final AuditRepository auditRepository;

    @Override
    public void jobWasExecuted(JobExecutionContext ctx, JobExecutionException ex) {
        auditRepository.save(AuditRecord.builder()
            .jobKey(ctx.getJobDetail().getKey())
            .fireTime(ctx.getFireTime())
            .scheduledFireTime(ctx.getScheduledFireTime())
            .runTimeMs(ctx.getJobRunTime())
            .status(ex == null ? "SUCCESS" : "FAILED")
            .errorMessage(ex != null ? ex.getMessage() : null)
            .nodeId(System.getenv("NODE_ID"))
            .build());
    }
}
```

---

## 7. JobStore Implementations

### 7.1 JdbcJobStore (Production — Persistent, Clustered)

```java
public class JdbcJobStore implements JobStore {
    private final DataSource dataSource;
    private final String tablePrefix;          // allows multi-tenant in same DB
    private final String instanceId;           // unique per node (hostname + PID)
    private final long clusterCheckinInterval; // 7500ms default
    private final long misfireThreshold;       // 60000ms — time before a trigger is "misfired"

    // acquireNextTriggers uses SELECT FOR UPDATE (pessimistic) or optimistic CAS
    // to ensure exactly one node fires each trigger in a cluster
    @Override
    @Transactional
    public List<OperableTrigger> acquireNextTriggers(long noLaterThan, int maxCount, long timeWindow) {
        List<OperableTrigger> acquiredTriggers = new ArrayList<>();
        try (Connection conn = getConnection()) {
            // SELECT triggers WHERE state = 'WAITING'
            //   AND next_fire_time <= noLaterThan + timeWindow
            //   ORDER BY priority DESC, next_fire_time ASC
            //   LIMIT maxCount
            //   FOR UPDATE SKIP LOCKED        ← key for cluster safety
            List<TriggerKey> keys = dao.selectTriggerToAcquire(conn, noLaterThan, maxCount);
            for (TriggerKey key : keys) {
                OperableTrigger trigger = dao.selectTrigger(conn, key);
                // Handle misfire
                if (trigger.getNextFireTime().before(new Date(now - misfireThreshold))) {
                    doUpdateOfMisfiredTrigger(conn, trigger);
                    continue;
                }
                // CAS state: WAITING -> ACQUIRED
                if (dao.updateTriggerStateFromOtherState(conn, key, "ACQUIRED", "WAITING") == 1) {
                    acquiredTriggers.add(trigger);
                }
            }
        }
        return acquiredTriggers;
    }

    @Override
    @Transactional
    public void triggeredJobComplete(OperableTrigger trigger, JobDetail job,
                                     CompletedExecutionInstruction instruction) {
        switch (instruction) {
            case DELETE_TRIGGER:
                dao.deleteTrigger(trigger.getKey());
                break;
            case SET_TRIGGER_COMPLETE:
                dao.updateTriggerState(trigger.getKey(), "COMPLETE");
                break;
            case SET_ALL_JOB_TRIGGERS_COMPLETE:
                dao.updateTriggersStatesForJob(job.getKey(), "COMPLETE");
                break;
            default:
                // Advance trigger to next fire time
                trigger.triggered(null);
                if (trigger.getNextFireTime() != null) {
                    dao.updateTrigger(trigger, "WAITING");
                } else {
                    dao.updateTriggerState(trigger.getKey(), "COMPLETE");
                    if (!job.isDurable()) dao.deleteJob(job.getKey());
                }
        }
        // Release DisallowConcurrentExecution block
        if (job.isConcurrentExecutionDisallowed()) {
            dao.updateTriggersStatesForJobFromOtherState(job.getKey(), "WAITING", "BLOCKED");
        }
    }
}
```

#### Database Schema

```sql
CREATE TABLE SCHEDULER_JOB_DETAILS (
    sched_name        VARCHAR(120) NOT NULL,
    job_name          VARCHAR(200) NOT NULL,
    job_group         VARCHAR(200) NOT NULL,
    description       VARCHAR(250),
    job_class_name    VARCHAR(250) NOT NULL,
    is_durable        BOOLEAN      NOT NULL DEFAULT FALSE,
    is_nonconcurrent  BOOLEAN      NOT NULL DEFAULT FALSE,
    is_update_data    BOOLEAN      NOT NULL DEFAULT FALSE,
    requests_recovery BOOLEAN      NOT NULL DEFAULT FALSE,
    job_data          BLOB,
    PRIMARY KEY (sched_name, job_name, job_group)
);

CREATE TABLE SCHEDULER_TRIGGERS (
    sched_name         VARCHAR(120) NOT NULL,
    trigger_name       VARCHAR(200) NOT NULL,
    trigger_group      VARCHAR(200) NOT NULL,
    job_name           VARCHAR(200) NOT NULL,
    job_group          VARCHAR(200) NOT NULL,
    description        VARCHAR(250),
    next_fire_time     BIGINT,      -- epoch ms, indexed
    prev_fire_time     BIGINT,
    priority           INTEGER      DEFAULT 5,
    trigger_state      VARCHAR(16)  NOT NULL,  -- WAITING|ACQUIRED|EXECUTING|PAUSED|BLOCKED|ERROR|COMPLETE
    trigger_type       VARCHAR(8)   NOT NULL,  -- CRON|SIMPLE|BLOB
    start_time         BIGINT       NOT NULL,
    end_time           BIGINT,
    calendar_name      VARCHAR(200),
    misfire_instr      SMALLINT     DEFAULT 0,
    job_data           BLOB,
    PRIMARY KEY (sched_name, trigger_name, trigger_group),
    FOREIGN KEY (sched_name, job_name, job_group) REFERENCES SCHEDULER_JOB_DETAILS
);

CREATE TABLE SCHEDULER_CRON_TRIGGERS (
    sched_name      VARCHAR(120) NOT NULL,
    trigger_name    VARCHAR(200) NOT NULL,
    trigger_group   VARCHAR(200) NOT NULL,
    cron_expression VARCHAR(120) NOT NULL,
    time_zone_id    VARCHAR(80),
    PRIMARY KEY (sched_name, trigger_name, trigger_group),
    FOREIGN KEY (sched_name, trigger_name, trigger_group) REFERENCES SCHEDULER_TRIGGERS
);

CREATE TABLE SCHEDULER_SIMPLE_TRIGGERS (
    sched_name       VARCHAR(120) NOT NULL,
    trigger_name     VARCHAR(200) NOT NULL,
    trigger_group    VARCHAR(200) NOT NULL,
    repeat_count     BIGINT       NOT NULL,
    repeat_interval  BIGINT       NOT NULL,
    times_triggered  BIGINT       NOT NULL DEFAULT 0,
    PRIMARY KEY (sched_name, trigger_name, trigger_group)
);

CREATE TABLE SCHEDULER_FIRED_TRIGGERS (
    sched_name        VARCHAR(120) NOT NULL,
    entry_id          VARCHAR(140) NOT NULL,
    trigger_name      VARCHAR(200) NOT NULL,
    trigger_group     VARCHAR(200) NOT NULL,
    instance_name     VARCHAR(200) NOT NULL,  -- which node fired it
    fired_time        BIGINT       NOT NULL,
    sched_time        BIGINT       NOT NULL,
    priority          INTEGER      NOT NULL,
    state             VARCHAR(16)  NOT NULL,
    job_name          VARCHAR(200),
    job_group         VARCHAR(200),
    is_nonconcurrent  BOOLEAN,
    requests_recovery BOOLEAN,
    PRIMARY KEY (sched_name, entry_id)
);

-- Node heartbeats for cluster membership
CREATE TABLE SCHEDULER_SCHEDULER_STATE (
    sched_name        VARCHAR(120) NOT NULL,
    instance_name     VARCHAR(200) NOT NULL,
    last_checkin_time BIGINT       NOT NULL,
    checkin_interval  BIGINT       NOT NULL,
    PRIMARY KEY (sched_name, instance_name)
);

-- Covering index for the hot path: acquireNextTriggers
CREATE INDEX idx_triggers_next_fire ON SCHEDULER_TRIGGERS (sched_name, trigger_state, next_fire_time);
```

---

## 8. Clustering & Failure Recovery

```java
public class ClusterManager extends Thread {
    private final JdbcJobStore jobStore;
    private final long checkinInterval = 7_500L;   // 7.5s

    @Override
    public void run() {
        while (!shutdown) {
            try {
                // 1. Update own heartbeat
                jobStore.clusterCheckIn();

                // 2. Find dead nodes (last_checkin > 2 * checkinInterval ago)
                List<SchedulerStateRecord> deadNodes = jobStore.findFailedInstances();
                if (!deadNodes.isEmpty()) {
                    // 3. Recover: find ACQUIRED/EXECUTING triggers from dead nodes
                    //    → reset to WAITING if requestsRecovery, else ERROR
                    jobStore.clusterRecover(deadNodes);
                }

                Thread.sleep(checkinInterval);
            } catch (Exception e) {
                log.error("Cluster check-in failed", e);
            }
        }
    }
}

// Recovery logic — called by any surviving node
void clusterRecover(List<SchedulerStateRecord> failedInstances) {
    for (SchedulerStateRecord instance : failedInstances) {
        List<FiredTriggerRecord> firedTriggers = dao.selectFiredTriggerRecords(instance.getInstanceId());

        for (FiredTriggerRecord rec : firedTriggers) {
            if (rec.isRequestsRecovery()) {
                // Create a recovery trigger — fire immediately
                OperableTrigger recoveryTrigger = new SimpleTrigger(
                    "RECOVER_" + instance.getInstanceId() + "_" + rec.getEntryId(),
                    Scheduler.DEFAULT_RECOVERY_GROUP,
                    new Date()
                );
                recoveryTrigger.setJobKey(rec.getJobKey());
                dao.storeTrigger(recoveryTrigger, false);
            }
            // Mark the fired entry as recovered
            dao.deleteFiredTrigger(rec.getEntryId());
            // Reset trigger state
            dao.updateTriggerStateFromOtherState(rec.getTriggerKey(), "WAITING", "ACQUIRED");
        }

        dao.deleteSchedulerState(instance.getInstanceId());
    }
}
```

---

## 9. REST API Layer

```java
@RestController
@RequestMapping("/api/v1/scheduler")
public class SchedulerController {

    @PostMapping("/jobs")
    public ResponseEntity<JobResponse> createJob(@RequestBody @Valid CreateJobRequest req) {
        JobDetail job = JobBuilder.newJob(resolveClass(req.getJobClass()))
            .withIdentity(req.getName(), req.getGroup())
            .withDescription(req.getDescription())
            .usingJobData(new JobDataMap(req.getDataMap()))
            .storeDurably(req.isDurable())
            .requestRecovery(req.isRequestsRecovery())
            .build();

        Trigger trigger = buildTrigger(req.getTrigger());
        scheduler.scheduleJob(job, trigger);
        return ResponseEntity.ok(JobResponse.from(job, trigger));
    }

    @PostMapping("/jobs/{jobKey}/trigger")
    public ResponseEntity<Void> triggerNow(@PathVariable String jobKey,
                                            @RequestBody(required=false) Map<String, Object> data) {
        scheduler.triggerJob(jobKey, data != null ? new JobDataMap(data) : null);
        return ResponseEntity.accepted().build();
    }

    @PutMapping("/jobs/{jobKey}/pause")
    public ResponseEntity<Void> pause(@PathVariable String jobKey) {
        scheduler.pauseJob(jobKey);
        return ResponseEntity.ok().build();
    }

    @PutMapping("/jobs/{jobKey}/resume")
    public ResponseEntity<Void> resume(@PathVariable String jobKey) {
        scheduler.resumeJob(jobKey);
        return ResponseEntity.ok().build();
    }

    @DeleteMapping("/jobs/{jobKey}")
    public ResponseEntity<Void> delete(@PathVariable String jobKey) {
        scheduler.deleteJob(jobKey);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/jobs")
    public ResponseEntity<List<JobSummary>> listJobs(
            @RequestParam(defaultValue = "DEFAULT") String group) {
        return ResponseEntity.ok(scheduler.getJobKeys(GroupMatcher.groupEquals(group))
            .stream().map(k -> JobSummary.from(scheduler.getJobDetail(k))).toList());
    }

    @GetMapping("/jobs/{jobKey}/history")
    public ResponseEntity<Page<AuditRecord>> history(@PathVariable String jobKey, Pageable page) {
        return ResponseEntity.ok(auditRepository.findByJobKey(jobKey, page));
    }
}
```

---

## 10. Design Patterns Applied

| Pattern | Where Used | Why |
|---|---|---|
| **Strategy** | `Trigger` hierarchy (Cron / Simple / OneTime) | Pluggable scheduling strategies without conditionals |
| **Template Method** | `AbstractTrigger.triggered()` → `computeNextFireTime()` | Common lifecycle; subclasses only override the delta |
| **Command** | `Job` interface | Encapsulates executable work; enables queuing, retry, undo |
| **Observer** | `JobListener`, `TriggerListener`, `SchedulerListener` | Decouple audit, chaining, alerting from core engine |
| **Factory Method** | `JobFactory.newJob()` | Allow DI containers to inject dependencies into Job instances |
| **Builder** | `JobBuilder`, `TriggerBuilder` | Readable construction of complex immutable objects |
| **Null Object** | `NoOpJob` | Safe default for recovered jobs whose class no longer exists |
| **Chain of Responsibility** | Listener pipeline (veto chain) | Multiple listeners can inspect/veto before execution |

---

## 11. SOLID Analysis

| Principle | Compliance |
|---|---|
| **SRP** | `Scheduler` coordinates; `JobStore` persists; `ThreadPool` executes; `JobRunShell` runs one job — each class has one axis of change |
| **OCP** | New trigger types added by implementing `OperableTrigger`; new listeners added without modifying the scheduler |
| **LSP** | Any `Trigger` implementation can substitute another — `acquireNextTriggers` only calls interface methods |
| **ISP** | `SchedulerListener`, `JobListener`, `TriggerListener` are separate interfaces; clients implement only what they need |
| **DIP** | `Scheduler` depends on `JobStore` interface, not `JdbcJobStore`; swap to in-memory store for tests |

---

## 12. Concurrency Design

```
┌─────────────────────────────────────────────────────┐
│  QuartzSchedulerThread  (single thread)              │
│  ┌──────────────┐                                    │
│  │ Main Loop    │ ──acquireNextTriggers──► JobStore  │
│  │              │ ◄── TriggerFiredBundle ──          │
│  │              │                                    │
│  │  for each    │ ──runInThread──► ThreadPool        │
│  │  bundle      │                  │                 │
│  └──────────────┘                  ▼                 │
│                              Worker Thread 1         │
│                              Worker Thread 2   ...   │
│                              Worker Thread N         │
└─────────────────────────────────────────────────────┘

DisallowConcurrentExecution:
  When job J is executing → all triggers for J are set to BLOCKED in DB
  On completion → all BLOCKED triggers for J reset to WAITING
  This uses DB state (not in-memory) so it works across nodes.
```

**Thread safety guarantees:**
- `JobStore` is the single concurrency arbiter — all nodes compete via `SELECT FOR UPDATE SKIP LOCKED`
- `QuartzSchedulerThread` is the single producer of work items per node
- Worker threads are consumers — they read `JobRunShell` which captures all state at fire time
- `volatile boolean halted/paused` on the scheduler thread — safe cross-thread signal

---

## 13. Key Extension Points

```java
// 1. Custom Job implementations
public class HttpCallbackJob implements Job {
    @Override
    public void execute(JobExecutionContext ctx) {
        String url = ctx.getMergedJobDataMap().getString("url");
        String method = ctx.getMergedJobDataMap().getString("method");
        restTemplate.exchange(url, HttpMethod.valueOf(method), null, Void.class);
    }
}

public class ShellCommandJob implements Job {
    @Override
    public void execute(JobExecutionContext ctx) throws JobExecutionException {
        String command = ctx.getMergedJobDataMap().getString("command");
        // Replaces Jenkins "Execute Shell" build step
        int exitCode = ProcessRunner.run(command);
        if (exitCode != 0) throw new JobExecutionException("Exit code: " + exitCode);
    }
}

// 2. Custom ThreadPool (e.g., virtual threads in Java 21)
public class VirtualThreadPool implements ThreadPool {
    private final ExecutorService executor = Executors.newVirtualThreadPerTaskExecutor();
    
    @Override
    public boolean runInThread(Runnable runnable) {
        executor.submit(runnable);
        return true;
    }
}

// 3. Dead Letter Queue listener — capture all failed jobs
public class DlqJobListener implements JobListener {
    @Override
    public void jobWasExecuted(JobExecutionContext ctx, JobExecutionException ex) {
        if (ex != null) {
            dlqService.publish(FailedJobEvent.from(ctx, ex));
        }
    }
}
```

---

## 14. Failure Modes & Mitigations

| Failure | Detection | Mitigation |
|---|---|---|
| Node crashes mid-execution | Heartbeat timeout in `SCHEDULER_STATE` | `ClusterManager` on surviving nodes detects dead nodes; re-fires if `requestsRecovery=true` |
| DB unavailable | `acquireNextTriggers` throws | Backoff + retry in main loop; jobs miss but don't duplicate |
| Thread pool saturated | `blockForAvailableThreads` blocks | Trigger stays ACQUIRED; re-acquire on next loop pass after threads free |
| Cron trigger misfired (node was down) | `next_fire_time < now - misfireThreshold` | Apply misfire instruction (FIRE_NOW / DO_NOTHING / IGNORE) |
| Concurrent execution of DisallowConcurrentExecution job | DB state BLOCKED | Second trigger stays BLOCKED until first completes, then fires |
| Job class not found after deploy | `ClassNotFoundException` in `JobFactory.newJob()` | Set trigger to ERROR state; alert via `SchedulerListener.schedulerError()` |
| Infinite job loop | No built-in — job never returns | Max execution timeout via `ThreadPool` future with timeout; kill and mark ERROR |

---

## 15. Sequence Diagram: Cron Job Fires in Cluster

```
Node-1 (QuartzSchedulerThread)         DB                     Node-2 (QuartzSchedulerThread)
        │                               │                               │
        │── acquireNextTriggers ────────►                               │
        │                               │◄── acquireNextTriggers ───────│
        │◄── [trigger T1, ACQUIRED] ───  │    (SKIP LOCKED: misses T1)  │
        │                               │── [empty] ───────────────────►│
        │── triggersFired(T1) ──────────►                               │
        │◄── TriggerFiredBundle ────────│                               │
        │                               │                               │
        │──[dispatch to ThreadPool]──►  │                               │
        │   JobRunShell.run()           │                               │
        │   job.execute(ctx)            │                               │
        │   [completes]                 │                               │
        │── triggeredJobComplete ───────►                               │
        │   (advance to next fire time) │                               │
        │   trigger → WAITING           │                               │
```

---

## 16. Metrics to Expose

```
scheduler.jobs.active                    # currently executing
scheduler.jobs.waiting                   # triggers in WAITING state
scheduler.trigger.misfire.count          # tagged by job_group
scheduler.job.execution.duration.ms      # histogram, tagged by job_class
scheduler.thread_pool.utilization        # active / pool_size
scheduler.cluster.nodes                  # live node count
scheduler.job.failure.count              # tagged by job_key, exception_type
scheduler.db.acquire_triggers.latency.ms # hot path latency
```

---

## FAANG Interview Callouts

**Q: How do you guarantee a job fires exactly once in a 3-node cluster?**
`SELECT FOR UPDATE SKIP LOCKED` on the trigger row — exactly one node wins the lock and transitions state from `WAITING` → `ACQUIRED`. Other nodes skip that row.

**Q: What's your misfire strategy for a financial batch job?**
`IGNORE_MISFIRE_POLICY` — fire once immediately for every missed window, because missing a settlement window is a compliance issue. For idempotent reporting jobs: `DO_NOTHING` (skip missed windows).

**Q: How does DisallowConcurrentExecution work across nodes?**
It's DB-backed. When node-1 fires job J, all other triggers for J are set to `BLOCKED` in `FIRED_TRIGGERS`. Node-2's `acquireNextTriggers` skips `BLOCKED` triggers. When node-1's job completes, `triggeredJobComplete` resets all of J's triggers from `BLOCKED` → `WAITING`.

**Q: How do you replace Jenkins without losing observability?**
`AuditLogListener` + `DlqJobListener` gives you execution history, failure capture, and alerting. The REST API + metrics replace Jenkins' UI dashboard. `ShellCommandJob` wraps existing scripts verbatim — zero migration friction.

**Q: How does the scheduler handle clock skew in a cluster?**
Nodes compare `next_fire_time` against the DB server's `NOW()` (not their local clock) in the `acquireNextTriggers` query. This eliminates per-node clock drift as a source of duplicate or missed firings.
