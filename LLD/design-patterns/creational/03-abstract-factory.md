# 03. Abstract Factory
**Category**: Creational  
**GoF**: Yes  
**Complexity**: Medium  
**Frequency in FAANG interviews**: Occasional

> Provide an interface for creating families of related or dependent objects without specifying their concrete classes.

---

## Problem It Solves

A multi-cloud platform tool provisions infrastructure resources — compute, object storage, and managed databases. For AWS it needs EC2 + S3 + RDS; for GCP it needs GCE + GCS + CloudSQL. The same provisioning workflow must work for both clouds, but the products are incompatible — an S3 bucket can't substitute for a GCS bucket in the GCP provisioning flow. Abstract Factory ensures that only *compatible families* of products are used together.

## Structure (Participants)

```
         «interface»
    CloudResourceFactory
  ┌──────────────────────────┐
  │ + createCompute()        │
  │ + createObjectStorage()  │
  │ + createDatabase()       │
  └──────────────────────────┘
             △
    ┌────────┴────────┐
    │                 │
AWSResourceFactory  GCPResourceFactory
(EC2, S3, RDS)      (GCE, GCS, CloudSQL)


«interface»   «interface»    «interface»
ComputeInstance  ObjectStorage  ManagedDatabase
    △  △            △  △            △  △
   EC2  GCE        S3   GCS        RDS  CloudSQL
```

Key participants:
- **Abstract Factory** (`CloudResourceFactory`): declares creation methods for each product type
- **Concrete Factory** (`AWSResourceFactory`, `GCPResourceFactory`): creates a family of compatible products
- **Abstract Product** (`ComputeInstance`, `ObjectStorage`, `ManagedDatabase`): interfaces for each product type
- **Concrete Product** (`EC2Instance`, `S3Bucket`, `RDSInstance`, etc.): specific implementations per cloud
- **Client** (`InfrastructureProvisioner`): uses only abstract factory and product interfaces

---

## Real-World Use Case: Cloud Infrastructure Provisioning

A platform engineering tool provisions a standard "production stack" (compute + storage + database) for any team. The cloud provider is determined by the team's cloud account config. The provisioning logic is identical — only the concrete resources differ.

### The Design

`InfrastructureProvisioner` takes a `CloudResourceFactory` and calls `createCompute()`, `createObjectStorage()`, `createDatabase()`. At startup, `CloudResourceFactoryProvider` reads the team's config (`cloud: aws` or `cloud: gcp`) and returns the appropriate factory. The provisioner never imports any AWS or GCP SDK — it only depends on the abstract interfaces.

### Implementation

```java
// Abstract Products
public interface ComputeInstance {
    void launch(ComputeConfig config);
    void terminate();
    String getInstanceId();
    String getPublicIp();
}

public interface ObjectStorage {
    void createBucket(String name, StorageClass storageClass);
    void upload(String bucket, String key, byte[] data);
    byte[] download(String bucket, String key);
}

public interface ManagedDatabase {
    void provision(DatabaseConfig config);
    String getConnectionString();
    void createSnapshot(String snapshotId);
}

// Concrete Products — AWS family
public class EC2Instance implements ComputeInstance {
    private final AmazonEC2 ec2Client;
    public EC2Instance() { this.ec2Client = AmazonEC2ClientBuilder.defaultClient(); }

    @Override
    public void launch(ComputeConfig config) {
        RunInstancesRequest req = new RunInstancesRequest()
            .withImageId(config.amiId())
            .withInstanceType(config.instanceType())
            .withMinCount(1).withMaxCount(1);
        ec2Client.runInstances(req);
    }
    // terminate, getInstanceId, getPublicIp...
}

public class S3Bucket implements ObjectStorage { /* ... */ }
public class RDSInstance implements ManagedDatabase { /* ... */ }

// Concrete Products — GCP family
public class GCEInstance implements ComputeInstance { /* ... GCP Compute Engine ... */ }
public class GCSBucket implements ObjectStorage { /* ... GCP Cloud Storage ... */ }
public class CloudSQLInstance implements ManagedDatabase { /* ... GCP CloudSQL ... */ }

// Abstract Factory
public interface CloudResourceFactory {
    ComputeInstance createCompute();
    ObjectStorage createObjectStorage();
    ManagedDatabase createDatabase();
}

// Concrete Factories
public class AWSResourceFactory implements CloudResourceFactory {
    @Override public ComputeInstance createCompute()       { return new EC2Instance(); }
    @Override public ObjectStorage createObjectStorage()   { return new S3Bucket(); }
    @Override public ManagedDatabase createDatabase()      { return new RDSInstance(); }
}

public class GCPResourceFactory implements CloudResourceFactory {
    @Override public ComputeInstance createCompute()       { return new GCEInstance(); }
    @Override public ObjectStorage createObjectStorage()   { return new GCSBucket(); }
    @Override public ManagedDatabase createDatabase()      { return new CloudSQLInstance(); }
}

// Factory provider — selects family from config
public class CloudResourceFactoryProvider {
    public static CloudResourceFactory forCloud(String cloud) {
        return switch (cloud) {
            case "aws" -> new AWSResourceFactory();
            case "gcp" -> new GCPResourceFactory();
            default    -> throw new IllegalArgumentException("Unsupported cloud: " + cloud);
        };
    }
}

// Client — knows only abstract interfaces
public class InfrastructureProvisioner {
    private final CloudResourceFactory factory;

    public InfrastructureProvisioner(CloudResourceFactory factory) {
        this.factory = factory;
    }

    public ProductionStack provisionStack(TeamConfig team) {
        ComputeInstance compute = factory.createCompute();
        compute.launch(team.computeConfig());

        ObjectStorage storage = factory.createObjectStorage();
        storage.createBucket(team.bucketName(), StorageClass.STANDARD);

        ManagedDatabase db = factory.createDatabase();
        db.provision(team.dbConfig());

        return new ProductionStack(compute, storage, db);
    }
}

// Bootstrap
CloudResourceFactory factory = CloudResourceFactoryProvider.forCloud(team.cloud()); // "aws" or "gcp"
InfrastructureProvisioner provisioner = new InfrastructureProvisioner(factory);
ProductionStack stack = provisioner.provisionStack(team);
```

