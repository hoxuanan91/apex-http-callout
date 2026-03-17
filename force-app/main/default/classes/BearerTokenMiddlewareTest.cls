@IsTest
private class BearerTokenMiddlewareTest {

    @IsTest
    static void addsAuthorizationHeader() {
        RequestCaptureMock mock = new RequestCaptureMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        HttpCallout.builder()
            .endpoint('https://example.com/api')
            .get()
            .use(new BearerTokenMiddleware('my-token-123'))
            .build()
            .execute();
        Test.stopTest();

        System.assertEquals('Bearer my-token-123', mock.lastRequest.getHeader('Authorization'));
    }

    @IsTest
    static void blankToken_throws() {
        try {
            new BearerTokenMiddleware('');
            System.assert(false, 'Expected exception');
        } catch (HttpCallout.HttpCalloutException ex) {
            System.assert(ex.getMessage().contains('token cannot be blank'), ex.getMessage());
        }
    }

    @IsTest
    static void nullToken_throws() {
        try {
            new BearerTokenMiddleware(null);
            System.assert(false, 'Expected exception');
        } catch (HttpCallout.HttpCalloutException ex) {
            System.assert(ex.getMessage().contains('token cannot be blank'), ex.getMessage());
        }
    }

    @IsTest
    static void tokenIsAppendedCorrectly() {
        RequestCaptureMock mock = new RequestCaptureMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        HttpCallout.builder()
            .endpoint('https://example.com/api')
            .get()
            .use(new BearerTokenMiddleware('eyJhbGciOiJIUzI1NiJ9.payload.sig'))
            .build()
            .execute();
        Test.stopTest();

        String authHeader = mock.lastRequest.getHeader('Authorization');
        System.assert(authHeader.startsWith('Bearer '), 'Should start with Bearer');
        System.assertEquals('Bearer eyJhbGciOiJIUzI1NiJ9.payload.sig', authHeader);
    }

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
