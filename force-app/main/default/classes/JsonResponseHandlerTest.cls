@IsTest
private class JsonResponseHandlerTest {

    // DTO used across all tests — avoids Map<String,Object>.class which is unsupported by JSON.deserialize
    private class PostDto {
        public String name;
        public Integer value;
    }

    @IsTest
    static void successResponse_deserializesBody() {
        Test.setMock(HttpCalloutMock.class, HttpCalloutMockFactory.withJson(200, '{"name":"Test","value":42}'));

        Test.startTest();
        HttpCalloutResult result = HttpCallout.builder()
            .endpoint('https://example.com/api/item')
            .get()
            .handleResponseWith(new JsonResponseHandler(PostDto.class))
            .build()
            .execute();
        Test.stopTest();

        System.assert(result.isSuccess());
        System.assertEquals(null, result.parseError);

        PostDto post = (PostDto) result.getDataAs(PostDto.class);
        System.assertEquals('Test', post.name);
        System.assertEquals(42, post.value);
    }

    @IsTest
    static void errorResponse_doesNotDeserialize() {
        Test.setMock(HttpCalloutMock.class, HttpCalloutMockFactory.withJson(404, '{"error":"Not found"}'));

        Test.startTest();
        HttpCalloutResult result = HttpCallout.builder()
            .endpoint('https://example.com/api/item')
            .get()
            .handleResponseWith(new JsonResponseHandler(PostDto.class))
            .build()
            .execute();
        Test.stopTest();

        System.assert(!result.isSuccess());
        System.assertEquals(null, result.data, 'Data should not be set on error response');
    }

    @IsTest
    static void invalidJson_setsParseError() {
        Test.setMock(HttpCalloutMock.class, HttpCalloutMockFactory.withBody(200, 'not-valid-json'));

        Test.startTest();
        HttpCalloutResult result = HttpCallout.builder()
            .endpoint('https://example.com/api/item')
            .get()
            .handleResponseWith(new JsonResponseHandler(PostDto.class))
            .build()
            .execute();
        Test.stopTest();

        System.assert(result.isSuccess());
        System.assertNotEquals(null, result.parseError, 'parseError should be set on invalid JSON');
    }

    @IsTest
    static void emptyBody_skipsDeserialization() {
        Test.setMock(HttpCalloutMock.class, HttpCalloutMockFactory.withStatus(204));

        Test.startTest();
        HttpCalloutResult result = HttpCallout.builder()
            .endpoint('https://example.com/api/item')
            .get()
            .handleResponseWith(new JsonResponseHandler(PostDto.class))
            .build()
            .execute();
        Test.stopTest();

        System.assertEquals(null, result.data);
        System.assertEquals(null, result.parseError);
    }

    @IsTest
    static void nullType_throws() {
        try {
            new JsonResponseHandler(null);
            System.assert(false, 'Expected exception');
        } catch (HttpCallout.HttpCalloutException ex) {
            System.assert(ex.getMessage().contains('responseType cannot be null'), ex.getMessage());
        }
    }
}
