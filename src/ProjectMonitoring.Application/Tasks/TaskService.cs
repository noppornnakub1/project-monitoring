using System.ComponentModel.DataAnnotations;
using ProjectMonitoring.Application.Common;
using ProjectMonitoring.Application.Projects;
using ProjectMonitoring.Application.Users;
using ProjectMonitoring.Domain.Entities;

namespace ProjectMonitoring.Application.Tasks;

public record TaskDto
{
    public int Id { get; init; }
    public int ProjectId { get; init; }
    public string ProjectName { get; init; } = "";
    public int? AssigneeId { get; init; }
    public string? AssigneeName { get; init; }
    public string Title { get; init; } = "";
    public string? Description { get; init; }
    public string Status { get; init; } = "";
    public string Priority { get; init; } = "";
    public short Progress { get; init; }
    public DateOnly? DueDate { get; init; }
    public bool IsOverdue { get; init; }
    public DateTime? CompletedAt { get; init; }
    public DateTime CreatedAt { get; init; }
    public DateTime UpdatedAt { get; init; }
}

public record SaveTaskRequest(
    [Range(1, int.MaxValue)] int ProjectId,
    int? AssigneeId,
    [Required, StringLength(200, MinimumLength = 2)] string Title,
    string? Description,
    [Required, AllowedValues("todo", "in_progress", "review", "done")] string Status,
    [Required, AllowedValues("low", "medium", "high", "critical")] string Priority,
    [Range(0, 100)] short Progress,
    DateOnly? DueDate);

public class TaskQuery : PageQuery
{
    public int? ProjectId { get; set; }
    public int? AssigneeId { get; set; }
    public string? Status { get; set; }
    public string? Priority { get; set; }
    /// <summary>true = only open tasks whose due date has passed.</summary>
    public bool? Overdue { get; set; }
}

public interface ITaskRepository
{
    Task<PagedResult<TaskDto>> ListAsync(TaskQuery query, CancellationToken ct);
    Task<TaskDto?> GetAsync(int id, CancellationToken ct);
    Task<int> CreateAsync(TaskItem task, CancellationToken ct);
    Task<bool> UpdateAsync(TaskItem task, CancellationToken ct);
    Task<bool> DeleteAsync(int id, CancellationToken ct);
}

public class TaskService(ITaskRepository repo, IProjectRepository projects, IUserRepository users)
{
    public Task<PagedResult<TaskDto>> ListAsync(TaskQuery query, CancellationToken ct) => repo.ListAsync(query, ct);

    public async Task<TaskDto> GetAsync(int id, CancellationToken ct) =>
        await repo.GetAsync(id, ct) ?? throw new NotFoundException("Task", id);

    public async Task<TaskDto> CreateAsync(SaveTaskRequest req, CancellationToken ct)
    {
        var task = await ValidateAsync(null, req, ct);
        var id = await repo.CreateAsync(task, ct);
        // Re-read: DB trigger may have adjusted progress / completed_at
        return await GetAsync(id, ct);
    }

    public async Task<TaskDto> UpdateAsync(int id, SaveTaskRequest req, CancellationToken ct)
    {
        var task = await ValidateAsync(id, req, ct);
        if (!await repo.UpdateAsync(task, ct)) throw new NotFoundException("Task", id);
        return await GetAsync(id, ct);
    }

    public async Task DeleteAsync(int id, CancellationToken ct)
    {
        if (!await repo.DeleteAsync(id, ct)) throw new NotFoundException("Task", id);
    }

    private async Task<TaskItem> ValidateAsync(int? id, SaveTaskRequest req, CancellationToken ct)
    {
        var projectStatus = await projects.GetStatusAsync(req.ProjectId, ct)
            ?? throw new BusinessRuleException($"Project {req.ProjectId} does not exist.");
        if (id is null && projectStatus is ProjectStatuses.Completed or ProjectStatuses.Cancelled)
            throw new BusinessRuleException($"Cannot add tasks to a {projectStatus} project.");
        if (req.AssigneeId is { } assigneeId && !await users.ExistsActiveAsync(assigneeId, ct))
            throw new BusinessRuleException($"Assignee {assigneeId} does not exist or is inactive.");

        return new TaskItem
        {
            Id = id ?? 0,
            ProjectId = req.ProjectId,
            AssigneeId = req.AssigneeId,
            Title = req.Title.Trim(),
            Description = req.Description,
            Status = req.Status,
            Priority = req.Priority,
            Progress = req.Progress,
            DueDate = req.DueDate
        };
    }
}
