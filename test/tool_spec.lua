local tool = require("jin.tool")

describe("jin.tool.args", function()
  it(
    "passes jj a diff editor of vim-jin's own with an output to fill, answering through the named pipe",
    function()
      local argv = tool.args("/tmp/jin.fifo")
      assert.same({ "--tool", "jin", "--config", 'merge-tools.jin.program="sh"', "--config" }, {
        argv[1],
        argv[2],
        argv[3],
        argv[4],
        argv[5],
      })
      local edit = argv[6]
      assert.truthy(edit:find("^merge%-tools%.jin%.edit%-args=%["))
      assert.truthy(edit:find("'/tmp/jin.fifo', '$left', '$right', '$output'%]$"))
    end
  )
end)

describe("jin.tool.parse", function()
  it("reads the line the diff editor writes on stderr", function()
    assert.same(
      {
        kind = "diff",
        fifo = "/tmp/jin.fifo",
        left = "/tmp/jj-diff/left",
        right = "/tmp/jj-diff/right",
        output = "/tmp/jj-diff/output",
      },
      tool.parse(
        "\30jin\31/tmp/jin.fifo\31/tmp/jj-diff/left\31/tmp/jj-diff/right\31/tmp/jj-diff/output"
      )
    )
  end)

  it("takes any other line of stderr for jj's own", function()
    assert.is_nil(tool.parse("Warning: All changes have been selected"))
  end)
end)

describe("the merge tool", function()
  it("is passed with its conflict markers in the output to edit", function()
    local argv = require("jin.tool").merge_args("/tmp/jin.fifo")
    assert.same({ "--tool", "jin" }, { argv[1], argv[2] })
    local joined = table.concat(argv, " ")
    assert.truthy(joined:find("merge-tools.jin.merge-tool-edits-conflict-markers=true", 1, true))
    assert.truthy(joined:find("'/tmp/jin.fifo', '$base', '$left', '$right', '$output'%]"))
  end)

  it("asks for the four files of a conflict", function()
    assert.same({
      kind = "merge",
      fifo = "/f",
      base = "/b",
      left = "/l",
      right = "/r",
      output = "/o",
    }, require("jin.tool").parse("\30jin-merge\31/f\31/b\31/l\31/r\31/o"))
  end)
end)
