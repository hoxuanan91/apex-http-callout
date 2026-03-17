/**
 * @description Fluent HTTP callout builder with a composable middleware pipeline.
 *
 * Implements three design patterns:
 *  - Builder     : Stepped builder via HttpCallout.builder() for compile-time safety
 *  - Decorator   : Middleware are chained via IHttpMiddleware and executed in order
 *  - Strategy    : IResponseHandler decouples response processing from request building
 *
 * Body rules are enforced at COMPILE TIME by the return type of each verb:
 *
 *   Verb        Returns             body()   build()
 *   ──────────  ──────────────────  ───────  ───────
 *   get()       IBuildStep          ✗        ✓
 *   head()      IBuildStep          ✗        ✓
 *   delete_x()  IOptionalBodyStep   optional ✓
 *   post()      IBodyRequiredStep   required ✗ (until body is set)
 *   put()       IBodyRequiredStep   required ✗ (until body is set)
 *   patch()     IBodyRequiredStep   required ✗ (until body is set)
 *
 * Entry point is HttpCallout.builder() — not new HttpCallout.Builder().
 *
 * @example
 * // GET — build() available immediately
 * HttpCalloutResult result = HttpCallout.builder()
 *     .endpoint('https://api.example.com/accounts')
 *     .get()
 *     .build()
 *     .execute();
 *
 * @example
 * // POST — build() only available after bodyJson() or body()
 * HttpCalloutResult result = HttpCallout.builder()
 *     .endpoint('https://api.example.com/orders')
 *     .post()                            // → IBodyRequiredStep (no build yet)
 *     .bodyJson(new Map<String,Object>{'ref'=>'123'}) // → IBuildStep (build now available)
 *     .timeout(20000)
 *     .use(new CircuitBreakerMiddleware('OrderAPI'))
 *     .use(new BearerTokenMiddleware(myToken))
 *     .use(new RetryMiddleware(3))
 *     .use(new LoggingMiddleware())
 *     .handleResponseWith(new JsonResponseHandler(OrderResponse.class))
 *     .build()
 *     .execute();
 *
 * @example
 * // Compile error — post() without body
 * HttpCallout.builder().endpoint('/api').post().build(); // ERROR: build() not on IBodyRequiredStep
 *
 * @example
 * // Compile error — get() with body
 * HttpCallout.builder().endpoint('/api').get().bodyJson(data); // ERROR: bodyJson() not on IBuildStep
 */
