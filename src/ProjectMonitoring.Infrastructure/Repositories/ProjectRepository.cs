using Npgsql;
using ProjectMonitoring.Application.Common;
using ProjectMonitoring.Application.Projects;
using ProjectMonitoring.Domain.Entities;
using ProjectMonitoring.Infrastructure.Persistence;

namespace ProjectMonitoring.Infrastructure.Repositories;

public class ProjectRepository(NpgsqlDataSource db) : IProjectRepository
{
    public Task<PagedResult<ProjectDto>> ListAsync(ProjectQuery q, CancellationToken ct) =>
        db.QueryPagedFunctionAsync<ProjectDto>("fn_project_list",
            new { q.DepartmentId, q.Status, q.Search }, q, ct);

    public Task<ProjectDto?> GetAsync(int id, CancellationToken ct) =>
        db.QueryFunctionSingleAsync<ProjectDto>("fn_project_get", new { Id = id }, ct);

    public Task<string?> GetStatusAsync(int id, CancellationToken ct) =>
        db.ScalarFunctionAsync<string>("fn_project_status", new { Id = id }, ct);

    public Task<int> CreateAsync(Project p, CancellationToken ct) =>
        db.CallProcedureAsync<int>("sp_project_create",
            new { p.DepartmentId, p.OwnerId, p.Name, p.Description, p.Status, p.StartDate, p.EndDate }, "p_id", ct);

    public Task<bool> UpdateAsync(Project p, CancellationToken ct) =>
        db.CallProcedureAsync<bool>("sp_project_update",
            new { p.Id, p.DepartmentId, p.OwnerId, p.Name, p.Description, p.Status, p.StartDate, p.EndDate }, "p_found", ct);

    public Task<bool> DeleteAsync(int id, CancellationToken ct) =>
        db.CallProcedureAsync<bool>("sp_project_delete", new { Id = id }, "p_found", ct);
}
