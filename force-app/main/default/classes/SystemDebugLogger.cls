/**
 * @description Default IHttpLogger implementation that writes to System.debug.
 *
 * Used automatically by LoggingMiddleware when no custom logger is provided.
 * For production-grade logging, implement IHttpLogger with your preferred framework.
 *
 * @see IHttpLogger
 */
public class SystemDebugLogger implements IHttpLogger {

    public void debug(String message, Map<String, Object> context) {
        System.debug(LoggingLevel.DEBUG, format(message, context));
    }

    public void info(String message, Map<String, Object> context) {
        System.debug(LoggingLevel.INFO, format(message, context));
    }

    public void warn(String message, Map<String, Object> context) {
        System.debug(LoggingLevel.WARN, format(message, context));
    }

    public void error(String message, Map<String, Object> context) {
        System.debug(LoggingLevel.ERROR, format(message, context));
    }

    private String format(String message, Map<String, Object> context) {
        if (context == null || context.isEmpty()) {
            return message;
        }
        return message + ' ' + JSON.serialize(context);
    }
}
