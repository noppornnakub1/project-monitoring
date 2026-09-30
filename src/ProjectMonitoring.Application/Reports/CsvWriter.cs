using System.Globalization;
using System.Reflection;
using System.Text;

namespace ProjectMonitoring.Application.Reports;

/// <summary>Minimal RFC 4180 CSV serializer for flat report rows (public properties become columns).</summary>
public static class CsvWriter
{
    public static string Write<T>(IEnumerable<T> rows)
    {
        var props = typeof(T).GetProperties(BindingFlags.Public | BindingFlags.Instance);
        var sb = new StringBuilder();
        sb.AppendLine(string.Join(',', props.Select(p => Escape(p.Name))));
        foreach (var row in rows)
            sb.AppendLine(string.Join(',', props.Select(p => Escape(Format(p.GetValue(row))))));
        return sb.ToString();
    }

    private static string Format(object? value) => value switch
    {
        null => "",
        DateOnly d => d.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
        DateTime dt => dt.ToString("O", CultureInfo.InvariantCulture),
        IFormattable f => f.ToString(null, CultureInfo.InvariantCulture),
        _ => value.ToString() ?? ""
    };

    private static string Escape(string value) =>
        value.IndexOfAny([',', '"', '\n', '\r']) >= 0
            ? $"\"{value.Replace("\"", "\"\"")}\""
            : value;
}
