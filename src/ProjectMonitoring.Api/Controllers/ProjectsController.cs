using Microsoft.AspNetCore.Mvc;
using ProjectMonitoring.Application.Common;
using ProjectMonitoring.Application.Projects;

namespace ProjectMonitoring.Api.Controllers;

[ApiController]
[Route("api/projects")]
public class ProjectsController(ProjectService service) : ControllerBase
{
    [HttpGet]
    public Task<PagedResult<ProjectDto>> List([FromQuery] ProjectQuery query, CancellationToken ct) =>
        service.ListAsync(query, ct);

    [HttpGet("{id:int}")]
    public Task<ProjectDto> Get(int id, CancellationToken ct) => service.GetAsync(id, ct);

    [HttpPost]
    public async Task<ActionResult<ProjectDto>> Create(SaveProjectRequest req, CancellationToken ct)
    {
        var dto = await service.CreateAsync(req, ct);
        return CreatedAtAction(nameof(Get), new { id = dto.Id }, dto);
    }

    [HttpPut("{id:int}")]
    public Task<ProjectDto> Update(int id, SaveProjectRequest req, CancellationToken ct) =>
        service.UpdateAsync(id, req, ct);

    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id, CancellationToken ct)
    {
        await service.DeleteAsync(id, ct);
        return NoContent();
    }
}
