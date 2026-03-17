@IsTest
private class HttpCalloutQueueableTest {

    // -------------------------------------------------------------------------
    // Test callback implementation
    // -------------------------------------------------------------------------

    private class TestCallback implements IHttpCalloutCallback {
        public HttpCalloutResult result;
        public Exception error;

        public void onSuccess(HttpCalloutResult result) {
            this.result = result;
        }

        public void onFailure(Exception ex) {
            this.error = ex;
        }
    }

    // -------------------------------------------------------------------------
    // executeAsync() — verifies job is enqueued
    // -------------------------------------------------------------------------

    @IsTest
    static void executeAsync_returnsJobId() {
        Test.setMock(HttpCalloutMock.class, new HttpCalloutMockFactory.StaticMock(200, 'ok'));

        Test.startTest();
        Id jobId = HttpCallout.builder()
            .endpoint('https://api.example.com/test')
            .get()
            .build()
            .executeAsync(null);
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'executeAsync should return a Queueable job Id');
    }

    @IsTest
    static void executeAsync_nullCallback_noException() {
        Test.setMock(HttpCalloutMock.class, new HttpCalloutMockFactory.StaticMock(200, 'ok'));

        Test.startTest();
        Id jobId = HttpCallout.builder()
            .endpoint('https://api.example.com/test')
            .get()
            .build()
            .executeAsync(null);
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Job should be enqueued even with null callback');
    }

    // -------------------------------------------------------------------------
    // HttpCalloutQueueable.execute() — tested directly to assert callback behavior.
    // Queueable jobs run in an isolated context so the callback instance inside
    // the job is a separate copy — direct execution is the correct way to verify
    // callback behavior in unit tests.
    // -------------------------------------------------------------------------

    @IsTest
    static void execute_success_callsOnSuccess() {
        Test.setMock(HttpCalloutMock.class, new HttpCalloutMockFactory.StaticMock(200, '{"id":1}'));
        TestCallback cb = new TestCallback();

        HttpCallout callout = HttpCallout.builder()
            .endpoint('https://api.example.com/test')
            .get()
            .build();

        Test.startTest();
        new HttpCalloutQueueable(callout, cb).execute(null);
        Test.stopTest();

        System.assertNotEquals(null, cb.result, 'onSuccess should have been called');
        System.assertEquals(200, cb.result.statusCode, 'Status code should be 200');
        System.assertEquals(null, cb.error, 'onFailure should not have been called');
    }

    @IsTest
    static void execute_errorResponse_callsOnSuccessWithErrorStatus() {
        Test.setMock(HttpCalloutMock.class, new HttpCalloutMockFactory.StaticMock(500, 'Internal Server Error'));
        TestCallback cb = new TestCallback();

        HttpCallout callout = HttpCallout.builder()
            .endpoint('https://api.example.com/test')
            .get()
            .build();

        Test.startTest();
        new HttpCalloutQueueable(callout, cb).execute(null);
        Test.stopTest();

        // 500 is a valid HTTP response — onSuccess is called, caller checks isServerError()
        System.assertNotEquals(null, cb.result, 'onSuccess should be called for HTTP error responses');
        System.assertEquals(500, cb.result.statusCode, 'Status code should be 500');
        System.assert(cb.result.isServerError(), 'isServerError() should be true');
        System.assertEquals(null, cb.error, 'onFailure should not be called for HTTP error codes');
    }

    @IsTest
    static void execute_calloutException_callsOnFailure() {
        Test.setMock(HttpCalloutMock.class, HttpCalloutMockFactory.withCalloutException('Simulated network error'));
        TestCallback cb = new TestCallback();

        HttpCallout callout = HttpCallout.builder()
            .endpoint('https://api.example.com/test')
            .get()
            .build();

        Test.startTest();
        new HttpCalloutQueueable(callout, cb).execute(null);
        Test.stopTest();

        System.assertNotEquals(null, cb.error, 'onFailure should have been called');
        System.assertEquals(null, cb.result, 'onSuccess should not have been called');
    }

    @IsTest
    static void execute_nullCallback_noException() {
        Test.setMock(HttpCalloutMock.class, new HttpCalloutMockFactory.StaticMock(200, 'ok'));

        HttpCallout callout = HttpCallout.builder()
            .endpoint('https://api.example.com/test')
            .get()
            .build();

        Test.startTest();
        new HttpCalloutQueueable(callout, null).execute(null);  // must not throw
        Test.stopTest();
    }

    @IsTest
    static void execute_withMiddleware_executesCorrectly() {
        Test.setMock(HttpCalloutMock.class, new HttpCalloutMockFactory.StaticMock(201, '{"id":99}'));
        TestCallback cb = new TestCallback();

        HttpCallout callout = HttpCallout.builder()
            .endpoint('https://api.example.com/orders')
            .post(new Map<String, Object>{ 'ref' => 'ORD-001' })
            .use(new LoggingMiddleware())
            .handleResponseWith(new JsonResponseHandler(Map<String, Object>.class))
            .build();

        Test.startTest();
        new HttpCalloutQueueable(callout, cb).execute(null);
        Test.stopTest();

        System.assertNotEquals(null, cb.result, 'onSuccess should have been called');
        System.assertEquals(201, cb.result.statusCode, 'Status code should be 201');
    }
}
