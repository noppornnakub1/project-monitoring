using System.Data;
using System.Text.Json;
using Dapper;

namespace ProjectMonitoring.Infrastructure.Persistence;

internal static class DapperSetup
{
    private static int _configured;

    public static void Configure()
    {
        if (Interlocked.Exchange(ref _configured, 1) == 1) return;

        // snake_case columns (department_id) -> PascalCase properties (DepartmentId)
        DefaultTypeMap.MatchNamesWithUnderscores = true;
        SqlMapper.AddTypeHandler(new DateOnlyHandler());
        SqlMapper.AddTypeHandler(new JsonElementHandler());
    }

    /// <summary>Npgsql returns <c>date</c> columns as DateTime; the API models use DateOnly.</summary>
    private sealed class DateOnlyHandler : SqlMapper.TypeHandler<DateOnly>
    {
        public override DateOnly Parse(object value) =>
            value is DateTime dt ? DateOnly.FromDateTime(dt) : (DateOnly)value;

        public override void SetValue(IDbDataParameter parameter, DateOnly value)
        {
            parameter.DbType = DbType.Date;
            parameter.Value = value;
        }
    }

    /// <summary>jsonb comes back as text; expose it as a JsonElement so the API returns real JSON.</summary>
    private sealed class JsonElementHandler : SqlMapper.TypeHandler<JsonElement>
    {
        public override JsonElement Parse(object value)
        {
            using var doc = JsonDocument.Parse((string)value);
            return doc.RootElement.Clone();
        }

        public override void SetValue(IDbDataParameter parameter, JsonElement value)
        {
            parameter.Value = value.GetRawText();
        }
    }
}
