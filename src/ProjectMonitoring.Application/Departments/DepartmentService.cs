using System.ComponentModel.DataAnnotations;
using ProjectMonitoring.Application.Common;
using ProjectMonitoring.Domain.Entities;

namespace ProjectMonitoring.Application.Departments;

public record DepartmentDto
{
    public int Id { get; init; }
    public string Name { get; init; } = "";
    public int UserCount { get; init; }
    public int ProjectCount { get; init; }
    public DateTime CreatedAt { get; init; }
}

public record SaveDepartmentRequest([Required, StringLength(100, MinimumLength = 2)] string Name);

public interface IDepartmentRepository
{
    Task<IReadOnlyList<DepartmentDto>> ListAsync(CancellationToken ct);
    Task<DepartmentDto?> GetAsync(int id, CancellationToken ct);
    Task<bool> ExistsAsync(int id, CancellationToken ct);
    /// <summary>True when users or projects still reference the department.</summary>
    Task<bool> IsInUseAsync(int id, CancellationToken ct);
    Task<int> CreateAsync(Department department, CancellationToken ct);
    Task<bool> UpdateAsync(Department department, CancellationToken ct);
    Task<bool> DeleteAsync(int id, CancellationToken ct);
}

public class DepartmentService(IDepartmentRepository repo)
{
    public Task<IReadOnlyList<DepartmentDto>> ListAsync(CancellationToken ct) => repo.ListAsync(ct);

    public async Task<DepartmentDto> GetAsync(int id, CancellationToken ct) =>
        await repo.GetAsync(id, ct) ?? throw new NotFoundException("Department", id);

    public async Task<DepartmentDto> CreateAsync(SaveDepartmentRequest req, CancellationToken ct)
    {
        // Duplicate names are rejected by uq_departments_name -> 409 via GlobalExceptionHandler
        var id = await repo.CreateAsync(new Department { Name = req.Name.Trim() }, ct);
        return await GetAsync(id, ct);
    }

    public async Task<DepartmentDto> UpdateAsync(int id, SaveDepartmentRequest req, CancellationToken ct)
    {
        if (!await repo.UpdateAsync(new Department { Id = id, Name = req.Name.Trim() }, ct))
            throw new NotFoundException("Department", id);
        return await GetAsync(id, ct);
    }

    public async Task DeleteAsync(int id, CancellationToken ct)
    {
        if (!await repo.ExistsAsync(id, ct)) throw new NotFoundException("Department", id);
        if (await repo.IsInUseAsync(id, ct))
            throw new ConflictException("Department still has users or projects; reassign them first.");
        await repo.DeleteAsync(id, ct);
    }
}
