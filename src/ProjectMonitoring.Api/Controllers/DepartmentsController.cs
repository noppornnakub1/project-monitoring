using Microsoft.AspNetCore.Mvc;
using ProjectMonitoring.Application.Departments;

namespace ProjectMonitoring.Api.Controllers;

[ApiController]
[Route("api/departments")]
public class DepartmentsController(DepartmentService service) : ControllerBase
{
    [HttpGet]
    public Task<IReadOnlyList<DepartmentDto>> List(CancellationToken ct) => service.ListAsync(ct);

    [HttpGet("{id:int}")]
    public Task<DepartmentDto> Get(int id, CancellationToken ct) => service.GetAsync(id, ct);

    [HttpPost]
    public async Task<ActionResult<DepartmentDto>> Create(SaveDepartmentRequest req, CancellationToken ct)
    {
        var dto = await service.CreateAsync(req, ct);
        return CreatedAtAction(nameof(Get), new { id = dto.Id }, dto);
    }

    [HttpPut("{id:int}")]
    public Task<DepartmentDto> Update(int id, SaveDepartmentRequest req, CancellationToken ct) =>
        service.UpdateAsync(id, req, ct);

    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id, CancellationToken ct)
    {
        await service.DeleteAsync(id, ct);
        return NoContent();
    }
}
