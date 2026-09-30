using Microsoft.Extensions.Diagnostics.HealthChecks;
using Npgsql;

namespace ProjectMonitoring.Infrastructure.Persistence;

/// <summary>Healthy when PostgreSQL answers a trivial query.</summary>
public class PostgresHealthCheck(NpgsqlDataSource db) : IHealthCheck
{
    public async Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken ct = default)
    {
        try
        {
            await using var cmd = db.CreateCommand("SELECT 1");
            await cmd.ExecuteScalarAsync(ct);
            return HealthCheckResult.Healthy();
        }
        catch (Exception ex)
        {
            return new HealthCheckResult(context.Registration.FailureStatus, "PostgreSQL is not reachable", ex);
        }
    }
}
