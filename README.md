# apex-http-callout

A fluent, composable HTTP callout library for Salesforce Apex.

Enforces correct request construction **at compile time** via a stepped builder, and lets you attach cross-cutting concerns (auth, logging, retry, circuit breaking) through a clean middleware pipeline.

---

## Design patterns

| Pattern | Where |
|---|---|
| **Stepped Builder** | `HttpCallout.builder()` — compile-time body-rule enforcement |
| **Decorator** | `IHttpMiddleware` — middleware chained and executed in order |
| **Strategy** | `IResponseHandler` — decoupled response processing |

---

## Installation

Copy the contents of `force-app/main/default/classes/` into your Salesforce project and deploy with the Salesforce CLI:

```bash
sf project deploy start \
  --source-dir force-app/main/default/classes \
  --target-org <your-org-alias>
```

Or deploy to a sandbox with no test run:

```bash
sf project deploy start \
  --source-dir force-app/main/default/classes \
  --target-org <your-org-alias> \
  --test-level NoTestRun
```

---

## Quick start

```apex
// GET
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
// POST with JSON body (shortcut — body and Content-Type set automatically)
HttpCalloutResult result = HttpCallout.builder()
    .endpoint('https://api.example.com/orders')
    .post(new Map<String, Object>{ 'ref' => 'ORD-001', 'amount' => 99 })
    .build()
    .execute();
```

```apex
// Named Credential — no Remote Site Setting needed, auth handled by Salesforce
HttpCalloutResult result = HttpCallout.builder()
    .endpoint('callout:MyNamedCredential/api/v1/accounts')
    .get()
    .build()
    .execute();
```

---

## Compile-time body safety

The return type of each verb controls what you can call next. Wrong usage is a **compiler error**, not a runtime exception.

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
    .endpoint(String url)           // required

    // Verbs
    .get()
    .head()
    .delete_x()
    .post()                         // body required separately
    .put()
    .patch()
    .post(Object jsonBody)          // shortcut: sets body + Content-Type in one step
    .put(Object jsonBody)
    .patch(Object jsonBody)

    // Body (on IBodyRequiredStep / IOptionalBodyStep)
    .body(String rawBody)
    .bodyJson(Object obj)           // JSON.serialize + sets Content-Type

    // Options (on IBuildStep)
    .timeout(Integer ms)            // default: 30000
    .header(String key, String val)
    .contentTypeJson()
    .use(IHttpMiddleware middleware)
    .handleResponseWith(IResponseHandler handler)

    .build()
    .execute()                      // returns HttpCalloutResult
```

---

## HttpCalloutResult

```apex
result.statusCode       // Integer
result.body             // String — raw response body
result.data             // Object — populated by IResponseHandler
result.parseError       // String — set if deserialization failed
result.errorCode        // String — from response handler
result.errorMessage     // String — from response handler

result.isSuccess()      // 2xx
result.isClientError()  // 4xx
result.isServerError()  // 5xx

result.getDataAs(MyClass.class)  // cast data to a typed Apex class
```

---

## Middleware

Middleware implements `IHttpMiddleware` and is executed in the order it is registered with `.use()`.

```apex
public interface IHttpMiddleware {
    HttpResponse handle(HttpRequest req, IHttpMiddleware next);
}
```

### Built-in middleware

#### `BearerTokenMiddleware`
Adds an `Authorization: Bearer <token>` header (RFC 6750).

```apex
.use(new BearerTokenMiddleware('eyJhbGci...'))
```

#### `ApiKeyMiddleware`
Adds an API key as a header or query parameter.

```apex
.use(new ApiKeyMiddleware('my-secret-key'))                     // x-api-key header (default)
.use(new ApiKeyMiddleware('my-secret-key', 'X-Api-Key'))        // custom header name
.use(ApiKeyMiddleware.asQueryParam('my-secret-key', 'api_key')) // query param
```

#### `LoggingMiddleware`
Logs request and response using `IHttpLogger`. Uses `SystemDebugLogger` (wraps `System.debug`) by default.

```apex
.use(new LoggingMiddleware())                    // default System.debug logger
.use(new LoggingMiddleware(myCustomLogger))      // inject custom IHttpLogger
```

#### `RetryMiddleware`
Retries on network errors and configurable HTTP status codes with exponential backoff.

Default retryable codes: `408, 429, 500, 502, 503, 504`

```apex
.use(new RetryMiddleware(3))                                           // 3 retries, default codes
.use(new RetryMiddleware(2, new Set<Integer>{ 503, 504 }))             // custom codes
```

> **Apex limitation:** True async sleep is not available in synchronous Apex. Backoff is simulated with a CPU busy-wait capped at ~500ms to respect governor limits. For real delays between retries, use Queueable Apex with a chained job.

#### `CircuitBreakerMiddleware`
Prevents cascading failures with the classic CLOSED → OPEN → HALF_OPEN state machine.

Trips to OPEN after `failureThreshold` consecutive 5xx responses or `CalloutException`s. After `recoveryTimeoutSeconds`, one request is allowed through (HALF_OPEN). Success resets to CLOSED; failure re-opens.

```apex
.use(new CircuitBreakerMiddleware('PaymentAPI'))                    // 5 failures, 60s recovery
.use(new CircuitBreakerMiddleware('PaymentAPI', 3, 30))             // custom thresholds
```

> **State scope:** Circuit state is stored in a static `Map`, scoped to the current Apex transaction. It does not persist across transactions. For persistent state, back it with Platform Cache or a Custom Object.

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

If deserialization fails, `result.parseError` is set (non-null) and `result.isSuccess()` remains `true` — the HTTP call itself succeeded.

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
    public void debug(String msg, Map<String, Object> ctx) { /* ... */ }
    public void info(String msg, Map<String, Object> ctx)  { /* ... */ }
    public void warn(String msg, Map<String, Object> ctx)  { /* ... */ }
    public void error(String msg, Map<String, Object> ctx) { /* ... */ }
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

## Manual testing

An anonymous Apex script for the Developer Console is provided at `scripts/apex/testHttpCallout.apex`.

It runs 15 tests against [JSONPlaceholder](https://jsonplaceholder.typicode.com) covering all verbs, middleware, and response handling.

**Prerequisite — Remote Site Setting:**
> Setup → Remote Site Settings → New
> - Name: `JsonPlaceholder`
> - URL: `https://jsonplaceholder.typicode.com`

Then run via CLI:
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
├── IHttpLogger.cls                  # Logger interface
├── SystemDebugLogger.cls            # Default logger (System.debug)
├── LoggingMiddleware.cls            # Request/response logging
├── RetryMiddleware.cls              # Retry with exponential backoff
├── CircuitBreakerMiddleware.cls     # Circuit breaker
├── ApiKeyMiddleware.cls             # API key auth (header or query param)
├── BearerTokenMiddleware.cls        # Bearer token auth
├── JsonResponseHandler.cls          # JSON deserialization handler
└── HttpCalloutMockFactory.cls       # Test utilities (@IsTest)
```

---

## License

MIT
