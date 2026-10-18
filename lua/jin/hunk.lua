-- The hunks between lines of text, and the hunk of a result between two
-- sides, for taking both sides of it at once as the panes of a diff editor
-- and a merge tool do.

local M = {}

---The pairs of lines of `a` and `b` that stay, by index, in order: Myers'
---diff, of the part between the lines both start and end with.
---@param a string[]
---@param b string[]
---@return { [1]: integer, [2]: integer }[]
local function matches(a, b)
  local first = 1
  while first <= #a and first <= #b and a[first] == b[first] do
    first = first + 1
  end
  local a_last, b_last = #a, #b
  while a_last >= first and b_last >= first and a[a_last] == b[b_last] do
    a_last, b_last = a_last - 1, b_last - 1
  end
  local pairs_found = {}
  for i = 1, first - 1 do
    pairs_found[#pairs_found + 1] = { i, i }
  end
  local n, m = a_last - first + 1, b_last - first + 1
  local offset = first - 1
  local v, trace = { [1] = 0 }, {}
  local found_d
  for d = 0, n + m do
    local copy = {}
    for k, x in pairs(v) do
      copy[k] = x
    end
    trace[d] = copy
    for k = -d, d, 2 do
      local x
      if k == -d or (k ~= d and v[k - 1] < v[k + 1]) then
        x = v[k + 1]
      else
        x = v[k - 1] + 1
      end
      local y = x - k
      while x < n and y < m and a[offset + x + 1] == b[offset + y + 1] do
        x, y = x + 1, y + 1
      end
      v[k] = x
      if x >= n and y >= m then
        found_d = d
        break
      end
    end
    if found_d then
      break
    end
  end
  local middle = {}
  local x, y = n, m
  for d = found_d, 0, -1 do
    local prev = trace[d]
    local k = x - y
    local prev_k
    if k == -d or (k ~= d and (prev[k - 1] or -1) < (prev[k + 1] or -1)) then
      prev_k = k + 1
    else
      prev_k = k - 1
    end
    local prev_x = prev[prev_k] or 0
    local prev_y = prev_x - prev_k
    while x > prev_x and y > prev_y do
      middle[#middle + 1] = { offset + x, offset + y }
      x, y = x - 1, y - 1
    end
    if d > 0 then
      x, y = prev_x, prev_y
    end
  end
  for i = #middle, 1, -1 do
    pairs_found[#pairs_found + 1] = middle[i]
  end
  for i = 1, #a - a_last do
    pairs_found[#pairs_found + 1] = { a_last + i, b_last + i }
  end
  return pairs_found
end

---The hunks where `b` differs from `a`, each as { start in a, lines in a,
---start in b, lines in b }; a side with no lines starts where its lines
---would go.
---@param a string[]
---@param b string[]
---@return { [1]: integer, [2]: integer, [3]: integer, [4]: integer }[]
function M.diff(a, b)
  local hunks = {}
  local pa, pb = 0, 0
  local all = matches(a, b)
  all[#all + 1] = { #a + 1, #b + 1 }
  for _, pair in ipairs(all) do
    if pair[1] > pa + 1 or pair[2] > pb + 1 then
      hunks[#hunks + 1] = { pa + 1, pair[1] - pa - 1, pb + 1, pair[2] - pb - 1 }
    end
    pa, pb = pair[1], pair[2]
  end
  return hunks
end

---The lines `first`..`last` of `lines`.
---@param lines string[]
---@param first integer
---@param last integer
---@return string[]
local function slice(lines, first, last)
  local out = {}
  for i = first, last do
    out[#out + 1] = lines[i]
  end
  return out
end

---The hunk of `result` at line `lnum`, where it differs from `left` or
---`right`, or from both, and overlapping or touching hunks with it: the
---lines it spans in `result` as { first, last }, empty when last < first,
---and what each side has in their place. Lines a side has and the result
---lacks count from the line below them, as Vim shows them above it. Nil
---where the result agrees with both sides.
---@param left string[]
---@param result string[]
---@param right string[]
---@param lnum integer
---@return { result: { [1]: integer, [2]: integer }, left: string[], right: string[] }?
function M.at(left, result, right, lnum)
  local diffs = { M.diff(result, left), M.diff(result, right) }
  local first, last
  local included = { {}, {} }
  for side, hunks in ipairs(diffs) do
    for i, h in ipairs(hunks) do
      local s, e = h[1], h[1] + h[2] - 1
      local here
      if h[2] > 0 then
        here = s <= lnum and lnum <= e
      else
        here = s == lnum or (s == #result + 1 and lnum == #result)
      end
      if here then
        included[side][i] = true
        first = math.min(first or s, s)
        last = math.max(last or e, e)
      end
    end
  end
  if not first then
    return nil
  end
  local grew = true
  while grew do
    grew = false
    for side, hunks in ipairs(diffs) do
      for i, h in ipairs(hunks) do
        local s, e = h[1], h[1] + h[2] - 1
        if not included[side][i] and s <= last + 1 and e + 1 >= first then
          included[side][i] = true
          first, last = math.min(first, s), math.max(last, e)
          grew = true
        end
      end
    end
  end
  local sides = {}
  for side, hunks in ipairs(diffs) do
    local before, within = 0, 0
    for i, h in ipairs(hunks) do
      if included[side][i] then
        within = within + h[4] - h[2]
      elseif h[1] < first then
        before = before + h[4] - h[2]
      end
    end
    local lines = side == 1 and left or right
    sides[side] = slice(lines, first + before, last + before + within)
  end
  return { result = { first, last }, left = sides[1], right = sides[2] }
end

---Whether a hunk starting at `start` with `count` lines, in lines of
---`size` in all, lies at lines `first`..`last`: overlaps them, or, with no
---lines, lies just above one of them or below the last line.
---@return boolean
local function lies_at(start, count, size, first, last)
  if count > 0 then
    return start <= last and start + count - 1 >= first
  end
  return (first <= start and start <= last) or (start == size + 1 and last >= size)
end

---The hunks between `result` and `side` at lines `first`..`last` of the
---result, or of the side with `of_side`, each as the lines it spans in the
---result, empty when last < first, and what the side has in their place.
---@param result string[]
---@param side string[]
---@param first integer
---@param last integer
---@param of_side? boolean
---@return { result: { [1]: integer, [2]: integer }, lines: string[] }[]
function M.select(result, side, first, last, of_side)
  local found = {}
  for _, h in ipairs(M.diff(result, side)) do
    local here
    if of_side then
      here = lies_at(h[3], h[4], #side, first, last)
    else
      here = lies_at(h[1], h[2], #result, first, last)
    end
    if here then
      found[#found + 1] =
        { result = { h[1], h[1] + h[2] - 1 }, lines = slice(side, h[3], h[3] + h[4] - 1) }
    end
  end
  return found
end

return M
