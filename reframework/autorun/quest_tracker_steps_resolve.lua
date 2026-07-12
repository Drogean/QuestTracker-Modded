-- quest_tracker_steps_resolve — resolve_ongoing_step chain + wiki progress
local M = package.loaded["quest_tracker_steps_resolve"]
if M then return M end
M = {}

function M.install(ctx)
  local mod = ctx.mod
  local mlog = ctx.mlog
  local mlog_boot = ctx.mlog_boot or ctx.mlog
  local QD = ctx.QD
  local safe_get_field = ctx.safe_get_field
  local safe_call = ctx.safe_call
  local iter_list = ctx.iter_list
  local get_quest_resource = ctx.get_quest_resource
  local _guid_to_en_text = ctx._guid_to_en_text
  local resolve_meta = ctx.resolve_meta
  local _text_from_hex32 = ctx._text_from_hex32
  local to_int = ctx.to_int
  local _is_flavor_text = ctx._is_flavor_text
  local _is_weak_step = ctx._is_weak_step
  local _pick_step = ctx._pick_step
  local _log_info_entry = ctx._log_info_entry
  local _info_task_index = ctx._info_task_index
  local _text_from_dest = ctx._text_from_dest
  local _iter_managed_list = ctx._iter_managed_list
  local _task_tree_sources = ctx._task_tree_sources
  local _count_cleared_and_last_open = ctx._count_cleared_and_last_open
  local _step_from_vi_task = ctx._step_from_vi_task
  local _log_objective_from_vi = ctx._log_objective_from_vi
  local _journal_step_from_sources = ctx._journal_step_from_sources
  local _step_from_active_dests = ctx._step_from_active_dests
  local _step_from_decomp_by_index = ctx._step_from_decomp_by_index
  local _step_from_decomp_dests = ctx._step_from_decomp_dests
  local _step_from_all_tasks_scavenge = ctx._step_from_all_tasks_scavenge
  local _step_from_log_info_dict = ctx._step_from_log_info_dict
  local _task_from_questlog_vi = ctx._task_from_questlog_vi
  local _task_lists_from_vi = ctx._task_lists_from_vi
  local _walk_task_list = ctx._walk_task_list
  local _walk_journal_current = ctx._walk_journal_current
  local _task_title_and_detail = ctx._task_title_and_detail
  local _scavenge_object_text = ctx._scavenge_object_text
  local _completed_task_count = ctx._completed_task_count
  local _resolve_info_dest_step = ctx._resolve_info_dest_step
  local _probe_step_api = ctx._probe_step_api

  local _text_blobs_for_step_match

  local function _quest_progress_game_done(qlm, qid)
      local best = 0
      if qlm then
          local entry = _log_info_entry(qlm, qid)
          if entry then
              local c = _completed_task_count(entry)
              if c > best then best = c end
          end
      end
      for _, src in ipairs(_task_tree_sources(qlm, qid)) do
          local c = _count_cleared_and_last_open(src)
          if c > best then best = c end
      end
      return best
  end

  local function _quest_progress_done_count(qlm, qid)
      local best = _quest_progress_game_done(qlm, qid)
      local game_best = best
      if QD and QD.effective_progress_done and _text_blobs_for_step_match then
          best = QD.effective_progress_done(qid, best, _text_blobs_for_step_match(qlm, qid))
      end
      -- #region agent log
      if tonumber(qid) == 30220 then
          local ok_dbg, _ = pcall(function()
              local f = io.open("c:/Users/jzafi/Desktop/New folder/OTHERMODS/QuestTracker-Modded/debug-62ebea.log", "a")
              if f then
                  f:write(string.format(
                      '{"sessionId":"62ebea","hypothesisId":"A","location":"steps_resolve.lua:_quest_progress_done_count","message":"30220 done counts","data":{"game_done":%d,"effective_done":%d},"timestamp":%d}\n',
                      game_best, best, os.time() * 1000))
                  f:close()
              end
          end)
      end
      -- #endregion
      return best
  end

  local function _quest_current_task_index(qlm, qid)
      if not qlm then return nil end
      local entry = _log_info_entry(qlm, qid)
      if not entry then return nil end
      return _info_task_index(entry)
  end

  local function _wiki_step_from_progress(qid, qlm)
      if not QD or not QD.get_wiki_step_for_progress then return nil, nil end
      if QD.has_wiki_step_order and not QD.has_wiki_step_order(qid) then return nil, nil end
      local done = _quest_progress_done_count(qlm, qid)
      local task_idx = _quest_current_task_index(qlm, qid)
      local ok, title, idx, total = pcall(QD.get_wiki_step_for_progress, qid, done, task_idx)
      if not ok or not title then return nil, nil end
      mod._step_field_src = mod._step_field_src or {}
      mod._step_field_src[qid] = string.format("wiki_progress done=%d task_idx=%s step=%d/%d",
          done, tostring(task_idx), idx or 0, total or 0)
      local detail = mod.summary_cache and mod.summary_cache[qid] or nil
      if detail and _is_flavor_text(detail, qid) == false and title == detail then detail = nil end
      return title, detail
  end

  -- Live strings only — no journal cache, no guid decode (unreliable on many PCs).
  local function _get_live_quest_step(qlm, qid)
      if qlm == nil then return nil, nil end
      mod._step_field_src = mod._step_field_src or {}
      mod._step_field_src[qid] = nil
      local vi = safe_call(qlm, "getQuestLog", qid)
      if vi then
          local t, d = _step_from_vi_task(vi, qid)
          if t then return t, d end
          local lo, ld = _log_objective_from_vi(vi, qid)
          if lo then return lo, ld end
      end
      t = _step_from_active_dests(qlm, qid)
      if t then
          mod._step_field_src[qid] = "active_dest"
          return t, nil
      end
      -- Try live info dict early: game's current objective beats noisy resource/task scavenge
      do
          local t_lid, d_lid = _step_from_log_info_dict(qlm, qid)
          if t_lid then return t_lid, d_lid end
      end
      local jt, jd = _journal_step_from_sources(qlm, qid)
      local t, d = _pick_step(qid, jt, jd, "journal_tree")
      if t then return t, d end
      local entry_early = _log_info_entry(qlm, qid)
      if entry_early then
          local done = _completed_task_count(entry_early)
          local ti = _info_task_index(entry_early)
          local try_idx = math.max(done, (ti or 0) + 1) - 1
          if try_idx < 0 then try_idx = 0 end
          local dd2 = _step_from_decomp_by_index(qid, try_idx)
              or _step_from_decomp_by_index(qid, ti)
              or _step_from_decomp_by_index(qid, done)
          if dd2 then
              mod._step_field_src[qid] = "InfoDict.completed+decomp"
              return dd2, nil
          end
      end
      t, d = _step_from_all_tasks_scavenge(qlm, qid)
      if t then return t, d end
      if vi then
          local backing = _task_from_questlog_vi(vi)
          if backing then
              local title, detail = _task_title_and_detail(backing)
              t, d = _pick_step(qid, title, detail, "QuestLog.Task")
              if t then return t, d end
          end
          for _, key in ipairs({
              "CurrentTaskName", "QuestCurrentTaskName", "ActiveTaskName", "ObjectiveName",
              "CurrentObjective", "TaskName", "ProgressName",
          }) do
              local v = safe_get_field(vi, key)
              if type(v) == "string" and v ~= "" then
                  t, d = _pick_step(qid, v, nil, key)
                  if t then return t, d end
              end
          end
          for _, key in ipairs({
              "CurrentTaskNameId", "ActiveTaskNameId", "ObjectiveNameId", "TaskNameId",
          }) do
              local gt = _guid_to_en_text(safe_get_field(vi, key))
              t, d = _pick_step(qid, gt, nil, key)
              if t then return t, d end
          end
          local cur_task = safe_call(vi, "get_CurrentTask") or safe_call(vi, "get_ActiveTask")
          if cur_task then
              local title, detail = _task_title_and_detail(cur_task)
              t, d = _pick_step(qid, title, detail, "CurrentTask")
              if t then return t, d end
          end
      end
      for _, src in ipairs(_task_lists_from_vi(vi)) do
          local found = {}
          _walk_task_list(src, found, 1)
          if not found[1] then _walk_task_list(src, found, 2) end
          if not found[1] then _walk_journal_current(src, found) end
          t, d = _pick_step(qid, found[1], found[2], "task_list")
          if t then return t, d end
      end
      local res = get_quest_resource(qlm, qid)
      if res then
          local found = {}
          for _, src in ipairs({
              safe_get_field(res, "_CurrentTaskList"),
              safe_call(res, "get_CurrentTaskList"),
              safe_get_field(res, "_TaskList"),
              safe_get_field(res, "_FirstTaskList"),
              safe_call(res, "get_FirstTaskList"),
              safe_get_field(res, "_TaskLogList"),
              safe_call(res, "get_TaskLogList"),
          }) do
              _walk_task_list(src, found, 1)
              if not found[1] then _walk_task_list(src, found, 2) end
              if not found[1] then _walk_journal_current(src, found) end
              if found[1] then break end
          end
          t, d = _pick_step(qid, found[1], found[2], "resource_task")
          if t then return t, d end
      end
      local entry = _log_info_entry(qlm, qid)
      local task_idx = entry and _info_task_index(entry) or nil
      local dd = _step_from_decomp_by_index(qid, task_idx) or _step_from_decomp_dests(qlm, qid)
      if dd then
          mod._step_field_src[qid] = task_idx ~= nil and "decomp_by_index" or "decomp_dest"
          return dd, nil
      end
      local t, d = _step_from_log_info_dict(qlm, qid)
      if t then return t, d end
      if vi then
          local ok_sc, sc = pcall(_scavenge_object_text, vi, qid, { QuestName = true, QuestSummary = true, QuestNameId = true })
          t, d = _pick_step(qid, ok_sc and sc or nil, nil, "scavenge")
          if t then return t, d end
      end
      if mod.debug_logging then _probe_step_api(qid, vi, res) end
      return nil, nil
  end

  local function _scrape_quest_log_strings(vi)
      local out, seen = {}, {}
      local function add(s)
          if type(s) ~= "string" or s == "" or #s < 4 then return end
          local k = s:lower()
          if seen[k] then return end
          seen[k] = true
          out[#out + 1] = s
      end
      if vi == nil then return out end
      for _, key in ipairs({
          "QuestLogText", "GuideText", "CurrentLogText", "TaskLogText", "QuestGuideText",
          "QuestSummary", "ObjectiveText", "CurrentObjectiveText", "ProgressText", "SubTaskName",
          "CurrentTaskName", "QuestCurrentTaskName", "ActiveTaskName", "ObjectiveName",
          "MainTaskName", "SubTaskText", "GuideDetailText",
      }) do
          add(safe_get_field(vi, key))
          add(_guid_to_en_text(safe_get_field(vi, key .. "Id")))
      end
      return out
  end

  _text_blobs_for_step_match = function(qlm, qid)
      local blobs, seen = {}, {}
      local function add(s)
          if type(s) ~= "string" or s == "" or #s < 4 then return end
          local k = s:lower()
          if seen[k] then return end
          seen[k] = true
          blobs[#blobs + 1] = s
      end
      if qlm then resolve_meta(qlm, qid) end
      local vi = qlm and safe_call(qlm, "getQuestLog", qid) or nil
      for _, b in ipairs(_scrape_quest_log_strings(vi)) do add(b) end
      if _log_objective_from_vi and vi then
          local ok_o, ot = pcall(_log_objective_from_vi, vi, qid)
          if ok_o and type(ot) == "string" then add(ot) end
      end
      if mod.summary_cache and type(mod.summary_cache[qid]) == "string" then add(mod.summary_cache[qid]) end
      return blobs
  end

  local function _wiki_step_from_blob_index(qid, qlm)
      if not QD or not QD.get_wiki_step_order or not QD.get_step_title_from_order_index then return nil end
      local order = QD.get_wiki_step_order(qid)
      if not order or #order == 0 then return nil end
      local max_idx = 0
      for _, blob in ipairs(_text_blobs_for_step_match(qlm, qid)) do
          local idx = QD.max_matched_step_index and QD.max_matched_step_index(qid, blob)
          if idx and idx > max_idx then max_idx = idx end
      end
      if max_idx <= 0 then return nil end
      local done = _quest_progress_done_count(qlm, qid)
      local cur = math.max(done + 1, max_idx)
      cur = math.min(cur, #order)
      local title = QD.get_step_title_from_order_index(qid, cur)
      if title then
          mod._step_field_src[qid] = string.format("wiki_blob_idx done=%d max=%d cur=%d", done, max_idx, cur)
          return title
      end
      return nil
  end

  local function _wiki_step_from_scraped_text(qid, qlm)
      if not QD then return nil end
      for _, blob in ipairs(_text_blobs_for_step_match(qlm, qid)) do
          if QD.guess_step_from_hints then
              local t = QD.guess_step_from_hints(qid, blob)
              if t then return t end
          elseif QD.match_step_key_from_text then
              local t = QD.match_step_key_from_text(qid, blob)
              if t then return t end
          end
      end
      return nil
  end

  local function _wiki_step_from_task_progress(qlm, qid)
      if not QD then return nil, nil, false end
      local sources = _task_tree_sources(qlm, qid)
      local best_cleared, last_title, last_detail = 0, nil, nil
      for _, src in ipairs(sources) do
          local c, lt, ld = _count_cleared_and_last_open(src)
          if c > best_cleared then best_cleared = c end
          if lt and not _is_flavor_text(lt, qid) and not _is_weak_step(lt) then
              last_title, last_detail = lt, ld
          end
      end
      if last_title then return last_title, last_detail, true end
      return nil, nil, false
  end

  -- Journal-first when quest log is open for this qid; else live game strings, then wiki.
  local function _resolve_ongoing_step(qlm, qid)
      mod._step_field_src = mod._step_field_src or {}
      mod._step_field_src[qid] = nil

      local step_title, step_detail = nil, nil
      local step_from_game = false
      local wiki_fallback = false
      local wiki_progress = false
      local has_wiki_order = QD and QD.has_wiki_step_order and QD.has_wiki_step_order(qid)

      local journal_open = (mod._qt_journal_qid and tonumber(mod._qt_journal_qid) == tonumber(qid))
          or (mod._qt_journal_menu_qid and tonumber(mod._qt_journal_menu_qid) == tonumber(qid))
      local jt_raw, jd_raw = nil, nil
      if journal_open and qlm then
          jt_raw, jd_raw = _journal_step_from_sources(qlm, qid)
          local t, d = _pick_step(qid, jt_raw, jd_raw, "journal")
          if t then
              step_title, step_detail = t, d
              step_from_game = true
              mod._step_field_src[qid] = "journal"
          end
      end

      local live_title, live_detail = nil, nil
      if not step_title then
          live_title, live_detail = _get_live_quest_step(qlm, qid)
          step_title, step_detail = live_title, live_detail
          step_from_game = step_title ~= nil
      end
      -- Prefer journal/objective TEXT → wiki step key (global). Game done-count often
      -- overshoots curated step_order (e.g. 30220 done=2 → last tip while still in gaol).
      if not step_title and has_wiki_order and QD and QD.match_step_key_from_text and _text_blobs_for_step_match then
          local blobs = _text_blobs_for_step_match(qlm, qid)
          local best_t, best_len = nil, 0
          for _, blob in ipairs(blobs or {}) do
              if type(blob) == "string" and blob ~= "" then
                  local t = QD.match_step_key_from_text(qid, blob)
                  if type(t) == "string" and #t > best_len then
                      best_t, best_len = t, #t
                  end
              end
          end
          if best_t then
              step_title = best_t
              wiki_fallback = true
              wiki_progress = false
              mod._step_field_src[qid] = "wiki_text_match"
          end
      end
      if not step_title then
          if has_wiki_order then
              local wt, wd = _wiki_step_from_progress(qid, qlm)
              if wt then
                  -- Guard: do not show the LAST curated tip unless journal text mentions that step.
                  local order = QD.get_wiki_step_order and QD.get_wiki_step_order(qid)
                  local guarded = false
                  if type(order) == "table" and #order >= 2 then
                      local field_src = mod._step_field_src and mod._step_field_src[qid] or ""
                      local idx = tonumber(field_src:match("step=(%d+)/")) or 0
                      if idx >= #order then
                          local late_key = order[#order]
                          local late_hit = false
                          local blobs = _text_blobs_for_step_match and _text_blobs_for_step_match(qlm, qid) or {}
                          local late_l = type(late_key) == "string" and late_key:lower() or ""
                          for _, blob in ipairs(blobs) do
                              if type(blob) == "string" and late_l ~= "" and blob:lower():find(late_l, 1, true) then
                                  late_hit = true
                                  break
                              end
                          end
                          if not late_hit and QD.get_fallback_step_title then
                              local ok_fb, fb = pcall(QD.get_fallback_step_title, qid)
                              if ok_fb and type(fb) == "string" and fb ~= "" then
                                  step_title, step_detail = fb, nil
                                  wiki_fallback = true
                                  wiki_progress = false
                                  mod._step_field_src[qid] = "wiki_fallback_guard"
                                  guarded = true
                              end
                          end
                      end
                  end
                  if not guarded then
                      step_title, step_detail = wt, wd
                      wiki_fallback = true
                      wiki_progress = true
                  end
              end
          end
      end
      -- #region agent log
      if tonumber(qid) == 30220 then
          pcall(function()
              local function esc(s)
                  if type(s) ~= "string" then return "" end
                  return (s:gsub("[\\\"]", "\\%0"):gsub("\n", " "):sub(1, 80))
              end
              local paths = {
                  "reframework/data/debug-62ebea.log",
                  "c:/Users/jzafi/Desktop/New folder/OTHERMODS/QuestTracker-Modded/debug-62ebea.log",
              }
              local line = string.format(
                  '{"sessionId":"62ebea","runId":"post-fix","hypothesisId":"B","location":"steps_resolve.lua:_resolve_ongoing_step","message":"30220 resolve branches","data":{"journal_open":%s,"jt":"%s","live":"%s","picked":"%s","field":"%s","has_wiki_order":%s},"timestamp":%d}\n',
                  journal_open and "true" or "false",
                  esc(jt_raw), esc(live_title), esc(step_title),
                  esc(mod._step_field_src and mod._step_field_src[qid]),
                  has_wiki_order and "true" or "false",
                  os.time() * 1000)
              for _, p in ipairs(paths) do
                  local f = io.open(p, "a")
                  if f then f:write(line); f:close() end
              end
          end)
          if mlog_boot then
              mlog_boot(string.format("[QT][dbg62ebea] 30220 jopen=%s jt=%s live=%s picked=%s field=%s",
                  tostring(journal_open), tostring(jt_raw and jt_raw:sub(1,40)), tostring(live_title and live_title:sub(1,40)),
                  tostring(step_title and step_title:sub(1,40)), tostring(mod._step_field_src and mod._step_field_src[qid])))
          elseif mlog then
              mlog(string.format("[QT][dbg62ebea] 30220 jopen=%s jt=%s live=%s picked=%s field=%s",
                  tostring(journal_open), tostring(jt_raw and jt_raw:sub(1,40)), tostring(live_title and live_title:sub(1,40)),
                  tostring(step_title and step_title:sub(1,40)), tostring(mod._step_field_src and mod._step_field_src[qid])))
          end
      end
      -- #endregion
      if not step_title then
          local pt, pd, pg = _wiki_step_from_task_progress(qlm, qid)
          if pt then
              step_title, step_detail, step_from_game = pt, pd, pg
              wiki_fallback = not pg
              wiki_progress = false
          end
      end
      if not step_title and not has_wiki_order then
          step_title = _wiki_step_from_blob_index(qid, qlm)
          if step_title then
              wiki_fallback = true
              wiki_progress = true
          end
      end
      if not step_title and not has_wiki_order then
          step_title = _wiki_step_from_scraped_text(qid, qlm)
          if step_title then
              wiki_fallback = true
              wiki_progress = false
              mod._step_field_src[qid] = "wiki_scraped"
          end
      end
      if not step_title and not has_wiki_order then
          local wt, wd = _wiki_step_from_progress(qid, qlm)
          if wt then
              step_title, step_detail = wt, wd
              wiki_fallback = true
              wiki_progress = true
          end
      end
      if not step_title and QD and QD.get_fallback_step_title then
          local ok_fb, fb = pcall(QD.get_fallback_step_title, qid)
          if ok_fb and type(fb) == "string" and fb ~= "" then
              step_title = fb
              wiki_fallback = true
              wiki_progress = false
              mod._step_field_src[qid] = "wiki_fallback_key"
          end
      end
      mod._step_last_title = mod._step_last_title or {}
      local field = (mod._step_field_src and mod._step_field_src[qid]) or "-"
      if field == "journal" then
          step_from_game = true
          wiki_fallback = false
          wiki_progress = false
      elseif field == "wiki_text_match" or field == "wiki_fallback_key" or field == "wiki_scraped"
          or field == "wiki_fallback_guard" then
          wiki_fallback = true
          wiki_progress = false
          step_from_game = false
      elseif field:find("wiki_blob_idx", 1, true) or field:find("wiki_progress", 1, true) then
          wiki_fallback = true
          wiki_progress = true
          step_from_game = false
      elseif field:find("InfoDict.live_pin", 1, true) or field:find("InfoDict._CurrentDestinations", 1, true)
          or field:find("InfoDict.taskIndex", 1, true) or field:find("active_dest", 1, true) then
          step_from_game = step_title ~= nil
          wiki_fallback = false
          wiki_progress = false
      end
      mod._wiki_progress_flag = mod._wiki_progress_flag or {}
      mod._wiki_progress_flag[qid] = wiki_progress
      if qlm and _text_blobs_for_step_match then
          mod._qt_step_blobs = mod._qt_step_blobs or {}
          mod._qt_step_blobs[qid] = _text_blobs_for_step_match(qlm, qid)
      end
      local src = (field == "journal") and "journal"
          or (wiki_progress and "wiki_progress" or (wiki_fallback and "wiki_fallback" or (step_from_game and "live" or "none")))
      local title_key = (step_title or "") .. "|" .. src .. "|" .. field
      if mod._step_last_title[qid] ~= title_key then
          mod._step_last_title[qid] = title_key
          local idx = (QD and QD.get_step_order_index and step_title) and (QD.get_step_order_index(qid, step_title) or "-") or "-"
          mlog(string.format("[QT][resolve] qid=%d src=%s idx=%s field=%s step=%s",
              qid, src, tostring(idx), field, step_title or "(none)"))
          mlog(string.format("[QT][step] qid=%d title=%s src=%s field=%s", qid, step_title or "(none)", src, field))
          if not step_title and QD and QD.get_wiki_hint_lines then
              local ok_ln, ln = pcall(QD.get_wiki_hint_lines, qid)
              local n = (ok_ln and type(ln) == "table") and #ln or 0
              if n > 0 then mlog(string.format("[QT][step] qid=%d wiki_lines=%d (no step — showing hints)", qid, n)) end
          end
          if mod.debug_logging and qlm then
              for i, blob in ipairs(_text_blobs_for_step_match(qlm, qid)) do
                  if i <= 4 then
                      mlog(string.format("[QT][step] qid=%d blob[%d]=%s", qid, i, blob:sub(1, 120)))
                  end
              end
          end
      end
      return step_title, step_detail, step_from_game, wiki_fallback
  end
  ctx._quest_progress_done_count = _quest_progress_done_count
  ctx._quest_current_task_index = _quest_current_task_index
  ctx._get_live_quest_step = _get_live_quest_step
  ctx._text_blobs_for_step_match = _text_blobs_for_step_match
  ctx._resolve_ongoing_step = _resolve_ongoing_step

end

return M
