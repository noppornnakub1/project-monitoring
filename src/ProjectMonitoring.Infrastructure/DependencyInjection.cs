using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using ProjectMonitoring.Application.Departments;
using ProjectMonitoring.Application.Projects;
using ProjectMonitoring.Application.Reports;
using ProjectMonitoring.Application.SystemLogs;
using ProjectMonitoring.Application.Tasks;
using ProjectMonitoring.Application.Users;
using ProjectMonitoring.Infrastructure.Persistence;
using ProjectMonitoring.Infrastructure.Repositories;

namespace ProjectMonitoring.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(this IServiceCollection services, IConfiguration config)
    {
        var connectionString = config.GetConnectionString("Default")
            ?? throw new InvalidOperationException("Connection string 'Default' is not configured.");

        DapperSetup.Configure();

        // One pooled data source for the whole app; repositories open short-lived connections from it
        services.AddSingleton(_ => NpgsqlDataSource.Create(connectionString));

        services.AddScoped<IDepartmentRepository, DepartmentRepository>();
        services.AddScoped<IUserRepository, UserRepository>();
        services.AddScoped<IProjectRepository, ProjectRepository>();
        services.AddScoped<ITaskRepository, TaskRepository>();
        services.AddScoped<ISystemLogRepository, SystemLogRepository>();
        services.AddScoped<IReportQueries, ReportQueries>();
        return services;
    }
}
