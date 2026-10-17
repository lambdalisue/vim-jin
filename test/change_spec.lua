local fake_host = require("support.fake_host")
local api = require("jin.api")
local view = require("jin.view")
local action = require("jin.action")

local function ok(stdout, stderr)
  return { code = 0, stdout = stdout or "", stderr = stderr or "" }
end

local function setup()
  local host = fake_host.new({ cwd = "/repo", dirs = { "/repo", "/repo/.jj" } })
  local jin = api.new(function()
    return host
  end)
  return host, jin
end

local function m(...)
  local fields = {}
  for i, value in ipairs({ ... }) do
    fields[i] = '"' .. value:gsub('[\\"]', "\\%0") .. '"'
  end
  return "\30" .. table.concat(fields, " ") .. "\31"
end

local OUTPUT = m("kkk", "c1", "-") .. "x\n" .. m("zzz", "c2", "-") .. "y\n"

---A log showing kkk on line 1 and zzz on line 2.
local function log(host, jin, name)
  local bufnr = host.load(name)
  view.read(jin, host, bufnr, name)
  host.finish(ok("tpl\n"))
  host.finish(ok(OUTPUT))
  return bufnr
end

describe("changing the repository", function()
  it("never runs in a view at an earlier operation", function()
    for _, name in ipairs({ "describe", "commit" }) do
      local host, jin = setup()
      local bufnr = log(host, jin, "jin:///repo;view=log#--at-op op1")
      assert.has_error(function()
        action.run(jin, host, bufnr, name, 1, 1)
      end, "jin: this view shows an earlier operation, which is not to be changed")
      assert.equal(2, #host.runs)
    end
  end)
end)
