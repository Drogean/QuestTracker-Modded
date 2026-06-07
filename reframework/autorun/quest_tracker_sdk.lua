-- quest_tracker_sdk — SDK helpers (td, safe_call, guid text)
local M = package.loaded["quest_tracker_sdk"]
if M then return M end
M = {}

function M.install(ctx)
  local mod = ctx.mod
  local mlog = ctx.mlog
  local mlog_boot = ctx.mlog_boot

  local function td(n) return sdk.find_type_definition(n) end

  local function safe_get_field(obj, name)
      if obj == nil then return nil end
      local ok, res = pcall(function() return obj:get_field(name) end)
      return ok and res or nil
  end

  local function safe_call(obj, name, ...)
      if obj == nil then return nil end
      local args = {...}
      local ok, res = pcall(function() return obj:call(name, table.unpack(args)) end)
      return ok and res or nil
  end

  local function call_method(m, this, ...)
      if m == nil then return nil end
      local args = {...}
      local ok, res = pcall(function() return m:call(this, table.unpack(args)) end)
      return ok and res or nil
  end

  local function iter_list(list, cb)
      if list == nil then return end
      local ok_sz, asz = pcall(function() return list:get_size() end)
      if ok_sz and type(asz) == "number" and asz > 0 then
          for i = 0, asz - 1 do
              local okEl, el = pcall(function() return list:get_element(i) end)
              if okEl and el ~= nil then cb(el, i) end
          end
          return
      end
      local c = safe_call(list, "get_Count") or safe_call(list, "getCount") or safe_call(list, "get_size")
      if c ~= nil then
          for i = 0, c - 1 do
              local el = safe_call(list, "get_Item", i) or safe_call(list, "getItem", i)
              if el == nil then
                  local okEl, e2 = pcall(function() return list:get_element(i) end)
                  if okEl then el = e2 end
              end
              if el ~= nil then cb(el, i) end
          end
          return
      end
      local items = safe_get_field(list, "_items")
      if items then
          local ok, sz = pcall(function() return items:get_size() end)
          if ok and sz then
              for i = 0, sz - 1 do
                  local okEl, el = pcall(function() return items:get_element(i) end)
                  if okEl and el then cb(el, i) end
              end
          end
      end
  end

  local function iter_array(arr, cb)
      if arr == nil then return end
      local ok, sz = pcall(function() return arr:get_size() end)
      if ok and sz then
          for i = 0, sz - 1 do
              local okEl, el = pcall(function() return arr:get_element(i) end)
              if okEl and el ~= nil then cb(el, i) end
          end
      end
  end

  local function to_int(x)
      if type(x) == "number" then return x end
      if type(x) == "userdata" then
          local ok, v = pcall(function() return x:get_field("value__") end)
          if ok and type(v) == "number" then return v end
      end
      return nil
  end

  local function cid_eq(a, b)
      if a == nil or b == nil then return false end
      if a == b then return true end
      -- handle signed/unsigned wrapping for uint32 CIDs
      local function norm(v)
          if type(v) == "number" and v < 0 then return v + 4294967296 end
          return v
      end
      return norm(a) == norm(b)
  end

  local function cid_norm(v)
      if v == nil then return nil end
      if type(v) == "number" and v < 0 then return v + 4294967296 end
      return v
  end
  local function dump_quest_id_enum()
      local t = td("app.QuestDefine.ID")
      if t == nil then return {} end
      local out = {}
      for _, f in ipairs(t:get_fields()) do
          if f:is_static() and f:is_literal() then
              local ok, v = pcall(function() return f:get_data(nil) end)
              if ok and type(v) == "number" then out[v] = f:get_name() end
          end
      end
      return out
  end
  local function init_english_lookup()
      if LANG_EN ~= nil then return end
      local lt = td("via.Language")
      if lt then
          for _, f in ipairs(lt:get_fields()) do
              if f:is_static() and f:is_literal() then
                  local nm = f:get_name()
                  if nm == "English" or nm == "ENGLISH" then
                      local ok, v = pcall(function() return f:get_data(nil) end)
                      if ok and type(v) == "number" then LANG_EN = v; break end
                  end
              end
          end
      end
      if LANG_EN == nil then LANG_EN = 1 end
      if mod._guid_lookup_ok == false then return end
      local mt = td("via.gui.message")
      if mt then
          MSG_GET = mt:get_method("get(System.Guid)")
          MSG_GET_LANG = mt:get_method("get(System.Guid, via.Language)")
      end
      local gt = td("System.Guid")
      if gt then GUID_PARSE = gt:get_method("Parse(System.String)") end
      if not MSG_GET and not MSG_GET_LANG then
          mod._guid_lookup_ok = false
          mlog_boot("[QT] guid text lookup OFF (via.gui.message unavailable)")
      end
  end

  local function _guid_to_en_text(guid)
      if guid == nil then return nil end
      if mod._guid_lookup_ok == false then return nil end
      if MSG_GET == nil then init_english_lookup() end
      if mod._guid_lookup_ok == false then return nil end
      local tries = {}
      if MSG_GET_LANG then tries[#tries + 1] = function() return MSG_GET_LANG:call(nil, guid, LANG_EN) end end
      if MSG_GET then tries[#tries + 1] = function() return MSG_GET:call(nil, guid) end end
      for _, fn in ipairs(tries) do
          local ok, s = pcall(fn)
          if ok and type(s) == "string" and s ~= "" then return s end
          if not ok then
              mod._guid_lookup_ok = false
              mlog_boot("[QT] guid text lookup disabled after via.gui.message error")
              return nil
          end
      end
      return nil
  end

  local function _text_from_hex32(hex)
      if mod._guid_lookup_ok == false then return nil end
      if type(hex) ~= "string" then return nil end
      hex = hex:lower():gsub("[^0-9a-f]", "")
      if #hex ~= 32 then return nil end
      if GUID_PARSE == nil then init_english_lookup() end
      if mod._guid_lookup_ok == false or not GUID_PARSE then return nil end
      local gs = string.format("%s-%s-%s-%s-%s", hex:sub(1, 8), hex:sub(9, 12), hex:sub(13, 16), hex:sub(17, 20), hex:sub(21, 32))
      local ok, g = pcall(function() return GUID_PARSE:call(nil, gs) end)
      if ok and g then return _guid_to_en_text(g) end
      return nil
  end
  local function _read_text_field(obj, string_keys, guid_keys)
      if obj == nil then return nil, nil end
      for _, key in ipairs(string_keys) do
          local v = safe_get_field(obj, key)
          if type(v) == "string" and v ~= "" then return v, nil end
      end
      for _, key in ipairs(guid_keys) do
          local t = _guid_to_en_text(safe_get_field(obj, key))
          if t then return t, key end
      end
      return nil, nil
  end
  ctx.td = td
  ctx.safe_get_field = safe_get_field
  ctx.safe_call = safe_call
  ctx.call_method = call_method
  ctx.iter_list = iter_list
  ctx.iter_array = iter_array
  ctx.to_int = to_int
  ctx.cid_eq = cid_eq
  ctx.cid_norm = cid_norm
  ctx.dump_quest_id_enum = dump_quest_id_enum
  ctx.init_english_lookup = init_english_lookup
  ctx._guid_to_en_text = _guid_to_en_text
  ctx._text_from_hex32 = _text_from_hex32
  ctx._read_text_field = _read_text_field

end

return M
