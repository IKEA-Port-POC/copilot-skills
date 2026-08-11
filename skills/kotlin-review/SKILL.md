---
name: kotlin-review
description: Use when reviewing Kotlin PRs, after writing significant Kotlin code, or when asked to review Kotlin files. Checks correctness, style, and architectural compliance.
---

# Kotlin Code Review

Review Kotlin source files, Gradle build configs, and Flyway migrations against
team conventions and official Kotlin best practices. This skill should be loaded
both when explicitly asked to review Kotlin code and proactively after writing
significant Kotlin code.

## Bootstrap

No setup required. The agent must have read access to the Kotlin source files
under review. Before starting:

1. Identify which service or module the code belongs to.
2. Read the project's `AGENTS.md` and `.editorconfig` if you have not already.
3. Check the project's `build.gradle.kts` to understand toolchain version, linting, and coverage settings.

---

## Workflow

Follow these steps for every review. Do NOT skip any step.

### 1. Identify changed files

Determine which files are under review -- from a PR diff, staged changes, or
files the agent just wrote. Categorize each file:

| Category | File patterns |
|----------|---------------|
| Production source | `src/main/kotlin/**/*.kt` |
| Unit test | `src/test/kotlin/**/*Test.kt` |
| Integration test | `src/integrationTest/kotlin/**/*Test.kt` |
| Gradle build config | `build.gradle.kts`, `settings.gradle.kts` |
| Flyway migration | `src/main/resources/db/migration/*.sql` |
| Application config | `src/main/resources/application*.yaml` |
| Generated code | `build/generated/**` -- **skip entirely** |

### 2. Run the formatting and lint checklist

For each production and test Kotlin file, verify:

- [ ] **No star imports** -- every import is explicit
- [ ] **Trailing commas** on all multi-line parameter lists, argument lists, and collection literals
- [ ] **Max line length** -- respect the project's `.editorconfig` setting (typically 140 chars for production, unlimited for tests)
- [ ] **No tabs** -- indentation uses 4 spaces

If in doubt, suggest running:

```bash
./gradlew formatKotlin && ./gradlew lintKotlinMain
```

### 3. Review naming conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Service class | `*Service` | `OrderService` |
| Message consumer | `*Consumer` | `OrderReceivingConsumer` |
| Message publisher | `*Publisher` | `EventPublisher` |
| JPA entity | `*Entity` | `OrderEntity` |
| Spring Data repo | `*Repository` | `OrderRepository` |
| Spring configuration | `*Config` or `*Configuration` | `ObjectMapperConfig` |
| REST controller | `*Controller` | `OrderController` |
| Exception handler | `GlobalExceptionHandler` | -- |
| HTTP client | `*Client` | `InventoryClient` |
| Scheduled job | `*Job` | `RetryJob` |
| Domain value object | Plain noun, no suffix | `OrderId` |
| Test subject variable | `sut` | `private lateinit var sut: MyService` |
| Logger | `private val logger` in `companion object` | See below |
| Constants | `private const val SCREAMING_SNAKE_CASE` in `companion object` | `MAX_RETRY_COUNT` |
| MDC keys | camelCase strings via dedicated constants | `"orderId"`, `"businessUnit"` |
| Test methods | Backtick with GIVEN/WHEN/THEN | `` `GIVEN x WHEN y THEN z` `` |

Flag any deviation from these patterns.

### 4. Review language idioms

Check for these **required patterns**:

- **`val` over `var`** -- mutable state must be justified
- **Data classes** for entities, DTOs, value objects, config properties
- **`@Embeddable` data class** for composite JPA keys with `@EmbeddedId`
- **Named arguments** on all multi-parameter function calls
- **`when` expression** over `if`/`else` chains with 3+ branches
- **Extension functions** for mappers (not Mapper objects or standalone functions)
- **`requireNotNull()` / `require()`** for precondition validation -- never silent fallbacks
- **`copy()`** for immutable updates on data classes
- **Nested enums** inside entities when they logically belong there, with `companion object` factory methods using `entries.find {}` (not `valueOf()`)
- **`inline fun <reified T>`** to avoid type erasure when deserializing generics

Check for these **anti-patterns** and flag them:

| Anti-pattern | Correct alternative |
|--------------|---------------------|
| `val x = nullable ?: "UNKNOWN"` (silent fallback) | `requireNotNull(nullable) { "description" }` |
| `enum.valueOf(str)` (throws on unknown) | `entries.find { it.name.equals(str, ignoreCase = true) }` |
| Passing generated event DTO to service layer | Extract primitives in consumer, pass domain types to service |
| Auto-creating reference entities on missing data | Throw `IllegalArgumentException` -- let the message go to dead-letter for investigation |
| `KotlinLogging.logger {}` | `LoggerFactory.getLogger(this::class.java)` in `companion object` |
| Non-private logger | `private val logger: Logger` |
| `assert()` in tests | `assertThat()` from AssertJ |
| Star imports | Explicit imports only |
| Editing files under `build/generated/` | Edit the source schema (OpenAPI/AsyncAPI YAML), regenerate |
| snake_case MDC keys | camelCase via dedicated logging key constants |

### 5. Review error handling

#### Message consumer error classification

Every message consumer must classify errors into retryable vs. non-retryable:

| Exception type | Action | Rationale |
|----------------|--------|-----------|
| `MismatchedInputException` / `JsonProcessingException` | Reject → dead-letter queue | Deserialization failure -- never retryable |
| `ConstraintViolationException` | Reject → dead-letter queue | Validation failure -- never retryable |
| `IllegalArgumentException` | Reject → dead-letter queue | Invalid business data -- never retryable |
| Any other `Exception` | Requeue for retry | Transient failure -- retryable |

