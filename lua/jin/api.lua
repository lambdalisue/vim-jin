local M = {}

---The public API, as `require("jin")` offers it.
---@class jin.Api
---Run jj with `argv` and return what it printed, without echoing anything or
---firing events: for reading jj's output. jj runs in the workspace of
---`opts.cwd`, or else of the current buffer or directory. With `on_exit` it
---returns at once and calls `on_exit` with the result; without, it blocks
---until jj finishes and returns the result.
---@field jj (fun(argv: string[], opts?: jin.JjOptions): jin.RunResult)|fun(argv: string[], opts: jin.JjOptions?, on_exit: fun(result: jin.RunResult))
---The Lua counterpart of `:Jin`: run jj with `argv`, echo what it printed,
---then fire `User JinCommandPost`. Use it for commands that change the
---repository, so that everything showing it refreshes.
---@field command fun(argv: string[], opts?: jin.CommandOptions, on_exit?: fun(result: jin.RunResult))
---Return the root of the jj workspace that holds `path`, or of the current
---buffer or directory when `path` is nil; nil outside any workspace.
---@field root fun(path?: string): string?
---The Lua counterpart of `:JinBuffer`: open a buffer showing what jj prints
---for `argv`, refreshed whenever `User JinCommandPost` fires, and return its
---number.
---@field buffer fun(argv: string[], opts?: jin.BufferOptions): integer

---Build the public API on the host `get_host` returns. The host is asked for
---on each call, so building the API needs no editor.
---@param get_host fun(): jin.Host
---@return jin.Api
function M.new(get_host)
  local api = {}

  function api.jj(argv, opts, on_exit)
    return require("jin.jj").run(get_host(), argv, opts or {}, on_exit)
  end

  function api.command(argv, opts, on_exit)
    require("jin.command.bare").run(get_host(), argv, opts or {}, on_exit)
  end

  function api.root(path)
    return require("jin.jj").root(get_host(), path)
  end

  function api.buffer(argv, opts)
    return require("jin.command.buffer").open(api, get_host(), argv, opts or {})
  end

  return api --[[@as jin.Api]]
end

return M
