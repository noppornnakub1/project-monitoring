# ---------- build stage ----------
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Restore first (separate layer) so dependency download is cached until a csproj changes
COPY ProjectMonitoring.sln ./
COPY src/ProjectMonitoring.Domain/*.csproj         src/ProjectMonitoring.Domain/
COPY src/ProjectMonitoring.Application/*.csproj    src/ProjectMonitoring.Application/
COPY src/ProjectMonitoring.Infrastructure/*.csproj src/ProjectMonitoring.Infrastructure/
COPY src/ProjectMonitoring.Api/*.csproj            src/ProjectMonitoring.Api/
RUN dotnet restore src/ProjectMonitoring.Api/ProjectMonitoring.Api.csproj

COPY src/ src/
RUN dotnet publish src/ProjectMonitoring.Api/ProjectMonitoring.Api.csproj \
      -c Release -o /app/publish --no-restore /p:UseAppHost=false

# ---------- runtime stage ----------
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app

# curl is only used by the container HEALTHCHECK
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl \
 && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/publish .

ENV ASPNETCORE_HTTP_PORTS=8080 \
    DOTNET_RUNNING_IN_CONTAINER=true
EXPOSE 8080

# Run as the non-root user shipped with the .NET 8 images
USER app

HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS http://localhost:8080/health || exit 1

ENTRYPOINT ["dotnet", "ProjectMonitoring.Api.dll"]
