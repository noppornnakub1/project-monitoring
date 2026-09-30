using Microsoft.AspNetCore.Mvc;
using ProjectMonitoring.Application.Common;
using ProjectMonitoring.Application.Tasks;

namespace ProjectMonitoring.Api.Controllers;

[ApiController]
[Route("api/tasks")]
public class TasksController(TaskService service) : ControllerBase
{
    [HttpGet]
    public Task<PagedResult<TaskDto>> List([FromQuery] TaskQuery query, CancellationToken ct) =>
        service.ListAsync(query, ct);

    [HttpGet("{id:int}")]
    public Task<TaskDto> Get(int id, CancellationToken ct) => service.GetAsync(id, ct);

    [HttpPost]
    public async Task<ActionResult<TaskDto>> Create(SaveTaskRequest req, CancellationToken ct)
    {
        var dto = await service.CreateAsync(req, ct);
        return CreatedAtAction(nameof(Get), new { id = dto.Id }, dto);
    }

    [HttpPut("{id:int}")]
    public Task<TaskDto> Update(int id, SaveTaskRequest req, CancellationToken ct) =>
        service.UpdateAsync(id, req, ct);

    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id, CancellationToken ct)
    {
        await service.DeleteAsync(id, ct);
        return NoContent();
    }
}
