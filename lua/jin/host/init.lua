---The editor services the core is given. Callbacks are always called on the
---main loop, where the editor can be used freely.
---@class jin.Host
---@field name "nvim"|"vim"
---Run `argv` without a shell or stdin; `on_exit` receives its whole output.
---`env` adds to the editor's environment.
---@field run fun(argv: string[], opts: { cwd?: string, env?: table<string, string> }, on_exit: fun(result: jin.RunResult))
---Process events until `cond` holds or `timeout` ms pass; false on timeout.
---@field wait fun(timeout: integer, cond: fun(): boolean): boolean
---Show `text`, which may span lines, and record it in the message history.
---@field echo fun(text: string, hl?: string)
---@field cwd fun(): string
---Absolute path of the current buffer, or "" when it has no name.
---@field bufname fun(): string
---`path` with symlinks resolved.
---@field realpath fun(path: string): string
---@field is_dir fun(path: string): boolean
---Fire the User autocmd `event` if any is defined.
---@field doautocmd fun(event: string)
---A monotonic clock in milliseconds, for measuring how much time passed.
---@field now fun(): number
---@field defer fun(ms: integer, fn: fun()): any
---@field cancel fun(timer: any)
---Turn a list handed over by the editor into a Lua table.
---@field list fun(value: any): any[]
---Turn a Lua table into a list to hand back to the editor.
---@field to_list fun(items: any[]): any

---@class jin.RunResult
---@field code integer
---@field stdout string
---@field stderr string

if vim.api then
  return require("jin.host.nvim")
end
return require("jin.host.vim")
