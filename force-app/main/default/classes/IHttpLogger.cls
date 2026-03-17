/**
 * @description Logger abstraction for the HTTP callout library.
 *
 * Implement this interface to integrate with your preferred logging framework
 * (e.g. Nebula Logger, custom platform event logging, etc.).
 * The default implementation is `SystemDebugLogger`, which writes to System.debug.
 *
 * @see SystemDebugLogger
 *
 * @example
 * public class NebulaHttpLogger implements IHttpLogger {
 *     public void debug(String msg, Map<String, Object> ctx) { Logger.debug(msg).addField('context', ctx); }
 *     public void info(String msg, Map<String, Object> ctx)  { Logger.info(msg).addField('context', ctx);  }
 *     public void warn(String msg, Map<String, Object> ctx)  { Logger.warn(msg).addField('context', ctx);  }
 *     public void error(String msg, Map<String, Object> ctx) { Logger.error(msg).addField('context', ctx); }
 * }
 */
public interface IHttpLogger {
    void debug(String message, Map<String, Object> context);
    void info(String message, Map<String, Object> context);
    void warn(String message, Map<String, Object> context);
    void error(String message, Map<String, Object> context);
}
