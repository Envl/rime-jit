-- RimeScreenWords local screen vocabulary.
-- One atomic snapshot per screen update. Read just the header on a cache hit.
local M = {}

function M.init(env)
  env.path = os.getenv("HOME") .. "/Library/Caches/RimeScreenWords/words.tsv"
  env.rows = {}
end

local function read_snapshot(env)
  local file = io.open(env.path, "r")
  if not file then
    env.rows, env.version = {}, nil
    return
  end
  local expiry, version = (file:read("*l") or ""):match("^(%d+)\t([%w%-]+)$")
  if not expiry or tonumber(expiry) <= os.time() then
    env.rows, env.version = {}, nil
  elseif env.version ~= version then
    local rows = {}
    for line in file:lines() do
      local code, word = line:match("^([a-z0-9_]+)\t([^%c]+)$")
      if code then rows[#rows + 1] = {code = code, word = word} end
      if #rows >= 2000 then break end
    end
    env.rows, env.version = rows, version
  end
  file:close()
end

function M.func(input, seg, env)
  if not seg:has_tag("abc") or not input:match("^[a-z' ]+$") then return end
  local key = input:gsub("[' ]", "")
  if #key < 2 then return end
  read_snapshot(env)

  -- The installed schema accepts both ju/jv, qu/qv, xu/xv and yu/yv.
  -- Normalize only at syllable boundaries and only when matching a Chinese word.
  local flypyKey = key:gsub("([a-z])([a-z])", function(initial, final)
    if final == "v" and initial:match("[jqxy]") then final = "u" end
    return initial .. final
  end)
  local matches = {}
  for _, row in ipairs(env.rows) do
    local query = row.word:byte() >= 128 and flypyKey or key
    if row.code == query or (#query >= 3 and row.code:sub(1, #query) == query) then
      matches[#matches + 1] = row
    end
  end
  table.sort(matches, function(a, b)
    if #a.code ~= #b.code then return #a.code < #b.code end
    return a.word < b.word
  end)
  for i = 1, math.min(2, #matches) do
    local row = matches[i]
    local cand = Candidate("screen_words", seg.start, seg._end, row.word, "屏")
    cand.quality = #row.code == #key and 2 or 0.5
    yield(cand)
  end
end

return M
