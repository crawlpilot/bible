# Spring Batch — Interview Questions

---

## Fundamentals (L3–L4)

**Q1. What is the chunk-oriented processing model?**
Read one item at a time → optionally process/transform it → accumulate N items in memory → write the chunk in one batch transaction. Transaction commits every N items (chunk size). Memory is bounded — only N items in memory at once regardless of total dataset size. If write fails for a chunk, only that chunk's transaction rolls back; previous chunks are committed.

**Q2. What are the main components of a Spring Batch Job?**
- `Job`: named workflow containing one or more Steps
- `Step`: a unit of work — either chunk-oriented or Tasklet
- `ItemReader<T>`: reads one item at a time
- `ItemProcessor<T, R>`: transforms/validates (returns null to skip)
- `ItemWriter<R>`: writes a list of items (one chunk) at a time
- `JobRepository`: persists Job/Step execution state to DB
- `JobLauncher`: triggers a job with parameters

**Q3. What is `@StepScope` and why is it required?**
`@StepScope` creates a new bean instance per Step execution. Required when a bean needs `@Value("#{jobParameters['date']}")` — job parameters are only available at Step execution time, not at ApplicationContext startup. Without `@StepScope`, `@Value` of job parameters is null (evaluated too early).

**Q4. What happens when a Spring Batch job fails midway?**
Spring Batch records the step status in `JobRepository` (FAILED). On rerun with the same job parameters, it skips COMPLETED steps and retries from the FAILED step. Within a chunk-oriented step, it resumes from the next unprocessed item based on the read count saved in `StepExecution`.

**Q5. What is the difference between a chunk step and a Tasklet step?**
- **Chunk step**: reads/processes/writes N items per transaction — for processing large datasets
- **Tasklet**: executes arbitrary code once per step run — for non-data tasks (file rename, directory cleanup, trigger a downstream API, send notification email)

---

## Advanced (L5 Senior)

**Q6. How do you design a skip policy for data quality issues?**
```java
.faultTolerant()
    .skip(ValidationException.class)     // skip bad records
    .skipLimit(100)                      // but only up to 100 — more = job fails
    .noSkip(DataAccessException.class)   // never skip DB errors — they're fatal
    .skipPolicy(new CustomSkipPolicy())  // fine-grained control per exception + count
```
Skip policy rule at principal level: business data errors (bad format, null required field) → skip and log to DLQ. Infrastructure errors (DB down, network) → don't skip, retry, then fail the job.

**Q7. How does partitioned step execution work?**
A master step divides the dataset into partitions using a `Partitioner`. Each partition is described by a `StepExecutionContext` (e.g., `minId=0, maxId=1000`). Worker steps process partitions — locally via thread pool or remotely via message broker. Master step completes when all workers complete.

```
Master:  [0-1M records]
Divide → 4 partitions:
  Worker 1: records 0-250K
  Worker 2: records 250K-500K
  Worker 3: records 500K-750K
  Worker 4: records 750K-1M
All run in parallel → 4x throughput
```

**Q8. How do you prevent a job from running if a previous run is still active?**
```java
@Bean
public JobLauncher jobLauncher(JobRepository jobRepository) throws Exception {
    TaskExecutorJobLauncher launcher = new TaskExecutorJobLauncher();
    launcher.setJobRepository(jobRepository);
    launcher.setTaskExecutor(new SyncTaskExecutor());  // synchronous — blocks
    launcher.afterPropertiesSet();
    return launcher;
}
// Or check JobExplorer before launching:
JobExecution lastRun = jobExplorer.getLastJobExecution("myJob", params);
if (lastRun != null && lastRun.isRunning()) {
    throw new JobExecutionException("Job already running");
}
```

**Q9. How do you pass data between steps in a Job?**
```java
// Step 1 writes to JobExecutionContext
@BeforeStep
public void saveStepContext(StepExecution stepExecution) {
    this.stepExecution = stepExecution;
}

// In reader/processor/writer:
stepExecution.getJobExecution().getExecutionContext()
    .put("processedCount", totalProcessed);

// Step 2 reads from JobExecutionContext
@BeforeStep
public void readPreviousData(StepExecution stepExecution) {
    int count = (int) stepExecution.getJobExecution()
        .getExecutionContext().get("processedCount");
}
```
`StepExecutionContext` is step-scoped (not shared between steps). `JobExecutionContext` is job-scoped (shared across steps).

