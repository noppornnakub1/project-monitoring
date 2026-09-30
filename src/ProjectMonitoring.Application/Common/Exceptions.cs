namespace ProjectMonitoring.Application.Common;

/// <summary>Base type for errors that are safe to show to API clients.</summary>
public abstract class AppException(string message) : Exception(message);

/// <summary>Maps to 404.</summary>
public sealed class NotFoundException(string entity, object key)
    : AppException($"{entity} with id '{key}' was not found.");

/// <summary>Maps to 409 (duplicate, still referenced, ...).</summary>
public sealed class ConflictException(string message) : AppException(message);

/// <summary>Maps to 400 for rule violations that DataAnnotations cannot express.</summary>
public sealed class BusinessRuleException(string message) : AppException(message);
