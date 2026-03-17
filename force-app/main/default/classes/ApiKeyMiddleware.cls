/**
 * @description Middleware that adds API key authentication to requests.
 *
 * Supports two delivery modes:
 *  - Header (default) : sets a request header (e.g. x-api-key, Authorization)
 *  - Query param      : appends the key as a URL query parameter (URL-encoded)
 *
 * @example
 * // Header with default name 'x-api-key'
 * .use(new ApiKeyMiddleware('my-secret-key'))
 *
 * @example
 * // Custom header name
 * .use(new ApiKeyMiddleware('my-secret-key', 'X-Api-Key'))
 *
 * @example
 * // Query parameter
 * .use(ApiKeyMiddleware.asQueryParam('my-secret-key', 'api_key'))
 */
public class ApiKeyMiddleware implements IHttpMiddleware {

    private static final String DEFAULT_HEADER = 'x-api-key';

    private final String  apiKey;
    private final String  paramName;
    private final Boolean useQueryParam;

    public ApiKeyMiddleware(String apiKey) {
        this(apiKey, DEFAULT_HEADER, false);
    }

    public ApiKeyMiddleware(String apiKey, String headerName) {
        this(apiKey, headerName, false);
    }

    private ApiKeyMiddleware(String apiKey, String paramName, Boolean useQueryParam) {
        if (String.isBlank(apiKey)) {
            throw new HttpCallout.HttpCalloutException('ApiKeyMiddleware: apiKey cannot be blank');
        }
        if (String.isBlank(paramName)) {
            throw new HttpCallout.HttpCalloutException('ApiKeyMiddleware: header/param name cannot be blank');
        }
        this.apiKey        = apiKey;
        this.paramName     = paramName;
        this.useQueryParam = useQueryParam;
    }

    /**
     * @description Creates an ApiKeyMiddleware that appends the key as a query parameter.
     * @param apiKey     The API key value
     * @param paramName  The query parameter name (e.g. 'api_key', 'token', 'access_token')
     */
    public static ApiKeyMiddleware asQueryParam(String apiKey, String paramName) {
        return new ApiKeyMiddleware(apiKey, paramName, true);
    }

    public HttpResponse handle(HttpRequest req, IHttpMiddleware next) {
        if (useQueryParam) {
            String endpoint  = req.getEndpoint();
            String separator = endpoint.contains('?') ? '&' : '?';
            req.setEndpoint(
                endpoint +
                separator +
                EncodingUtil.urlEncode(paramName, 'UTF-8') +
                '=' +
                EncodingUtil.urlEncode(apiKey, 'UTF-8')
            );
        } else {
            req.setHeader(paramName, apiKey);
        }

        return next.handle(req, null);
    }
}
