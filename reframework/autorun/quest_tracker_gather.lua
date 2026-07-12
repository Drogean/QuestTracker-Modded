-- quest_tracker_gather — gather/rebuild, NPC, time, meta resolve
local M = package.loaded["quest_tracker_gather"]
if M then return M end
M = {}

function M.install(ctx)
  local mod = ctx.mod
  local mlog = ctx.mlog
  local mlog_boot = ctx.mlog_boot
  local QD = ctx.QD
  local td = ctx.td
  local safe_get_field = ctx.safe_get_field
  local safe_call = ctx.safe_call
  local iter_list = ctx.iter_list
  local iter_array = ctx.iter_array
  local to_int = ctx.to_int
  local cid_eq = ctx.cid_eq
  local _guid_to_en_text = ctx._guid_to_en_text
  local mark_prefs_dirty = ctx.mark_prefs_dirty
  local TAB_NAMES = ctx.TAB_NAMES
  local FEAST_MILESTONE = ctx.FEAST_MILESTONE
  local PONR_NAMES = ctx.PONR_NAMES
  local BUNDLED_LOCKOUTS = ctx.BUNDLED_LOCKOUTS
  local BUNDLED_POS_OVERRIDES = ctx.BUNDLED_POS_OVERRIDES
  local MANUAL_POS_OVERRIDES = ctx.MANUAL_POS_OVERRIDES
  local MANUAL_GIVER_OVERRIDES = ctx.MANUAL_GIVER_OVERRIDES
  local VOIDED_QUESTS = ctx.VOIDED_QUESTS
  local LOCKED_QUESTS = ctx.LOCKED_QUESTS
  local QUEST_START_DAYS = ctx.QUEST_START_DAYS
  local QUEST_START_HOURS = ctx.QUEST_START_HOURS
  local LEARNED_CHARA_NAMES = ctx.LEARNED_CHARA_NAMES
  local MAP_API = ctx.MAP_API
  local MapBridge = ctx.MapBridge
  local COL_NPC_GOOD = ctx.COL_NPC_GOOD
  local COL_NPC_ORANGE = ctx.COL_NPC_ORANGE
  local COL_NPC_NEON_GREEN = ctx.COL_NPC_NEON_GREEN or COL_NPC_GOOD
  local NPC_SCAN_CACHE_TTL = ctx.NPC_SCAN_CACHE_TTL
  local ALL_IDS = ctx.ALL_IDS
  local dump_quest_id_enum = ctx.dump_quest_id_enum

  local function resolve_meta(qlm, qid)
      if mod.name_cache[qid] and mod.summary_cache[qid] ~= nil and mod.name_en_cache[qid] ~= nil then return end
      local vi = safe_call(qlm, "getQuestLog", qid)
      if vi == nil then return end
      mod._qt_name_guid_cache = mod._qt_name_guid_cache or {}
      for _, key in ipairs({ "QuestNameId", "_QuestNameId", "NameId", "_NameId", "TitleId", "_TitleId" }) do
          local g = safe_get_field(vi, key) or safe_call(vi, "get_" .. key)
          if g and type(g) ~= "string" and type(g) ~= "number" then
              mod._qt_name_guid_cache[qid] = g
              break
          end
      end
      local name = safe_get_field(vi, "QuestName")
      if type(name) == "string" and name ~= "" then mod.name_cache[qid] = name end
      local summary = safe_get_field(vi, "QuestSummary")
      if type(summary) == "string" then mod.summary_cache[qid] = summary end
      if mod.name_en_cache[qid] == nil and mod.name_cache[qid] then
          mod.name_en_cache[qid] = mod.name_cache[qid]
      end
  end
  local function qd_givers(qid)
      if not QD or not QD.get_givers then return nil end
      local ok, list = pcall(QD.get_givers, qid)
      if ok and type(list) == "table" and #list > 0 then return list end
      return nil
  end

  local function qd_prereqs(qid)
      if not QD or not QD.get_prereq_quests then return nil end
      local ok, list = pcall(QD.get_prereq_quests, qid)
      if ok and type(list) == "table" then return list end
      return nil
  end

  local function qd_note(qid)
      if not QD or not QD.get_note then return nil end
      local ok, v = pcall(QD.get_note, qid)
      return ok and v or nil
  end

  local function qd_time_limit(qid)
      if not QD or not QD.get_time_limit_days then return nil end
      local ok, v = pcall(QD.get_time_limit_days, qid)
      return ok and type(v) == "number" and v > 0 and v or nil
  end

  local function qd_locked_if(qid)
      if not QD or not QD.get_locked_if_completed then return nil end
      local ok, v = pcall(QD.get_locked_if_completed, qid)
      return ok and type(v) == "table" and v or nil
  end

  local function qd_lockout_after(qid)
      if not QD or not QD.get_lockout_after then return nil end
      local ok, v = pcall(QD.get_lockout_after, qid)
      return ok and type(v) == "number" and v or nil
  end

  local function qd_available_after(qid)
      if not QD or not QD.get_available_after then return nil end
      local ok, v = pcall(QD.get_available_after, qid)
      return ok and type(v) == "number" and v or nil
  end

  pcall(merge_meta_feast_lockouts)

  local PONR_NAMES = {
      [10140] = "Feast of Deception",
      [10170] = "A New Godsway",
      [10180] = "The Guardian Gigantus",
      [10190] = "Legacy",
  }

  local function story_gate_open(qid, completed)
      local aa = qd_available_after(qid)
      if type(aa) ~= "number" then return true end
      return completed[aa] == true
  end

  local function qd_iter_meta_qids()
      if not QD or not QD.iter_meta_qids then return {} end
      local ok, v = pcall(QD.iter_meta_qids)
      return (ok and type(v) == "table") and v or {}
  end

  local function qd_giver_name(qid)
      if not QD or not QD.get_giver_name then return nil end
      local ok, v = pcall(QD.get_giver_name, qid)
      if ok and type(v) == "string" and v ~= "" then return v end
      return nil
  end

  local function qd_timing_note(qid)
      if not QD or not QD.get_timing_note then return nil end
      local ok, v = pcall(QD.get_timing_note, qid)
      if ok and type(v) == "string" and v ~= "" then return v end
      return nil
  end

  local function qd_during_quest(qid)
      if not QD or not QD.get_during_quest then return nil end
      local ok, v = pcall(QD.get_during_quest, qid)
      if ok and type(v) == "string" and v ~= "" then return v end
      return nil
  end

  local function qd_trigger(qid)
      if not QD or not QD.get_trigger then return nil end
      local ok, v = pcall(QD.get_trigger, qid)
      if ok and type(v) == "string" and v ~= "" then return v end
      return nil
  end

  local function qd_schedule(qid)
      if not QD or not QD.get_schedule then return nil end
      local ok, v = pcall(QD.get_schedule, qid)
      return ok and v or nil
  end
  -- =========== CHARACTER NAMES + POSITION + MAP (before NPC helpers — Lua 200-local limit) ===========
  -- Cache survives across sessions via LEARNED_CHARA_NAMES (persisted in prefs JSON, hoisted above).
  local _name_cache = {}
  for cid_str, nm in pairs(LEARNED_CHARA_NAMES) do
      local n = tonumber(cid_str)
      if n then _name_cache[n] = nm end
  end
  -- Lazily resolved game-canonical name lookup: app.GUIBase:getName(app.CharacterID).
  -- This is the same path show_name.lua uses for dialogue nameplates; works for any NPC
  -- the game knows about, even when NPCHolderDic doesn't carry CharaName.
  local _GUIBase_getName = nil
  local function _try_guibase_getname(cid)
      if _GUIBase_getName == false then return nil end
      if _GUIBase_getName == nil then
          local ok, td = pcall(sdk.find_type_definition, "app.GUIBase")
          if ok and td then
              local m = td:get_method("getName(app.CharacterID)")
              _GUIBase_getName = m or false
          else
              _GUIBase_getName = false
          end
          if _GUIBase_getName == false then return nil end
      end
      local ok, n = pcall(function() return _GUIBase_getName:call(nil, cid) end)
      if ok and type(n) == "string" and n ~= "" then return n end
      return nil
  end

  local function chara_name(cid)
      if not cid or cid == 0 then return nil end
      if _name_cache[cid] ~= nil then
          if _name_cache[cid] == false then return nil end
          return _name_cache[cid]
      end
      local function remember(n)
          _name_cache[cid] = n
          LEARNED_CHARA_NAMES[tostring(cid)] = n
          mark_prefs_dirty()
          return n
      end
      -- 1) NPCHolderDic CharaName (fastest when NPC is loaded)
      local nm = sdk.get_managed_singleton("app.NPCManager")
      if nm then
          local dic = safe_get_field(nm, "NPCHolderDic")
          if dic then
              local sz = 0; pcall(function() sz = dic:get_size() end)
              for i = 0, sz - 1 do
                  local ok, h = pcall(function() return dic:get_element(i) end)
                  if ok and h then
                      local hcid = to_int(safe_get_field(h, "CharaID"))
                      if cid_eq(hcid, cid) then
                          local n = safe_get_field(h, "CharaName") or safe_call(h, "get_CharaName")
                          if type(n) == "string" and n ~= "" then return remember(n) end
                      end
                  end
              end
          end
      end
      -- 2) app.GUIBase getName â€” works for every NPC the dialogue UI can name, including
      --    quest cast members not currently in the NPCHolderDic walk.
      local g = _try_guibase_getname(cid)
      if g then return remember(g) end
      -- Don't poison-cache as `false` permanently â€” try again next session.
      return nil
  end

  local function friendly_chara_name(cid, qid, role)
      role = role or "primary"
      local nm = chara_name(cid)
      if type(nm) == "string" and nm ~= "" then return nm end
      if QD and QD.lookup_chara_name then
          local ok, v = pcall(QD.lookup_chara_name, cid)
          if ok and type(v) == "string" and v ~= "" then return v end
      end
      -- Only attribute the wiki giver_name to a CID when the user (or bundled override) has
      -- explicitly endorsed that CID as the primary giver. Auto-applying it to whatever sits
      -- in slot #1 of the decomp list mislabels rumor / shopkeeper NPCs as the wiki-named giver.
      if role == "primary" then
          local ov = MANUAL_GIVER_OVERRIDES[qid]
          if ov and cid_eq(ov, cid) then
              local wiki = qd_giver_name(qid)
              if type(wiki) == "string" and wiki ~= "" then return wiki end
          end
      end
      return nil
  end

  -- =========== NPC POSITION (CACHED) ===========
  -- Cache cleared each rebuild cycle so UI doesn't re-scan all NPCs at 60fps.
  -- IMPORTANT: never call get_GameObject() on NPC objects â€” throws InvalidOperationException
  -- on unspawned NPCs and spams the RE2 framework log.
  local _pos_cache = {}
  local function _flush_pos_cache()
      _pos_cache = {}
  end

  local function _flush_pos_cache_cid(cid_int)
      if type(cid_int) == "number" then _pos_cache[cid_int] = nil end
  end

  local function _log_tp(qid, cid, ok, src, reason)
      mlog_boot(string.format("[QT][tp] qid=%s cid=%s ok=%s src=%s%s",
          tostring(qid or "?"), tostring(cid or "?"), ok and "true" or "false",
          tostring(src or "?"), reason and (" reason=" .. reason) or ""))
  end

  local function _pos_from_pinned(qid)
      if not qid then return nil end
      local pins = MAP_API and MAP_API.pinned_pos and MAP_API.pinned_pos[qid]
      if type(pins) == "table" and pins[1] then
          local p = pins[1]
          if type(p.x) == "number" and type(p.y) == "number" and type(p.z) == "number" then
              return p.x, p.y, p.z, "pinned_pos"
          end
      end
      local dests = MAP_API and MAP_API.pinned_data and MAP_API.pinned_data[qid]
      if type(dests) == "table" and dests[1] then
          local d = dests[1]
          if type(d.x) == "number" and type(d.y) == "number" and type(d.z) == "number" then
              return d.x, d.y, d.z, "pinned_dest"
          end
      end
      return nil
  end

  local function _extract_pos_from(obj)
      if obj == nil then return nil end
      for _, mn in ipairs({"get_UniversalPosition", "get_Position", "get_WorldPosition"}) do
          local ok, p = pcall(function() return obj:call(mn) end)
          if ok and p ~= nil then
              local x, y, z; pcall(function() x, y, z = p.x, p.y, p.z end)
              if x ~= nil and not (x == 0 and y == 0 and z == 0) then return x, y, z end
          end
      end
      return nil
  end

  local function _get_character_world_pos_raw(cid_int)
      if type(cid_int) ~= "number" then return nil end
      local cid32 = cid_int > 2147483647 and (cid_int - 4294967296) or cid_int

      local cm = sdk.get_managed_singleton("app.CharacterManager")
      if cm then
          for _, mn in ipairs({"findByCharacterID","findCharacterByCharacterID","findCharacter","getCharacter"}) do
              for _, arg in ipairs({cid_int, cid32}) do
                  local ok, c = pcall(function() return cm:call(mn, arg) end)
                  if ok and c then
                      local x, y, z = _extract_pos_from(c)
                      if x then return x, y, z end
                  end
              end
          end
      end

      local nm = sdk.get_managed_singleton("app.NPCManager")
      if nm == nil then return nil end
      local dic = safe_get_field(nm, "NPCHolderDic")
      if dic == nil then return nil end
      local sz = 0; pcall(function() sz = dic:get_size() end)
      for i = 0, sz - 1 do
          local ok, h = pcall(function() return dic:get_element(i) end)
          if ok and h then
              local hcid = to_int(safe_get_field(h, "CharaID"))
              if cid_eq(hcid, cid_int) then
                  local x, y, z = _extract_pos_from(h)
                  if x then return x, y, z end
              end
          end
      end
      return nil
  end

  local function get_character_world_pos(cid_int)
      if type(cid_int) ~= "number" then return nil end
      local cached = _pos_cache[cid_int]
      if cached ~= nil then
          if cached == false then return nil end
          return cached[1], cached[2], cached[3]
      end
      local x, y, z = _get_character_world_pos_raw(cid_int)
      if x then _pos_cache[cid_int] = {x,y,z}; return x,y,z
      else _pos_cache[cid_int] = false; return nil end
  end

  -- Fresh teleport coords: never trust stale _pos_cache false negatives.
  -- MUST be after get_character_world_pos (forward-ref guard — v1.4.19 hotfix).
  -- live_only=true: named NPC rows must not inherit quest pin/manual coords (fake green TP).
  local function resolve_teleport_pos(qid, cid_int, live_only)
      if type(cid_int) == "number" and cid_int > 0 then
          _flush_pos_cache_cid(cid_int)
          local x, y, z = get_character_world_pos(cid_int)
          if x then return x, y, z, "npc" end
      end
      if live_only then
          return nil, nil, nil, "not_loaded"
      end
      local mp = MANUAL_POS_OVERRIDES and MANUAL_POS_OVERRIDES[qid]
      if mp and type(mp.x) == "number" then
          return mp.x, mp.y, mp.z, "manual_pos"
      end
      local px, py, pz, psrc = _pos_from_pinned(qid)
      if px then return px, py, pz, psrc end
      if type(cid_int) == "number" and cid_int > 0 then
          local ov = MANUAL_GIVER_OVERRIDES and MANUAL_GIVER_OVERRIDES[qid]
          if ov and cid_eq(ov, cid_int) then
              _flush_pos_cache_cid(cid_int)
              local x, y, z = _get_character_world_pos_raw(cid_int)
              if x then
                  _pos_cache[cid_int] = { x, y, z }
                  return x, y, z, "npc_retry"
              end
          end
      end
      return nil, nil, nil, "none"
  end

  -- =========== PLAYER POSITION ===========
  local function get_player_universal_pos()
      local gm = sdk.get_managed_singleton("app.GuiManager")
      if gm == nil then return nil end
      local x, y, z
      pcall(function() local p = gm.PlUPos; x, y, z = p.x, p.y, p.z end)
      return x, y, z
  end

  local function _get_manual_player()
      local cm = sdk.get_managed_singleton("app.CharacterManager")
      return cm and cm:get_field("<ManualPlayer>k__BackingField") or nil
  end


  local function matches_filter(q)
      local Map = ctx.Map
      if Map and Map.matches_filter then return Map.matches_filter(q) end
      return true
  end
  local function pin_all_in_current_filtered_tab()
      local Map = ctx.Map
      if Map and Map.pin_all then return Map.pin_all() end
  end

  -- Reorder merged giver list so wiki primary (giver_name / primary_giver_cid) is first for UI + TP.
  local function _giver_first_token_lower(s)
      if type(s) ~= "string" or s == "" then return "" end
      local t = s:lower():gsub("%([^)]*%)", "")
      t = (t:match("^%s*(.-)%s*$") or t):gsub("%s+", " ")
      return (t:match("^(%S+)") or t)
  end

  local function _lookup_name_for_giver_sort(cid)
      if QD and QD.lookup_chara_name then
          local ok, v = pcall(QD.lookup_chara_name, cid)
          if ok and type(v) == "string" and v ~= "" then return v end
      end
      return nil
  end

  local function qd_givers_display_order(qid)
      local gst = qd_givers(qid)
      if not gst or #gst < 2 then return gst end
      if QD and QD.get_primary_giver_cid then
          local ok, pc = pcall(QD.get_primary_giver_cid, qid)
          if ok and type(pc) == "number" and pc > 0 then
              for i, c in ipairs(gst) do
                  if cid_eq(c, pc) then
                      if i == 1 then return gst end
                      local out = { c }
                      for j, c2 in ipairs(gst) do
                          if j ~= i then out[#out + 1] = c2 end
                      end
                      return out
                  end
              end
          end
      end
      local want = qd_giver_name(qid)
      if type(want) ~= "string" or want == "" then return gst end
      local wtok = _giver_first_token_lower(want)
      if wtok == "" then return gst end
      for i, cid in ipairs(gst) do
          local nm = _lookup_name_for_giver_sort(cid)
          if nm and _giver_first_token_lower(nm) == wtok then
              if i == 1 then return gst end
              local out = { cid }
              for j, c2 in ipairs(gst) do
                  if j ~= i then out[#out + 1] = c2 end
              end
              return out
          end
      end
      return gst
  end

  -- Curated NPC list for UI: primary + extras + wiki_cast names only (no decomp dump spam).
  local DISPLAY_NPC_MAX = 12
  local _MONSTER_NAME_HINTS = {
      "wight", "saurian", "goblin", "cyclops", "chimera", "drake", "skeleton", "phantom",
      "dullahan", "ogre", "harpy", "slime", "wolf", "bandit",
  }
  local function _wiki_cast_lower(qid)
      if not (QD and QD.get_wiki_cast) then return nil end
      local ok, v = pcall(QD.get_wiki_cast, qid)
      if ok and type(v) == "table" and #v > 0 then return v end
      return nil
  end

  local function _name_matches_wiki(nm, wiki_lower)
      if not nm then return false end
      local low = nm:lower()
      for _, w in ipairs(wiki_lower) do
          if low:find(w, 1, true) then return true end
      end
      return false
  end

  local function _looks_like_monster_name(nm)
      if not nm then return true end
      local low = nm:lower()
      for _, tok in ipairs(_MONSTER_NAME_HINTS) do
          if low:find(tok, 1, true) then return true end
      end
      return false
  end

  local function _resolve_cid_name(c)
      local nm = chara_name(c)
      if nm then return nm end
      if QD and QD.lookup_chara_name then
          local ok, v = pcall(QD.lookup_chara_name, c)
          if ok and type(v) == "string" and v ~= "" then return v end
      end
      return nil
  end

  local function _cid_list_has(out, c)
      for _, x in ipairs(out) do
          if cid_eq(x, c) then return true end
      end
      return false
  end

  local function _want_names_for_quest(qid, step_title)
      local want = {}
      local seen = {}
      local function add(low)
          if type(low) ~= "string" or low == "" or seen[low] then return end
          seen[low] = true
          want[#want + 1] = low
      end
      local subkey = mod._wiki_substep_key and mod._wiki_substep_key[qid]
      local step_focus = false
      if QD and QD.has_step_cast_focus then
          local ok_sf, sf = pcall(QD.has_step_cast_focus, qid, step_title, subkey)
          step_focus = ok_sf and sf == true
      end
      if QD and QD.get_quest_npc_names then
          local ok, list = pcall(QD.get_quest_npc_names, qid, step_title, subkey)
          if ok and type(list) == "table" then
              if #list == 0 and step_focus then return {}, true end
              for _, n in ipairs(list) do add(n:lower()) end
          end
      end
      if not step_focus then
          local wiki_lower = _wiki_cast_lower(qid)
          if wiki_lower then
              for _, w in ipairs(wiki_lower) do add(w) end
          end
          local giver_nm = qd_giver_name(qid)
          if giver_nm then add(giver_nm:lower()) end
      end
      if #want == 0 then return nil end
      return want, step_focus
  end

  local function _scan_loaded_cids_for_names(want_names)
      if not want_names or #want_names == 0 then return {} end
      local key = table.concat(want_names, "\0")
      local now = os.clock()
      local ent = mod._npc_scan_cache[key]
      if ent and (now - ent.t) < NPC_SCAN_CACHE_TTL then return ent.out end
      local out, seen = {}, {}
      local function try_push(cid, nm)
          if type(cid) ~= "number" or cid <= 0 or seen[cid] then return end
          if not nm or not _name_matches_wiki(nm, want_names) then return end
          seen[cid] = true
          out[#out + 1] = cid
      end
      local nmgr = sdk.get_managed_singleton("app.NPCManager")
      if nmgr then
          local dic = safe_get_field(nmgr, "NPCHolderDic")
          if dic then
              local sz = 0
              pcall(function() sz = dic:get_size() end)
              for i = 0, sz - 1 do
                  local ok, h = pcall(function() return dic:get_element(i) end)
                  if ok and h then
                      local hcid = to_int(safe_get_field(h, "CharaID"))
                      local n = safe_get_field(h, "CharaName") or safe_call(h, "get_CharaName")
                      if (not n or n == "") and hcid and chara_name then
                          n = chara_name(hcid)
                      end
                      try_push(hcid, n)
                  end
              end
          end
      end
      if QD and QD.iter_chara_name_cids then
          local ok_cache, cache = pcall(QD.iter_chara_name_cids)
          if ok_cache and type(cache) == "table" then
              for cid, name in pairs(cache) do
                  try_push(cid, name)
              end
          end
      end
      for cid_str, name in pairs(LEARNED_CHARA_NAMES) do
          local cid = tonumber(cid_str)
          try_push(cid, name)
      end
      mod._npc_scan_cache[key] = { t = now, out = out }
      return out
  end

  local function get_all_giver_cids(qid, step_title)
      local out = {}
      local function push(c, force)
          if type(c) ~= "number" or c <= 0 then return end
          if _cid_list_has(out, c) then return end
          if not force then
              local nm = _resolve_cid_name(c)
              if nm and _looks_like_monster_name(nm) then return end
          end
          if #out >= DISPLAY_NPC_MAX then return end
          out[#out + 1] = c
      end

      local want_names, step_focus = _want_names_for_quest(qid, step_title)
      if not step_focus then
          if QD and QD.get_primary_giver_cid then
              local ok, pc = pcall(QD.get_primary_giver_cid, qid)
              if ok and pc then push(pc, true) end
          end
          local mq_extra = nil
          if QD and QD.get_extra_giver_cids then
              local ok, ex = pcall(QD.get_extra_giver_cids, qid)
              if ok and type(ex) == "table" then mq_extra = ex end
          end
          if mq_extra then
              for _, c in ipairs(mq_extra) do push(c, true) end
          end
      end
      if want_names then
          if QD and QD.get_npc_cids then
              local ok_nc, nc = pcall(QD.get_npc_cids, qid)
              if ok_nc and type(nc) == "table" then
                  for _, wn in ipairs(want_names) do
                      local cid = nc[wn] or nc[wn:sub(1, 1):upper() .. wn:sub(2)]
                      if type(cid) == "number" and cid > 0 then push(cid, true) end
                  end
              end
          end
          local ov = MANUAL_GIVER_OVERRIDES[qid]
          if ov then
              local gnm = qd_giver_name(qid)
              if gnm then
                  local glow = gnm:lower()
                  for _, wn in ipairs(want_names) do
                      if glow == wn or glow:find(wn, 1, true) or wn:find(glow, 1, true) then
                          push(ov, true)
                          break
                      end
                  end
              end
          end
          for _, c in ipairs(_scan_loaded_cids_for_names(want_names)) do push(c, false) end
          if QD and QD.iter_chara_name_cids then
              local ok_cache, cache = pcall(QD.iter_chara_name_cids)
              if ok_cache and type(cache) == "table" then
                  for cid, nm in pairs(cache) do
                      if _name_matches_wiki(nm, want_names) then push(cid, false) end
                  end
              end
          end
          if not step_focus then
              local cast = MapBridge.get_quest_cast_charaids(qid)
              if type(cast) == "table" then
                  for _, c in ipairs(cast) do
                      if _name_matches_wiki(_resolve_cid_name(c), want_names) then push(c, false) end
                  end
              end
          end
      end

      if want_names and #out > 1 then
          local scored = {}
          for i, cid in ipairs(out) do
              local nm = (_resolve_cid_name(cid) or ""):lower()
              local rank = 900 + i
              for wi, w in ipairs(want_names) do
                  if nm:find(w, 1, true) then rank = wi; break end
              end
              scored[#scored + 1] = { cid = cid, rank = rank }
          end
          table.sort(scored, function(a, b)
              if a.rank ~= b.rank then return a.rank < b.rank end
              return false
          end)
          for i, row in ipairs(scored) do out[i] = row.cid end
      end

      return out, want_names
  end

  local function get_primary_secondary_cids(qid, step_title)
      local all = get_all_giver_cids(qid, step_title)
      if #all == 0 then
          local o = MANUAL_GIVER_OVERRIDES[qid]
          return o, nil
      end
      return all[1], all[2]
  end

  local function _get_quest_start_pos(qid, pri_c)
      local p = MANUAL_POS_OVERRIDES[qid]
      if p and p.x then return p.x, p.y, p.z end
      p = BUNDLED_POS_OVERRIDES[qid]
      if p and p.x then return p.x, p.y, p.z end
      if type(pri_c) == "number" and pri_c > 0 then
          local x, y, z = get_character_world_pos(pri_c)
          if x then return x, y, z end
      end
      return nil, nil, nil
  end

  -- Resolve a friendly NPC name. Tries: live game CharaName -> meta chara_names map ->
  -- per-quest giver_name (when this is the primary giver) -> generic fallback (NEVER NPC#xxx).
  -- =========== TIME MANAGER ===========
  -- Uses absolute minute count (day*1440 + hour*60 + min) so no midnight wrap logic
  -- is needed. Pattern matches simple_time_scaler reference mod.

  local function _get_tm()
      return sdk.get_managed_singleton("app.TimeManager")
  end

  local function _get_game_clock_integers()
      local tm = _get_tm()
      if not tm then return nil, nil, nil end
      local d, h, mi = 0, nil, nil
      pcall(function() d = tm:get_InGameDay() end)
      pcall(function() h = tm:get_InGameHour() end)
      pcall(function() mi = tm:get_InGameMinute() end)
      if type(h) ~= "number" or type(mi) ~= "number" then return nil end
      if type(d) ~= "number" then d = 0 end
      return math.floor(d + 0.5), math.floor(h + 0.5), math.floor(mi + 0.5)
  end

  -- Fractional hour [0,24) for NPC schedule windows (uses integer minute from TimeManager).
  local function _get_game_hour_sched()
      local _, h, mi = _get_game_clock_integers()
      if h == nil or mi == nil then return nil end
      return h + mi / 60.0
  end

  local function _format_game_time_line()
      local d, h, mi = _get_game_clock_integers()
      if h == nil or mi == nil then return "In-game time: (unavailable)" end
      local ap, hh = "AM", h
      if h == 0 then hh = 12
      elseif h == 12 then ap = "PM"
      elseif h > 12 then hh = h - 12; ap = "PM"
      end
      return string.format("In-game: day %d   %d:%02d %s", d or 0, hh, mi, ap)
  end

  local function _format_hour_12(h)
      if type(h) ~= "number" then return "?" end
      local ih = math.floor(h) % 24
      if ih == 0 then return "12AM"
      elseif ih < 12 then return tostring(ih) .. "AM"
      elseif ih == 12 then return "12PM"
      else return tostring(ih - 12) .. "PM" end
  end

  local function _format_hour_lower(h)
      if type(h) ~= "number" then return "?" end
      local ih = math.floor(h) % 24
      if ih == 0 then return "12am"
      elseif ih < 12 then return tostring(ih) .. "am"
      elseif ih == 12 then return "12pm"
      else return tostring(ih - 12) .. "pm" end
  end

  local function _format_hour_window(s, f)
      return _format_hour_12(s) .. "-" .. _format_hour_12(f)
  end

  local function _format_hour_window_paren(s, f)
      return _format_hour_lower(s) .. "-" .. _format_hour_lower(f)
  end

  local function _in_hour_window(cur_h, s, f)
      if cur_h == nil or s == nil or f == nil then return nil end
      if s > f then return cur_h >= s or cur_h < f end
      return cur_h >= s and cur_h < f
  end

  local function _hours_until_window_start(cur_h, s, f)
      if cur_h == nil or s == nil then return nil end
      if _in_hour_window(cur_h, s, f) then return 0 end
      if s > f then
          if cur_h < f then return s - cur_h end
          return (24 - cur_h) + s
      end
      if cur_h < s then return s - cur_h end
      return (24 - cur_h) + s
  end

  local function _get_total_game_minutes()
      local d, h, mi = _get_game_clock_integers()
      if h == nil or mi == nil then return nil end
      d = d or 0
      return d * 1440 + h * 60 + mi
  end

  local _scale_ok_logged = {}
  local _scale_fail_logged = {}

  local function _get_time_scale()
      local tm = _get_tm()
      if not tm then return nil end
      local v = nil
      pcall(function() v = tm:call("get_TimeScale()") end)
      if type(v) ~= "number" then
          pcall(function() v = tm:call("get_TimeScale") end)
      end
      if type(v) ~= "number" then
          v = safe_get_field(tm, "_TimeScale") or safe_get_field(tm, "TimeScale")
      end
      if type(v) == "number" then return v end
      return nil
  end

  local function _try_set_time_scale(tm, want)
      if not tm then return false end
      local any = false
      local tries = {
          function() tm:call("setTimeScale(System.Single)", want) end,
          function() tm:call("setTimeScale", want) end,
          function() tm:call("set_TimeScale(System.Single)", want) end,
          function() tm:call("set_TimeScale", want) end,
      }
      for _, fn in ipairs(tries) do
          if pcall(fn) then any = true end
      end
      pcall(function()
          local tdef = tm:get_type_definition()
          if tdef then
              for _, fname in ipairs({ "_TimeScale", "TimeScale", "m_TimeScale" }) do
                  local f = tdef:get_field(fname)
                  if f then f:set_data(tm, want); any = true end
              end
          end
      end)
      return any
  end

  local function _scale_matches(want, live)
      if live == nil then return false end
      if want < 0.01 then return live < 0.02 end
      return math.abs(live - want) <= 0.01
  end

  local function _log_scale_set(want, live, ok)
      local boot = mlog_boot or mlog
      if not boot then return end
      if ok then
          if _scale_ok_logged[want] then return end
          _scale_ok_logged[want] = true
          _scale_fail_logged[want] = nil
          boot(string.format("[QT][time] set OK want=%.4f live=%.4f", want, live))
      else
          if _scale_fail_logged[want] then return end
          _scale_fail_logged[want] = true
          _scale_ok_logged[want] = nil
          local live_s = live and string.format("%.4f", live) or "nil"
          boot(string.format("[QT][time] set FAIL want=%.4f live=%s method=all_failed", want, live_s))
      end
  end

  local function _set_time_scale(scale)
      local want = tonumber(scale) or 1.0
      local tm = _get_tm()
      if not tm then
          _log_scale_set(want, nil, false)
          return false, nil
      end
      _try_set_time_scale(tm, want)
      local live = _get_time_scale()
      local ok = _scale_matches(want, live)
      _log_scale_set(want, live, ok)
      return ok, live
  end

  local function _set_game_clock_integers(d, h, mi)
      local tm = _get_tm()
      if not tm or h == nil or mi == nil then return false end
      d = d or 0
      local any = false
      pcall(function() tm:set_InGameDay(d); any = true end)
      pcall(function() tm:call("set_InGameDay", d) end)
      pcall(function() tm:set_InGameHour(h); any = true end)
      pcall(function() tm:call("set_InGameHour", h) end)
      pcall(function() tm:set_InGameMinute(mi); any = true end)
      pcall(function() tm:call("set_InGameMinute", mi) end)
      pcall(function()
          local tdef = tm:get_type_definition()
          if not tdef then return end
          local fields = {
              { "InGameDay", d }, { "_InGameDay", d },
              { "InGameHour", h }, { "_InGameHour", h },
              { "InGameMinute", mi }, { "_InGameMinute", mi },
          }
          for i = 1, #fields, 2 do
              local f = tdef:get_field(fields[i])
              if f then f:set_data(tm, fields[i + 1]); any = true end
          end
      end)
      return any
  end

  mod._qt_doze = nil
  local _ff_warned_scaler = false

  local function _start_fast_forward(hours_to_advance)
      local cur = _get_total_game_minutes()
      if not cur then mlog("[FF] FAIL: no TimeManager"); return false end
      local target = cur + math.floor((hours_to_advance or 0) * 60)
      mod._qt_doze = { target = target, phase = "fast" }
      _set_time_scale(120.0)
      mlog(string.format("[FF] start cur_min=%.0f target_min=%.0f (+%.1fh)", cur, target, hours_to_advance or 0))
      if not _ff_warned_scaler then
          _ff_warned_scaler = true
          mlog("[FF] If time does not move, another mod may overwrite time scale each frame — rename this script to z_quest_tracker.lua to load after time mods, or adjust Simple Time Scaler.")
      end
      return true
  end

  local function _tick_fast_forward()
      if not mod._qt_doze then return end
      local want = (mod._qt_doze.phase == "slow") and 30.0 or 120.0
      _set_time_scale(want)

      local cur = _get_total_game_minutes()
      if not cur then mod._qt_doze = nil; _set_time_scale(1.0); return end

      local remaining = mod._qt_doze.target - cur
      if remaining <= 0 then
          mod._qt_doze = nil
          _set_time_scale(1.0)
          mlog(string.format("[FF] done at min=%.0f", cur))
          return
      end
      if remaining <= 30 and mod._qt_doze.phase == "fast" then
          mod._qt_doze.phase = "slow"
      end
  end

  local function _cid_for_wiki_name(qid, wiki_name, givers_all)
      local want = wiki_name:lower()
      if givers_all then
          for _, gc in ipairs(givers_all) do
              local nm = friendly_chara_name(gc, qid, "alt") or _resolve_cid_name(gc)
              if nm and nm:lower():find(want, 1, true) then return gc end
          end
      end
      if QD and QD.get_npc_cids then
          local ok, nc = pcall(QD.get_npc_cids, qid)
          if ok and type(nc) == "table" then
              local cid = nc[want] or nc[wiki_name] or nc[wiki_name:sub(1, 1):upper() .. wiki_name:sub(2)]
              if type(cid) == "number" and cid > 0 then return cid end
          end
      end
      for _, c in ipairs(_scan_loaded_cids_for_names({ wiki_name })) do return c end
      return nil
  end

  local function _build_npc_display_rows(qid, step_title, givers_all, want_names)
      local rows, seen = {}, {}
      local function add(display_name, cid)
          local key = (type(cid) == "number" and cid > 0) and ("c" .. cid) or ("n" .. display_name:lower())
          if seen[key] then return end
          seen[key] = true
          rows[#rows + 1] = { name = display_name, cid = cid }
      end
      if want_names and #want_names > 0 then
          for _, wn in ipairs(want_names) do
              local disp = wn:sub(1, 1):upper() .. wn:sub(2)
              add(disp, _cid_for_wiki_name(qid, wn, givers_all))
          end
          return rows
      end
      if givers_all then
          for _, gc in ipairs(givers_all) do
              local nm = friendly_chara_name(gc, qid, "alt") or _resolve_cid_name(gc) or ("NPC " .. tostring(gc))
              add(nm, gc)
          end
      end
      return rows
  end

  local function _draw_npc_rows_cached(qid, npc_rows, can_tp)
      if not npc_rows or #npc_rows == 0 then return end
      local per_line = 3
      for i, nr in ipairs(npc_rows) do
          if i > 1 and ((i - 1) % per_line) ~= 0 then imgui.same_line(0, 8) end
          imgui.text_colored(nr.label, nr.col)
          if can_tp then
              imgui.same_line(0, 4)
              if nr.cid then
                  if imgui.button("TP##gtp" .. qid .. "_" .. tostring(nr.cid)) then
                      -- Named NPC TP: live body only (pin/manual = wrong person / empty cell).
                      local tx, ty, tz, src = resolve_teleport_pos(qid, nr.cid, true)
                      local ok = false
                      if tx and ctx._teleport_player_to then
                          ok = ctx._teleport_player_to(tx, ty, tz, { qid = qid, cid = nr.cid, src = src }) == true
                      elseif ctx._log_tp then
                          ctx._log_tp(qid, nr.cid, false, src or "not_loaded", "no_live_npc")
                      end
                      if ok then
                          MAP_API.last_msg = "TP to " .. nr.nm
                      else
                          MAP_API.last_msg = nr.nm .. " not in world"
                      end
                      if mod._refresh_one_row and mod.quests then
                          for _, rq in ipairs(mod.quests) do
                              if rq.id == qid then pcall(mod._refresh_one_row, rq); break end
                          end
                      end
                  end
              else
                  imgui.text_colored("TP", 0xFF555555)
              end
              imgui.same_line(0, 4)
              if nr.show_ff then
                  if imgui.button("FF>>##ff" .. qid .. "_" .. nr.nm) then
                      _start_fast_forward(nr.ff_h + (1 / 60))
                      mlog(string.format("[FF] %s qid=%d +%.1fh -> window", nr.nm, qid, nr.ff_h))
                  end
              end
          end
      end
  end

  local function _build_npc_rows_for_cache(qid, step_title, givers_all, want_names, cur_h)
      local out = {}
      local rows = _build_npc_display_rows(qid, step_title, givers_all, want_names)
      for _, row in ipairs(rows) do
          local nm, cid = row.name, row.cid
          local hrs = nil
          if QD and QD.get_npc_hours_for_name then
              local ok_h, h = pcall(QD.get_npc_hours_for_name, qid, nm)
              if ok_h then hrs = h end
          end
          local s, f = hrs and hrs.start, hrs and hrs.finish
          local has_hours = s and f
          local label = nm
          if has_hours then
              label = string.format("%s (%s)", nm, _format_hour_window_paren(s, f))
          end
          local gx, gy, gz, pos_src = nil, nil, nil, nil
          if cid then
              -- Live NPC only for row color/TP readiness (pin fallback lied for Brefft).
              gx, gy, gz, pos_src = resolve_teleport_pos(qid, cid, true)
          end
          local live = (pos_src == "npc" or pos_src == "npc_retry")
          local in_schedule = (not has_hours) or (cur_h and _in_hour_window(cur_h, s, f))
          local available_now = in_schedule and ((not cid) or live)
          local ff_h = 3
          if has_hours and cur_h and not available_now then
              local h = _hours_until_window_start(cur_h, s, f)
              if h and h > 0.01 then ff_h = math.min(h, 18) end
          end
          -- #region agent log
          if qid == 30220 then
              mlog_boot(string.format("[QT][dbg62] hyp=H3 npc_row qid=30220 nm=%s live=%s src=%s tp_ready=%s",
                  tostring(nm), live and "1" or "0", tostring(pos_src or "nil"), live and "1" or "0"))
          end
          -- #endregion
          out[#out + 1] = {
              nm = nm, label = label,
              col = available_now and COL_NPC_NEON_GREEN or COL_NPC_ORANGE,
              cid = cid, gx = gx, gy = gy, gz = gz, ff_h = ff_h,
              show_ff = has_hours and not available_now,
              tp_ready = live,
              live_npc = live,
              pos_src = pos_src,
          }
      end
      return out
  end
  -- =========== GATHER / REBUILD ===========
  local _warned_qlm_nil = false

  local function _boot_completion_sweep(qlm, progressing, acceptable, completed)
      if ALL_IDS == nil then ALL_IDS = dump_quest_id_enum() end
      if not ALL_IDS then return 0 end
      local added = 0
      for qid in pairs(ALL_IDS) do
          if qid and qid >= 0 and not completed[qid] and not progressing[qid] and not acceptable[qid] then
              if safe_call(qlm, "isQuestLogEnd", qid) == true then
                  completed[qid] = true
                  added = added + 1
              end
          end
      end
      return added
  end

  local function gather()
      local qlm = sdk.get_managed_singleton("app.QuestLogManager")
      if qlm == nil then
          if not _warned_qlm_nil then
              _warned_qlm_nil = true
              mlog("[QT] gather: QuestLogManager nil until in-game save loads")
          end
          return
      end
      if not mod._qt_qlm_ready_logged then
          mod._qt_qlm_ready_logged = true
          mlog_boot("[QT] QuestLogManager online — reading quest progress from save")
          mod._logic_force = true
          mod._last_state_probe = 0
          if mod._qt_schedule_cache_refresh then pcall(mod._qt_schedule_cache_refresh, "boot") end
      end
      if ALL_IDS == nil then ALL_IDS = dump_quest_id_enum() end

      local progressing, acceptable, completed, recency = {}, {}, {}, {}

      local function _count_set(t)
          local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n
      end
      local prev_prog_n = _count_set(mod.progressing_ids)
      local prev_acc_n = _count_set(mod.acceptable_ids)

      local pl = safe_call(qlm, "getProgressingQuestIds")
      if pl then iter_list(pl, function(q) local n=to_int(q); if n then progressing[n]=true end end) end

      local al = safe_call(qlm, "getAcceptableQuestList")
      if al then iter_list(al, function(q) local n=to_int(q); if n then acceptable[n]=true end end) end

      if _count_set(progressing) == 0 and prev_prog_n >= 2 then
          mlog("[QT] WARN progressing list empty — keeping last snapshot (" .. prev_prog_n .. " quests)")
          for qid in pairs(mod.progressing_ids or {}) do progressing[qid] = true end
      end
      if _count_set(acceptable) == 0 and prev_acc_n >= 2 then
          mlog("[QT] WARN acceptable list empty — keeping last snapshot (" .. prev_acc_n .. " quests)")
          for qid in pairs(mod.acceptable_ids or {}) do acceptable[qid] = true end
      end

      -- Carry forward known-completed IDs (completion is permanent).
      for qid, v in pairs(mod.completed_ids or {}) do completed[qid] = v end

      if not mod._qt_boot_completion_sweep then
          mod._qt_boot_completion_sweep = true
          local added = _boot_completion_sweep(qlm, progressing, acceptable, completed)
          if added > 0 then
              mlog_boot(string.format("[QT] boot completion sweep: +%d completed", added))
          end
          mod._last_completion_sweep = os.clock()
      end

      local rec = safe_call(qlm, "getOrderedByUpdateQuestList")
      if rec ~= nil then
          iter_array(rec, function(q, i) local n=to_int(q); if n then recency[n]=i+1 end end)
          if next(recency) == nil then
              iter_list(rec, function(q, i) local n=to_int(q); if n then recency[n]=i+1 end end)
          end
      end

      -- Resolve names only for relevant quests (not all 600+)
      for qid in pairs(progressing) do resolve_meta(qlm, qid) end
      for qid in pairs(acceptable)  do resolve_meta(qlm, qid) end
      for qid in pairs(completed)   do if not mod.name_cache[qid] then resolve_meta(qlm, qid) end end

      -- Track quest start day+hour for live timers (hour-precision countdowns)
      local tm2 = sdk.get_managed_singleton("app.TimeManager")
      if tm2 then
          local cd, ch, cm = _get_game_clock_integers()
          if cd ~= nil then
              mod._live_in_game_day = cd
              mod._live_in_game_hour = ch
              mod._live_in_game_minute = cm
              for qid in pairs(progressing) do
                  if not QUEST_START_DAYS[qid] then
                      QUEST_START_DAYS[qid] = cd
                      QUEST_START_HOURS[qid] = ch or 0
                      mark_prefs_dirty()
                  end
              end
          end
      end

      -- Auto-unpin when quest transitions Available → Ongoing
      for qid in pairs(mod.acceptable_ids or {}) do
          if progressing[qid] and MAP_API then
              if (MAP_API.pinned_pos and MAP_API.pinned_pos[qid]) or
                 (MAP_API.pinned_data and MAP_API.pinned_data[qid]) then
                  pcall(MapBridge.unpin_quest, qid)
              end
          end
      end

      -- Auto-unpin when quest transitions Ongoing → Completed
      for qid in pairs(mod.progressing_ids or {}) do
          if completed[qid] and MAP_API then
              if (MAP_API.pinned_data and MAP_API.pinned_data[qid]) or
                 (MAP_API.pinned_pos and MAP_API.pinned_pos[qid]) then
                  pcall(MapBridge.unpin_quest, qid)
                  mlog("[QT][map] unpin complete qid=" .. qid .. " reason=quest_completed")
              end
          end
      end

      if MapBridge.sweep_ghost_pins then
          pcall(MapBridge.sweep_ghost_pins, progressing, acceptable, completed)
      end

      -- "Upcoming": meta quests whose prereqs are completed and lockout milestone not fired,
      -- but the game has not flagged them as Acceptable yet (wandering-NPC starts, area-gated NPCs).
      local upcoming = {}
      for _, qid in ipairs(qd_iter_meta_qids()) do
          if not progressing[qid] and not acceptable[qid] and not completed[qid]
             and not LOCKED_QUESTS[qid] then
              local lock_after = qd_lockout_after(qid) or (BUNDLED_LOCKOUTS[qid] and BUNDLED_LOCKOUTS[qid].after)
              local lock_done = type(lock_after) == "number" and completed[lock_after] == true
              local lic = qd_locked_if(qid)
              if lic then
                  for _, blocker in ipairs(lic) do
                      if completed[blocker] then lock_done = true; break end
                  end
              end
              if not lock_done and story_gate_open(qid, completed) then
                  local prereqs = qd_prereqs(qid)
                  local ready = true
                  if type(prereqs) == "table" then
                      for _, pq in ipairs(prereqs) do
                          local pn = tonumber(pq)
                          if pn and not completed[pn] then ready = false; break end
                      end
                  end
                  if ready then
                      upcoming[qid] = true
                      if not mod.name_cache[qid] then resolve_meta(qlm, qid) end
                  end
              end
          end
      end

      -- Game may flag Acceptable before wiki PoNR; strip until available_after milestone is done.
      for qid in pairs(acceptable) do
          if not story_gate_open(qid, completed) then acceptable[qid] = nil end
      end
      for qid in pairs(upcoming) do
          if not story_gate_open(qid, completed) then upcoming[qid] = nil end
      end

      mod.progressing_ids = progressing
      mod.acceptable_ids  = acceptable
      mod.completed_ids   = completed
      mod.upcoming_ids    = upcoming
      mod.recency_order   = recency

      local best_rank, best_qid = 999999, nil
      for qid in pairs(completed) do
          local r = recency[qid] or 999999
          if r < best_rank then best_rank = r; best_qid = qid end
      end
      mod.newest_completed = best_qid
  end

  local function classify(qid)
      if mod.completed_ids[qid]   then return "Completed" end
      if mod.progressing_ids[qid] then return "Ongoing" end
      if mod.acceptable_ids[qid]  then return "Available" end
      -- Upcoming sides only. Main-story 10xxx chain is NOT "Available" until the game
      -- flags Acceptable/Progressing (stops Legacy/Gigantus/Godsway cluttering the tab).
      if mod.upcoming_ids and mod.upcoming_ids[qid] and qid >= 20000 then return "Available" end
      return nil
  end

  local function milestone_label(mid)
      return PONR_NAMES[mid] or ("Quest " .. tostring(mid))
  end

  local function _name_for_qid(qid)
      for _, pq in ipairs(mod.quests or {}) do
          if pq.id == qid then return pq.name end
      end
      if mod.name_en_cache and mod.name_en_cache[qid] then return mod.name_en_cache[qid] end
      if mod.name_cache and mod.name_cache[qid] then return mod.name_cache[qid] end
      if PONR_NAMES and PONR_NAMES[qid] then return PONR_NAMES[qid] end
      if QD and QD.get_quest_meta_name then
          local ok_m, mn = pcall(QD.get_quest_meta_name, qid)
          if ok_m and type(mn) == "string" and mn ~= "" then return mn end
      end
      return "Quest " .. tostring(qid)
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


  -- =========== STEP RESOLVER (separate file: Lua 200-local limit) ===========
  local StepsBridge = {}
  do
    local ok_st, Steps = pcall(require, "quest_tracker_steps")
    if ok_st and Steps and Steps.reset then Steps.reset() end
    mod._steps_module_ok = false
    if ok_st and Steps and Steps.install then
      local st_ctx = {
        mod = mod, mlog = mlog, mlog_boot = mlog_boot, QD = QD,
        safe_get_field = safe_get_field, safe_call = safe_call,
        iter_list = iter_list, get_quest_resource = MapBridge.get_quest_resource,
        to_int = to_int,
        _guid_to_en_text = _guid_to_en_text,
        _text_from_hex32 = _text_from_hex32,
        _read_text_field = _read_text_field,
        _name_for_qid = _name_for_qid,
        resolve_meta = resolve_meta,
      }
      Steps.install(st_ctx)
      StepsBridge._resolve_ongoing_step = st_ctx._resolve_ongoing_step
      StepsBridge._quest_progress_done_count = st_ctx._quest_progress_done_count
      mod._quest_progress_done_count = st_ctx._quest_progress_done_count
      StepsBridge._is_flavor_text = st_ctx._is_flavor_text
      StepsBridge._get_live_quest_step = st_ctx._get_live_quest_step
      StepsBridge._text_blobs_for_step_match = st_ctx._text_blobs_for_step_match
      StepsBridge._quest_log_info_fingerprint = st_ctx._quest_log_info_fingerprint
      StepsBridge._text_from_dest = st_ctx._text_from_dest
      mod._steps_module_ok = true
      mlog_boot("[QT] quest_tracker_steps OK")
    else
      mlog("[QT] FATAL quest_tracker_steps require failed: " .. tostring(Steps))
      StepsBridge._resolve_ongoing_step = function() return nil, nil, false, false end
      StepsBridge._is_flavor_text = function() return false end
    end
  end

  local function is_must_before_feast(qid, qname)
      if qid == FEAST_MILESTONE then return false end
      if mod.completed_ids[FEAST_MILESTONE] then return false end
      if mod.completed_ids[qid] then return false end
      if QD and QD.is_must_before_feast then
          local ok, v = pcall(QD.is_must_before_feast, qid)
          if ok and v then return true end
      end
      local n = (qname or _name_for_qid(qid) or ""):lower()
      if n:find("arisen") and n:find("shadow") then return true end
      return false
  end

  local function rebuild()
      if ALL_IDS == nil then ALL_IDS = dump_quest_id_enum() end
      local ok, err = pcall(gather)
      if not ok then mlog("[ERROR] gather() crashed: " .. tostring(err)) end

      local list = {}
      local counts = {0, 0, 0, 0, 0}  -- [1]=Available [2]=Ongoing [3]=Completed [4]=All [5]=Hidden
      local seen_qid = {}
      -- Union of enum-known ids and meta-only Upcoming ids (some side quests are missing from the enum dump).
      local function consider(qid, enum_name)
          if qid == nil or qid < 0 then return end
          if seen_qid[qid] then return end
          seen_qid[qid] = true
          local cat = classify(qid)
          if cat == nil then return end
          local voided = VOIDED_QUESTS[qid] == true
          -- Always prefer a real name: live cache â†’ meta name â†’ enum â†’ "Quest <id>" (last resort).
          local meta_nm = (QD and QD.get_quest_meta_name) and QD.get_quest_meta_name(qid) or nil
          local name = mod.name_cache[qid] or meta_nm or enum_name or ("Quest " .. tostring(qid))
          table.insert(list, {
              id        = qid,
              enum_name = enum_name or name,
              name      = name,
              name_en   = mod.name_en_cache[qid],
              summary   = mod.summary_cache[qid],
              recency   = mod.recency_order[qid] or 999999,
              category  = cat,
              voided    = voided,
          })
          if not voided then
              if     cat == "Available" then counts[1] = counts[1] + 1
              elseif cat == "Ongoing"   then counts[2] = counts[2] + 1
              elseif cat == "Completed" then counts[3] = counts[3] + 1 end
              counts[4] = counts[4] + 1
          else
              counts[5] = counts[5] + 1
          end
      end
      for qid, enum_name in pairs(ALL_IDS) do
          if enum_name ~= "Invalid" and enum_name ~= "None" then consider(qid, enum_name) end
      end
      for qid in pairs(mod.upcoming_ids or {}) do
          consider(qid, ALL_IDS and ALL_IDS[qid] or nil)
      end

      -- Sort
      local px, _, pz = get_player_universal_pos()
      local function quest_dist(qid)
          local Map = ctx.Map
          if Map and Map.quest_objective_dist_sq and px and pz then
              local step = mod._qt_step_title and mod._qt_step_title[qid]
              local ok_d, d = pcall(Map.quest_objective_dist_sq, qid, px, pz, step)
              if ok_d and type(d) == "number" then return d end
          end
          local p = MANUAL_POS_OVERRIDES[qid]
          if p then
              local dx = p.x - (px or 0); local dz = p.z - (pz or 0)
              return dx*dx + dz*dz
          end
          return 999999999
      end

      local function cat_weight(c)
          if c == "Ongoing"   then return 0 end
          if c == "Available" then return 1 end
          return 2
      end

      if mod.sort_mode == 1 then
          table.sort(list, function(a, b)
              if mod.tab == 2 then
                  local fa = (a.category == "Ongoing" and is_must_before_feast(a.id, a.name)) and 0 or 1
                  local fb = (b.category == "Ongoing" and is_must_before_feast(b.id, b.name)) and 0 or 1
                  if fa ~= fb then return fa < fb end
              end
              local wa, wb = cat_weight(a.category), cat_weight(b.category)
              if wa ~= wb then return wa < wb end
              if a.recency ~= b.recency then return a.recency < b.recency end
              return string.lower(a.name) < string.lower(b.name)
          end)
      elseif mod.sort_mode == 2 then
          table.sort(list, function(a, b)
              if a.recency ~= b.recency then return a.recency < b.recency end
              return a.name < b.name
          end)
      else
          table.sort(list, function(a, b) return quest_dist(a.id) < quest_dist(b.id) end)
      end

      mod.quests = list
      mod.state_counts = counts
      mod._qt_rebuild_n = (mod._qt_rebuild_n or 0) + 1
      local nenum = 0
      if ALL_IDS then for _ in pairs(ALL_IDS) do nenum = nenum + 1 end end
      local cnt_key = string.format("%d|%d|%d|%d", counts[1], counts[2], counts[3], counts[5])
      local tclock = os.clock()
      if cnt_key ~= mod._qt_cnt_key or (tclock - (mod._qt_last_rebuild_log or 0)) >= 45 then
          mod._qt_cnt_key = cnt_key
          mod._qt_last_rebuild_log = tclock
          local n_feast = 0
          if not mod.completed_ids[FEAST_MILESTONE] then
              for _, q in ipairs(list) do
                  if (q.category == "Available" or q.category == "Ongoing") and LOCKED_QUESTS[q.id] ~= true then
                      if is_must_before_feast(q.id, q.name) then n_feast = n_feast + 1 end
                  end
              end
          end
          mlog_boot(string.format(
              "[QT] rebuild #%d: list_rows=%d Available=%d Ongoing=%d Completed=%d Hidden=%d before_feast=%d feast_done=%s (enum_qids=%d)",
              mod._qt_rebuild_n, #list, counts[1], counts[2], counts[3], counts[5], n_feast,
              tostring(mod.completed_ids[FEAST_MILESTONE] or false), nenum))
          if mod.debug_logging and not mod.completed_ids[FEAST_MILESTONE] then
              for _, q in ipairs(list) do
                  if (q.category == "Available" or q.category == "Ongoing") and LOCKED_QUESTS[q.id] ~= true then
                      if is_must_before_feast(q.id, q.name) then
                          mlog(string.format("[QT][feast] qid=%d name=%s", q.id, q.name or "?"))
                      end
                  end
              end
          end
      end
      if mod.debug_logging then
          local na, no_, nc = 0, 0, 0
          for _ in pairs(mod.acceptable_ids or {}) do na = na + 1 end
          for _ in pairs(mod.progressing_ids or {}) do no_ = no_ + 1 end
          for _ in pairs(mod.completed_ids or {}) do nc = nc + 1 end
          mlog(string.format("[QT][debug] gather buckets acceptable=%d progressing=%d completed=%d", na, no_, nc))
      end
  end
  ctx.ALL_IDS = ALL_IDS
  ctx.resolve_meta = resolve_meta
  ctx.qd_givers = qd_givers
  ctx.qd_prereqs = qd_prereqs
  ctx.qd_note = qd_note
  ctx.qd_time_limit = qd_time_limit
  ctx.qd_available_after = qd_available_after
  ctx.qd_during_quest = qd_during_quest
  ctx.qd_trigger = qd_trigger
  ctx.qd_schedule = qd_schedule
  ctx.qd_timing_note = qd_timing_note
  ctx.qd_givers_display_order = qd_givers_display_order
  ctx.get_character_world_pos = get_character_world_pos
  ctx.get_player_universal_pos = get_player_universal_pos
  ctx._get_manual_player = _get_manual_player
  ctx.matches_filter = matches_filter
  ctx.pin_all_in_current_filtered_tab = pin_all_in_current_filtered_tab
  ctx.get_all_giver_cids = get_all_giver_cids
  ctx.get_primary_secondary_cids = get_primary_secondary_cids
  ctx._get_quest_start_pos = _get_quest_start_pos
  ctx.friendly_chara_name = friendly_chara_name
  ctx._resolve_cid_name = _resolve_cid_name
  ctx._build_npc_rows_for_cache = _build_npc_rows_for_cache
  ctx._draw_npc_rows_cached = _draw_npc_rows_cached
  ctx._hours_until_window_start = _hours_until_window_start
  ctx._get_game_clock_integers = _get_game_clock_integers
  ctx._get_game_hour_sched = _get_game_hour_sched
  ctx._format_game_time_line = _format_game_time_line
  ctx._format_hour_12 = _format_hour_12
  ctx._flush_pos_cache = _flush_pos_cache
  ctx._flush_pos_cache_cid = _flush_pos_cache_cid
  ctx.resolve_teleport_pos = resolve_teleport_pos
  ctx._log_tp = _log_tp
  ctx._start_fast_forward = _start_fast_forward
  ctx._tick_fast_forward = _tick_fast_forward
  ctx._set_time_scale = _set_time_scale
  ctx._get_time_scale = _get_time_scale
  ctx._set_game_clock_integers = _set_game_clock_integers
  ctx.gather = gather
  ctx.rebuild = rebuild
  ctx.classify = classify
  ctx.milestone_label = milestone_label
  ctx._name_for_qid = _name_for_qid
  ctx.is_must_before_feast = is_must_before_feast

end

return M