public with sharing class HttpCallout {

    private String endpoint;
    private String method = 'GET';
    private Integer timeout = 30000;
    private Map<String, String> headers = new Map<String, String>();
    private String body;
    private List<IHttpMiddleware> middlewares = new List<IHttpMiddleware>();
    private IResponseHandler responseHandler;

    private HttpCallout() {}

    // =========================================================================
    // FACTORY METHOD — only valid entry point
    // =========================================================================

    /** @return The first step of the stepped builder. */
    public static IEndpointStep builder() {
        return new Builder();
    }

    // =========================================================================
    // STEPPED BUILDER INTERFACES
    // =========================================================================

    /** Step 1 — set the endpoint. */
    public interface IEndpointStep {
        IMethodStep endpoint(String url);
    }

    /** Step 2 — choose the HTTP verb. Return type determines what comes next. */
    public interface IMethodStep {
        IBuildStep        get();
        IBuildStep        head();
        IOptionalBodyStep delete_x();
        IBodyRequiredStep post();
        IBodyRequiredStep put();
        IBodyRequiredStep patch();
        // Verb + body shortcuts → go straight to IBuildStep
        IBuildStep post(Object jsonBody);
        IBuildStep put(Object jsonBody);
        IBuildStep patch(Object jsonBody);
    }

    /**
     * Step 3a — body is REQUIRED (POST / PUT / PATCH).
     * build() is intentionally absent: you cannot build without providing a body.
     */
    public interface IBodyRequiredStep {
        IBuildStep body(String rawBody);
        IBuildStep bodyJson(Object obj);
    }

    /**
     * Step 3b — body is OPTIONAL (DELETE).
     * Extends IBuildStep so build() is available immediately,
     * but body/bodyJson are also available if needed.
     */
    public interface IOptionalBodyStep extends IBuildStep {
        IBuildStep body(String rawBody);
        IBuildStep bodyJson(Object obj);
    }

    /**
     * Step 4 — configure options and build.
     * Returned by get()/head() directly, and by body()/bodyJson() on required/optional steps.
     * Notably does NOT expose body() — prevents re-setting the body after the verb step.
     */
    public interface IBuildStep {
        IBuildStep  timeout(Integer ms);
        IBuildStep  header(String key, String value);
        IBuildStep  contentTypeJson();
        IBuildStep  use(IHttpMiddleware middleware);
        IBuildStep  handleResponseWith(IResponseHandler handler);
        HttpCallout build();
    }

    // =========================================================================
    // BUILDER IMPLEMENTATION (private — access only via HttpCallout.builder())
    // =========================================================================

    private class Builder implements IEndpointStep, IMethodStep, IBodyRequiredStep, IOptionalBodyStep, IBuildStep {

        private final HttpCallout instance = new HttpCallout();

        // ----- IEndpointStep -----

        public IMethodStep endpoint(String url) {
            instance.endpoint = url;
            return this;
        }

        // ----- IMethodStep -----

        public IBuildStep        get()      { instance.method = 'GET';    return this; }
        public IBuildStep        head()     { instance.method = 'HEAD';   return this; }
        public IOptionalBodyStep delete_x() { instance.method = 'DELETE'; return this; }
        public IBodyRequiredStep post()     { instance.method = 'POST';   return this; }
        public IBodyRequiredStep put()      { instance.method = 'PUT';    return this; }
        public IBodyRequiredStep patch()    { instance.method = 'PATCH';  return this; }

        public IBuildStep post(Object jsonBody)  { instance.method = 'POST';  return setJsonBody(jsonBody); }
        public IBuildStep put(Object jsonBody)   { instance.method = 'PUT';   return setJsonBody(jsonBody); }
        public IBuildStep patch(Object jsonBody) { instance.method = 'PATCH'; return setJsonBody(jsonBody); }

        // ----- IBodyRequiredStep + IOptionalBodyStep -----

        public IBuildStep body(String rawBody) {
            instance.body = rawBody;
            return this;
        }

        public IBuildStep bodyJson(Object obj) {
            return setJsonBody(obj);
        }

        // ----- IBuildStep -----

        public IBuildStep timeout(Integer ms) {
            instance.timeout = ms;
            return this;
        }

        public IBuildStep header(String key, String value) {
            instance.headers.put(key, value);
            return this;
        }

        public IBuildStep contentTypeJson() {
            return header('Content-Type', 'application/json; charset=utf-8');
        }

        public IBuildStep use(IHttpMiddleware middleware) {
            if (middleware != null) {
                instance.middlewares.add(middleware);
            }
            return this;
        }

        public IBuildStep handleResponseWith(IResponseHandler handler) {
            instance.responseHandler = handler;
            return this;
        }

        public HttpCallout build() {
            if (String.isBlank(instance.endpoint)) {
                throw new HttpCalloutException('Endpoint is required');
            }
            return instance;
        }

        // ----- private helpers -----

        private IBuildStep setJsonBody(Object obj) {
            instance.body = JSON.serialize(obj, true);
            instance.headers.put('Content-Type', 'application/json; charset=utf-8');
            return this;
        }
    }

    // =========================================================================
    // EXECUTION
    // =========================================================================

    /**
     * Executes the HTTP request through the middleware pipeline.
     *
     * @return HttpCalloutResult wrapping the response (and deserialized data if a handler was set)
     * @throws HttpCalloutException propagated from middleware (e.g. circuit breaker open)
     * @throws CalloutException if the HTTP callout itself fails
     */
    public HttpCalloutResult execute() {
        HttpRequest req = buildRequest();

        // Build middleware chain in reverse so the first-added middleware executes first
        IHttpMiddleware chain = new FinalMiddleware();
        for (Integer i = middlewares.size() - 1; i >= 0; i--) {
            chain = new MiddlewareChain(middlewares[i], chain);
        }

        HttpResponse res = chain.handle(req, null);

        if (responseHandler != null) {
            return responseHandler.handle(res);
        }
        return new HttpCalloutResult(res);
    }

    private HttpRequest buildRequest() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod(method);
        req.setTimeout(timeout);

        for (String key : headers.keySet()) {
            req.setHeader(key, headers.get(key));
        }

        if (String.isNotBlank(body)) {
            req.setBody(body);
        }

        return req;
    }

    // =========================================================================
    // INNER CLASSES
    // =========================================================================

    /** Links two middlewares into an executable chain node. */
    private class MiddlewareChain implements IHttpMiddleware {
        private final IHttpMiddleware current;
        private final IHttpMiddleware next;

        public MiddlewareChain(IHttpMiddleware current, IHttpMiddleware next) {
            this.current = current;
            this.next = next;
        }

        public HttpResponse handle(HttpRequest req, IHttpMiddleware ignored) {
            return current.handle(req, next);
        }
    }

    /** Terminal middleware that performs the actual HTTP callout. */
    private class FinalMiddleware implements IHttpMiddleware {
        public HttpResponse handle(HttpRequest req, IHttpMiddleware next) {
            return new Http().send(req);
        }
    }

    public class HttpCalloutException extends Exception {}
}
