/**
 * @description Callback interface for handling the result of an async HTTP callout.
 *
 * Implement this interface to receive the outcome of a callout executed via
 * HttpCallout.build().executeAsync(callback). The callback runs inside a Queueable
 * job in a separate Apex transaction.
 *
 * @example
 * public class OrderCalloutCallback implements IHttpCalloutCallback {
 *     public void onSuccess(HttpCalloutResult result) {
 *         if (result.isSuccess()) {
 *             // process result
 *         }
 *     }
 *     public void onFailure(Exception ex) {
 *         // log or re-enqueue
 *     }
 * }
 *
 * HttpCallout.builder()
 *     .endpoint('https://api.example.com/orders')
 *     .get()
 *     .build()
 *     .executeAsync(new OrderCalloutCallback());
 */
public interface IHttpCalloutCallback {
    /**
     * Called when the HTTP callout completes — regardless of the status code.
     * Check result.isSuccess() / result.isClientError() / result.isServerError()
     * to determine the outcome.
     *
     * @param result  The result of the HTTP callout
     */
    void onSuccess(HttpCalloutResult result);

    /**
     * Called when the callout throws an unhandled exception —
     * e.g. CalloutException, circuit breaker open, or any middleware exception.
     *
     * @param ex  The exception thrown during execution
     */
    void onFailure(Exception ex);
}
