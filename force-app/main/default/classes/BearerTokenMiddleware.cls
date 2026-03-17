/**
 * @description Middleware that adds Bearer token authentication (RFC 6750).
 *
 * Sets the Authorization header to "Bearer <token>" on every request.
 * Commonly used for OAuth 2.0 / JWT-authenticated APIs.
 *
 * @example
 * .use(new BearerTokenMiddleware(myAccessToken))
 *
 * @example
 * // Fetch a token dynamically from a Named Credential or Custom Setting first:
 * String token = MyTokenService.getAccessToken();
 * .use(new BearerTokenMiddleware(token))
 */
public class BearerTokenMiddleware implements IHttpMiddleware {

    private final String token;

    public BearerTokenMiddleware(String token) {
        if (String.isBlank(token)) {
            throw new HttpCallout.HttpCalloutException(
                'BearerTokenMiddleware: token cannot be blank'
            );
        }
        this.token = token;
    }

    public HttpResponse handle(HttpRequest req, IHttpMiddleware next) {
        req.setHeader('Authorization', 'Bearer ' + token);
        return next.handle(req, null);
    }
}
