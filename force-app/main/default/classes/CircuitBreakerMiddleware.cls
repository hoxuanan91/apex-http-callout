/**
 * @description Circuit breaker middleware to prevent cascading failures.
 *
 * Implements the classic three-state circuit breaker:
 *   CLOSED    → Normal operation. Failures are counted.
 *   OPEN      → Requests fail immediately without hitting the downstream service.
 *   HALF_OPEN → After the recovery timeout, one request is allowed through.
 *               Success → CLOSED. Failure → OPEN again.
 *
 * Trips to OPEN when failureThreshold consecutive failures (5xx or CalloutException)
 * are recorded. After recoveryTimeoutSeconds, transitions to HALF_OPEN.
 *
 * ⚠️  STATE SCOPE — Circuit state is stored in a static Map, which is scoped to a
 * single Apex transaction. State does NOT persist between separate transactions,
 * between synchronous and asynchronous contexts, or across different Apex processes.
 * For persistent circuit state, back the CircuitState with Platform Cache or a
 * Custom Object.
 *
 * @example
 * // Defaults: 5 failures, 60s recovery window
 * .use(new CircuitBreakerMiddleware('PaymentAPI'))
 *
 * @example
 * // Custom thresholds
 * .use(new CircuitBreakerMiddleware('PaymentAPI', 3, 30))
 */
public class CircuitBreakerMiddleware implements IHttpMiddleware {

    private static final Integer DEFAULT_FAILURE_THRESHOLD        = 5;
    private static final Integer DEFAULT_RECOVERY_TIMEOUT_SECONDS = 60;

    @TestVisible
    private static final Map<String, CircuitState> CIRCUITS = new Map<String, CircuitState>();

    private final String  serviceName;
    private final Integer failureThreshold;
    private final Integer recoveryTimeoutSeconds;

    public CircuitBreakerMiddleware(String serviceName) {
        this(serviceName, DEFAULT_FAILURE_THRESHOLD, DEFAULT_RECOVERY_TIMEOUT_SECONDS);
    }

    public CircuitBreakerMiddleware(
        String  serviceName,
        Integer failureThreshold,
        Integer recoveryTimeoutSeconds
    ) {
        if (String.isBlank(serviceName)) {
            throw new HttpCallout.HttpCalloutException('CircuitBreaker: serviceName is required');
        }
        this.serviceName             = serviceName;
        this.failureThreshold        = failureThreshold;
        this.recoveryTimeoutSeconds  = recoveryTimeoutSeconds;
    }

    public HttpResponse handle(HttpRequest req, IHttpMiddleware next) {
        CircuitState state = getState();

        if (state.isOpen()) {
            if (state.shouldAttemptReset(recoveryTimeoutSeconds)) {
                state.halfOpen();
            } else {
                throw new HttpCallout.HttpCalloutException(
                    'Circuit breaker is OPEN for service: ' + serviceName +
                    '. Will retry after ' + recoveryTimeoutSeconds + 's.'
                );
            }
        }

        try {
            HttpResponse res = next.handle(req, null);

            if (res.getStatusCode() >= 500) {
                state.recordFailure(failureThreshold, serviceName);
            } else {
                state.recordSuccess(serviceName);
            }

            return res;

        } catch (Exception ex) {
            state.recordFailure(failureThreshold, serviceName);
            throw ex;
        }
    }

    // -------------------------------------------------------------------------
    // State management helpers
    // -------------------------------------------------------------------------

    @TestVisible
    private CircuitState getState() {
        if (!CIRCUITS.containsKey(serviceName)) {
            CIRCUITS.put(serviceName, new CircuitState());
        }
        return CIRCUITS.get(serviceName);
    }

    /** Resets all circuit states. Primarily intended for use in test isolation. */
    @TestVisible
    private static void resetAll() {
        CIRCUITS.clear();
    }

    // =========================================================================
    // CIRCUIT STATE
    // =========================================================================

    public class CircuitState {

        private Integer  failureCount     = 0;
        private Datetime lastFailureTime;
        private String   status           = 'CLOSED';

        public Boolean isOpen() {
            return status == 'OPEN';
        }

        public Boolean isHalfOpen() {
            return status == 'HALF_OPEN';
        }

        public Boolean isClosed() {
            return status == 'CLOSED';
        }

        public Boolean shouldAttemptReset(Integer recoverySeconds) {
            return lastFailureTime != null &&
                   lastFailureTime.addSeconds(recoverySeconds) < Datetime.now();
        }

        public void halfOpen() {
            status = 'HALF_OPEN';
        }

        public void recordFailure(Integer threshold, String serviceName) {
            failureCount++;
            lastFailureTime = Datetime.now();

            if (failureCount >= threshold) {
                status = 'OPEN';
                System.debug(
                    LoggingLevel.WARN,
                    'CircuitBreaker: OPENED for ' + serviceName +
                    ' after ' + failureCount + ' consecutive failures'
                );
            }
        }

        public void recordSuccess(String serviceName) {
            if (failureCount > 0 || !isClosed()) {
                System.debug(
                    LoggingLevel.INFO,
                    'CircuitBreaker: CLOSED (recovered) for ' + serviceName
                );
            }
            failureCount = 0;
            status = 'CLOSED';
        }

        public Integer getFailureCount() {
            return failureCount;
        }

        public String getStatus() {
            return status;
        }
    }
}
