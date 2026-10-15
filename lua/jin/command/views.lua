-- The Ex commands that open views, such as :JinLog. Each takes the ++
-- options of view.OPTIONS, then jj arguments that follow its jj words.

local view = require("jin.view")

local M = {}

---@class jin.ViewCommand: jin.CompletedCommand
---@field view string

---@type table<string, jin.ViewCommand>
M.COMMANDS = {
  JinLog = { name = "JinLog", shortest = 4, view = "log", jj = { "log" }, options = view.OPTIONS },
  JinShow = {
    name = "JinShow",
    shortest = 4,
    view = "show",
    jj = { "show" },
    options = view.OPTIONS,
  },
  JinDiff = {
    name = "JinDiff",
    shortest = 4,
    view = "diff",
    jj = { "diff" },
    options = view.OPTIONS,
  },
  JinFile = {
    name = "JinFile",
    shortest = 4,
    view = "file",
    jj = { "file", "show" },
    options = view.OPTIONS,
  },
  JinOpLog = {
    name = "JinOpLog",
    shortest = 4,
    view = "oplog",
    jj = { "op", "log" },
    options = view.OPTIONS,
  },
  JinEvolog = {
    name = "JinEvolog",
    shortest = 4,
    view = "evolog",
    jj = { "evolog" },
    options = view.OPTIONS,
  },
}

---Open the view of the Ex command `name` for its arguments as typed.
---@param jin jin.Api
---@param host jin.Host
---@param name string
---@param line string
---@param opts { bang?: boolean, mods?: string }
function M.run(jin, host, name, line, opts)
  local command = M.COMMANDS[name]
  if not command then
    error("jin: unknown command: " .. tostring(name), 0)
  end
  view.command(jin, host, command.view, line, opts)
end

---The view command the command line `cmdline` invokes, if any.
---@param cmdline string
---@return jin.ViewCommand?
function M.find(cmdline)
  for word in cmdline:gmatch("%S+") do
    for _, command in pairs(M.COMMANDS) do
      if #word >= command.shortest and command.name:sub(1, #word) == word then
        return command
      end
    end
  end
  return nil
end

return M
