using System.Data.Common;
using System.Text.RegularExpressions;
using Dapper;
using Npgsql;
using ProjectMonitoring.Application.Common;

namespace ProjectMonitoring.Infrastructure.Persistence;

/// <summary>
/// Calls the stored procedures / functions in db/init/02-procedures.sql by name.
/// Arguments are passed with PostgreSQL named notation, derived from the argument object:
/// property <c>DepartmentId</c> becomes <c>p_department_id =&gt; @DepartmentId</c>, so argument
/// order never matters and every value travels as a parameter.
/// </summary>
internal static partial class StoredProcedureExtensions
{
    /// <summary>Set-returning function: <c>SELECT * FROM fn(...)</c>.</summary>
    public static async Task<IReadOnlyList<T>> QueryFunctionAsync<T>(
        this NpgsqlDataSource db, string function, object? args, CancellationToken ct)
    {
        await using var conn = db.CreateConnection();
        var rows = await conn.QueryAsync<T>(Command($"SELECT * FROM {Name(function)}({Join(ArgList(args))})", args, ct));
        return rows.AsList();
    }

    /// <summary>Set-returning function expected to return zero or one row.</summary>
    public static async Task<T?> QueryFunctionSingleAsync<T>(
        this NpgsqlDataSource db, string function, object? args, CancellationToken ct)
    {
        await using var conn = db.CreateConnection();
        return await conn.QuerySingleOrDefaultAsync<T>(
            Command($"SELECT * FROM {Name(function)}({Join(ArgList(args))})", args, ct));
    }

    /// <summary>Scalar function: <c>SELECT fn(...)</c>.</summary>
    public static async Task<T?> ScalarFunctionAsync<T>(
        this NpgsqlDataSource db, string function, object? args, CancellationToken ct)
    {
        await using var conn = db.CreateConnection();
        return await conn.ExecuteScalarAsync<T>(Command($"SELECT {Name(function)}({Join(ArgList(args))})", args, ct));
    }

    /// <summary>
    /// Paged list function returning <c>(total_count, item)</c>. <c>p_limit</c>/<c>p_offset</c> are added
    /// from <paramref name="page"/>. A row with a NULL item means "no rows on this page" but still carries the total.
    /// </summary>
    public static async Task<PagedResult<T>> QueryPagedFunctionAsync<T>(
        this NpgsqlDataSource db, string function, object args, PageQuery page, CancellationToken ct)
    {
        var parameters = new DynamicParameters(args);
        parameters.Add("Limit", page.PageSize);
        parameters.Add("Offset", page.Offset);
        var argList = Join([.. ArgList(args), "p_limit => @Limit", "p_offset => @Offset"]);

        await using var conn = await db.OpenConnectionAsync(ct);
        await using var reader = await conn.ExecuteReaderAsync(Command(
            $"SELECT r.total_count, (r.item).* FROM {Name(function)}({argList}) r", parameters, ct));

        var parseItem = reader.GetRowParser<T>(startIndex: 1); // column 0 is total_count
        var total = 0;
        var items = new List<T>();
        while (await reader.ReadAsync(ct))
        {
            total = reader.GetInt32(0);
            if (!reader.IsDBNull(1)) items.Add(parseItem(reader));
        }
        return new PagedResult<T>(items, page.Page, page.PageSize, total);
    }

    /// <summary>
    /// <c>CALL sp(...)</c> and return the value of its INOUT parameter <paramref name="output"/> (e.g. p_id, p_found).
    /// </summary>
    public static async Task<T> CallProcedureAsync<T>(
        this NpgsqlDataSource db, string procedure, object args, string output, CancellationToken ct)
    {
        var argList = Join([.. ArgList(args), $"{Name(output)} => NULL"]);
        await using var conn = db.CreateConnection();
        return await conn.ExecuteScalarAsync<T>(Command($"CALL {Name(procedure)}({argList})", args, ct))
            ?? throw new InvalidOperationException($"{procedure} returned no value for {output}.");
    }

    private static CommandDefinition Command(string sql, object? args, CancellationToken ct) =>
        new(sql, args, cancellationToken: ct);

    // "DepartmentId" -> "p_department_id => @DepartmentId"
    private static IEnumerable<string> ArgList(object? args) =>
        args?.GetType().GetProperties()
            .Select(p => $"p_{PascalToSnake().Replace(p.Name, "_$1").ToLowerInvariant()} => @{p.Name}")
        ?? [];

    private static string Join(IEnumerable<string> args) => string.Join(", ", args);

    // Procedure / function names are code constants, but never let anything else reach the SQL text
    private static string Name(string identifier) =>
        Identifier().IsMatch(identifier) ? identifier : throw new ArgumentException($"Invalid identifier: {identifier}");

    [GeneratedRegex("(?<=[a-z0-9])([A-Z])")]
    private static partial Regex PascalToSnake();

    [GeneratedRegex("^[a-z_][a-z0-9_]*$")]
    private static partial Regex Identifier();
}
