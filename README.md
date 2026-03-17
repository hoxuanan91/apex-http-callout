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
- [Response handlers](#response-handlers)
- [Custom middleware](#custom-middleware-example)
- [Custom logger](#custom-logger-example)
- [Full pipeline example](#full-pipeline-example)
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
// POST with JSON body (shortcut — body + Content-Type set automatically)
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
    .post()                                          // → IBodyRequiredStep (no build() yet)
    .bodyJson(new Map<String, Object>{ 'ref' => 'ORD-001' })  // → IBuildStep
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
HttpCallout.builder().endpoint('/api').post().build(); // build() not on IBodyRequiredStep

// Compile error — GET with body
HttpCallout.builder().endpoint('/api').get().bodyJson(data); // bodyJson() not on IBuildStep
```

---

## Builder API

```apex
HttpCallout.builder()
    .endpoint(String url)           // required — full URL or callout:NamedCredential/path

    // HTTP verbs
    .get()
    .head()
    .delete_x()
    .post()                         // body required separately → IBodyRequiredStep
    .put()
    .patch()
    .post(Object jsonBody)          // shortcut: serializes body + sets Content-Type → IBuildStep
    .put(Object jsonBody)
    .patch(Object jsonBody)

    // Body (on IBodyRequiredStep / IOptionalBodyStep)
    .body(String rawBody)
    .bodyJson(Object obj)           // JSON.serialize + sets Content-Type → IBuildStep

    // Options (on IBuildStep)
    .timeout(Integer ms)            // default: 30 000 ms
    .header(String key, String val)
    .contentTypeJson()
    .use(IHttpMiddleware middleware) // attach middleware in order
    .handleResponseWith(IResponseHandler handler)

    .build()                        // returns HttpCallout instance
    .execute()                      // sends the request, returns HttpCalloutResult
```

---

## HttpCalloutResult

```apex
result.statusCode       // Integer — HTTP status code
result.body             // String  — raw response body
result.data             // Object  — populated by IResponseHandler (null if none)
result.parseError       // String  — set if deserialization failed, null otherwise
result.errorCode        // String  — from response handler
result.errorMessage     // String  — from response handler

result.isSuccess()      // true for 2xx
result.isClientError()  // true for 4xx
result.isServerError()  // true for 5xx

result.getDataAs(MyClass.class)  // safely cast data to a typed Apex class
```

---

## Middleware

Middleware implements `IHttpMiddleware` and is executed in the order it is registered with `.use()`.

```apex
public interface IHttpMiddleware {
    HttpResponse handle(HttpRequest req, IHttpMiddleware next);
}
```

### `BearerTokenMiddleware`

Adds an `Authorization: Bearer <token>` header (RFC 6750).

```apex
.use(new BearerTokenMiddleware('eyJhbGci...'))
```

### `ApiKeyMiddleware`

Adds an API key as a header or query parameter.

```apex
.use(new ApiKeyMiddleware('my-secret-key'))                      // x-api-key header (default)
.use(new ApiKeyMiddleware('my-secret-key', 'X-Api-Key'))         // custom header name
.use(ApiKeyMiddleware.asQueryParam('my-secret-key', 'api_key'))  // query param
```

### `LoggingMiddleware`

Logs request and response using `IHttpLogger`. Uses `SystemDebugLogger` (`System.debug`) by default.

```apex
.use(new LoggingMiddleware())                   // default System.debug logger
.use(new LoggingMiddleware(myCustomLogger))     // inject custom IHttpLogger
```

### `RetryMiddleware`

Retries on network errors and configurable HTTP status codes with exponential backoff.

Default retryable codes: `408, 429, 500, 502, 503, 504`

```apex
.use(new RetryMiddleware(3))                                     // 3 retries, default codes
.use(new RetryMiddleware(2, new Set<Integer>{ 503, 504 }))       // custom codes
```

> **Apex limitation:** True async sleep is not available in synchronous Apex. Backoff is simulated with a CPU busy-wait capped at ~500ms to respect governor limits. For real inter-retry delays, use Queueable Apex with a chained job.

### `CircuitBreakerMiddleware`

Prevents cascading failures with the classic CLOSED → OPEN → HALF_OPEN state machine.

Trips to OPEN after `failureThreshold` consecutive 5xx responses or `CalloutException`s. After `recoveryTimeoutSeconds`, one probe request is allowed through (HALF_OPEN). Success resets to CLOSED; failure re-opens.

```apex
.use(new CircuitBreakerMiddleware('PaymentAPI'))           // 5 failures, 60s recovery (defaults)
.use(new CircuitBreakerMiddleware('PaymentAPI', 3, 30))    // custom thresholds
```

> **State scope:** Circuit state is stored in a static `Map`, scoped to the current Apex transaction. It does not persist across transactions. For persistent state across transactions, back it with Platform Cache or a Custom Object.

---

## Response handlers

Response handlers implement `IResponseHandler` and are registered with `.handleResponseWith()`.

```apex
public interface IResponseHandler {
    HttpCalloutResult handle(HttpResponse res);
}
```

### `JsonResponseHandler`

Deserializes the response body into a typed Apex class. Only runs on 2xx responses.

```apex
HttpCalloutResult result = HttpCallout.builder()
    .endpoint('https://api.example.com/products/1')
    .get()
    .handleResponseWith(new JsonResponseHandler(Product.class))
    .build()
    .execute();

Product p = (Product) result.getDataAs(Product.class);
```

If deserialization fails, `result.parseError` is set and `result.isSuccess()` remains `true` — the HTTP call itself succeeded.

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
    .use(new CircuitBreakerMiddleware('OrderAPI', 3, 30))
    .use(new BearerTokenMiddleware(accessToken))
    .use(new RetryMiddleware(3))
    .use(new LoggingMiddleware())
    .handleResponseWith(new JsonResponseHandler(OrderResponse.class))
    .build()
    .execute();

if (result.isSuccess()) {
    OrderResponse order = (OrderResponse) result.getDataAs(OrderResponse.class);
}
```

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

**Benefits:** no Remote Site Setting needed, authentication (Basic, OAuth 2.0, JWT) handled by Salesforce.

> If your Named Credential already handles authentication, do not also attach `BearerTokenMiddleware` or `ApiKeyMiddleware` — they would conflict.

---

## Manual testing

An anonymous Apex script for the Developer Console is provided at `scripts/apex/testHttpCallout.apex`.

It runs 15 tests against [JSONPlaceholder](https://jsonplaceholder.typicode.com) covering all verbs, middleware, and response handling.

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
