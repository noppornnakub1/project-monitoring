using Npgsql;
using ProjectMonitoring.Application.Common;
using ProjectMonitoring.Application.Tasks;
using ProjectMonitoring.Domain.Entities;
using ProjectMonitoring.Infrastructure.Persistence;

namespace ProjectMonitoring.Infrastructure.Repositories;

public class TaskRepository(NpgsqlDataSource db) : ITaskRepository
{
    public Task<PagedResult<TaskDto>> ListAsync(TaskQuery q, CancellationToken ct) =>
        db.QueryPagedFunctionAsync<TaskDto>("fn_task_list",
            new { q.ProjectId, q.AssigneeId, q.Status, q.Priority, q.Overdue }, q, ct);

    public Task<TaskDto?> GetAsync(int id, CancellationToken ct) =>
        db.QueryFunctionSingleAsync<TaskDto>("fn_task_get", new { Id = id }, ct);

    public Task<int> CreateAsync(TaskItem t, CancellationToken ct) =>
        db.CallProcedureAsync<int>("sp_task_create",
            new { t.ProjectId, t.AssigneeId, t.Title, t.Description, t.Status, t.Priority, t.Progress, t.DueDate },
            "p_id", ct);

    public Task<bool> UpdateAsync(TaskItem t, CancellationToken ct) =>
        db.CallProcedureAsync<bool>("sp_task_update",
            new { t.Id, t.ProjectId, t.AssigneeId, t.Title, t.Description, t.Status, t.Priority, t.Progress, t.DueDate },
            "p_found", ct);

    public Task<bool> DeleteAsync(int id, CancellationToken ct) =>
        db.CallProcedureAsync<bool>("sp_task_delete", new { Id = id }, "p_found", ct);
}
