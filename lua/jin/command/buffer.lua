-- :JinBuffer and jin.buffer(): the raw view of whatever jj prints.

local view = require("jin.view")

local M = {}

---@type jin.CompletedCommand
M.COMMAND = { name = "JinBuffer", shortest = 5, options = view.OPTIONS }

---@alias jin.BufferOptions jin.ViewOptions

---Open a buffer showing what `jj {argv}` prints.
---@param jin jin.Api
---@param host jin.Host
---@param argv string[]
---@param opts jin.BufferOptions
---@return integer bufnr
function M.open(jin, host, argv, opts)
  return view.open(jin, host, "buffer", argv, opts)
end

---Open the buffer for the arguments of `:JinBuffer` as typed.
---@param jin jin.Api
---@param host jin.Host
---@param line string
---@param opts { bang?: boolean, mods?: string }
function M.command(jin, host, line, opts)
  view.command(jin, host, "buffer", line, opts)
end

return M
