# Spring Batch — Bulk Processing, ETL, and Scheduled Jobs

Spring Batch provides a framework for **bulk data processing**: reading large datasets, transforming them, and writing results — reliably, with restart capability, skip/retry policies, and parallel execution. It's the go-to for ETL pipelines, end-of-day financial processing, and large-scale data migration.

---

## Core Architecture

```
  Job
   │
   ├── Step 1 (Chunk-Oriented)
   │       ├── ItemReader      ← reads one item at a time
   │       ├── ItemProcessor   ← transforms/validates item (optional)
   │       └── ItemWriter      ← writes chunk of N items in batch
   │
   ├── Step 2 (Tasklet — for non-chunk work)
   │       └── Tasklet         ← execute arbitrary logic once
   │
   └── Step 3 (Partitioned)
           ├── PartitionHandler
           └── Worker Steps (run in parallel)
                   ├── Worker 1: reads partition 0
                   ├── Worker 2: reads partition 1
                   └── Worker N: reads partition N-1

  JobRepository ← persists job execution state (JobInstance, JobExecution, StepExecution)
  JobLauncher   ← triggers job execution
  JobExplorer   ← queries past executions
```

---

## Chunk-Oriented Processing

The most common Step type. Reads items one by one, processes them, accumulates a chunk, then writes the chunk in one batch:

```java
@Configuration
public class OrderBatchConfig {

    @Bean
    public Job orderProcessingJob(JobRepository jobRepository,
                                   Step readOrdersStep,
                                   Step generateReportStep) {
        return new JobBuilder("orderProcessingJob", jobRepository)
            .incrementer(new RunIdIncrementer())  // unique JobInstance per run
            .start(readOrdersStep)
            .next(generateReportStep)
            .build();
    }

    @Bean
    @StepScope  // REQUIRED for late binding of job parameters
    public JpaPagingItemReader<Order> orderReader(
            @Value("#{jobParameters['processDate']}") String processDate,
            EntityManagerFactory emf) {
        return new JpaPagingItemReaderBuilder<Order>()
            .name("orderReader")
            .entityManagerFactory(emf)
            .queryString("SELECT o FROM Order o WHERE DATE(o.createdAt) = :date AND o.status = 'PENDING'")
            .parameterValues(Map.of("date", LocalDate.parse(processDate)))
            .pageSize(500)  // JPA page size — tune for memory/performance
            .build();
    }

    @Bean
    public ItemProcessor<Order, ProcessedOrder> orderProcessor() {
        return order -> {
            if (!order.isValid()) {
                return null;  // null = skip this item — NOT written to output
            }
            return new ProcessedOrder(order, calculateTotal(order));
        };
    }

    @Bean
    public JdbcBatchItemWriter<ProcessedOrder> orderWriter(DataSource dataSource) {
        return new JdbcBatchItemWriterBuilder<ProcessedOrder>()
            .sql("INSERT INTO processed_orders (id, total, processed_at) VALUES (:id, :total, NOW())")
            .dataSource(dataSource)
            .beanMapped()
            .build();
    }

    @Bean
    public Step readOrdersStep(JobRepository jobRepository,
                                PlatformTransactionManager txManager,
                                JpaPagingItemReader<Order> reader,
                                ItemProcessor<Order, ProcessedOrder> processor,
                                JdbcBatchItemWriter<ProcessedOrder> writer) {
        return new StepBuilder("readOrdersStep", jobRepository)
            .<Order, ProcessedOrder>chunk(100, txManager)  // commit every 100 items
            .reader(reader)
            .processor(processor)
            .writer(writer)
            .faultTolerant()
                .skip(ValidationException.class)
                .skipLimit(50)              // skip up to 50 bad items
                .retry(TransientDbException.class)
                .retryLimit(3)
            .listener(new StepExecutionListener() {
                @Override
                public void beforeStep(StepExecution stepExecution) {
                    log.info("Starting step: {}", stepExecution.getStepName());
                }
            })
            .build();
    }
}
```

---

## Tasklet Step

For non-chunk work: clean temp files, send notification, move files, trigger downstream:

