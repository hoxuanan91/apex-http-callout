/**
 * @description Fluent HTTP callout builder with a composable middleware pipeline.
 *
 * Implements three design patterns:
 *  - Builder     : HttpCallout.Builder provides a fluent API for constructing requests
 *  - Decorator   : Middleware are chained via IHttpMiddleware and executed in order
 *  - Strategy    : IResponseHandler decouples response processing from request building
 *
 * Supported methods: GET, HEAD, DELETE, POST, PUT, PATCH
 *
 * Body validation is enforced at build time:
 *  - GET / HEAD        → body forbidden
 *  - DELETE            → body optional
 *  - POST / PUT / PATCH → body required
 *
 * @example
 * // Minimal GET
 * HttpCalloutResult result = new HttpCallout.Builder()
 *     .endpoint('https://api.example.com/accounts')
 *     .get()
 *     .build()
 *     .execute();
 *
 * @example
 * // POST with full middleware pipeline
 * HttpCalloutResult result = new HttpCallout.Builder()
 *     .endpoint('https://api.example.com/orders')
 *     .post(new Map<String, Object>{ 'ref' => '123' })
 *     .timeout(20000)
 *     .use(new CircuitBreakerMiddleware('OrderAPI'))
 *     .use(new BearerTokenMiddleware(myToken))
 *     .use(new RetryMiddleware(3))
 *     .use(new LoggingMiddleware())
 *     .handleResponseWith(new JsonResponseHandler(OrderResponse.class))
 *     .build()
 *     .execute();
 */
public with sharing class HttpCallout {

    // HTTP method configuration: bodyRequired, bodyAllowed
    @TestVisible
    private static final Map<String, MethodConfig> METHOD_CONFIGS = new Map<String, MethodConfig>{
        'GET'    => new MethodConfig(false, false),
        'HEAD'   => new MethodConfig(false, false),
        'DELETE' => new MethodConfig(false, true),
        'POST'   => new MethodConfig(true,  true),
        'PUT'    => new MethodConfig(true,  true),
        'PATCH'  => new MethodConfig(true,  true)
    };

    private String endpoint;
    private String method = 'GET';
    private Integer timeout = 30000;
    private Map<String, String> headers = new Map<String, String>();
    private String body;
    private List<IHttpMiddleware> middlewares = new List<IHttpMiddleware>();
    private IResponseHandler responseHandler;

    private HttpCallout() {}

    // =========================================================================
    // BUILDER
    // =========================================================================

    public class Builder {
        private final HttpCallout instance = new HttpCallout();

        /** Sets the request endpoint (absolute URL or relative path). Required. */
        public Builder endpoint(String url) {
            instance.endpoint = url;
            return this;
        }

        /**
         * Sets the HTTP method. Throws HttpCalloutException for unsupported methods.
         * Prefer the verb shortcuts (get(), post(), etc.) over this method.
         */
        public Builder method(String httpMethod) {
            String upper = String.isNotBlank(httpMethod) ? httpMethod.toUpperCase() : '';
            if (!METHOD_CONFIGS.containsKey(upper)) {
                throw new HttpCalloutException('Unsupported HTTP method: ' + httpMethod);
            }
            instance.method = upper;
            return this;
        }

        // ----- Verb shortcuts -----
        public Builder get()      { return method('GET'); }
        public Builder head()     { return method('HEAD'); }
        public Builder delete_x() { return method('DELETE'); }
        public Builder post()     { return method('POST'); }
        public Builder put()      { return method('PUT'); }
        public Builder patch()    { return method('PATCH'); }

        // ----- Verb + body shortcuts (enforces correct usage) -----
        public Builder post(Object jsonBody)  { return method('POST').bodyJson(jsonBody); }
        public Builder put(Object jsonBody)   { return method('PUT').bodyJson(jsonBody); }
        public Builder patch(Object jsonBody) { return method('PATCH').bodyJson(jsonBody); }

        /** Sets the request timeout in milliseconds. Default: 30000 (30s). */
        public Builder timeout(Integer ms) {
            instance.timeout = ms;
            return this;
        }

        /** Adds a single request header. */
        public Builder header(String key, String value) {
            instance.headers.put(key, value);
            return this;
        }

        /** Shortcut to set Content-Type: application/json; charset=utf-8 */
        public Builder contentTypeJson() {
            return header('Content-Type', 'application/json; charset=utf-8');
        }

        /** Sets a raw string body. Does not set Content-Type automatically. */
        public Builder body(String rawBody) {
            instance.body = rawBody;
            return this;
        }

        /**
         * Serializes obj to JSON and sets Content-Type to application/json.
         * Suppresses null fields (suppressApexObjectNulls = true).
         */
        public Builder bodyJson(Object obj) {
            instance.body = JSON.serialize(obj, true);
            return contentTypeJson();
        }

        /**
         * Adds a middleware to the pipeline. Middleware execute in the order they are added.
         * Null middleware are silently ignored.
         */
        public Builder use(IHttpMiddleware middleware) {
            if (middleware != null) {
                instance.middlewares.add(middleware);
            }
            return this;
        }

        /** Sets a response handler (Strategy Pattern) for post-processing the HttpResponse. */
        public Builder handleResponseWith(IResponseHandler handler) {
            instance.responseHandler = handler;
            return this;
        }

        /**
         * Validates and returns the built HttpCallout instance.
         *
         * @throws HttpCalloutException if endpoint is blank, or if body rules are violated.
         */
        public HttpCallout build() {
            if (String.isBlank(instance.endpoint)) {
                throw new HttpCalloutException('Endpoint is required');
            }

            MethodConfig config = METHOD_CONFIGS.get(instance.method);
            Boolean hasBody = String.isNotBlank(instance.body);

            if (config.bodyRequired && !hasBody) {
                throw new HttpCalloutException(
                    instance.method + ' request requires a body. Use .body() or .bodyJson()'
                );
            }
            if (!config.bodyAllowed && hasBody) {
                throw new HttpCalloutException(
                    instance.method + ' request does not allow a body'
                );
            }

            return instance;
        }
    }

    // =========================================================================
    // EXECUTION
    // =========================================================================

    /**
     * Executes the HTTP request through the middleware pipeline.
     *
     * @return HttpCalloutResult wrapping the response (and deserialized data if a handler was set)
     * @throws HttpCalloutException propagated from middleware (e.g. circuit breaker, auth failure)
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

    /** Describes body constraints for an HTTP method. */
    public class MethodConfig {
        public final Boolean bodyRequired;
        public final Boolean bodyAllowed;

        public MethodConfig(Boolean required, Boolean allowed) {
            this.bodyRequired = required;
            this.bodyAllowed = allowed;
        }
    }

    public class HttpCalloutException extends Exception {}
}
