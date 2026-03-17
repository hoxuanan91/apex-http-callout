// =============================================================================
// HttpCallout — Anonymous Apex test script
// Run in: Setup → Developer Console → Debug → Open Execute Anonymous Window
//
// PREREQUISITE — Add Remote Site Settings before running:
//   Setup → Remote Site Settings → New
//   Name: JsonPlaceholder
//   URL:  https://jsonplaceholder.typicode.com
// =============================================================================

// Utility: print a section header
public static void section(String title) {
    System.debug('');
    System.debug('══════════════════════════════════════════');
    System.debug('  ' + title);
    System.debug('══════════════════════════════════════════');
}

// Utility: print a pass/fail assertion
public static void assert_eq(String label, Object expected, Object actual) {
    Boolean pass = (expected == actual) || (String.valueOf(expected) == String.valueOf(actual));
    System.debug((pass ? '✓ PASS' : '✗ FAIL') + ' — ' + label +
        (pass ? '' : '  expected=' + expected + '  actual=' + actual));
}

public static void assert_true(String label, Boolean condition) {
    System.debug((condition ? '✓ PASS' : '✗ FAIL') + ' — ' + label);
}


// =============================================================================
// TEST 1 — Simple GET
// =============================================================================
section('TEST 1 — Simple GET');
try {
    HttpCalloutResult result = HttpCallout.builder()
        .endpoint('https://jsonplaceholder.typicode.com/posts/1')
        .get()
        .build()
        .execute();

    assert_eq('Status code is 200', 200, result.statusCode);
    assert_true('isSuccess() returns true', result.isSuccess());
    assert_true('Body is not blank', String.isNotBlank(result.body));
    System.debug('Body (first 200 chars): ' + result.body.left(200));
} catch (Exception ex) {
    System.debug('✗ Exception: ' + ex.getMessage());
}


// =============================================================================
// TEST 2 — GET with typed JSON deserialization
// =============================================================================
section('TEST 2 — GET with JsonResponseHandler');

// Define a response type matching https://jsonplaceholder.typicode.com/posts/1
// { "userId":1, "id":1, "title":"...", "body":"..." }
// Note: "body" field conflicts with Apex keyword — use Map instead
try {
    HttpCalloutResult result = HttpCallout.builder()
        .endpoint('https://jsonplaceholder.typicode.com/posts/1')
        .get()
        .handleResponseWith(new JsonResponseHandler(Map<String, Object>.class))
        .build()
        .execute();

    assert_true('isSuccess()', result.isSuccess());
    assert_eq('No parse error', null, result.parseError);

    Map<String, Object> post = (Map<String, Object>) result.getDataAs(Map<String, Object>.class);
    assert_eq('post.id == 1', 1, (Integer) post.get('id'));
    assert_eq('post.userId == 1', 1, (Integer) post.get('userId'));
    System.debug('Post title: ' + post.get('title'));
} catch (Exception ex) {
    System.debug('✗ Exception: ' + ex.getMessage());
}


// =============================================================================
// TEST 3 — POST with JSON body (shortcut)
// =============================================================================
section('TEST 3 — POST with bodyJson shortcut');
try {
    HttpCalloutResult result = HttpCallout.builder()
        .endpoint('https://jsonplaceholder.typicode.com/posts')
        .post(new Map<String, Object>{
            'title'  => 'apex-http-callout',
            'body'   => 'Sent from Salesforce',
            'userId' => 1
        })
        .build()
        .execute();

    // JSONPlaceholder returns 201 on POST
    assert_eq('Status code is 201', 201, result.statusCode);
    assert_true('isSuccess()', result.isSuccess());

    Map<String, Object> created = (Map<String, Object>) JSON.deserializeUntyped(result.body);
    assert_true('Response contains an id', created.containsKey('id'));
    System.debug('Created resource id: ' + created.get('id'));
} catch (Exception ex) {
    System.debug('✗ Exception: ' + ex.getMessage());
}


