@IsTest
private class ApiKeyMiddlewareTest {

    @IsTest
    static void headerMode_addsDefaultHeader() {
        Test.setMock(HttpCalloutMock.class, new RequestCaptureMock());

        Test.startTest();
        new HttpCallout.Builder()
            .endpoint('https://example.com/api')
            .get()
            .use(new ApiKeyMiddleware('secret-key'))
            .build()
            .execute();
        Test.stopTest();

        // Verified via mock capture below
        System.assertEquals('secret-key', RequestCaptureMock.lastRequest.getHeader('x-api-key'));
    }

    @IsTest
    static void headerMode_customHeaderName() {
        Test.setMock(HttpCalloutMock.class, new RequestCaptureMock());

        Test.startTest();
        new HttpCallout.Builder()
            .endpoint('https://example.com/api')
            .get()
            .use(new ApiKeyMiddleware('my-token', 'X-Auth-Token'))
            .build()
            .execute();
        Test.stopTest();

        System.assertEquals('my-token', RequestCaptureMock.lastRequest.getHeader('X-Auth-Token'));
    }

    @IsTest
    static void queryParamMode_appendsParam() {
        Test.setMock(HttpCalloutMock.class, new RequestCaptureMock());

        Test.startTest();
        new HttpCallout.Builder()
            .endpoint('https://example.com/api')
            .get()
            .use(ApiKeyMiddleware.asQueryParam('my-key', 'api_key'))
            .build()
            .execute();
        Test.stopTest();

        String endpoint = RequestCaptureMock.lastRequest.getEndpoint();
        System.assert(endpoint.contains('api_key=my-key'), 'Endpoint should contain api_key param: ' + endpoint);
    }

    @IsTest
    static void queryParamMode_existingQueryString_usesAmpersand() {
        Test.setMock(HttpCalloutMock.class, new RequestCaptureMock());

        Test.startTest();
        new HttpCallout.Builder()
            .endpoint('https://example.com/api?version=2')
            .get()
            .use(ApiKeyMiddleware.asQueryParam('my-key', 'api_key'))
            .build()
            .execute();
        Test.stopTest();

        String endpoint = RequestCaptureMock.lastRequest.getEndpoint();
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

    // Captures the last HttpRequest for inspection
    private class RequestCaptureMock implements HttpCalloutMock {
        public static HttpRequest lastRequest;

        public HttpResponse respond(HttpRequest req) {
            lastRequest = req;
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('');
            return res;
        }
    }
}
