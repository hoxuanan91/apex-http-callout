/**
 * @description Test utility: factory for HttpCalloutMock implementations.
 *
 * Provides ready-made mocks for common test scenarios:
 *  - Static responses (fixed status + body)
 *  - Sequential responses (different response per call)
 *  - Error simulations (CalloutException)
 *
 * All inner classes implement HttpCalloutMock.
 *
 * @example
 * Test.setMock(HttpCalloutMock.class, HttpCalloutMockFactory.withJson(200, '{"id":"1"}'));
 *
 * @example
 * Test.setMock(HttpCalloutMock.class, HttpCalloutMockFactory.sequence(
 *     new List<HttpCalloutMockFactory.StaticMock>{
 *         HttpCalloutMockFactory.withStatus(503),
 *         HttpCalloutMockFactory.withStatus(503),
 *         HttpCalloutMockFactory.withJson(200, '{"ok":true}')
 *     }
 * ));
 */
@IsTest
public class HttpCalloutMockFactory {

    // -------------------------------------------------------------------------
    // Factory methods
    // -------------------------------------------------------------------------

    public static StaticMock withStatus(Integer statusCode) {
        return new StaticMock(statusCode, '');
    }

    public static StaticMock withJson(Integer statusCode, String jsonBody) {
        return new StaticMock(statusCode, jsonBody);
    }

    public static StaticMock withBody(Integer statusCode, String body) {
        return new StaticMock(statusCode, body);
    }

    public static ErrorMock withCalloutException(String message) {
        return new ErrorMock(message);
    }

    public static SequenceMock sequence(List<StaticMock> responses) {
        return new SequenceMock(responses);
    }

    // -------------------------------------------------------------------------
    // Static mock — returns the same response every time
    // -------------------------------------------------------------------------

    public class StaticMock implements HttpCalloutMock {
        private final Integer statusCode;
        private final String  body;
        private final Map<String, String> headers;

        public StaticMock(Integer statusCode, String body) {
            this(statusCode, body, new Map<String, String>());
        }

        public StaticMock(Integer statusCode, String body, Map<String, String> headers) {
            this.statusCode = statusCode;
            this.body       = body;
            this.headers    = headers != null ? headers : new Map<String, String>();
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(body);
            for (String key : headers.keySet()) {
                res.setHeader(key, headers.get(key));
            }
            return res;
        }
    }

    // -------------------------------------------------------------------------
    // Error mock — throws CalloutException
    // -------------------------------------------------------------------------

    public class ErrorMock implements HttpCalloutMock {
        private final String message;

        public ErrorMock(String message) {
            this.message = message;
        }

        public HttpResponse respond(HttpRequest req) {
            CalloutException ex = (CalloutException) CalloutException.class.newInstance();
            ex.setMessage(message);
            throw ex;
        }
    }

    // -------------------------------------------------------------------------
    // Sequence mock — returns a different response on each call
    // -------------------------------------------------------------------------

    public class SequenceMock implements HttpCalloutMock {
        private final List<StaticMock> responses;
        private Integer index = 0;

        public SequenceMock(List<StaticMock> responses) {
            this.responses = responses;
        }

        public HttpResponse respond(HttpRequest req) {
            if (index >= responses.size()) {
                // Repeat last response if calls exceed list size
                return responses[responses.size() - 1].respond(req);
            }
            return responses[index++].respond(req);
        }

        public Integer getCallCount() {
            return index;
        }
    }
}
