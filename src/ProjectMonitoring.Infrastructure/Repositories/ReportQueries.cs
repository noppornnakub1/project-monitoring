using Npgsql;
using ProjectMonitoring.Application.Reports;
using ProjectMonitoring.Infrastructure.Persistence;

namespace ProjectMonitoring.Infrastructure.Repositories;

public class ReportQueries(NpgsqlDataSource db) : IReportQueries
{
    public Task<IReadOnlyList<DepartmentProgressRow>> DepartmentProgressAsync(int? departmentId, CancellationToken ct) =>
        db.QueryFunctionAsync<DepartmentProgressRow>("fn_report_department_progress", new { DepartmentId = departmentId }, ct);

    public Task<IReadOnlyList<ProjectProgressRow>> ProjectProgressAsync(int? departmentId, string? status, CancellationToken ct) =>
        db.QueryFunctionAsync<ProjectProgressRow>("fn_report_project_progress", new { DepartmentId = departmentId, Status = status }, ct);

    public Task<IReadOnlyList<UserWorkloadRow>> UserWorkloadAsync(int? departmentId, CancellationToken ct) =>
        db.QueryFunctionAsync<UserWorkloadRow>("fn_report_user_workload", new { DepartmentId = departmentId }, ct);
}