```java
@Bean
public Step cleanupStep(JobRepository jobRepository, PlatformTransactionManager txManager) {
    return new StepBuilder("cleanupStep", jobRepository)
        .tasklet((contribution, chunkContext) -> {
            String processDate = chunkContext.getStepContext()
                .getJobParameters().get("processDate").toString();
            fileService.deleteProcessingFiles(processDate);
            return RepeatStatus.FINISHED;
        }, txManager)
        .build();
}
```

---

## Partitioned Steps — Parallel Processing

Split a large dataset into partitions processed in parallel:

```java
@Bean
public Step masterStep(JobRepository jobRepository,
                        PartitionHandler partitionHandler,
                        Partitioner partitioner) {
    return new StepBuilder("masterStep", jobRepository)
        .partitioner("workerStep", partitioner)
        .partitionHandler(partitionHandler)
        .gridSize(4)  // 4 parallel workers
        .build();
}

@Bean
public Partitioner orderPartitioner(DataSource dataSource) {
    // Splits by customer ID range
    ColumnRangePartitioner partitioner = new ColumnRangePartitioner();
    partitioner.setColumn("customer_id");
    partitioner.setTable("orders");
    partitioner.setDataSource(dataSource);
    return partitioner;
}

@Bean
public TaskExecutorPartitionHandler partitionHandler(
        @Qualifier("workerStep") Step workerStep,
        TaskExecutor taskExecutor) {
    TaskExecutorPartitionHandler handler = new TaskExecutorPartitionHandler();
    handler.setStep(workerStep);
    handler.setTaskExecutor(taskExecutor);
    handler.setGridSize(4);
    return handler;
}

@Bean
public TaskExecutor batchTaskExecutor() {
    ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
    executor.setCorePoolSize(4);
    executor.setMaxPoolSize(8);
    executor.setQueueCapacity(100);
    executor.setThreadNamePrefix("batch-");
    return executor;
}
```

---

## JobRepository — State Management

Spring Batch persists all execution state in a relational database (H2 for tests, PostgreSQL for prod):

```sql
-- Tables created automatically by Spring Batch schema
BATCH_JOB_INSTANCE     -- unique job + parameters combination
BATCH_JOB_EXECUTION    -- each run of a JobInstance
BATCH_STEP_EXECUTION   -- each step within a job execution
BATCH_JOB_EXECUTION_PARAMS  -- parameters passed to the job
```

```java
// Restart: only reruns FAILED steps — skips COMPLETED steps
// This is automatic — no code needed

// Check job history
JobExecution lastExecution = jobExplorer.getLastJobExecution("orderProcessingJob",
    new JobParameters(Map.of("processDate", new JobParameter("2024-01-15"))));
```

---

## Running Jobs

```java
// Launch programmatically
@Component
public class BatchScheduler {
    @Scheduled(cron = "0 0 2 * * *")  // 2 AM daily
    public void runNightlyBatch() throws Exception {
        JobParameters params = new JobParametersBuilder()
            .addString("processDate", LocalDate.now().minusDays(1).toString())
            .addLong("timestamp", System.currentTimeMillis())  // makes each run unique
            .toJobParameters();
        jobLauncher.run(orderProcessingJob, params);
    }
}

// Or via REST endpoint for on-demand
@PostMapping("/admin/batch/run")
public JobExecution triggerBatch(@RequestBody BatchRequest req) {
    JobParameters params = new JobParametersBuilder()
        .addString("processDate", req.getDate())
        .addLong("timestamp", System.currentTimeMillis())
        .toJobParameters();
    return jobLauncher.run(orderProcessingJob, params);
}
```

---

## Skip and Retry Policy

```java
// Fine-grained control with SkipPolicy
public class ValidationSkipPolicy implements SkipPolicy {
    @Override
    public boolean shouldSkip(Throwable t, long skipCount) {
        if (t instanceof ValidationException) {
            return skipCount < 100;  // skip up to 100 validation errors
        }
        return false;  // don't skip anything else (let it fail the job)
    }
}

// Listener to track skipped items
@Component
public class SkipListener implements org.springframework.batch.core.SkipListener<Order, ProcessedOrder> {
    @Override
    public void onSkipInRead(Throwable t) {
        log.warn("Skipped read: {}", t.getMessage());
        metrics.increment("batch.skipped.read");
    }

    @Override
    public void onSkipInProcess(Order item, Throwable t) {
        log.warn("Skipped processing of order {}: {}", item.getId(), t.getMessage());
        deadLetterQueue.publish(item);
    }
}
```

