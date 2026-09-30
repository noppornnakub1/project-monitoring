using Npgsql;
using ProjectMonitoring.Application.Common;
using ProjectMonitoring.Application.Users;
using ProjectMonitoring.Domain.Entities;
using ProjectMonitoring.Infrastructure.Persistence;

namespace ProjectMonitoring.Infrastructure.Repositories;

public class UserRepository(NpgsqlDataSource db) : IUserRepository
{
    public Task<PagedResult<UserDto>> ListAsync(UserQuery q, CancellationToken ct) =>
        db.QueryPagedFunctionAsync<UserDto>("fn_user_list",
            new { q.DepartmentId, q.IsActive, q.Search }, q, ct);

    public Task<UserDto?> GetAsync(int id, CancellationToken ct) =>
        db.QueryFunctionSingleAsync<UserDto>("fn_user_get", new { Id = id }, ct);

    public Task<bool> ExistsActiveAsync(int id, CancellationToken ct) =>
        db.ScalarFunctionAsync<bool>("fn_user_exists_active", new { Id = id }, ct);

    public Task<bool> EmailTakenAsync(string email, int? excludeUserId, CancellationToken ct) =>
        db.ScalarFunctionAsync<bool>("fn_user_email_taken", new { Email = email, ExcludeId = excludeUserId }, ct);

    public Task<int> CreateAsync(User u, CancellationToken ct) =>
        db.CallProcedureAsync<int>("sp_user_create",
            new { u.DepartmentId, u.FullName, u.Email, u.Role, u.IsActive }, "p_id", ct);

    public Task<bool> UpdateAsync(User u, CancellationToken ct) =>
        db.CallProcedureAsync<bool>("sp_user_update",
            new { u.Id, u.DepartmentId, u.FullName, u.Email, u.Role, u.IsActive }, "p_found", ct);

    public Task<bool> DeleteAsync(int id, CancellationToken ct) =>
        db.CallProcedureAsync<bool>("sp_user_delete", new { Id = id }, "p_found", ct);
}
