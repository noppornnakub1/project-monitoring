namespace ProjectMonitoring.Domain.Entities;

public class Project
{
    public int Id { get; set; }
    public int DepartmentId { get; set; }
    public int? OwnerId { get; set; }
    public string Name { get; set; } = null!;
    public string? Description { get; set; }
    public string Status { get; set; } = ProjectStatuses.Planning;
    public DateOnly? StartDate { get; set; }
    public DateOnly? EndDate { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}

public static class ProjectStatuses
{
    public const string Planning = "planning";
    public const string Active = "active";
    public const string OnHold = "on_hold";
    public const string Completed = "completed";
    public const string Cancelled = "cancelled";

    public static readonly string[] All = [Planning, Active, OnHold, Completed, Cancelled];
}