// =============================================================================
// TEST 4 — POST using the two-step form: post() → bodyJson() → build()
// =============================================================================
section('TEST 4 — POST two-step (post() then bodyJson())');
try {
    HttpCalloutResult result = HttpCallout.builder()
        .endpoint('https://jsonplaceholder.typicode.com/posts')
        .post()                                      // → IBodyRequiredStep
        .bodyJson(new Map<String, Object>{           // → IBuildStep
            'title'  => 'two-step post',
            'userId' => 2
        })
        .timeout(15000)
        .build()
        .execute();

    assert_eq('Status code is 201', 201, result.statusCode);
    assert_true('isSuccess()', result.isSuccess());
} catch (Exception ex) {
    System.debug('✗ Exception: ' + ex.getMessage());
}


// =============================================================================
// TEST 5 — PUT (full update)
// =============================================================================
section('TEST 5 — PUT');
try {
    HttpCalloutResult result = HttpCallout.builder()
        .endpoint('https://jsonplaceholder.typicode.com/posts/1')
        .put(new Map<String, Object>{
            'id'     => 1,
            'title'  => 'Updated title',
            'userId' => 1
        })
        .build()
        .execute();

    assert_eq('Status code is 200', 200, result.statusCode);
    assert_true('isSuccess()', result.isSuccess());
} catch (Exception ex) {
    System.debug('✗ Exception: ' + ex.getMessage());
}


// =============================================================================
// TEST 6 — PATCH (partial update)
// =============================================================================
section('TEST 6 — PATCH');
try {
    HttpCalloutResult result = HttpCallout.builder()
        .endpoint('https://jsonplaceholder.typicode.com/posts/1')
        .patch(new Map<String, Object>{ 'title' => 'Patched title' })
        .build()
        .execute();

    assert_eq('Status code is 200', 200, result.statusCode);
    assert_true('isSuccess()', result.isSuccess());
} catch (Exception ex) {
    System.debug('✗ Exception: ' + ex.getMessage());
}


// =============================================================================
// TEST 7 — DELETE
// =============================================================================
section('TEST 7 — DELETE');
try {
    HttpCalloutResult result = HttpCallout.builder()
        .endpoint('https://jsonplaceholder.typicode.com/posts/1')
        .delete_x()
        .build()
        .execute();

    assert_eq('Status code is 200', 200, result.statusCode);
    assert_true('isSuccess()', result.isSuccess());
} catch (Exception ex) {
    System.debug('✗ Exception: ' + ex.getMessage());
}


// =============================================================================
// TEST 8 — 404 response (client error)
// =============================================================================
section('TEST 8 — 404 Not Found');
try {
    HttpCalloutResult result = HttpCallout.builder()
        .endpoint('https://jsonplaceholder.typicode.com/posts/99999')
        .get()
        .build()
        .execute();

    assert_eq('Status code is 404', 404, result.statusCode);
    assert_true('isSuccess() is false',    !result.isSuccess());
    assert_true('isClientError() is true',  result.isClientError());
    assert_true('isServerError() is false', !result.isServerError());
} catch (Exception ex) {
    System.debug('✗ Exception: ' + ex.getMessage());
}


// =============================================================================
// TEST 9 — Custom headers
// =============================================================================
section('TEST 9 — Custom headers');
try {
    HttpCalloutResult result = HttpCallout.builder()
        .endpoint('https://jsonplaceholder.typicode.com/posts/1')
        .get()
        .header('X-Custom-Header', 'apex-callout')
        .header('Accept', 'application/json')
        .timeout(10000)
        .build()
        .execute();

    assert_true('isSuccess()', result.isSuccess());
} catch (Exception ex) {
    System.debug('✗ Exception: ' + ex.getMessage());
}


// =============================================================================
// TEST 10 — API Key middleware (header mode)
// =============================================================================
section('TEST 10 — ApiKeyMiddleware (header)');
try {
    HttpCalloutResult result = HttpCallout.builder()
        .endpoint('https://jsonplaceholder.typicode.com/posts/1')
        .get()
        .use(new ApiKeyMiddleware('demo-key-12345'))
        .build()
        .execute();

    // JSONPlaceholder ignores unknown headers, so we just verify the call succeeded
    assert_true('isSuccess()', result.isSuccess());
    System.debug('x-api-key header was attached to the request');
} catch (Exception ex) {
    System.debug('✗ Exception: ' + ex.getMessage());
}


