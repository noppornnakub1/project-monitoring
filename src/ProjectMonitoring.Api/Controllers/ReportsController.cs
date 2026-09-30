using System.Text;
using Microsoft.AspNetCore.Mvc;
using ProjectMonitoring.Application.Reports;

namespace ProjectMonitoring.Api.Controllers;

/// <summary>Summary reports. Every endpoint accepts <c>?format=json</c> (default) or <c>?format=csv</c>.</summary>
[ApiController]
[Route("api/reports")]
public class ReportsController(ReportService service) : ControllerBase
{
    /// <summary>Task progress per department (completion %, average progress, overdue tasks, rank).</summary>
    [HttpGet("department-progress")]
    public async Task<IActionResult> DepartmentProgress(
        [FromQuery] int? departmentId, [FromQuery] ReportFormat format, CancellationToken ct) =>
        Render(await service.DepartmentProgressAsync(departmentId, ct), format, "department-progress");

    /// <summary>Progress per project, late projects first.</summary>
    [HttpGet("project-progress")]
    public async Task<IActionResult> ProjectProgress(
        [FromQuery] int? departmentId, [FromQuery] string? status, [FromQuery] ReportFormat format, CancellationToken ct) =>
        Render(await service.ProjectProgressAsync(departmentId, status, ct), format, "project-progress");

    /// <summary>Open / overdue / recently finished tasks per active user.</summary>
    [HttpGet("user-workload")]
    public async Task<IActionResult> UserWorkload(
        [FromQuery] int? departmentId, [FromQuery] ReportFormat format, CancellationToken ct) =>
        Render(await service.UserWorkloadAsync(departmentId, ct), format, "user-workload");

    private IActionResult Render<T>(IReadOnlyList<T> rows, ReportFormat format, string name)
    {
        if (format == ReportFormat.Json)
            return Ok(new { generatedAt = DateTime.UtcNow, count = rows.Count, data = rows });

        // UTF-8 BOM so Excel shows Thai text correctly
        var bytes = Encoding.UTF8.GetPreamble().Concat(Encoding.UTF8.GetBytes(CsvWriter.Write(rows))).ToArray();
        return File(bytes, "text/csv; charset=utf-8", $"{name}-{DateTime.UtcNow:yyyyMMdd-HHmmss}.csv");
    }
}

public enum ReportFormat { Json, Csv }
