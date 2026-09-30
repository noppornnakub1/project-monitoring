using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using Npgsql;
using ProjectMonitoring.Application.Common;

namespace ProjectMonitoring.Api.Infrastructure;

/// <summary>
/// Turns every unhandled exception into an RFC 7807 ProblemDetails response.
/// Known application / database errors get a meaningful status; anything else is a 500
/// whose details are logged but never leaked to the client.
/// </summary>
public class GlobalExceptionHandler(IProblemDetailsService problemDetails, ILogger<GlobalExceptionHandler> logger)
    : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(HttpContext ctx, Exception ex, CancellationToken ct)
    {
        var (status, title, detail) = Map(ex);

        if (status >= 500)
            logger.LogError(ex, "Unhandled exception for {Method} {Path}", ctx.Request.Method, ctx.Request.Path);
        else
            logger.LogWarning("Request failed with {Status}: {Detail}", status, detail);

        ctx.Response.StatusCode = status;
        return await problemDetails.TryWriteAsync(new ProblemDetailsContext
        {
            HttpContext = ctx,
            Exception = ex,
            ProblemDetails = new ProblemDetails { Status = status, Title = title, Detail = detail }
        });
    }

    private static (int Status, string Title, string? Detail) Map(Exception ex) => ex switch
    {
        NotFoundException e => (StatusCodes.Status404NotFound, "Resource not found", e.Message),
        ConflictException e => (StatusCodes.Status409Conflict, "Conflict", e.Message),
        BusinessRuleException e => (StatusCodes.Status400BadRequest, "Business rule violated", e.Message),
        // Safety net: constraint violations caught by PostgreSQL itself (e.g. race conditions)
        PostgresException pg => MapPostgres(pg),
        OperationCanceledException => (499, "Client closed request", null),
        _ => (StatusCodes.Status500InternalServerError, "Internal server error", "An unexpected error occurred.")
    };

    private static (int, string, string?) MapPostgres(PostgresException pg) => pg.SqlState switch
    {
        PostgresErrorCodes.UniqueViolation => (409, "Duplicate value", $"Constraint '{pg.ConstraintName}' was violated."),
        PostgresErrorCodes.ForeignKeyViolation => (409, "Related record conflict", $"Constraint '{pg.ConstraintName}' was violated."),
        PostgresErrorCodes.CheckViolation => (400, "Invalid value", $"Constraint '{pg.ConstraintName}' was violated."),
        PostgresErrorCodes.NotNullViolation => (400, "Missing value", $"Column '{pg.ColumnName}' is required."),
        _ => (500, "Database error", "An unexpected database error occurred.")
    };
}