**Q10. How do you test a Spring Batch job?**
```java
@SpringBatchTest  // provides JobLauncherTestUtils, JobRepositoryTestUtils, StepScopeTestUtils
@SpringBootTest
class MyJobTest {
    @Autowired JobLauncherTestUtils utils;

    @Test
    void testFullJob() throws Exception {
        JobExecution exec = utils.launchJob(new JobParametersBuilder()
            .addString("date", "2024-01-15").addLong("run", 1L).toJobParameters());
        assertThat(exec.getStatus()).isEqualTo(BatchStatus.COMPLETED);
        assertThat(exec.getStepExecutions()).extracting(StepExecution::getWriteCount)
            .containsExactly(100L);
    }

    @Test
    void testSingleStep() throws Exception {
        JobExecution exec = utils.launchStep("processStep");
        assertThat(exec.getStatus()).isEqualTo(BatchStatus.COMPLETED);
    }
}
```

---

## Principal Engineer Level

**Q11. How do you design Spring Batch for processing 100 million records nightly within a 4-hour window?**

Back-of-envelope: 100M records / 4 hours = 6.9K records/sec throughput required.

Architecture:
1. **Partitioning**: split by ID range, date range, or hash — 20 partitions
2. **Remote partitioning**: partitions run as separate pods (Kubernetes Jobs) triggered via Kafka
3. **Chunk size tuning**: large chunks (1000-5000) for sequential I/O; smaller for complex processing
4. **JPA vs JDBC**: JDBC batch insert is 10-50x faster than JPA for bulk writes
5. **Connection pooling**: increase HikariCP pool to match partition count
6. **Read optimization**: `JdbcPagingItemReader` with sorted cursor; `JpaPagingItemReader` with indexed query

Expected throughput: 20 workers × 5K records/sec each = 100K records/sec → 100M in 16 minutes.

**Q12. How do you handle idempotency in Spring Batch?**
Problem: if a job runs twice with the same parameters, it processes the same data twice. Solution:
1. **Job parameters uniqueness**: include a `run.id` incremented by `RunIdIncrementer` — prevents exact duplicate runs
2. **Idempotent writes**: use `INSERT INTO ... ON CONFLICT DO NOTHING` or upsert patterns
3. **Output cleanup step**: first step deletes any partial output from a previous failed run
4. **Status tracking**: mark source records with a `processed = true` flag; reader filters `WHERE processed = false`

**Q13. When would you NOT use Spring Batch?**
- **Real-time processing**: Batch is for scheduled bulk runs; for streaming data, use Kafka Streams or Apache Flink
- **Simple scheduled tasks**: Spring `@Scheduled` is sufficient for tasks that don't need checkpointing or restartability
- **Sub-second latency**: batch commits every N items; for low-latency, use event-driven architecture
- **Very small datasets**: overhead of JobRepository and transaction management isn't worth it for < 1000 records

---

## Code Walkthroughs

**Q14. Why does this partitioned job fail intermittently?**
```java
@Bean
@StepScope  // missing on the Partitioner!
public Partitioner orderPartitioner() {
    return gridSize -> {
        Map<String, ExecutionContext> partitions = new HashMap<>();
        for (int i = 0; i < gridSize; i++) {
            ExecutionContext ctx = new ExecutionContext();
            ctx.put("minId", i * 1000);
            ctx.put("maxId", (i + 1) * 1000);
            partitions.put("partition" + i, ctx);
        }
        return partitions;
    };
}
```
**Answer**: The `Partitioner` doesn't need `@StepScope` — that's actually correct here. The likely cause of intermittent failure: `gridSize` is not matching partition count in `TaskExecutorPartitionHandler`. If `gridSize` in the Partitioner differs from `TaskExecutorPartitionHandler.setGridSize()`, some partitions may not be processed or extra workers spun for non-existent partitions. Ensure they match or use the same configuration source.

**Q15. What's wrong with this ItemProcessor?**
```java
@Bean
@StepScope
public ItemProcessor<Order, Order> orderProcessor() {
    return order -> {
        if (order.getTotal().compareTo(BigDecimal.ZERO) <= 0) {
            throw new ValidationException("Zero/negative total for order: " + order.getId());
        }
        return order;
    };
}
```
**Answer**: Throwing an exception instead of returning `null` causes the step to fail (or trigger skip/retry, depending on configuration). To skip invalid items without failing the step, return `null` — Spring Batch treats null as "skip this item". Pair with `.skip(ValidationException.class).skipLimit(50)` in the step config to fail the job after too many invalid records.

---

## Common Mistakes

| Mistake | Problem | Fix |
|---------|---------|-----|
| Missing `@StepScope` on reader | Job parameters null at startup | Add `@StepScope` to any bean using job parameters |
| Large chunk size with OOM | Memory exhausted | Tune chunk size; profile memory per item |
| No skip policy | One bad record fails entire job | Add `.faultTolerant().skip(ValidationException.class).skipLimit(N)` |
| Using JPA for bulk writes | 10-50x slower than JDBC batch | Use `JdbcBatchItemWriter` for bulk inserts/updates |
| No restart logic consideration | Rerun processes already-processed data | Design idempotent writes; use `RunIdIncrementer` |
