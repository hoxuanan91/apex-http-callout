/**
 * @description Middleware that logs HTTP requests and responses.
 *
 * Logs method, endpoint, status code, and duration for every call.
 * Uses IHttpLogger for output — defaults to SystemDebugLogger.
 * Inject a custom logger to integrate with Nebula Logger or any other framework.
 *
 * @example
 * // Default (System.debug)
 * .use(new LoggingMiddleware())
 *
 * @example
 * // Custom logger
 * .use(new LoggingMiddleware(new MyNebulaLogger()))
 */
public class LoggingMiddleware implements IHttpMiddleware {

    private final IHttpLogger logger;

    public LoggingMiddleware() {
        this.logger = new SystemDebugLogger();
    }

    public LoggingMiddleware(IHttpLogger logger) {
        this.logger = logger != null ? logger : new SystemDebugLogger();
    }

    public HttpResponse handle(HttpRequest req, IHttpMiddleware next) {
        Long startTime = System.currentTimeMillis();
        String requestId = 'REQ-' + startTime;

        logger.info('HTTP Request', new Map<String, Object>{
            'requestId' => requestId,
            'method'    => req.getMethod(),
            'endpoint'  => req.getEndpoint(),
            'hasBody'   => String.isNotBlank(req.getBody())
        });

        try {
            HttpResponse res = next.handle(req, null);

            logger.info('HTTP Response', new Map<String, Object>{
                'requestId'  => requestId,
                'statusCode' => res.getStatusCode(),
                'durationMs' => System.currentTimeMillis() - startTime
            });

            return res;

        } catch (Exception ex) {
            logger.error('HTTP Error', new Map<String, Object>{
                'requestId'  => requestId,
                'error'      => ex.getMessage(),
                'durationMs' => System.currentTimeMillis() - startTime
            });
            throw ex;
        }
    }
}
