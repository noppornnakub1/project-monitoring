using System.Text.Json.Serialization;
using ProjectMonitoring.Api.Infrastructure;
using ProjectMonitoring.Application;
using ProjectMonitoring.Infrastructure;
using ProjectMonitoring.Infrastructure.Persistence;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddApplication();
builder.Services.AddInfrastructure(builder.Configuration);

builder.Services.AddControllers()
    .AddJsonOptions(o => o.JsonSerializerOptions.DefaultIgnoreCondition = JsonIgnoreCondition.Never);
builder.Services.AddProblemDetails();
builder.Services.AddExceptionHandler<GlobalExceptionHandler>();
builder.Services.AddHealthChecks().AddCheck<PostgresHealthCheck>("database");
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(o => o.SwaggerDoc("v1", new() { Title = "Project Monitoring API", Version = "v1" }));

var app = builder.Build();

app.UseExceptionHandler();
app.UseStatusCodePages();

// Swagger is enabled in every environment on purpose: this is a demo/assessment project.
app.UseSwagger();
app.UseSwaggerUI(o => o.DefaultModelsExpandDepth(-1)); // hide the "Schemas" section at the bottom

app.MapControllers();
app.MapHealthChecks("/health");
app.MapGet("/", () => Results.Redirect("/swagger")).ExcludeFromDescription();

app.Run();
