using System.ComponentModel.DataAnnotations;
using ProjectMonitoring.Application.Common;
using ProjectMonitoring.Application.Departments;
using ProjectMonitoring.Domain.Entities;

namespace ProjectMonitoring.Application.Users;

public record UserDto
{
    public int Id { get; init; }
    public string FullName { get; init; } = "";
    public string Email { get; init; } = "";
    public string Role { get; init; } = "";
    public bool IsActive { get; init; }
    public int DepartmentId { get; init; }
    public string DepartmentName { get; init; } = "";
    public DateTime CreatedAt { get; init; }
    public DateTime UpdatedAt { get; init; }
}

public record SaveUserRequest(
    [Required, StringLength(150, MinimumLength = 2)] string FullName,
    [Required, EmailAddress, StringLength(255)] string Email,
    [Required, AllowedValues("admin", "manager", "member")] string Role,
    [Range(1, int.MaxValue)] int DepartmentId,
    bool IsActive = true);

public class UserQuery : PageQuery
{
    public int? DepartmentId { get; set; }
    public bool? IsActive { get; set; }
    /// <summary>Matches name or email (case-insensitive).</summary>
    public string? Search { get; set; }
}

public interface IUserRepository
{
    Task<PagedResult<UserDto>> ListAsync(UserQuery query, CancellationToken ct);
    Task<UserDto?> GetAsync(int id, CancellationToken ct);
    Task<bool> ExistsActiveAsync(int id, CancellationToken ct);
    Task<bool> EmailTakenAsync(string email, int? excludeUserId, CancellationToken ct);
    Task<int> CreateAsync(User user, CancellationToken ct);
    Task<bool> UpdateAsync(User user, CancellationToken ct);
    Task<bool> DeleteAsync(int id, CancellationToken ct);
}

public class UserService(IUserRepository repo, IDepartmentRepository departments)
{
    public Task<PagedResult<UserDto>> ListAsync(UserQuery query, CancellationToken ct) => repo.ListAsync(query, ct);

    public async Task<UserDto> GetAsync(int id, CancellationToken ct) =>
        await repo.GetAsync(id, ct) ?? throw new NotFoundException("User", id);

    public async Task<UserDto> CreateAsync(SaveUserRequest req, CancellationToken ct)
    {
        var user = await ValidateAsync(null, req, ct);
        var id = await repo.CreateAsync(user, ct);
        return await GetAsync(id, ct);
    }

    public async Task<UserDto> UpdateAsync(int id, SaveUserRequest req, CancellationToken ct)
    {
        var user = await ValidateAsync(id, req, ct);
        if (!await repo.UpdateAsync(user, ct)) throw new NotFoundException("User", id);
        return await GetAsync(id, ct);
    }

    public async Task DeleteAsync(int id, CancellationToken ct)
    {
        // FKs are ON DELETE SET NULL: owned projects / assigned tasks become unassigned.
        if (!await repo.DeleteAsync(id, ct)) throw new NotFoundException("User", id);
    }

    private async Task<User> ValidateAsync(int? id, SaveUserRequest req, CancellationToken ct)
    {
        if (!await departments.ExistsAsync(req.DepartmentId, ct))
            throw new BusinessRuleException($"Department {req.DepartmentId} does not exist.");

        var email = req.Email.Trim().ToLowerInvariant();
        if (await repo.EmailTakenAsync(email, id, ct))
            throw new ConflictException($"Email '{email}' is already in use.");

        return new User
        {
            Id = id ?? 0,
            FullName = req.FullName.Trim(),
            Email = email,
            Role = req.Role,
            DepartmentId = req.DepartmentId,
            IsActive = req.IsActive
        };
    }
}
