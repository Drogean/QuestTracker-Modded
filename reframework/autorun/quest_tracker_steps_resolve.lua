-- quest_tracker_steps_resolve — resolve_ongoing_step chain + wiki progress
local M = package.loaded["quest_tracker_steps_resolve"]
if M then return M end
M = {}

function M.install(ctx)
  local mod = ctx.mod
  local mlog = ctx.mlog
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

  local function _quest_progress_done_count(qlm, qid)
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

  local function _wiki_step_from_progress(qid, qlm)
      if not QD or not QD.get_wiki_step_for_progress then return nil, nil end
      if QD.has_wiki_step_order and not QD.has_wiki_step_order(qid) then return nil, nil end
      local done = _quest_progress_done_count(qlm, qid)
      local ok, title, idx, total = pcall(QD.get_wiki_step_for_progress, qid, done)
      if not ok or not title then return nil, nil end
      mod._step_field_src = mod._step_field_src or {}
      mod._step_field_src[qid] = string.format("wiki_progress done=%d step=%d/%d", done, idx or 0, total or 0)
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

  local function _text_blobs_for_step_match(qlm, qid)
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
      add(mod.summary_cache[qid])
      return blobs
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
          if QD.match_wiki_step_index then
              local idx, steps = QD.match_wiki_step_index(qid, blob)
              if idx and steps then
                  local s = steps[idx]
                  if type(s) == "string" then
                      if QD.titleize_step_key and not s:find("%s") then
                          return QD.titleize_step_key(s) or s
                      end
                      return s
                  end
              end
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

  -- Progress-first resolver: wiki walkthrough keyed off completed objectives, then safe live strings.
  -- Live game strings first, then wiki journal match, then task tree, then progress index last resort.
  local function _resolve_ongoing_step(qlm, qid)
      mod._step_field_src = mod._step_field_src or {}
      mod._step_field_src[qid] = nil

      local step_title, step_detail = _get_live_quest_step(qlm, qid)
      local step_from_game = step_title ~= nil
      local wiki_fallback = false
      local wiki_progress = false

      if not step_title then
          step_title = _wiki_step_from_scraped_text(qid, qlm)
          if step_title then
              wiki_fallback = true
              wiki_progress = false
              mod._step_field_src[qid] = "wiki_scraped"
          end
      end
      if not step_title then
          local pt, pd, pg = _wiki_step_from_task_progress(qlm, qid)
          if pt then
              step_title, step_detail, step_from_game = pt, pd, pg
              wiki_fallback = not pg
              wiki_progress = false
          end
      end
      if not step_title then
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
      if field:find("wiki_progress", 1, true) then
          wiki_fallback = true
          wiki_progress = true
          step_from_game = false
      elseif field:find("InfoDict.live_pin", 1, true) or field:find("InfoDict._CurrentDestinations", 1, true)
          or field:find("InfoDict.taskIndex", 1, true) or field:find("active_dest", 1, true) then
          step_from_game = step_title ~= nil
          wiki_fallback = false
          wiki_progress = false
      elseif field == "wiki_fallback_key" or field == "wiki_scraped" then
          wiki_fallback = true
          wiki_progress = false
          step_from_game = false
      end
      mod._wiki_progress_flag = mod._wiki_progress_flag or {}
      mod._wiki_progress_flag[qid] = wiki_progress
      local src = wiki_progress and "wiki_progress" or (wiki_fallback and "wiki_fallback" or (step_from_game and "game" or "none"))
      local title_key = (step_title or "") .. "|" .. src .. "|" .. field
      if mod._step_last_title[qid] ~= title_key then
          mod._step_last_title[qid] = title_key
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
  ctx._get_live_quest_step = _get_live_quest_step
  ctx._text_blobs_for_step_match = _text_blobs_for_step_match
  ctx._resolve_ongoing_step = _resolve_ongoing_step

end

return M
