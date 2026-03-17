/**
 * @description Middleware that retries failed requests with exponential backoff.
 *
 * Retries on:
 *   - Network errors   : CalloutException
 *   - Retryable codes  : 408, 429, 500, 502, 503, 504 (configurable)
 *
 * The retry count is the number of ADDITIONAL attempts after the first call.
 * A value of 3 means up to 4 total attempts (1 original + 3 retries).
 *
 * ⚠️  APEX LIMITATION — True async sleep is not possible in synchronous Apex.
 * This middleware simulates backoff with a short CPU busy-wait. The actual delay
 * is intentionally capped at ~500ms to avoid CPU governor limits.
 * For real delays between retries, use Queueable Apex with a chained job.
 *
 * @example
 * // Default retryable status codes, 3 retries
 * .use(new RetryMiddleware(3))
 *
 * @example
 * // Custom retryable codes
 * .use(new RetryMiddleware(2, new Set<Integer>{ 503, 504 }))
 */
public class RetryMiddleware implements IHttpMiddleware {

    private static final Set<Integer> DEFAULT_RETRYABLE_CODES = new Set<Integer>{
        408, 429, 500, 502, 503, 504
    };

    private final Integer maxRetries;
    private final Set<Integer> retryableCodes;

    public RetryMiddleware(Integer maxRetries) {
        this(maxRetries, DEFAULT_RETRYABLE_CODES);
    }

    public RetryMiddleware(Integer maxRetries, Set<Integer> retryableCodes) {
        this.maxRetries = maxRetries;
        this.retryableCodes = retryableCodes != null ? retryableCodes : DEFAULT_RETRYABLE_CODES;
    }

    public HttpResponse handle(HttpRequest req, IHttpMiddleware next) {
        Integer attempt = 0;
        HttpResponse lastResponse;
        Exception lastException;

        while (attempt <= maxRetries) {
            try {
                lastResponse  = next.handle(req, null);
                lastException = null; // clear any prior network error

                if (!retryableCodes.contains(lastResponse.getStatusCode())) {
                    return lastResponse;
                }

                System.debug(
                    LoggingLevel.WARN,
                    'RetryMiddleware: retryable status ' + lastResponse.getStatusCode() +
                    ' on attempt ' + attempt + '/' + maxRetries
                );

            } catch (CalloutException ex) {
                lastException = ex;
                lastResponse  = null;
                System.debug(
                    LoggingLevel.WARN,
                    'RetryMiddleware: CalloutException on attempt ' + attempt +
                    '/' + maxRetries + ': ' + ex.getMessage()
                );
            }

            if (attempt < maxRetries) {
                simulateBackoff(attempt);
            }
            attempt++;
        }

        if (lastException != null) {
            throw lastException;
        }

        // All retries exhausted — return last response even if retryable
        return lastResponse;
    }

    /**
     * Simulates exponential backoff via CPU busy-wait.
     * Target delay: 2^attempt * 100ms, capped at 500ms to stay within CPU limits.
     *
     * attempt 0 → ~100ms, attempt 1 → ~200ms, attempt 2 → ~400ms, attempt 3+ → ~500ms
     */
    @TestVisible
    private void simulateBackoff(Integer attempt) {
        Integer targetMs = Math.min((Integer) Math.pow(2, attempt) * 100, 500);
        Long deadline = System.currentTimeMillis() + targetMs;
        while (System.currentTimeMillis() < deadline) {
            // Intentional CPU busy-wait — see method comment above
        }
    }
}
