/**
 * @description Queueable wrapper that executes an HttpCallout in an async transaction.
 *
 * Not intended to be instantiated directly. Use HttpCallout.build().executeAsync(callback).
 *
 * The callout runs in a separate Apex transaction with its own governor limits.
 * The provided IHttpCalloutCallback receives either onSuccess or onFailure depending
 * on the outcome.
 *
 * ⚠️  CIRCUIT BREAKER STATE — since this runs in a new transaction, any circuit breaker
 * state accumulated in the calling transaction is not carried over. Each async job
 * starts with a fresh CLOSED state for all circuits.
 *
 * @example
 * // Preferred usage via the builder:
 * Id jobId = HttpCallout.builder()
 *     .endpoint('https://api.example.com/orders')
 *     .post(payload)
 *     .use(new RetryMiddleware(2))
 *     .use(new LoggingMiddleware())
 *     .build()
 *     .executeAsync(new MyCallback());
 */
public class HttpCalloutQueueable implements Queueable, Database.AllowsCallouts {

    private final HttpCallout callout;
    private final IHttpCalloutCallback callback;

    /**
     * @param callout   A fully configured HttpCallout instance (from .build())
     * @param callback  Optional callback to receive the result — may be null
     */
    public HttpCalloutQueueable(HttpCallout callout, IHttpCalloutCallback callback) {
        this.callout  = callout;
        this.callback = callback;
    }

    public void execute(QueueableContext ctx) {
        try {
            HttpCalloutResult result = callout.execute();
            if (callback != null) {
                callback.onSuccess(result);
            }
        } catch (Exception ex) {
            if (callback != null) {
                callback.onFailure(ex);
            }
        }
    }
}
