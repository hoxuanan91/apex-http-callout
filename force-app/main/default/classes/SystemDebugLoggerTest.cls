@IsTest
private class SystemDebugLoggerTest {

    @IsTest
    static void allLevels_doNotThrow() {
        SystemDebugLogger logger = new SystemDebugLogger();
        Map<String, Object> ctx = new Map<String, Object>{ 'key' => 'value' };

        // All four log levels must execute without exception
        Test.startTest();
        logger.debug('debug message', ctx);
        logger.info('info message', ctx);
        logger.warn('warn message', ctx);
        logger.error('error message', ctx);
        Test.stopTest();
    }

    @IsTest
    static void nullContext_doesNotThrow() {
        SystemDebugLogger logger = new SystemDebugLogger();

        Test.startTest();
        logger.debug('debug', null);
        logger.info('info', null);
        logger.warn('warn', null);
        logger.error('error', null);
        Test.stopTest();
    }

    @IsTest
    static void emptyContext_doesNotThrow() {
        SystemDebugLogger logger = new SystemDebugLogger();
        Map<String, Object> empty = new Map<String, Object>();

        Test.startTest();
        logger.debug('debug', empty);
        logger.info('info', empty);
        logger.warn('warn', empty);
        logger.error('error', empty);
        Test.stopTest();
    }
}
