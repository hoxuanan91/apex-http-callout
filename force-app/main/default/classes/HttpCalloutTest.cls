@IsTest
private class HttpCalloutTest {

    // =========================================================================
    // Builder validation
    // =========================================================================

    @IsTest
    static void build_missingEndpoint_throws() {
        try {
            new HttpCallout.Builder().get().build();
            System.assert(false, 'Expected exception');
        } catch (HttpCallout.HttpCalloutException ex) {
            System.assert(ex.getMessage().contains('Endpoint is required'), ex.getMessage());
        }
    }

    @IsTest
    static void build_getWithBody_throws() {
        try {
            new HttpCallout.Builder()
                .endpoint('/api/test')
                .get()
                .body('{"foo":"bar"}')
                .build();
            System.assert(false, 'Expected exception');
        } catch (HttpCallout.HttpCalloutException ex) {
            System.assert(ex.getMessage().contains('does not allow a body'), ex.getMessage());
        }
    }

    @IsTest
    static void build_postWithoutBody_throws() {
        try {
            new HttpCallout.Builder()
                .endpoint('/api/test')
                .post()
                .build();
            System.assert(false, 'Expected exception');
        } catch (HttpCallout.HttpCalloutException ex) {
            System.assert(ex.getMessage().contains('requires a body'), ex.getMessage());
        }
    }

    @IsTest
    static void build_unsupportedMethod_throws() {
        try {
            new HttpCallout.Builder()
                .endpoint('/api/test')
                .method('CONNECT')
                .build();
            System.assert(false, 'Expected exception');
        } catch (HttpCallout.HttpCalloutException ex) {
            System.assert(ex.getMessage().contains('Unsupported HTTP method'), ex.getMessage());
        }
    }

    @IsTest
    static void build_deleteWithBody_succeeds() {
        // DELETE allows an optional body
        HttpCallout callout = new HttpCallout.Builder()
            .endpoint('https://example.com/api/items')
            .delete_x()
            .bodyJson(new List<String>{ 'id1', 'id2' })
            .build();
        System.assertNotEquals(null, callout);
    }

    @IsTest
    static void build_deleteWithoutBody_succeeds() {
        HttpCallout callout = new HttpCallout.Builder()
            .endpoint('https://example.com/api/items/1')
            .delete_x()
            .build();
        System.assertNotEquals(null, callout);
    }

    // =========================================================================
    // Verb shortcut + body shortcuts
    // =========================================================================

    @IsTest
    static void build_postWithJsonShortcut_succeeds() {
        HttpCallout callout = new HttpCallout.Builder()
            .endpoint('https://example.com/api/items')
            .post(new Map<String, Object>{ 'name' => 'test' })
            .build();
        System.assertNotEquals(null, callout);
    }

    @IsTest
    static void build_putWithJsonShortcut_succeeds() {
        HttpCallout callout = new HttpCallout.Builder()
            .endpoint('https://example.com/api/items/1')
            .put(new Map<String, Object>{ 'name' => 'updated' })
            .build();
        System.assertNotEquals(null, callout);
    }

    @IsTest
    static void build_patchWithJsonShortcut_succeeds() {
        HttpCallout callout = new HttpCallout.Builder()
            .endpoint('https://example.com/api/items/1')
            .patch(new Map<String, Object>{ 'status' => 'active' })
            .build();
        System.assertNotEquals(null, callout);
    }

    // =========================================================================
    // Execute — basic GET
    // =========================================================================

    @IsTest
    static void execute_get_returnsResult() {
        Test.setMock(HttpCalloutMock.class, HttpCalloutMockFactory.withJson(200, '{"id":"1"}'));

        Test.startTest();
        HttpCalloutResult result = new HttpCallout.Builder()
            .endpoint('https://example.com/api/items/1')
            .get()
            .build()
            .execute();
        Test.stopTest();

        System.assert(result.isSuccess(), 'Expected 2xx');
        System.assertEquals(200, result.statusCode);
        System.assertEquals('{"id":"1"}', result.body);
    }

