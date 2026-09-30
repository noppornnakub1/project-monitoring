namespace ProjectMonitoring.Domain.Entities;

public class User
{
    public int Id { get; set; }
    public int DepartmentId { get; set; }
    public string FullName { get; set; } = null!;
    public string Email { get; set; } = null!;
    public string Role { get; set; } = UserRoles.Member;
    public bool IsActive { get; set; } = true;
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}

public static class UserRoles
{
    public const string Admin = "admin";
    public const string Manager = "manager";
    public const string Member = "member";

    public static readonly string[] All = [Admin, Manager, Member];
}
