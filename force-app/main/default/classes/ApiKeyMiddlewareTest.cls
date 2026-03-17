@IsTest
private class ApiKeyMiddlewareTest {

    @IsTest
    static void headerMode_addsDefaultHeader() {
        RequestCaptureMock mock = new RequestCaptureMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        HttpCallout.builder()
            .endpoint('https://example.com/api')
            .get()
            .use(new ApiKeyMiddleware('secret-key'))
            .build()
            .execute();
        Test.stopTest();

        System.assertEquals('secret-key', mock.lastRequest.getHeader('x-api-key'));
    }

    @IsTest
    static void headerMode_customHeaderName() {
        RequestCaptureMock mock = new RequestCaptureMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        HttpCallout.builder()
            .endpoint('https://example.com/api')
            .get()
            .use(new ApiKeyMiddleware('my-token', 'X-Auth-Token'))
            .build()
            .execute();
        Test.stopTest();

        System.assertEquals('my-token', mock.lastRequest.getHeader('X-Auth-Token'));
    }

    @IsTest
    static void queryParamMode_appendsParam() {
        RequestCaptureMock mock = new RequestCaptureMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        HttpCallout.builder()
            .endpoint('https://example.com/api')
            .get()
            .use(ApiKeyMiddleware.asQueryParam('my-key', 'api_key'))
            .build()
            .execute();
        Test.stopTest();

        String endpoint = mock.lastRequest.getEndpoint();
        System.assert(endpoint.contains('api_key=my-key'), 'Endpoint should contain api_key param: ' + endpoint);
    }

    @IsTest
    static void queryParamMode_existingQueryString_usesAmpersand() {
        RequestCaptureMock mock = new RequestCaptureMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        HttpCallout.builder()
            .endpoint('https://example.com/api?version=2')
            .get()
            .use(ApiKeyMiddleware.asQueryParam('my-key', 'api_key'))
            .build()
            .execute();
        Test.stopTest();

        String endpoint = mock.lastRequest.getEndpoint();
        System.assert(endpoint.contains('&api_key='), 'Should use & separator: ' + endpoint);
    }

    @IsTest
    static void blankApiKey_throws() {
        try {
            new ApiKeyMiddleware('');
            System.assert(false, 'Expected exception');
        } catch (HttpCallout.HttpCalloutException ex) {
            System.assert(ex.getMessage().contains('apiKey cannot be blank'), ex.getMessage());
        }
    }

    // Captures the HttpRequest for later inspection — lastRequest is an instance field (not static)
    private class RequestCaptureMock implements HttpCalloutMock {
        public HttpRequest lastRequest;

        public HttpResponse respond(HttpRequest req) {
            lastRequest = req;
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('');
            return res;
        }
    }
}
