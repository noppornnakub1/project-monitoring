namespace ProjectMonitoring.Application.Reports;

public record DepartmentProgressRow
{
    public int DepartmentId { get; init; }
    public string DepartmentName { get; init; } = "";
    public int TotalProjects { get; init; }
    public int ActiveProjects { get; init; }
    public int CompletedProjects { get; init; }
    public int TotalTasks { get; init; }
    public int DoneTasks { get; init; }
    public int InProgressTasks { get; init; }
    public int OverdueTasks { get; init; }
    public decimal CompletionRate { get; init; }
    public decimal AvgProgress { get; init; }
    public int ProgressRank { get; init; }
}

public record ProjectProgressRow
{
    public int ProjectId { get; init; }
    public string ProjectName { get; init; } = "";
    public string DepartmentName { get; init; } = "";
    public string? OwnerName { get; init; }
    public string Status { get; init; } = "";
    public DateOnly? EndDate { get; init; }
    public int TotalTasks { get; init; }
    public int DoneTasks { get; init; }
    public int OverdueTasks { get; init; }
    public decimal AvgProgress { get; init; }
    public bool IsLate { get; init; }
}

public record UserWorkloadRow
{
    public int UserId { get; init; }
    public string FullName { get; init; } = "";
    public string DepartmentName { get; init; } = "";
    public int OpenTasks { get; init; }
    public int CriticalOpenTasks { get; init; }
    public int OverdueTasks { get; init; }
    public int DoneLastMonth { get; init; }
}

/// <summary>Backed by the fn_report_* PostgreSQL functions (db/init/01-schema.sql).</summary>
public interface IReportQueries
{
    Task<IReadOnlyList<DepartmentProgressRow>> DepartmentProgressAsync(int? departmentId, CancellationToken ct);
    Task<IReadOnlyList<ProjectProgressRow>> ProjectProgressAsync(int? departmentId, string? status, CancellationToken ct);
    Task<IReadOnlyList<UserWorkloadRow>> UserWorkloadAsync(int? departmentId, CancellationToken ct);
}

public class ReportService(IReportQueries queries)
{
    public Task<IReadOnlyList<DepartmentProgressRow>> DepartmentProgressAsync(int? departmentId, CancellationToken ct) =>
        queries.DepartmentProgressAsync(departmentId, ct);

    public Task<IReadOnlyList<ProjectProgressRow>> ProjectProgressAsync(int? departmentId, string? status, CancellationToken ct) =>
        queries.ProjectProgressAsync(departmentId, status, ct);

    public Task<IReadOnlyList<UserWorkloadRow>> UserWorkloadAsync(int? departmentId, CancellationToken ct) =>
        queries.UserWorkloadAsync(departmentId, ct);
}
