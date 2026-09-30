namespace ProjectMonitoring.Domain.Entities;

// Named TaskItem to avoid clashing with System.Threading.Tasks.Task; maps to table "tasks".
public class TaskItem
{
    public int Id { get; set; }
    public int ProjectId { get; set; }
    public int? AssigneeId { get; set; }
    public string Title { get; set; } = null!;
    public string? Description { get; set; }
    public string Status { get; set; } = TaskStatuses.Todo;
    public string Priority { get; set; } = TaskPriorities.Medium;
    public short Progress { get; set; }
    public DateOnly? DueDate { get; set; }
    public DateTime? CompletedAt { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}

public static class TaskStatuses
{
    public const string Todo = "todo";
    public const string InProgress = "in_progress";
    public const string Review = "review";
    public const string Done = "done";

    public static readonly string[] All = [Todo, InProgress, Review, Done];
}

public static class TaskPriorities
{
    public const string Low = "low";
    public const string Medium = "medium";
    public const string High = "high";
    public const string Critical = "critical";

    public static readonly string[] All = [Low, Medium, High, Critical];
}
