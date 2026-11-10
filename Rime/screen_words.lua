-- RimeScreenWords local screen vocabulary.
local M = {}

-- Two-letter buckets keep prefix lookup proportional to matching vocabulary.
local function add(index, code, word, seen)
  local prefix = code:sub(1, 2)
  local bucket = index[prefix] or {}
  index[prefix] = bucket
  local mixed = word:find("%a") and word:find("[^%z\1-\127]") and #code > #word:gsub("[^%w]", "")
  local row = {code = code, word = word, seen = seen, mixed = mixed == true}
  bucket[code .. "\t" .. word] = row
  return row
end

-- Allow an exact Chinese tail to recall the adjacent English label in slot two.
-- The candidate retains the full key for selection and long-term learning.
local function index_context(context, row)
  if not row.mixed then return end
  local label, tail = row.word:match("^([%a%d%._%s%-]+)([^%z\1-\127]+)$")
  if not label or not label:find("%a") then return end
  local n = #label:gsub("[^%w]", "")
  local key = row.code:sub(n + 1)
  if #key < 6 or #key ~= 2 * (utf8.len(tail) or 0) then return end
  local bucket = context[key] or {}
  context[key] = bucket
  local old = bucket[tail]
  local rank = row.seen == 0 and math.huge or row.seen
  if not old or rank > old.rank or (rank == old.rank and
      (#row.code < #old.code or (#row.code == #old.code and row.word < old.word))) then
    bucket[tail] = {word = row.word, code = row.code, rank = rank}
  end
end

local function read_snapshot(env, now)
  local file = io.open(env.path, "r")
  if not file then
    env.rows, env.context, env.version = {}, {}, nil
    return
  end
  local expiry, version = (file:read("*l") or ""):match("^(%d+)\t([%w%-]+)$")
  if not expiry or tonumber(expiry) <= now then
    env.rows, env.context, env.version = {}, {}, nil
  elseif env.version ~= version then
    local rows, context = {}, {}
    for line in file:lines() do
      local code, word, seen = line:match("^([a-z0-9_]+)\t([^%c]+)\t(%d+)$")
      if not code then -- Live snapshot written by the earlier helper.
        code, word = line:match("^([a-z0-9_]+)\t([^%c]+)$")
      end
      if code then index_context(context, add(rows, code, word, tonumber(seen) or 0)) end
    end
    env.rows, env.context, env.version = rows, context, version
  end
  file:close()
end

-- Each committed full key/word pair is appended once. Other sessions pick up
-- new records by byte offset. A partially written final line is retried later.
local function read_selected(env)
  local file = io.open(env.selected_path, "rb")
  if not file then
    env.selected, env.offset = {}, 0
    return
  end
  local size = file:seek("end")
  if size < env.offset then env.selected, env.offset = {}, 0 end
  if size > env.offset then
    file:seek("set", env.offset)
    local tail = file:read("*a")
    for line in tail:gmatch("([^\n]*)\n") do
      local code, word = line:match("^([a-z0-9_]+)\t([^%c]+)$")
      if code then add(env.selected, code, word, -1) end
      env.offset = env.offset + #line + 1
    end
  end
  file:close()
end

local function remember(env, segment)
  if segment.status ~= "kSelected" and segment.status ~= "kConfirmed" then return end
  local candidate = segment:get_selected_candidate()
  if not candidate then return end
  local code = candidate:get_genuine().type:match("^screen_words:([a-z0-9_]+)$")
  local word = candidate.text
  if not code or word == "" or word:find("%c") then return end
  read_selected(env)
  local bucket = env.selected[code:sub(1, 2)]
  if bucket and bucket[code .. "\t" .. word] then return end
  local file = io.open(env.selected_path, "ab")
  if not file then log.error("rime-jit: cannot open selected-word file"); return end
  local written = file:write(code .. "\t" .. word .. "\n")
  local closed = file:close()
  if not written or not closed then log.error("rime-jit: cannot save selected word") end
end

-- Squirrel owns the current composition. A late clear from another context
-- must not remove its marker. No input text is written to the activity channel.
local owner
local function end_activity(env)
  if owner == env.activity_id then
    os.remove(env.marker)
    owner = nil
  end
end

local function update_activity(env, ctx)
  if not ctx:is_composing() or ctx:get_option("ascii_mode") then
    end_activity(env)
    return
  end
  -- A new helper or focus change may have cleared our previous marker.
  if owner == env.activity_id then
    local existing = io.open(env.marker, "r")
    if existing then existing:close(); return end
  end
  local marker = io.open(env.marker, "w")
  if marker then marker:close(); owner = env.activity_id end
end

function M.init(env)
  env.path = os.getenv("HOME") .. "/Library/Caches/RimeScreenWords/words.tsv"
  env.marker = os.getenv("HOME") .. "/Library/Caches/RimeScreenWords/activity/composing"
  env.activity_id = {}
  local ctx = env.engine.context
  env.activity = ctx.update_notifier:connect(function(ctx) update_activity(env, ctx) end)
  env.ascii = ctx.option_update_notifier:connect(function(ctx, name)
    if name == "ascii_mode" then update_activity(env, ctx) end
  end)
  local schema = env.engine.schema.schema_id:gsub("[^%w_%-]", "_")
  env.selected_path = rime_api.get_user_data_dir() .. "/rime-jit-selected-" .. schema .. ".tsv"
  env.rows, env.selected, env.offset = {}, {}, 0
  env.connection = env.engine.context.commit_notifier:connect(function(ctx)
    end_activity(env)
    for _, segment in ipairs(ctx.composition:toSegmentation():get_segments()) do
      remember(env, segment)
    end
  end)
end

function M.fini(env)
  end_activity(env)
  env.activity:disconnect()
  env.ascii:disconnect()
  env.connection:disconnect()
end

function M.func(input, seg, env)
  if not seg:has_tag("abc") or not input:match("^[a-z' ]+$") then return end
  local key = input:gsub("[' ]", "")
  if #key < 2 then return end
  local now = os.time()
  read_snapshot(env, now)
  read_selected(env)
  local flypyKey = key:gsub("([a-z])([a-z])", function(initial, final)
    if final == "v" and initial:match("[jqxy]") then final = "u" end
    return initial .. final
  end)
  local context = env.context[flypyKey] or {}
  local matches = {}
  local function collect(bucket)
    for _, row in pairs(bucket or {}) do
      local query = key
      if not row.word:find("%a") then query = flypyKey end
      local age = row.seen
      if (age <= 0 or age + 300 > now) and
          (row.code == query or (#query >= 3 and row.code:sub(1, #query) == query)) then
        local rank = age == 0 and math.huge or age
        local old = matches[row.word]
        local exact = #row.code == #key
        if not old or (exact and not old.exact) or (exact == old.exact and
            (rank > old.rank or (rank == old.rank and row.code < old.code))) then
          matches[row.word] = {word = row.word, code = row.code, rank = rank, exact = exact, mixed = row.mixed}
        end
      end
    end
  end
  local prefix, flypyPrefix = key:sub(1, 2), flypyKey:sub(1, 2)
  for _, index in ipairs({env.rows, env.selected}) do
    collect(index[prefix])
    if prefix ~= flypyPrefix then collect(index[flypyPrefix]) end
  end
  local ordered = {}
  for _, row in pairs(matches) do ordered[#ordered + 1] = row end
  table.sort(ordered, function(a, b)
    if a.exact ~= b.exact then return a.exact end
    if a.rank ~= b.rank then return a.rank > b.rank end
    if a.exact then
      if a.mixed ~= b.mixed then return a.mixed end
      local ac, bc = context[a.word], context[b.word]
      if ac and ac.rank < a.rank then ac = nil end
      if bc and bc.rank < b.rank then bc = nil end
      if ac and bc and ac.word ~= bc.word then return ac.word < bc.word end
      if (ac ~= nil) ~= (bc ~= nil) then return ac ~= nil end
    end
    if #a.code ~= #b.code then return #a.code < #b.code end
    return a.word < b.word
  end)
  local best = ordered[1]
  local expansion = best and best.exact and context[best.word]
  if expansion and expansion.rank >= best.rank and expansion.rank + 300 > now then
    ordered[2] = expansion
  end
  for i = 1, math.min(2, #ordered) do
    local row = ordered[i]
    local label = row.rank == -1 and "记" or "屏"
    local cand = Candidate("screen_words:" .. row.code, seg.start, seg._end, row.word, label)
    -- An exact mixed span is direct evidence for the spelling of the whole input.
    cand.quality = row.exact and (row.mixed and 4 or 2) or 0.5
    yield(cand)
  end
end

return M
