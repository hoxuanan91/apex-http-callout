/**
 * @description Response handler that deserializes a JSON response body to a typed Apex object.
 *
 * On a successful (2xx) response with a non-blank body, the body is deserialized into
 * the provided type and stored in HttpCalloutResult.data.
 * On failure, the raw body is still accessible via result.body.
 * JSON parse errors are captured in result.parseError rather than thrown.
 *
 * @example
 * HttpCalloutResult result = new HttpCallout.Builder()
 *     .endpoint('https://api.example.com/orders/123')
 *     .get()
 *     .handleResponseWith(new JsonResponseHandler(OrderResponse.class))
 *     .build()
 *     .execute();
 *
 * if (result.isSuccess()) {
 *     OrderResponse order = (OrderResponse) result.getDataAs(OrderResponse.class);
 * }
 */
public class JsonResponseHandler implements IResponseHandler {

    private final Type responseType;

    public JsonResponseHandler(Type responseType) {
        if (responseType == null) {
            throw new HttpCallout.HttpCalloutException(
                'JsonResponseHandler: responseType cannot be null'
            );
        }
        this.responseType = responseType;
    }

    public HttpCalloutResult handle(HttpResponse res) {
        HttpCalloutResult result = new HttpCalloutResult(res);

        if (result.isSuccess() && String.isNotBlank(res.getBody())) {
            try {
                result.data = JSON.deserialize(res.getBody(), responseType);
            } catch (Exception ex) {
                result.parseError = ex.getMessage();
                System.debug(
                    LoggingLevel.ERROR,
                    'JsonResponseHandler: failed to deserialize response body — ' + ex.getMessage()
                );
            }
        }

        return result;
    }
}
