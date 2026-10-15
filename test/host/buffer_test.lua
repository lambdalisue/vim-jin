local h = dofile("test/host/helper.lua")
local host = require("jin.host")

local function lines(bufnr)
  return host.list(vim.fn.getbufline(bufnr, 1, "$"))
end

local function option(bufnr, name)
  return vim.fn.getbufvar(bufnr, "&" .. name)
end

local highlights = h.highlights

local function content(text, extra)
  local c = { lines = text, highlights = {}, groups = {}, filetype = "jin-test" }
  for k, v in pairs(extra or {}) do
    c[k] = v
  end
  return c
end

return {
  {
    "open opens a buffer by name with the opener and modifiers",
    function()
      h.ex("only")
      local bufnr = host.open("jin-test://open", { opener = "split", mods = "botright" })
      h.eq(2, vim.fn.winnr("$"))
      h.eq(vim.fn.bufnr(), bufnr)
      h.eq("jin-test://open", vim.fn.bufname(bufnr))
      h.ex("only")
    end,
  },
  {
    "render replaces the lines and makes a read-only scratch buffer",
    function()
      local bufnr = host.open("jin-test://render", {})
      host.render(bufnr, content({ "a", "b", "c" }))
      host.render(bufnr, content({ "x" }))
      h.eq({ "x" }, lines(bufnr))
      h.eq("nofile", option(bufnr, "buftype"))
      h.eq(0, option(bufnr, "modifiable"))
      h.eq(0, option(bufnr, "modified"))
      h.eq(0, option(bufnr, "swapfile"))
      h.eq("jin-test", option(bufnr, "filetype"))
    end,
  },
  {
    "render shows an empty buffer for no lines",
    function()
      local bufnr = host.open("jin-test://empty", {})
      host.render(bufnr, content({}))
      h.eq({ "" }, lines(bufnr))
    end,
  },
  {
    "render highlights the given ranges with groups it defines",
    function()
      local bufnr = host.open("jin-test://hl", {})
      host.render(
        bufnr,
        content({ "red bold" }, {
          highlights = {
            { line = 1, col = 1, end_col = 4, group = "JinTestRed" },
            { line = 1, col = 5, end_col = 9, group = "JinTestBold" },
          },
          groups = { JinTestRed = { fg = 1 }, JinTestBold = { bold = true } },
        })
      )
      h.eq({ "JinTestRed", "JinTestBold" }, highlights(bufnr))
      h.eq(1, vim.fn.hlexists("JinTestRed"))
      h.eq("1", vim.fn.synIDattr(vim.fn.hlID("JinTestRed"), "fg", "cterm"))
      h.eq("1", vim.fn.synIDattr(vim.fn.hlID("JinTestBold"), "bold", "cterm"))
      host.render(bufnr, content({ "plain" }))
      h.eq({}, highlights(bufnr))
    end,
  },
  {
    "render keeps the cursor of the window showing the buffer",
    function()
      local bufnr = host.open("jin-test://view", {})
      host.render(bufnr, content({ "1", "2", "3", "4" }))
      vim.fn.cursor(3, 1)
      host.render(bufnr, content({ "a", "b", "c", "d", "e" }))
      h.eq(3, vim.fn.line("."))
    end,
  },
  {
    "buffers lists the loaded buffers with their names",
    function()
      local bufnr = host.open("jin-test://listed", {})
      local found
      for _, buf in ipairs(host.buffers()) do
        if buf.bufnr == bufnr then
          found = buf.name
        end
      end
      h.eq("jin-test://listed", found)
    end,
  },
}