---

## Testing Batch Jobs

```java
@SpringBatchTest  // provides JobLauncherTestUtils, JobRepositoryTestUtils
@SpringBootTest
@Transactional
class OrderBatchJobTest {

    @Autowired
    private JobLauncherTestUtils jobLauncherTestUtils;

    @Autowired
    private JobRepositoryTestUtils jobRepositoryTestUtils;

    @BeforeEach
    void cleanJobHistory() {
        jobRepositoryTestUtils.removeJobExecutions();
    }

    @Test
    void shouldProcessPendingOrders() throws Exception {
        // Given
        orderRepository.saveAll(List.of(
            new Order(UUID.randomUUID(), PENDING),
            new Order(UUID.randomUUID(), PENDING)
        ));

        // When
        JobExecution exec = jobLauncherTestUtils.launchJob(
            new JobParametersBuilder()
                .addString("processDate", "2024-01-15")
                .addLong("timestamp", System.currentTimeMillis())
                .toJobParameters());

        // Then
        assertThat(exec.getStatus()).isEqualTo(BatchStatus.COMPLETED);
        StepExecution stepExec = exec.getStepExecutions().iterator().next();
        assertThat(stepExec.getWriteCount()).isEqualTo(2);
        assertThat(stepExec.getSkipCount()).isEqualTo(0);
    }
}
```

---

## Design Patterns Used

| Pattern | Where in Spring Batch |
|---------|----------------------|
| **Template Method** | `AbstractItemReader`, `AbstractItemWriter` — define skeleton, subclasses implement specifics |
| **Strategy** | `ItemReader`, `ItemProcessor`, `ItemWriter` — pluggable implementations |
| **Chain of Responsibility** | Step sequence in Job — each step passes result to next |
| **Composite** | `CompositeItemProcessor`, `CompositeItemWriter` — chain multiple processors/writers |
| **Builder** | `JobBuilder`, `StepBuilder` — fluent construction of complex objects |
| **Repository** | `JobRepository` — persists and retrieves execution state |

---

## Trade-offs

| Aspect | Benefit | Cost |
|--------|---------|------|
| Chunk processing | Bounded memory; commit every N items | Tuning chunk size for optimal throughput |
| JobRepository | Restartability, observability | Requires schema in DB; migration overhead |
| Partitioning | Horizontal scale | Complexity; partition key design |
| Skip/retry | Fault tolerant; partial success | May mask data quality problems |
| @StepScope | Late binding job parameters | Beans created per step, not once |

---

## FAANG Interview Callout

1. **"How does Spring Batch handle restartability?"**
   - `JobRepository` persists step status; rerun skips COMPLETED steps, retries FAILED steps from last checkpoint

2. **"What's the difference between a chunk-oriented step and a tasklet?"**
   - Chunk: reads/processes/writes N items per transaction — memory efficient for large datasets
   - Tasklet: execute arbitrary code once per step — file moves, notifications, trigger downstream

3. **"How do you scale Spring Batch for 100M records?"**
   - Partitioning: split dataset by range/hash → N parallel workers
   - Remote partitioning: workers are separate JVMs/pods via Kafka or RabbitMQ
   - Async I/O: use async reader/writer where DB supports it

4. **"What happens if a step fails midway through processing?"**
   - Transaction rolls back for current chunk; step marked FAILED in JobRepository
   - On rerun: completed chunks before failure are skipped (idempotency via job parameters)

5. **"How do you monitor Spring Batch jobs in production?"**
   - `StepExecutionListener`: emit metrics per step (read/write/skip count, duration)
   - Spring Boot Actuator: expose job execution state via custom endpoint
   - Alert on `BatchStatus.FAILED` — integrate with PagerDuty/Opsgenie
