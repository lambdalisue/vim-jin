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
---Open the buffer `name` with `opener` (`edit` by default) and modifiers
---such as `botright`, and return its number.
---@field open fun(name: string, opts: { opener?: string, mods?: string }): integer
---Replace the lines of `bufnr`, highlight `highlights` with the `groups` it
---defines, and make the buffer a read-only scratch buffer of `filetype`.
---Windows showing the buffer keep their view.
---@field render fun(bufnr: integer, content: jin.Content)
---The loaded buffers and their names.
---@field buffers fun(): { bufnr: integer, name: string }[]
---The name of `bufnr` while it is loaded, nil otherwise.
---@field buffer_name fun(bufnr: integer): string?
---Turn a list handed over by the editor into a Lua table.
---@field list fun(value: any): any[]
---Turn a Lua table into a list to hand back to the editor.
---@field to_list fun(items: any[]): any

---@class jin.Content
---@field lines string[]
---@field highlights { line: integer, col: integer, end_col: integer, group: string }[] 1-based byte columns, end_col exclusive
---@field groups table<string, jin.AnsiStyle> the highlight groups to define
---@field filetype string
---@field title? string a short name for the buffer, kept in b:jin_title
---@field fresh? boolean the first content since the buffer was loaded, which its filetype has to be set up for anew

---@class jin.RunResult
---@field code integer
---@field stdout string
---@field stderr string

if vim.api then
  return require("jin.host.nvim")
end
return require("jin.host.vim")
