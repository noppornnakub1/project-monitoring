using System.ComponentModel.DataAnnotations;

namespace ProjectMonitoring.Application.Common;

public class PageQuery
{
    [Range(1, int.MaxValue)] public int Page { get; set; } = 1;
    [Range(1, 200)] public int PageSize { get; set; } = 20;

    public int Offset => (Page - 1) * PageSize;
}

public record PagedResult<T>(IReadOnlyList<T> Items, int Page, int PageSize, int TotalCount)
{
    public int TotalPages => (int)Math.Ceiling(TotalCount / (double)PageSize);
}
