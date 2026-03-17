/**
 * @description Middleware interface for the HTTP callout pipeline (Decorator Pattern).
 *
 * Implement this interface to intercept, modify, or enhance HTTP requests and responses.
 * Each middleware receives the request and a reference to the next middleware in the chain.
 * Middleware MUST call `next.handle(req, null)` to continue the chain, or return a response
 * directly to short-circuit (e.g. circuit breaker).
 *
 * @example
 * public class CorrelationIdMiddleware implements IHttpMiddleware {
 *     public HttpResponse handle(HttpRequest req, IHttpMiddleware next) {
 *         req.setHeader('X-Correlation-Id', UserInfo.getSessionId());
 *         return next.handle(req, null);
 *     }
 * }
 */
public interface IHttpMiddleware {
    HttpResponse handle(HttpRequest req, IHttpMiddleware next);
}
