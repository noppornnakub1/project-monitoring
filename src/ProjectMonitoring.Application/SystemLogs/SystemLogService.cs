using System.Text.Json;
using ProjectMonitoring.Application.Common;

namespace ProjectMonitoring.Application.SystemLogs;

public record SystemLogDto
{
    public long Id { get; init; }
    public string Level { get; init; } = "";
    public string Source { get; init; } = "";
    public string Action { get; init; } = "";
    public int? EntityId { get; init; }
    public string Message { get; init; } = "";
    public JsonElement Context { get; init; }
    public int? UserId { get; init; }
    public DateTime CreatedAt { get; init; }
}

public class SystemLogQuery : PageQuery
{
    public string? Source { get; set; }
    public string? Action { get; set; }
    public int? EntityId { get; set; }
    public string? Level { get; set; }
    public DateTime? From { get; set; }
    public DateTime? To { get; set; }
}

public interface ISystemLogRepository
{
    Task<PagedResult<SystemLogDto>> ListAsync(SystemLogQuery query, CancellationToken ct);
}

public class SystemLogService(ISystemLogRepository repo)
{
    public Task<PagedResult<SystemLogDto>> ListAsync(SystemLogQuery query, CancellationToken ct) => repo.ListAsync(query, ct);
}
