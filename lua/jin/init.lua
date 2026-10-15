-- The public Lua API of vim-jin, for its own features and for other plugins,
-- bound to the running editor. The editor is first reached on the first call,
-- so requiring this module needs no editor. See jin.api for the functions.

return require("jin.api").new(function()
  return require("jin.host")
end)
