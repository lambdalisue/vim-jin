-- The description of the working copy in a buffer to edit, committed with
-- jj commit once written.

local description = require("jin.description")
local support = require("jin.view.support")

---@type jin.View
return {
  command = { "log" },
  flags = { "--no-graph" },
  title = { "commit" },
  filetype = "jjdescription",
  template = {
    key = "draft_commit_description",
    default = "builtin_draft_commit_description",
    fields = support.DESCRIBED_FIELDS,
  },
  editable = true,
  decorate = function(meta)
    meta.data.originals = support.originals(meta)
  end,
  ---Commit the working copy with what the buffer says, as long as it is still
  ---the change the buffer was opened for: jj commit takes whatever the
  ---working copy is, and committing another change with this text would be
  ---a mistake.
  write = function(jin, host, bufnr, parsed)
    local opened = parsed.argv[2]
    local now = support.working_copy(jin, parsed.root)
    if now ~= opened then
      error(
        ("jin: the working copy is no longer %s; commit it again from a view"):format(opened),
        0
      )
    end
    local meta = require("jin.view").meta(host, bufnr)
    support.refuse_changed(jin, parsed.root, meta and meta.data.originals or {}, { opened })
    local written = host.lines(bufnr)
    local text = description.text(written)
    -- -m, as jj commit reads no description from its input.
    jin.command({ "commit", "-m", text }, { cwd = parsed.root, quiet = true }, function(result)
      -- Left open otherwise, as what it holds was not committed.
      if result.code == 0 and support.mark_saved(host, bufnr, written) then
        support.leave_commit(host, bufnr)
      end
    end)
  end,
}
