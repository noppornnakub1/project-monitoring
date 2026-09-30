using Microsoft.Extensions.DependencyInjection;
using ProjectMonitoring.Application.Departments;
using ProjectMonitoring.Application.Projects;
using ProjectMonitoring.Application.Reports;
using ProjectMonitoring.Application.SystemLogs;
using ProjectMonitoring.Application.Tasks;
using ProjectMonitoring.Application.Users;

namespace ProjectMonitoring.Application;

public static class DependencyInjection
{
    public static IServiceCollection AddApplication(this IServiceCollection services)
    {
        services.AddScoped<DepartmentService>();
        services.AddScoped<UserService>();
        services.AddScoped<ProjectService>();
        services.AddScoped<TaskService>();
        services.AddScoped<ReportService>();
        services.AddScoped<SystemLogService>();
        return services;
    }
}
