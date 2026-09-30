using Npgsql;
using ProjectMonitoring.Application.Departments;
using ProjectMonitoring.Domain.Entities;
using ProjectMonitoring.Infrastructure.Persistence;

namespace ProjectMonitoring.Infrastructure.Repositories;

public class DepartmentRepository(NpgsqlDataSource db) : IDepartmentRepository
{
    public Task<IReadOnlyList<DepartmentDto>> ListAsync(CancellationToken ct) =>
        db.QueryFunctionAsync<DepartmentDto>("fn_department_list", null, ct);

    public Task<DepartmentDto?> GetAsync(int id, CancellationToken ct) =>
        db.QueryFunctionSingleAsync<DepartmentDto>("fn_department_get", new { Id = id }, ct);

    public Task<bool> ExistsAsync(int id, CancellationToken ct) =>
        db.ScalarFunctionAsync<bool>("fn_department_exists", new { Id = id }, ct);

    public Task<bool> IsInUseAsync(int id, CancellationToken ct) =>
        db.ScalarFunctionAsync<bool>("fn_department_in_use", new { Id = id }, ct);

    public Task<int> CreateAsync(Department d, CancellationToken ct) =>
        db.CallProcedureAsync<int>("sp_department_create", new { d.Name }, "p_id", ct);

    public Task<bool> UpdateAsync(Department d, CancellationToken ct) =>
        db.CallProcedureAsync<bool>("sp_department_update", new { d.Id, d.Name }, "p_found", ct);

    public Task<bool> DeleteAsync(int id, CancellationToken ct) =>
        db.CallProcedureAsync<bool>("sp_department_delete", new { Id = id }, "p_found", ct);
}
