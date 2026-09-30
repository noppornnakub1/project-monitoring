namespace ProjectMonitoring.Domain.Entities;

public class Department
{
    public int Id { get; set; }
    public string Name { get; set; } = null!;
    public DateTime CreatedAt { get; set; }
}
