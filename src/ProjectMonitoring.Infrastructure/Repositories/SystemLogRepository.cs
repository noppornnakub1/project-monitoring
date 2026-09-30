using Npgsql;
using ProjectMonitoring.Application.Common;
using ProjectMonitoring.Application.SystemLogs;
using ProjectMonitoring.Infrastructure.Persistence;

namespace ProjectMonitoring.Infrastructure.Repositories;

public class SystemLogRepository(NpgsqlDataSource db) : ISystemLogRepository
{
    public Task<PagedResult<SystemLogDto>> ListAsync(SystemLogQuery q, CancellationToken ct) =>
        db.QueryPagedFunctionAsync<SystemLogDto>("fn_system_log_list",
            new
            {
                q.Source, q.Action, q.Level, q.EntityId,
                // timestamptz parameters must be UTC for Npgsql
                From = q.From?.ToUniversalTime(),
                To = q.To?.ToUniversalTime()
            }, q, ct);
}