Verify that all consumer code paths handle errors according to this
classification. If a shared pipeline function handles this centrally, verify
that manual consumers replicate the same classification.

#### Custom exceptions

- Must extend `RuntimeException` (Kotlin has no checked exceptions)
- HTTP clients should distinguish retryable vs. non-retryable subtypes
- Use `@Retryable` / `@Recover` for external HTTP calls with appropriate backoff configuration

#### REST API errors

- Global exception handling via `@RestControllerAdvice`
- Consistent error response body with `message`, `error`, `status`, `path`, `timestamp`

### 6. Review Spring Boot patterns

- [ ] **Constructor injection only** -- no `@Autowired` on fields, no setter injection
- [ ] **Controllers contain no business logic** -- delegate entirely to services
- [ ] **Controllers implement generated OpenAPI interface** when code generation is used
- [ ] **`@Transactional` on service methods only** -- not on controllers or consumers
- [ ] **Profile-split security** -- separate `@Configuration` classes for `@Profile("!local")` and `@Profile("local")`
- [ ] **Typed `@ConfigurationProperties`** data classes for configuration
- [ ] **Observability annotations** (`@Timed`, `@WithSpan`) on consumer handler methods
- [ ] **Structured logging context** via `withMDC()` helper or equivalent -- never raw `MDC.put()` without cleanup

#### Consumer-to-service boundary

Services must accept **primitives and domain value objects**, not generated
event DTO types. The consumer is responsible for:

1. Deserializing the event
2. Extracting fields
3. Passing primitives/domain objects to the service

```kotlin
// CORRECT -- consumer extracts, service receives domain types
orderService.processOrder(
    orderId = OrderId(type = event.orderType, code = event.orderCode),
    customerName = event.customer.name,
    quantity = event.quantity,
)

// WRONG -- service coupled to generated DTO
orderService.processOrder(event)
```

### 7. Review test code

#### Unit tests

- [ ] Uses `@ExtendWith(MockKExtension::class)`
- [ ] Test subject is `sut` with `@InjectMockKs`
- [ ] Dependencies are `@MockK` with `lateinit var`
- [ ] Test method names use backtick `GIVEN/WHEN/THEN` format
- [ ] Assertions use AssertJ `assertThat()` -- not Kotlin `assert()`
- [ ] `verify(exactly = N)` for call count verification
- [ ] `slot<T>()` for argument capture when needed
- [ ] `assertThrows<ExceptionType> {}` for exception assertions
- [ ] Parameterized tests use `@ParameterizedTest` + `@MethodSource` with `@JvmStatic` companion method
- [ ] No `@Disabled`, `@Ignore`, `.skip()`, or `.only()`

#### Integration tests

- [ ] Extends a shared `AbstractIntegrationTest` base class
- [ ] Uses Testcontainers for real infrastructure (database, message broker)
- [ ] External services stubbed with WireMock (`@AutoConfigureWireMock`)
- [ ] Reference data pre-seeded via JPA repositories
- [ ] Asynchronous assertions wrapped in Awaitility (`await().atMost(10.seconds).untilAsserted {}`)
- [ ] JSON fixtures loaded from `src/test/resources/`
- [ ] Tests exercise the full consumer path -- not just the service layer in isolation

### 8. Review Gradle build configuration

When `build.gradle.kts` or `settings.gradle.kts` is modified:

- [ ] Java 21 toolchain configured
- [ ] Kotlinter configured with `ignoreLintFailures = false` and `ignoreFormatFailures = false`
- [ ] JaCoCo minimum threshold is at least `0.8` (80%) -- flag any reduction
- [ ] Generated sources excluded from linting
- [ ] Generated sources excluded from JaCoCo coverage measurement
- [ ] `compileKotlin` depends on code generation tasks (OpenAPI, AsyncAPI)
- [ ] Test JVM args include `--add-opens` for MockK on Java 21+
- [ ] `check` task depends on `installKotlinterPrePushHook`
- [ ] Integration test source set properly configured with classpath extending `testImplementation`

### 9. Review Flyway migrations

When SQL migration files are added or modified:

- [ ] **Versioned migrations** follow `V{N}__description.sql` naming
- [ ] **Undo migrations** provided: `U{N}__description.sql` matching each versioned migration
- [ ] Version number `{N}` is the next sequential number (check existing migrations)
- [ ] No destructive operations without an undo migration
- [ ] Repeatable migrations use `R__description.sql`
- [ ] No secrets or hardcoded credentials in SQL files

### 10. Summarize findings

Produce a review summary grouped by severity:

| Severity | Meaning |
|----------|---------|
| **Blocker** | Breaks build, violates error handling contract, data correctness issue |
| **Warning** | Style violation, naming inconsistency, missing test coverage |
| **Suggestion** | Improvement opportunity, idiomatic Kotlin usage, readability |

For each finding, include:
- File path and line number
- What the issue is
- Why it matters
- Suggested fix (with code if applicable)

---

## Error Handling

| Error / situation | Meaning | Action |
|-------------------|---------|--------|
| `./gradlew lintKotlinMain` fails | Code has formatting issues | Run `./gradlew formatKotlin` first, then re-lint |
| `./gradlew test` fails | Unit tests broken | Review test failures before completing the review |
| `./gradlew jacocoTestReport` below threshold | Coverage below minimum | Flag as blocker -- new code must maintain coverage threshold |
| File is under `build/generated/` | Generated code | Skip entirely -- do not review or modify |
