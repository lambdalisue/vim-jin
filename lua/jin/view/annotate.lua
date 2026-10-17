-- A file with, on each line, the change that last touched it. The buffer
-- holds the file itself, highlighted as the file; what the template prints
-- before each line shows in front of it as virtual text, so that the two
-- never fall apart.

local action = require("jin.action")
local support = require("jin.view.support")

local actions = {}

action.openers(actions, "show", "show the change that wrote the line", function(ctx, opener)
  support.open(ctx, "show", { support.revision(action.entry(ctx)) }, opener)
end)

action.openers(
  actions,
  "diff",
  "show the diff of the change that wrote the line",
  function(ctx, opener)
    support.open(ctx, "diff", { "-r", support.revision(action.entry(ctx)) }, opener)
  end
)

action.openers(
  actions,
  "log",
  "show the log up to the change that wrote the line",
  function(ctx, opener)
    support.open(ctx, "log", { "-r", "::" .. support.revision(action.entry(ctx)) }, opener)
  end
)

action.openers(
  actions,
  "log:file",
  "show the log of the changes that touched the file, up to this revision",
  support.file_log
)

action.openers(actions, "file", "show the file without the annotation", function(ctx, opener)
  local rev, path = support.shown_file(ctx)
  support.open(ctx, "file", { "-r", rev, support.fileset(path) }, opener, ctx.first)
end)

support.describe_actions(actions)
support.commit_actions(actions)
support.select_actions(actions)
support.yank_actions(actions)

---The first `width` bytes of `line` as chunks of text, each with the style
---`spans` (those of the line, in order) give it.
---@param line string
---@param width integer
---@param spans jin.AnsiSpan[]
---@return { text: string, style?: jin.AnsiStyle }[]
local function chunks(line, width, spans)
  local out, col = {}, 1
  for _, span in ipairs(spans) do
    if span.col > width then
      break
    end
    if span.col > col then
      out[#out + 1] = { text = line:sub(col, span.col - 1) }
    end
    local stop = math.min(span.end_col, width + 1)
    out[#out + 1] = { text = line:sub(span.col, stop - 1), style = span.style }
    col = stop
  end
  if col <= width then
    out[#out + 1] = { text = line:sub(col, width) }
  end
  return out
end

---Split every line into the annotation the template printed and the line of
---the file at its end. Nil unless every line is one entry ending with its
---content: a template that prints the content elsewhere, or over several
---lines, cannot be split.
---@param meta jin.ViewMeta
---@return string[]? texts
---@return { text: string, style?: jin.AnsiStyle }[][]? annotations
local function split(meta)
  local spans = {}
  for _, span in ipairs(meta.spans) do
    spans[span.line] = spans[span.line] or {}
    table.insert(spans[span.line], span)
  end
  local texts, annotations = {}, {}
  for lnum, line in ipairs(meta.lines) do
    local entry = meta.entries[lnum]
    if not entry or entry == meta.entries[lnum - 1] then
      return nil
    end
    local content = (entry[4] or ""):gsub("\n$", "")
    local cut = #line - #content
    if cut < 0 or line:sub(cut + 1) ~= content then
      return nil
    end
    texts[lnum] = content
    annotations[lnum] = chunks(line, #(line:sub(1, cut):gsub("%s+$", "")), spans[lnum] or {})
  end
  return texts, annotations
end

local ANNOTATE_FIELDS = {
  "commit.change_id()",
  "commit.commit_id()",
  'if(commit.divergent(), "divergent", if(commit.hidden(), "hidden", "-"))',
  "content",
}

---@type jin.View
return {
  command = { "file", "annotate" },
  filetype = "jin-annotate",
  template = {
    key = "file_annotate",
    default = 'commit.change_id().shortest(8) ++ " " ++ content',
    fields = ANNOTATE_FIELDS,
  },
  decorate = function(meta)
    local texts, annotations = split(meta)
    if texts then
      meta.lines = texts
      meta.spans = {}
      meta.data.annotations = annotations
    end
  end,
  detect = function(meta)
    return meta.data.annotations and support.file_path(meta.parsed.argv) or nil
  end,
  actions = actions,
  scattered_changes = true,
  blocks = require("jin.view.block").changes,
  needs_path = true,
  primary = "show",
  yank = "yank:change",
}
