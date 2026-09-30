using System.ComponentModel.DataAnnotations;
using ProjectMonitoring.Application.Common;
using ProjectMonitoring.Application.Departments;
using ProjectMonitoring.Application.Users;
using ProjectMonitoring.Domain.Entities;

namespace ProjectMonitoring.Application.Projects;

public record ProjectDto
{
    public int Id { get; init; }
    public string Name { get; init; } = "";
    public string? Description { get; init; }
    public string Status { get; init; } = "";
    public DateOnly? StartDate { get; init; }
    public DateOnly? EndDate { get; init; }
    public int DepartmentId { get; init; }
    public string DepartmentName { get; init; } = "";
    public int? OwnerId { get; init; }
    public string? OwnerName { get; init; }
    public int TotalTasks { get; init; }
    public int DoneTasks { get; init; }
    public decimal Progress { get; init; }
    public DateTime CreatedAt { get; init; }
    public DateTime UpdatedAt { get; init; }
}

public record SaveProjectRequest(
    [Required, StringLength(200, MinimumLength = 2)] string Name,
    string? Description,
    [Required, AllowedValues("planning", "active", "on_hold", "completed", "cancelled")] string Status,
    [Range(1, int.MaxValue)] int DepartmentId,
    int? OwnerId,
    DateOnly? StartDate,
    DateOnly? EndDate);

public class ProjectQuery : PageQuery
{
    public int? DepartmentId { get; set; }
    public string? Status { get; set; }
    public string? Search { get; set; }
}

public interface IProjectRepository
{
    Task<PagedResult<ProjectDto>> ListAsync(ProjectQuery query, CancellationToken ct);
    Task<ProjectDto?> GetAsync(int id, CancellationToken ct);
    /// <summary>Current status, or null if the project does not exist.</summary>
    Task<string?> GetStatusAsync(int id, CancellationToken ct);
    Task<int> CreateAsync(Project project, CancellationToken ct);
    Task<bool> UpdateAsync(Project project, CancellationToken ct);
    /// <summary>Tasks are removed by ON DELETE CASCADE.</summary>
    Task<bool> DeleteAsync(int id, CancellationToken ct);
}

public class ProjectService(IProjectRepository repo, IDepartmentRepository departments, IUserRepository users)
{
    public Task<PagedResult<ProjectDto>> ListAsync(ProjectQuery query, CancellationToken ct) => repo.ListAsync(query, ct);

    public async Task<ProjectDto> GetAsync(int id, CancellationToken ct) =>
        await repo.GetAsync(id, ct) ?? throw new NotFoundException("Project", id);

    public async Task<ProjectDto> CreateAsync(SaveProjectRequest req, CancellationToken ct)
    {
        var project = await ValidateAsync(null, req, ct);
        var id = await repo.CreateAsync(project, ct);
        return await GetAsync(id, ct);
    }

    public async Task<ProjectDto> UpdateAsync(int id, SaveProjectRequest req, CancellationToken ct)
    {
        var project = await ValidateAsync(id, req, ct);
        if (!await repo.UpdateAsync(project, ct)) throw new NotFoundException("Project", id);
        return await GetAsync(id, ct);
    }

    public async Task DeleteAsync(int id, CancellationToken ct)
    {
        if (!await repo.DeleteAsync(id, ct)) throw new NotFoundException("Project", id);
    }

    private async Task<Project> ValidateAsync(int? id, SaveProjectRequest req, CancellationToken ct)
    {
        if (req.StartDate is { } start && req.EndDate is { } end && end < start)
            throw new BusinessRuleException("EndDate must be on or after StartDate.");
        if (!await departments.ExistsAsync(req.DepartmentId, ct))
            throw new BusinessRuleException($"Department {req.DepartmentId} does not exist.");
        if (req.OwnerId is { } ownerId && !await users.ExistsActiveAsync(ownerId, ct))
            throw new BusinessRuleException($"Owner {ownerId} does not exist or is inactive.");

        return new Project
        {
            Id = id ?? 0,
            Name = req.Name.Trim(),
            Description = req.Description,
            Status = req.Status,
            DepartmentId = req.DepartmentId,
            OwnerId = req.OwnerId,
            StartDate = req.StartDate,
            EndDate = req.EndDate
        };
    }
}
