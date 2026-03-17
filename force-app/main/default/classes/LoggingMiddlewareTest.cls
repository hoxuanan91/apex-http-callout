@IsTest
private class LoggingMiddlewareTest {

    @IsTest
    static void defaultConstructor_usesSystemDebugLogger() {
        Test.setMock(HttpCalloutMock.class, HttpCalloutMockFactory.withJson(200, '{}'));

        Test.startTest();
        HttpCalloutResult result = HttpCallout.builder()
            .endpoint('https://example.com/api')
            .get()
            .use(new LoggingMiddleware())
            .build()
            .execute();
        Test.stopTest();

        System.assertEquals(200, result.statusCode);
    }

    @IsTest
    static void customLogger_receivesLogMessages() {
        Test.setMock(HttpCalloutMock.class, HttpCalloutMockFactory.withJson(200, '{}'));
        SpyLogger spy = new SpyLogger();

        Test.startTest();
        HttpCallout.builder()
            .endpoint('https://example.com/api')
            .get()
            .use(new LoggingMiddleware(spy))
            .build()
            .execute();
        Test.stopTest();

        System.assertEquals(2, spy.infoCalls, 'Expected request + response log calls');
    }

    @IsTest
    static void nullLogger_fallsBackToSystemDebug() {
        Test.setMock(HttpCalloutMock.class, HttpCalloutMockFactory.withStatus(200));

        Test.startTest();
        HttpCallout.builder()
            .endpoint('https://example.com/api')
            .get()
            .use(new LoggingMiddleware(null))
            .build()
            .execute();
        Test.stopTest();
    }

    @IsTest
    static void onException_logsError_andRethrows() {
        Test.setMock(HttpCalloutMock.class, HttpCalloutMockFactory.withCalloutException('Network error'));
        SpyLogger spy = new SpyLogger();

        Test.startTest();
        try {
            HttpCallout.builder()
                .endpoint('https://example.com/api')
                .get()
                .use(new LoggingMiddleware(spy))
                .build()
                .execute();
            System.assert(false, 'Expected CalloutException');
        } catch (CalloutException ex) {
            System.assert(ex.getMessage().contains('Network error'));
        }
        Test.stopTest();

        System.assertEquals(1, spy.infoCalls,  'Request should be logged');
        System.assertEquals(1, spy.errorCalls, 'Error should be logged');
    }

    private class SpyLogger implements IHttpLogger {
        public Integer debugCalls = 0;
        public Integer infoCalls  = 0;
        public Integer warnCalls  = 0;
        public Integer errorCalls = 0;

        public void debug(String msg, Map<String, Object> ctx) { debugCalls++; }
        public void info(String msg, Map<String, Object> ctx)  { infoCalls++;  }
        public void warn(String msg, Map<String, Object> ctx)  { warnCalls++;  }
        public void error(String msg, Map<String, Object> ctx) { errorCalls++; }
    }
}
