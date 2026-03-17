/**
 * @description Strategy interface for processing HTTP responses.
 *
 * Implement this interface to customize how an HttpResponse is transformed into
 * an HttpCalloutResult. Useful for deserializing typed payloads, parsing error
 * envelopes, or applying domain-specific conventions.
 *
 * @example
 * public class MyHandler implements IResponseHandler {
 *     public HttpCalloutResult handle(HttpResponse res) {
 *         HttpCalloutResult result = new HttpCalloutResult(res);
 *         if (result.isSuccess()) {
 *             result.data = JSON.deserialize(res.getBody(), MyType.class);
 *         }
 *         return result;
 *     }
 * }
 */
public interface IResponseHandler {
    HttpCalloutResult handle(HttpResponse res);
}
