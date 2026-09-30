using Microsoft.AspNetCore.Mvc;
using ProjectMonitoring.Application.Common;
using ProjectMonitoring.Application.Users;

namespace ProjectMonitoring.Api.Controllers;

[ApiController]
[Route("api/users")]
public class UsersController(UserService service) : ControllerBase
{
    [HttpGet]
    public Task<PagedResult<UserDto>> List([FromQuery] UserQuery query, CancellationToken ct) =>
        service.ListAsync(query, ct);

    [HttpGet("{id:int}")]
    public Task<UserDto> Get(int id, CancellationToken ct) => service.GetAsync(id, ct);

    [HttpPost]
    public async Task<ActionResult<UserDto>> Create(SaveUserRequest req, CancellationToken ct)
    {
        var dto = await service.CreateAsync(req, ct);
        return CreatedAtAction(nameof(Get), new { id = dto.Id }, dto);
    }

    [HttpPut("{id:int}")]
    public Task<UserDto> Update(int id, SaveUserRequest req, CancellationToken ct) =>
        service.UpdateAsync(id, req, ct);

    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id, CancellationToken ct)
    {
        await service.DeleteAsync(id, ct);
        return NoContent();
    }
}
