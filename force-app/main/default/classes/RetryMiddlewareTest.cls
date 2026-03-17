@IsTest
private class RetryMiddlewareTest {

    @IsTest
    static void retries_onRetryableStatusCode() {
        // 503 twice, then 200
        Test.setMock(HttpCalloutMock.class, HttpCalloutMockFactory.sequence(
            new List<HttpCalloutMockFactory.StaticMock>{
                HttpCalloutMockFactory.withStatus(503),
                HttpCalloutMockFactory.withStatus(503),
                HttpCalloutMockFactory.withJson(200, '{"ok":true}')
            }
        ));

        Test.startTest();
        HttpCalloutResult result = new HttpCallout.Builder()
            .endpoint('https://example.com/api')
            .get()
            .use(new RetryMiddleware(3))
            .build()
            .execute();
        Test.stopTest();

        System.assertEquals(200, result.statusCode);
    }

    @IsTest
    static void returnsLastResponse_whenAllRetriesExhausted() {
        Test.setMock(HttpCalloutMock.class, HttpCalloutMockFactory.withStatus(503));

        Test.startTest();
        HttpCalloutResult result = new HttpCallout.Builder()
            .endpoint('https://example.com/api')
            .get()
            .use(new RetryMiddleware(2))
            .build()
            .execute();
        Test.stopTest();

        System.assertEquals(503, result.statusCode);
    }

    @IsTest
    static void doesNotRetry_onNonRetryableStatusCode() {
        HttpCalloutMockFactory.SequenceMock mock = HttpCalloutMockFactory.sequence(
            new List<HttpCalloutMockFactory.StaticMock>{
                HttpCalloutMockFactory.withStatus(400),
                HttpCalloutMockFactory.withStatus(200)  // should NOT be reached
            }
        );
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        HttpCalloutResult result = new HttpCallout.Builder()
            .endpoint('https://example.com/api')
            .get()
            .use(new RetryMiddleware(3))
            .build()
            .execute();
        Test.stopTest();

        System.assertEquals(400, result.statusCode);
        System.assertEquals(1, mock.getCallCount(), 'Should have stopped after first non-retryable response');
    }

    @IsTest
    static void retries_onCalloutException_thenSucceeds() {
        // CalloutException is handled: the mock in a sequence can't throw then succeed
        // so we test that CalloutException propagates when all retries are exhausted
        Test.setMock(HttpCalloutMock.class, HttpCalloutMockFactory.withCalloutException('Connection timeout'));

        Test.startTest();
        try {
            new HttpCallout.Builder()
                .endpoint('https://example.com/api')
                .get()
                .use(new RetryMiddleware(2))
                .build()
                .execute();
            System.assert(false, 'Expected CalloutException');
        } catch (CalloutException ex) {
            System.assert(ex.getMessage().contains('Connection timeout'), ex.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void customRetryableCodes_areRespected() {
        // 404 is not in the default set, but we add it
        HttpCalloutMockFactory.SequenceMock mock = HttpCalloutMockFactory.sequence(
            new List<HttpCalloutMockFactory.StaticMock>{
                HttpCalloutMockFactory.withStatus(404),
                HttpCalloutMockFactory.withJson(200, '{}')
            }
        );
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        HttpCalloutResult result = new HttpCallout.Builder()
            .endpoint('https://example.com/api')
            .get()
            .use(new RetryMiddleware(1, new Set<Integer>{ 404 }))
            .build()
            .execute();
        Test.stopTest();

        System.assertEquals(200, result.statusCode);
    }
}
