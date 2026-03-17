/**
 * @description Immutable wrapper for the result of an HTTP callout.
 *
 * Provides convenience methods for status code classification and typed data access.
 * The `data`, `errorCode`, `errorMessage`, and `parseError` fields are intended
 * to be populated by `IResponseHandler` implementations.
 *
 * @example
 * HttpCalloutResult result = new HttpCallout.Builder()
 *     .endpoint('https://api.example.com/items')
 *     .get()
 *     .handleResponseWith(new JsonResponseHandler(ItemList.class))
 *     .build()
 *     .execute();
 *
 * if (result.isSuccess()) {
 *     ItemList items = (ItemList) result.getDataAs(ItemList.class);
 * } else {
 *     System.debug(result.errorMessage);
 * }
 */
public class HttpCalloutResult {

    /** HTTP status code from the response. */
    public final Integer statusCode;

    /** Raw response body string. */
    public final String body;

    /**
     * Deserialized response payload. Populated by an IResponseHandler.
     * Use getDataAs(Type) to safely cast to your expected type.
     */
    public Object data { get; set; }

    /** Application-level error code, if extracted by a response handler. */
    public String errorCode { get; set; }

    /** Application-level error message, if extracted by a response handler. */
    public String errorMessage { get; set; }

    /** JSON deserialization error message, if parsing failed in a response handler. */
    public String parseError { get; set; }

    public HttpCalloutResult(HttpResponse res) {
        this.statusCode = res.getStatusCode();
        this.body = res.getBody();
    }

    // -------------------------------------------------------------------------
    // Status helpers
    // -------------------------------------------------------------------------

    /** @return true if statusCode is 2xx */
    public Boolean isSuccess() {
        return statusCode >= 200 && statusCode < 300;
    }

    /** @return true if statusCode is 4xx */
    public Boolean isClientError() {
        return statusCode >= 400 && statusCode < 500;
    }

    /** @return true if statusCode is 5xx */
    public Boolean isServerError() {
        return statusCode >= 500;
    }

    // -------------------------------------------------------------------------
    // Typed data access
    // -------------------------------------------------------------------------

    /**
     * @description Returns the deserialized `data` cast to the given Apex Type.
     *
     * NOTE: Apex does not support generic methods. This method round-trips through
     * JSON serialization to perform the cast safely, so it works for both plain Objects
     * and complex nested types.
     *
     * @param targetType  The Apex Type to cast data to (e.g. MyClass.class)
     * @return            The data as an instance of targetType, or null if data is null
     *
     * @example
     * MyResponse resp = (MyResponse) result.getDataAs(MyResponse.class);
     */
    public Object getDataAs(Type targetType) {
        if (data == null || targetType == null) {
            return null;
        }
        return JSON.deserialize(JSON.serialize(data), targetType);
    }
}
