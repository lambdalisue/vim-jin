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