### How It Works (walkthrough)

1. Team "Alpha" has `cloud: aws` in their config
2. `CloudResourceFactoryProvider.forCloud("aws")` returns `AWSResourceFactory`
3. `InfrastructureProvisioner` receives the factory — never imports AWS SDK directly
4. `provisionStack()` calls `factory.createCompute()` → `EC2Instance`, `.createObjectStorage()` → `S3Bucket`, `.createDatabase()` → `RDSInstance`
5. Adding Azure: implement `AzureComputeInstance`, `AzureBlobStorage`, `AzureSQLDatabase`, `AzureResourceFactory`, register `"azure"` → provisioner unchanged

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | Each factory creates one cloud family; provisioner just orchestrates |
| Open/Closed | ✅ | Add Azure by adding new classes and factory — no existing code changes |
| Liskov Substitution | ✅ | `AWSResourceFactory` and `GCPResourceFactory` are fully substitutable; all products implement the same interface |
| Interface Segregation | ✅ | `ComputeInstance`, `ObjectStorage`, `ManagedDatabase` are separate, focused interfaces |
| Dependency Inversion | ✅ | `InfrastructureProvisioner` depends on abstract factory and product interfaces, not on concrete cloud SDKs |

---

## When to Use

- You need to create families of related objects that must be used together (cloud resource families, UI theme families — buttons + dialogs + inputs)
- You want to swap the entire family at once based on config or environment (AWS ↔ GCP, dark theme ↔ light theme, test doubles ↔ production)
- You want to enforce that incompatible products are never mixed (GCE compute + S3 storage — wrong family)

## When NOT to Use

- Only one product type is being created — use Factory Method instead
- Products don't naturally form "families" — over-engineering adds complexity without benefit
- The family is unlikely to change — direct construction is simpler

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Ensures product compatibility — only compatible families assembled | Adding a new product type (e.g., CDN) requires changing the abstract factory interface AND all concrete factories |
| Client code is completely decoupled from concrete products | More classes — one interface + N implementations per product type |
| Easy to swap entire family from config | Harder to mix and match (e.g., AWS compute + GCP storage) if legitimately needed |

---

**FAANG interview application**: "Abstract Factory fits when you have *families* of related objects that must be created together. For a multi-cloud provisioning tool, the factory interface defines what resources exist (compute, storage, database) and each cloud factory (AWSResourceFactory, GCPResourceFactory) provides the compatible concrete implementations. The provisioner is a pure client — it only imports the abstract interfaces, not any cloud SDK. This makes unit testing trivial: inject a `FakeCloudResourceFactory` that returns in-memory stubs."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Factory Method](02-factory-method.md) | Abstract Factory is often implemented using Factory Methods per product type |
| [Singleton](01-singleton.md) | Concrete factories are usually Singletons |
| [Prototype](05-prototype.md) | Concrete factory can use Prototype to clone products instead of creating new ones |
| [Builder](04-builder.md) | Builder focuses on constructing one complex object step-by-step; Abstract Factory creates a family of objects in one call |
