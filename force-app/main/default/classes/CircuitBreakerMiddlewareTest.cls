@IsTest
private class CircuitBreakerMiddlewareTest {

    @IsTest
    static void closedCircuit_allowsRequests() {
        CircuitBreakerMiddleware.resetAll();
        Test.setMock(HttpCalloutMock.class, HttpCalloutMockFactory.withJson(200, '{}'));

        Test.startTest();
        HttpCalloutResult result = HttpCallout.builder()
            .endpoint('https://example.com/api')
            .get()
            .use(new CircuitBreakerMiddleware('TestService', 5, 60))
            .build()
            .execute();
        Test.stopTest();

        System.assertEquals(200, result.statusCode);
    }

    @IsTest
    static void circuit_opensAfterThresholdFailures() {
        CircuitBreakerMiddleware.resetAll();
        Test.setMock(HttpCalloutMock.class, HttpCalloutMockFactory.withStatus(500));

        CircuitBreakerMiddleware cbm = new CircuitBreakerMiddleware('TestService', 2, 60);

        CircuitBreakerMiddleware.CircuitState state = cbm.getState();
        state.recordFailure(2, 'TestService');
        state.recordFailure(2, 'TestService');

        Test.startTest();
        try {
            HttpCallout.builder()
                .endpoint('https://example.com/api')
                .get()
                .use(cbm)
                .build()
                .execute();
            System.assert(false, 'Expected circuit breaker to throw');
        } catch (HttpCallout.HttpCalloutException ex) {
            System.assert(ex.getMessage().contains('OPEN'), ex.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void closedCircuit_recordsSuccess_andResets() {
        CircuitBreakerMiddleware.resetAll();

        CircuitBreakerMiddleware cbm = new CircuitBreakerMiddleware('TestService', 5, 60);
        CircuitBreakerMiddleware.CircuitState state = cbm.getState();
        state.recordFailure(5, 'TestService');
        state.recordFailure(5, 'TestService');

        state.recordSuccess('TestService');

        System.assertEquals(0, state.getFailureCount());
        System.assertEquals('CLOSED', state.getStatus());
    }

    @IsTest
    static void blankServiceName_throws() {
        try {
            new CircuitBreakerMiddleware('');
            System.assert(false, 'Expected exception');
        } catch (HttpCallout.HttpCalloutException ex) {
            System.assert(ex.getMessage().contains('serviceName is required'), ex.getMessage());
        }
    }
}