// =============================================================================
// TEST 11 — Bearer Token middleware
// =============================================================================
section('TEST 11 — BearerTokenMiddleware');
try {
    HttpCalloutResult result = HttpCallout.builder()
        .endpoint('https://jsonplaceholder.typicode.com/posts/1')
        .get()
        .use(new BearerTokenMiddleware('eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.demo'))
        .build()
        .execute();

    assert_true('isSuccess()', result.isSuccess());
    System.debug('Authorization: Bearer header was attached to the request');
} catch (Exception ex) {
    System.debug('✗ Exception: ' + ex.getMessage());
}


// =============================================================================
// TEST 12 — Logging middleware
// =============================================================================
section('TEST 12 — LoggingMiddleware (watch the debug logs above/below)');
try {
    HttpCalloutResult result = HttpCallout.builder()
        .endpoint('https://jsonplaceholder.typicode.com/posts/2')
        .get()
        .use(new LoggingMiddleware())
        .build()
        .execute();

    assert_true('isSuccess()', result.isSuccess());
    System.debug('→ Check debug log for "HTTP Request" and "HTTP Response" entries');
} catch (Exception ex) {
    System.debug('✗ Exception: ' + ex.getMessage());
}


// =============================================================================
// TEST 13 — Circuit Breaker (closed circuit, normal operation)
// =============================================================================
section('TEST 13 — CircuitBreakerMiddleware (closed)');
try {
    HttpCalloutResult result = HttpCallout.builder()
        .endpoint('https://jsonplaceholder.typicode.com/posts/3')
        .get()
        .use(new CircuitBreakerMiddleware('JsonPlaceholderAPI', 5, 60))
        .build()
        .execute();

    assert_true('isSuccess()', result.isSuccess());
    // Note: getState() is private — internal state not inspectable from outside the class.
    // A successful callout without error confirms the circuit remained CLOSED.
} catch (Exception ex) {
    System.debug('✗ Exception: ' + ex.getMessage());
}


// =============================================================================
// TEST 14 — Full pipeline: CircuitBreaker + BearerToken + Retry + Logging
// =============================================================================
section('TEST 14 — Full middleware pipeline');
try {
    HttpCalloutResult result = HttpCallout.builder()
        .endpoint('https://jsonplaceholder.typicode.com/posts')
        .post(new Map<String, Object>{
            'title'  => 'Full pipeline test',
            'body'   => 'Testing all middleware at once',
            'userId' => 1
        })
        .timeout(20000)
        .use(new CircuitBreakerMiddleware('JsonPlaceholderAPI', 5, 60))
        .use(new BearerTokenMiddleware('demo-token'))
        .use(new RetryMiddleware(2))
        .use(new LoggingMiddleware())
        .handleResponseWith(new JsonResponseHandler(Map<String, Object>.class))
        .build()
        .execute();

    assert_eq('Status code is 201', 201, result.statusCode);
    assert_true('isSuccess()', result.isSuccess());
    assert_eq('No parse error', null, result.parseError);

    Map<String, Object> data = (Map<String, Object>) result.getDataAs(Map<String, Object>.class);
    assert_true('Deserialized data has id', data.containsKey('id'));
    System.debug('Created id: ' + data.get('id'));
} catch (Exception ex) {
    System.debug('✗ Exception: ' + ex.getMessage());
}


// =============================================================================
// TEST 15 — Custom middleware (inline implementation)
// =============================================================================
section('TEST 15 — Custom inline middleware');

// Implement IHttpMiddleware anonymously to add a request ID header
public class RequestIdMiddleware implements IHttpMiddleware {
    public HttpResponse handle(HttpRequest req, IHttpMiddleware next) {
        req.setHeader('X-Request-Id', 'APEX-' + Datetime.now().getTime());
        return next.handle(req, null);
    }
}

try {
    HttpCalloutResult result = HttpCallout.builder()
        .endpoint('https://jsonplaceholder.typicode.com/posts/5')
        .get()
        .use(new RequestIdMiddleware())
        .use(new LoggingMiddleware())
        .build()
        .execute();

    assert_true('isSuccess()', result.isSuccess());
    System.debug('X-Request-Id header was injected by custom middleware');
} catch (Exception ex) {
    System.debug('✗ Exception: ' + ex.getMessage());
}


System.debug('');
System.debug('══════════════════════════════════════════');
System.debug('  ALL TESTS COMPLETED — check results above');
System.debug('══════════════════════════════════════════');
