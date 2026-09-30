using Microsoft.AspNetCore.Mvc;
using ProjectMonitoring.Application.Common;
using ProjectMonitoring.Application.SystemLogs;

namespace ProjectMonitoring.Api.Controllers;

/// <summary>Read-only audit trail, written by PostgreSQL triggers on projects/tasks.</summary>
[ApiController]
[Route("api/system-logs")]
public class SystemLogsController(SystemLogService service) : ControllerBase
{
    [HttpGet]
    public Task<PagedResult<SystemLogDto>> List([FromQuery] SystemLogQuery query, CancellationToken ct) =>
        service.ListAsync(query, ct);
}
