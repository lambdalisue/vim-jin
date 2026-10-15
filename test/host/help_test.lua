local h = dofile("test/host/helper.lua")
local host = require("jin.host")

---Copy doc/ into a fresh directory and build its tags there, so that the
---checkout gets no tags file.
local function tags()
  local dir = h.tempdir()
  vim.fn.mkdir(dir .. "/doc", "p")
  vim.fn.writefile(vim.fn.readfile("doc/jin.txt"), dir .. "/doc/jin.txt")
  h.ex("helptags " .. vim.fn.fnameescape(dir .. "/doc"))
  local found = {}
  for _, line in ipairs(host.list(vim.fn.readfile(dir .. "/doc/tags"))) do
    found[line:match("^[^\t]+")] = true
  end
  return found
end

return {
  {
    "the help builds its tags and has one for every command",
    function()
      local found = tags()
      for _, tag in ipairs({
        ":Jin",
        ":JinBuffer",
        ":JinLog",
        ":JinShow",
        ":JinDiff",
        ":JinFile",
        ":JinOpLog",
        ":JinEvolog",
        "jin-mappings",
        "jin-blocks",
        "<Plug>(jin-next-block)",
        "jin-actions",
        "hl-JinCursorEntry",
        "b:jin_title",
        "jin.jj()",
      }) do
        h.truthy(found[tag], "no tag " .. tag)
      end
    end,
  },
}