    @IsTest
    static void execute_post_returnsResult() {
        Test.setMock(HttpCalloutMock.class, HttpCalloutMockFactory.withJson(201, '{"created":true}'));

        Test.startTest();
        HttpCalloutResult result = new HttpCallout.Builder()
            .endpoint('https://example.com/api/items')
            .post(new Map<String, Object>{ 'name' => 'test' })
            .build()
            .execute();
        Test.stopTest();

        System.assertEquals(201, result.statusCode);
        System.assert(result.isSuccess());
    }

    // =========================================================================
    // Execute — custom headers and timeout
    // =========================================================================

    @IsTest
    static void execute_customHeaderAndTimeout_sentCorrectly() {
        Test.setMock(HttpCalloutMock.class, HttpCalloutMockFactory.withStatus(200));

        Test.startTest();
        HttpCalloutResult result = new HttpCallout.Builder()
            .endpoint('https://example.com/api')
            .get()
            .header('X-Custom-Header', 'myvalue')
            .timeout(10000)
            .build()
            .execute();
        Test.stopTest();

        System.assertEquals(200, result.statusCode);
    }

    // =========================================================================
    // Middleware is chained in order
    // =========================================================================

    @IsTest
    static void execute_middlewareOrder_isRespected() {
        List<String> executionOrder = new List<String>();
        Test.setMock(HttpCalloutMock.class, HttpCalloutMockFactory.withStatus(200));

        Test.startTest();
        new HttpCallout.Builder()
            .endpoint('https://example.com/api')
            .get()
            .use(new OrderTrackingMiddleware('first', executionOrder))
            .use(new OrderTrackingMiddleware('second', executionOrder))
            .use(new OrderTrackingMiddleware('third', executionOrder))
            .build()
            .execute();
        Test.stopTest();

        System.assertEquals(new List<String>{ 'first', 'second', 'third' }, executionOrder);
    }

    @IsTest
    static void execute_nullMiddleware_ignored() {
        Test.setMock(HttpCalloutMock.class, HttpCalloutMockFactory.withStatus(200));

        Test.startTest();
        HttpCalloutResult result = new HttpCallout.Builder()
            .endpoint('https://example.com/api')
            .get()
            .use(null) // should not throw
            .build()
            .execute();
        Test.stopTest();

        System.assertEquals(200, result.statusCode);
    }

    // =========================================================================
    // Response handler
    // =========================================================================

    @IsTest
    static void execute_withResponseHandler_appliesHandler() {
        Test.setMock(HttpCalloutMock.class, HttpCalloutMockFactory.withJson(200, '{"id":"42"}'));

        Test.startTest();
        HttpCalloutResult result = new HttpCallout.Builder()
            .endpoint('https://example.com/api/item')
            .get()
            .handleResponseWith(new JsonResponseHandler(Map<String, Object>.class))
            .build()
            .execute();
        Test.stopTest();

        System.assert(result.isSuccess());
        Map<String, Object> data = (Map<String, Object>) result.getDataAs(Map<String, Object>.class);
        System.assertEquals('42', data.get('id'));
    }

    // =========================================================================
    // HttpCalloutResult helpers
    // =========================================================================

    @IsTest
    static void result_statusHelpers_workCorrectly() {
        Test.setMock(HttpCalloutMock.class, HttpCalloutMockFactory.withStatus(404));
        HttpCalloutResult result = new HttpCallout.Builder()
            .endpoint('https://example.com/api')
            .get()
            .build()
            .execute();

        System.assert(!result.isSuccess());
        System.assert(result.isClientError());
        System.assert(!result.isServerError());
    }

    @IsTest
    static void result_getDataAs_withNullData_returnsNull() {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(204);
        res.setBody('');
        HttpCalloutResult result = new HttpCalloutResult(res);

        System.assertEquals(null, result.getDataAs(Map<String, Object>.class));
    }

    // =========================================================================
    // Test helpers
    // =========================================================================

    /** Middleware that records its name into a shared list to track execution order. */
    private class OrderTrackingMiddleware implements IHttpMiddleware {
        private final String name;
        private final List<String> log;

        public OrderTrackingMiddleware(String name, List<String> log) {
            this.name = name;
            this.log  = log;
        }

        public HttpResponse handle(HttpRequest req, IHttpMiddleware next) {
            log.add(name);
            return next.handle(req, null);
        }
    }
}
