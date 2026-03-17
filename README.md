# apex-http-callout

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Salesforce API](https://img.shields.io/badge/Salesforce%20API-v66.0-blue)](https://developer.salesforce.com)
[![Unlocked Package](https://img.shields.io/badge/Unlocked%20Package-v1.0.0-green)](https://login.salesforce.com/packaging/installPackage.apexp?p0=04tWU000000QEfFYAW)

A fluent, composable HTTP callout library for Salesforce Apex.

Enforces correct request construction **at compile time** via a stepped builder, and lets you attach cross-cutting concerns (auth, logging, retry, circuit breaking) through a clean middleware pipeline.

---

## Table of contents

- [Installation](#installation)
- [Quick start](#quick-start)
- [Compile-time body safety](#compile-time-body-safety)
- [Builder API](#builder-api)
- [HttpCalloutResult](#httpcalloutresult)
- [Middleware](#middleware)
  - [How middleware works](#how-middleware-works)
  - [BearerTokenMiddleware](#beartokenmiddleware)
  - [ApiKeyMiddleware](#apikeymiddleware)
  - [LoggingMiddleware](#loggingmiddleware)
  - [RetryMiddleware](#retrymiddleware)
  - [CircuitBreakerMiddleware](#circuitbreakermiddleware)
- [Response handlers](#response-handlers)
  - [JsonResponseHandler](#jsonresponsehandler)
- [Custom middleware](#custom-middleware-example)
- [Custom logger](#custom-logger-example)
- [Full pipeline example](#full-pipeline-example)
- [Async usage — Queueable and Finalizer](#async-usage--queueable-and-finalizer)
- [Named Credentials](#named-credentials)
- [Manual testing](#manual-testing)
- [File structure](#file-structure)
- [Design patterns](#design-patterns)
- [Contributing](#contributing)
- [License](#license)

---

## Installation

### Option 1 — Unlocked Package (recommended)

Install the latest version with a single command:

```bash
sf package install \
  --package 04tWU000000QEfFYAW \
  --target-org <your-org-alias> \
  --wait 10
```

Or use the browser install link:
[https://login.salesforce.com/packaging/installPackage.apexp?p0=04tWU000000QEfFYAW](https://login.salesforce.com/packaging/installPackage.apexp?p0=04tWU000000QEfFYAW)

| Version | Package ID | API |
|---------|-----------|-----|
| v1.0.0 | `04tWU000000QEfFYAW` | 66.0 |

### Option 2 — Manual deploy

Clone this repo and deploy the classes directly to your org:

```bash
sf project deploy start \
  --source-dir force-app/main/default/classes \
  --target-org <your-org-alias>
```

For a sandbox with no test run:

```bash
sf project deploy start \
  --source-dir force-app/main/default/classes \
  --target-org <your-org-alias> \
  --test-level NoTestRun
```

---

## Quick start

```apex
// Simple GET
HttpCalloutResult result = HttpCallout.builder()
    .endpoint('https://api.example.com/accounts/1')
    .get()
    .build()
    .execute();

if (result.isSuccess()) {
    System.debug(result.body);
}
```

```apex
// POST with JSON body — shortcut form (body + Content-Type set in one step)
HttpCalloutResult result = HttpCallout.builder()
    .endpoint('https://api.example.com/orders')
    .post(new Map<String, Object>{ 'ref' => 'ORD-001', 'amount' => 99 })
    .build()
    .execute();
```

```apex
// POST two-step form — compile-time enforced body
HttpCalloutResult result = HttpCallout.builder()
    .endpoint('https://api.example.com/orders')
    .post()                                                          // → IBodyRequiredStep (no build() yet)
    .bodyJson(new Map<String, Object>{ 'ref' => 'ORD-001' })        // → IBuildStep
    .timeout(15000)
    .build()
    .execute();
```

---

## Compile-time body safety

The return type of each HTTP verb controls what methods are available next. Wrong usage is a **compile error**, not a runtime exception.

| Verb | Returns | `body()` | `build()` |
|---|---|---|---|
| `get()` | `IBuildStep` | not available | available |
| `head()` | `IBuildStep` | not available | available |
| `delete_x()` | `IOptionalBodyStep` | optional | available |
| `post()` | `IBodyRequiredStep` | required | **not available** until body is set |
| `put()` | `IBodyRequiredStep` | required | **not available** until body is set |
| `patch()` | `IBodyRequiredStep` | required | **not available** until body is set |

```apex
// Compile error — POST without body
HttpCallout.builder().endpoint('/api').post().build(); // build() does not exist on IBodyRequiredStep

// Compile error — GET with body
HttpCallout.builder().endpoint('/api').get().bodyJson(data); // bodyJson() does not exist on IBuildStep
```

This is enforced by the **Stepped Builder** pattern: each method returns a different interface type, so the Apex compiler itself rejects invalid combinations before your code ever runs.

---

## Builder API

```apex
HttpCallout.builder()
    .endpoint(String url)           // required — full URL or callout:NamedCredential/path

    // HTTP verbs
    .get()                          // → IBuildStep
    .head()                         // → IBuildStep
    .delete_x()                     // → IOptionalBodyStep (body optional)
    .post()                         // → IBodyRequiredStep (body required before build)
    .put()                          // → IBodyRequiredStep
    .patch()                        // → IBodyRequiredStep
    .post(Object jsonBody)          // shortcut: serializes body + sets Content-Type → IBuildStep
    .put(Object jsonBody)
    .patch(Object jsonBody)

    // Body (available on IBodyRequiredStep and IOptionalBodyStep)
    .body(String rawBody)           // raw string body
    .bodyJson(Object obj)           // JSON.serialize(obj) + sets Content-Type: application/json

    // Options (available on IBuildStep)
    .timeout(Integer ms)            // default: 30 000 ms
    .header(String key, String val) // add a custom request header
    .contentTypeJson()              // shortcut to set Content-Type: application/json
    .use(IHttpMiddleware middleware) // attach middleware — executed in registration order
    .handleResponseWith(IResponseHandler handler)

    .build()                        // returns a configured HttpCallout instance
    .execute()                      // fires the HTTP request, returns HttpCalloutResult
```

---

## HttpCalloutResult

`HttpCalloutResult` is an immutable wrapper around the HTTP response. It is always returned by `execute()`, regardless of the status code — no exceptions are thrown for 4xx or 5xx responses.

```apex
result.statusCode       // Integer — HTTP status code (e.g. 200, 404, 500)
result.body             // String  — raw response body
result.data             // Object  — populated by IResponseHandler (null if none registered)
result.parseError       // String  — set if JSON deserialization failed, null otherwise
result.errorCode        // String  — application-level error code from a response handler
result.errorMessage     // String  — application-level error message from a response handler

result.isSuccess()      // true for 2xx
result.isClientError()  // true for 4xx
result.isServerError()  // true for 5xx
```

### `getDataAs(Type)`

Safely casts the deserialized `data` to a typed Apex class:

```apex
OrderResponse order = (OrderResponse) result.getDataAs(OrderResponse.class);
```

> **Why not a generic method?** Apex does not support generic methods (`getDataAs<T>()`). `getDataAs(Type)` works around this by round-tripping through `JSON.serialize` / `JSON.deserialize`, which safely coerces any `Object` to the target type — including complex nested classes.

---

## Middleware

### How middleware works

Middleware implements `IHttpMiddleware` and wraps the HTTP call. Each middleware receives the request, can inspect or modify it, then calls `next.handle()` to pass control to the next middleware in the chain. The last middleware in the chain calls the actual HTTP endpoint.

```apex
public interface IHttpMiddleware {
    HttpResponse handle(HttpRequest req, IHttpMiddleware next);
}
```

Middleware is executed in **registration order** — the first `.use()` call is the outermost wrapper:

```
request ──► CircuitBreaker ──► BearerToken ──► Retry ──► Logging ──► HTTP call
response ◄── CircuitBreaker ◄── BearerToken ◄── Retry ◄── Logging ◄── HTTP call
```

This means:
- **CircuitBreaker** should be first — it needs to see every failure including retries
- **Logging** should be last — it logs the actual individual callout, not the retry group
- **Auth** (Bearer, ApiKey) should be before Retry so the token is re-attached on each attempt

---

### `BearerTokenMiddleware`

Adds an `Authorization: Bearer <token>` header on every request (RFC 6750). Used for OAuth 2.0 and JWT-authenticated APIs.

```apex
.use(new BearerTokenMiddleware('eyJhbGci...'))
```

```apex
// Fetch token dynamically (e.g. from a Custom Setting or Named Credential)
String token = MyTokenService.getAccessToken();
.use(new BearerTokenMiddleware(token))
```

> Throws `HttpCalloutException` at construction time if the token is blank — fails fast before any HTTP call is made.

---

### `ApiKeyMiddleware`

Adds an API key to the request either as a **header** or a **query parameter**.

```apex
.use(new ApiKeyMiddleware('my-secret-key'))                      // header: x-api-key (default)
.use(new ApiKeyMiddleware('my-secret-key', 'X-Api-Key'))         // header: custom name
.use(ApiKeyMiddleware.asQueryParam('my-secret-key', 'api_key'))  // ?api_key=my-secret-key
```

When using query param mode, the key and value are **URL-encoded** automatically. If the endpoint already contains a `?`, an `&` separator is used instead.

> Throws `HttpCalloutException` at construction time if the key or header/param name is blank.

---

### `LoggingMiddleware`

Logs each HTTP request and response, including method, endpoint, status code, and duration. Uses `IHttpLogger` for output — defaults to `SystemDebugLogger` which wraps `System.debug`.

```apex
.use(new LoggingMiddleware())                   // default System.debug output
.use(new LoggingMiddleware(myCustomLogger))     // inject Nebula Logger or any IHttpLogger
```

**What gets logged:**

| Event | Level | Fields |
|-------|-------|--------|
| Request sent | `INFO` | `requestId`, `method`, `endpoint`, `hasBody` |
| Response received | `INFO` | `requestId`, `statusCode`, `durationMs` |
| Exception thrown | `ERROR` | `requestId`, `error`, `durationMs` |

Each request gets a unique `requestId` (`REQ-<timestamp>`) so you can correlate the request and response log lines.

---

### `RetryMiddleware`

Automatically retries failed requests with exponential backoff **within a single request**.

```apex
.use(new RetryMiddleware(3))                                     // 3 retries = 4 total attempts
.use(new RetryMiddleware(2, new Set<Integer>{ 503, 504 }))       // custom retryable codes
```

**Default retryable status codes:** `408, 429, 500, 502, 503, 504`

**Retry count** is the number of *additional* attempts after the first call — `new RetryMiddleware(3)` means up to **4 total attempts**. You can pass any integer.

```
caller ──► RetryMiddleware ──► attempt 1 → 503
                           ──► attempt 2 → 503
                           ──► attempt 3 → 200 ✓ ──► caller gets 200
```

**Backoff schedule:**

| Attempt | Target delay |
|---------|-------------|
| After attempt 0 | ~100ms |
| After attempt 1 | ~200ms |
| After attempt 2 | ~400ms |
| After attempt 3+ | ~500ms (cap) |

**What triggers a retry:**
- `CalloutException` (network timeout, unreachable host)
- Any retryable HTTP status code (configurable)

**What does NOT trigger a retry:**
- `4xx` responses — those indicate a client-side error, retrying won't help

> **Apex limitation:** True async sleep is not available in synchronous Apex. Backoff is simulated with a CPU busy-wait capped at ~500ms to respect governor limits. For real delays between retries (e.g. waiting 30 seconds), use **Queueable Apex** with a chained job.

---

### `CircuitBreakerMiddleware`

Protects your org from hammering a failing external API **across multiple requests**. Instead of making every callout and waiting for each one to timeout, it **fails fast** after a failure threshold is reached, then probes for recovery automatically.

```apex
.use(new CircuitBreakerMiddleware('PaymentAPI'))           // 5 failures, 60s recovery (defaults)
.use(new CircuitBreakerMiddleware('PaymentAPI', 3, 30))    // 3 failures, 30s recovery
```

**The mechanism**

The circuit breaker is completely passive — it has no background thread, no scheduler, no timer. It only runs when your Apex code calls `.execute()`. It stores just 3 fields:

```apex
private Integer  failureCount     // consecutive failures so far
private Datetime lastFailureTime  // when the last failure occurred
private String   status           // 'CLOSED', 'OPEN', or 'HALF_OPEN'
```

Every `.execute()` call in your transaction is a separate request the circuit breaker evaluates independently. In a single Apex transaction you can make up to 100 callouts (Salesforce governor limit), so a loop calling the same API multiple times will hit the circuit breaker multiple times:

```apex
for (Order o : orders) {
    HttpCallout.builder()
        .endpoint('https://api.example.com/orders/' + o.Id)
        .get()
        .use(new CircuitBreakerMiddleware('OrderAPI', 3, 60))
        .build()
        .execute();  // each iteration = one request evaluated by the circuit breaker
}
```

```
iteration 1 → .execute() → 500  (failure 1/3)
iteration 2 → .execute() → 500  (failure 2/3)
iteration 3 → .execute() → 500  (failure 3/3 → OPEN)
iteration 4 → .execute() → throws immediately, no callout made
iteration 5 → .execute() → throws immediately, no callout made
```

**The three states:**

```
          failures >= threshold           next .execute() arrives
CLOSED ──────────────────────────► OPEN  AND recovery timeout elapsed ──► HALF_OPEN
  ▲                                                                              │
  │  success                                    failure                          │
  └──────────────────────────────────────────────────────────────────────────────┘
```

| State | Behaviour |
|-------|-----------|
| **CLOSED** | Normal operation. Every `.execute()` goes through. Failures are counted. |
| **OPEN** | Every `.execute()` throws immediately — no callout is made. |
| **HALF_OPEN** | The next `.execute()` after the recovery timeout is allowed through as a probe. Success → CLOSED. Failure → OPEN. |

**How HALF_OPEN works:**

There is no timer, no ping, no automatic retry. HALF_OPEN is triggered by the next `.execute()` call your code makes after `recoveryTimeoutSeconds` has elapsed. The circuit breaker does not create a new request — it simply allows *your* request to pass through unchanged (same endpoint, same body, same headers). If the service has recovered, it succeeds and the circuit resets. If not, it fails and the circuit reopens.

```
.execute() arrives → circuit OPEN → has recoveryTimeout elapsed?
                                            │
                                    NO  → throws immediately
                                    YES → status = HALF_OPEN → your callout is made
                                                                       │
                                                               success → CLOSED
                                                               failure → OPEN (clock resets)
```

> The probe is always the next real request your code makes — that caller may still receive a failed or slow response during HALF_OPEN.

**`failureThreshold` is NOT the same as retry count.** It counts consecutive *separate requests* that failed, not attempts within one request:

| | `RetryMiddleware(3)` | `CircuitBreakerMiddleware('API', 3, 30)` |
|---|---|---|
| What does `3` count? | Retries within **one request** | Failed **separate requests** over time |
| Resets after? | Each new request starts fresh | Only after a successful response |
| Scope | One call | Across all calls in the transaction |

**What trips the circuit (counts as a failure):**
- Any `5xx` HTTP response
- Any `CalloutException` (network error, timeout)

**What does NOT trip the circuit:**
- `4xx` responses — those are client-side errors, the downstream service is healthy

**Multiple services** are tracked independently by `serviceName`:
```apex
.use(new CircuitBreakerMiddleware('PaymentAPI'))
.use(new CircuitBreakerMiddleware('ShippingAPI'))  // separate counter and state
```

**Used together with RetryMiddleware:**

```apex
.use(new CircuitBreakerMiddleware('OrderAPI', 3, 30))  // outer — sees each request as a whole
.use(new RetryMiddleware(2))                           // inner — retries within each request
```

```
Request 1 → retry 1 fail, retry 2 fail, retry 3 fail → 503  (CB failure count: 1/3)
Request 2 → retry 1 fail, retry 2 fail, retry 3 fail → 503  (CB failure count: 2/3)
Request 3 → retry 1 fail, retry 2 fail, retry 3 fail → 503  (CB failure count: 3/3 → OPEN)
Request 4 → CircuitBreaker throws immediately — no callout made
```

Retry handles short transient blips. CircuitBreaker trips when the service is genuinely down across multiple callers.

> **State scope:** Circuit state is stored in a static `Map` scoped to the current Apex transaction. It does **not** persist between separate transactions, batch job rows, or async contexts. For persistent circuit state across transactions, back it with **Platform Cache** or a **Custom Object**.

---

## Response handlers

Response handlers implement `IResponseHandler` and are registered with `.handleResponseWith()`. They replace the default `HttpCalloutResult` construction logic, letting you control how the response is parsed.

```apex
public interface IResponseHandler {
    HttpCalloutResult handle(HttpResponse res);
}
```

---

### `JsonResponseHandler`

Deserializes the response body into a typed Apex class. Only runs deserialization on `2xx` responses with a non-blank body.

```apex
HttpCalloutResult result = HttpCallout.builder()
    .endpoint('https://api.example.com/products/1')
    .get()
    .handleResponseWith(new JsonResponseHandler(Product.class))
    .build()
    .execute();

if (result.isSuccess()) {
    Product p = (Product) result.getDataAs(Product.class);
}
```

**Error handling behaviour:**

| Scenario | `result.isSuccess()` | `result.data` | `result.parseError` |
|----------|---------------------|---------------|---------------------|
| 2xx + valid JSON | `true` | populated | `null` |
| 2xx + invalid JSON | `true` | `null` | error message |
| 4xx / 5xx | `false` | `null` | `null` |

The HTTP call result and the parse result are kept separate — a JSON parse failure does not change `isSuccess()`, because the HTTP call itself succeeded.

---

## Custom middleware example

```apex
public class RequestIdMiddleware implements IHttpMiddleware {
    public HttpResponse handle(HttpRequest req, IHttpMiddleware next) {
        req.setHeader('X-Request-Id', 'APEX-' + Datetime.now().getTime());
        return next.handle(req, null);
    }
}

HttpCallout.builder()
    .endpoint('https://api.example.com/items')
    .get()
    .use(new RequestIdMiddleware())
    .use(new LoggingMiddleware())
    .build()
    .execute();
```

---

## Custom logger example

Implement `IHttpLogger` to integrate with any logging framework (e.g. [Nebula Logger](https://github.com/jongpie/NebulaLogger)):

```apex
public class MyLogger implements IHttpLogger {
    public void debug(String msg, Map<String, Object> ctx) { /* your impl */ }
    public void info(String msg, Map<String, Object> ctx)  { /* your impl */ }
    public void warn(String msg, Map<String, Object> ctx)  { /* your impl */ }
    public void error(String msg, Map<String, Object> ctx) { /* your impl */ }
}

.use(new LoggingMiddleware(new MyLogger()))
```

---

## Full pipeline example

```apex
HttpCalloutResult result = HttpCallout.builder()
    .endpoint('https://api.example.com/orders')
    .post()
    .bodyJson(new Map<String, Object>{ 'ref' => 'ORD-001' })
    .timeout(20000)
    .use(new CircuitBreakerMiddleware('OrderAPI', 3, 30))   // outermost — sees all failures
    .use(new BearerTokenMiddleware(accessToken))            // auth injected before each attempt
    .use(new RetryMiddleware(3))                            // retries 5xx and network errors
    .use(new LoggingMiddleware())                           // innermost — logs each individual call
    .handleResponseWith(new JsonResponseHandler(OrderResponse.class))
    .build()
    .execute();

if (result.isSuccess()) {
    OrderResponse order = (OrderResponse) result.getDataAs(OrderResponse.class);
} else if (result.isServerError()) {
    System.debug('Server error: ' + result.statusCode);
}
```

---

## Async usage — Queueable and Finalizer

The library works in asynchronous Apex contexts. The class implementing `Queueable` must also implement `Database.AllowsCallouts` — this interface is required by Salesforce for any callout made from an async job.

### Queueable — fire and forget

Offloads the callout from the main transaction. The caller does not wait for the HTTP response.

```apex
public class HttpCalloutJob implements Queueable, Database.AllowsCallouts {

    private final String endpoint;
    private final Map<String, Object> body;

    public HttpCalloutJob(String endpoint, Map<String, Object> body) {
        this.endpoint = endpoint;
        this.body     = body;
    }

    public void execute(QueueableContext ctx) {
        HttpCalloutResult result = HttpCallout.builder()
            .endpoint(endpoint)
            .post(body)
            .use(new CircuitBreakerMiddleware('OrderAPI', 3, 60))
            .use(new RetryMiddleware(2))
            .use(new LoggingMiddleware())
            .build()
            .execute();

        if (!result.isSuccess()) {
            // handle failure
        }
    }
}

// enqueue from anywhere in your code
System.enqueueJob(new HttpCalloutJob('https://api.example.com/orders', payload));
```

**What you gain:**
- Main transaction does not wait for the callout to complete
- Separate governor limits from the calling transaction
- Can chain jobs for real retry delays (not CPU busy-wait)

### Chained Queueable — real retry delay

Replaces `RetryMiddleware`'s CPU busy-wait with actual time between attempts. Each chained job runs in a separate transaction, giving a genuine delay:

```apex
public class HttpCalloutWithRetryJob implements Queueable, Database.AllowsCallouts {

    private final String  endpoint;
    private final Integer attemptsLeft;

    public HttpCalloutWithRetryJob(String endpoint, Integer attemptsLeft) {
        this.endpoint     = endpoint;
        this.attemptsLeft = attemptsLeft;
    }

    public void execute(QueueableContext ctx) {
        HttpCalloutResult result = HttpCallout.builder()
            .endpoint(endpoint)
            .get()
            .build()
            .execute();

        if (!result.isSuccess() && attemptsLeft > 0) {
            // enqueue next attempt — runs in a new transaction after Salesforce schedules it
            System.enqueueJob(new HttpCalloutWithRetryJob(endpoint, attemptsLeft - 1));
        }
    }
}

System.enqueueJob(new HttpCalloutWithRetryJob('https://api.example.com/orders', 3));
```

### Finalizer — handle job failure

A `Finalizer` runs after the Queueable job completes regardless of outcome — success, unhandled exception, or governor limit breach. Finalizers **cannot make callouts** themselves, but can enqueue a new job:

```apex
public class HttpCalloutFinalizer implements Finalizer {

    private final String endpoint;

    public HttpCalloutFinalizer(String endpoint) {
        this.endpoint = endpoint;
    }

    public void execute(FinalizerContext ctx) {
        if (ctx.getResult() == ParentJobResult.UNHANDLED_EXCEPTION) {
            System.debug('Job failed: ' + ctx.getException().getMessage());
            System.enqueueJob(new HttpCalloutJob(endpoint, null));  // re-enqueue for retry
        }
    }
}

public class HttpCalloutJob implements Queueable, Database.AllowsCallouts {
    public void execute(QueueableContext ctx) {
        System.attachFinalizer(new HttpCalloutFinalizer('https://api.example.com/orders'));

        HttpCallout.builder()
            .endpoint('https://api.example.com/orders')
            .get()
            .use(new CircuitBreakerMiddleware('OrderAPI', 3, 60))
            .build()
            .execute();
    }
}
```

**Comparison:**

| | Queueable | Chained Queueable | Finalizer |
|---|---|---|---|
| Make callouts | Yes | Yes | **No** |
| Real retry delay | No | Yes | No — but can enqueue |
| Handles unhandled exceptions | No | No | **Yes** |

> **Circuit breaker in async:** each Queueable job runs in a separate transaction, so circuit breaker state resets between jobs. For persistent state across async jobs, back it with **Platform Cache** or a **Custom Object**.

---

## Named Credentials

The library works with [Named Credentials](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_callouts_named_credentials.htm) out of the box. Use the `callout:` prefix as the endpoint — Salesforce resolves the base URL and injects authentication automatically.

```apex
HttpCalloutResult result = HttpCallout.builder()
    .endpoint('callout:MyNamedCredential/api/v1/accounts')
    .get()
    .build()
    .execute();
```

**Benefits of Named Credentials:**
- No Remote Site Setting required
- Authentication (Basic, OAuth 2.0, JWT Bearer) handled by Salesforce — credentials never in code
- Works with per-user and org-wide authentication modes

> If your Named Credential already handles authentication, do **not** also attach `BearerTokenMiddleware` or `ApiKeyMiddleware` — they would conflict and overwrite Salesforce's injected auth header.

---

## Manual testing

An anonymous Apex script is provided at `scripts/apex/testHttpCallout.apex`. It runs 15 tests against [JSONPlaceholder](https://jsonplaceholder.typicode.com) covering all HTTP verbs, all built-in middleware, response deserialization, and custom middleware.

**Prerequisite — add a Remote Site Setting:**
> Setup → Remote Site Settings → New
> - Name: `JsonPlaceholder`
> - URL: `https://jsonplaceholder.typicode.com`

Run via CLI:
```bash
sf apex run --file scripts/apex/testHttpCallout.apex --target-org <your-org-alias>
```

Or paste the file contents into **Developer Console → Debug → Open Execute Anonymous Window**.

---

## File structure

```
force-app/main/default/classes/
├── HttpCallout.cls                  # Core builder + execution engine
├── HttpCalloutResult.cls            # Immutable response wrapper
├── IHttpMiddleware.cls              # Middleware interface
├── IResponseHandler.cls             # Response handler interface
├── IHttpLogger.cls                  # Logger abstraction
├── SystemDebugLogger.cls            # Default logger (System.debug)
├── LoggingMiddleware.cls            # Request/response logging
├── RetryMiddleware.cls              # Retry with exponential backoff
├── CircuitBreakerMiddleware.cls     # Circuit breaker (CLOSED/OPEN/HALF_OPEN)
├── ApiKeyMiddleware.cls             # API key auth (header or query param)
├── BearerTokenMiddleware.cls        # Bearer token auth (RFC 6750)
├── JsonResponseHandler.cls          # JSON deserialization handler
└── HttpCalloutMockFactory.cls       # Test utilities (@IsTest)
```

---

## Design patterns

| Pattern | Where | Purpose |
|---|---|---|
| **Stepped Builder** | `HttpCallout.builder()` | Compile-time body-rule enforcement via interface return types |
| **Decorator** | `IHttpMiddleware` | Middleware chained and executed in order around the HTTP call |
| **Strategy** | `IResponseHandler` | Decoupled, swappable response processing logic |

---

## Contributing

Contributions are welcome. Please open an issue to discuss your change before submitting a pull request.

1. Fork the repository
2. Create your feature branch: `git checkout -b feature/my-feature`
3. Commit your changes: `git commit -m 'Add my feature'`
4. Push to the branch: `git push origin feature/my-feature`
5. Open a pull request

---

## License

[MIT](LICENSE)
