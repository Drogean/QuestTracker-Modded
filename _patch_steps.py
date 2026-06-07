# Patch quest_tracker_steps.lua: remove resolve block, wire steps_resolve
from pathlib import Path

ROOT = Path(r"c:\Users\jzafi\Desktop\New folder\OTHERMODS\QuestTracker-Modded\reframework\autorun")
STEPS = ROOT / "quest_tracker_steps.lua"
lines = STEPS.read_text(encoding="utf-8", errors="replace").splitlines()

# Drop lines 808-1107 (1-based) = resolve chain moved to steps_resolve
keep = [ln for i, ln in enumerate(lines, 1) if i < 808 or i > 1107]

# Add reload guard after header if missing
if "package.loaded" not in keep[0]:
    header = keep[0]
    keep[0:1] = [
        header,
        'local M = package.loaded["quest_tracker_steps"]',
        "if M then return M end",
        "M = {}",
        "",
        "function M.reset()",
    ]
    # Fix: original has `local M = {}` and function M.reset - need to replace local M = {}
    text = "\n".join(keep)
    text = text.replace("local M = {}\n\nlocal TASK_WALK", "local TASK_WALK", 1)
    text = text.replace("function M.reset()\n    for k in pairs(_step_fail_logged)",
                        "function M.reset()\n    for k in pairs(_step_fail_logged)", 1)
    if 'local M = package.loaded["quest_tracker_steps"]' not in text:
        text = text.replace(
            "-- quest_tracker_steps.lua — quest step resolution (kept out of main chunk local limit)\nlocal M = {}",
            '-- quest_tracker_steps.lua — quest step resolution (kept out of main chunk local limit)\nlocal M = package.loaded["quest_tracker_steps"]\nif M then return M end\nM = {}',
            1,
        )

# Re-read and patch install end
lines = text.splitlines() if 'text' in dir() else keep
if 'text' not in dir():
    text = "\n".join(lines)

# Insert ctx exports + resolve require before fingerprint function
marker = "  ctx._quest_progress_done_count = _quest_progress_done_count"
if marker in text and "quest_tracker_steps_resolve" not in text:
    inject = '''
  ctx._is_flavor_text = _is_flavor_text
  ctx._is_weak_step = _is_weak_step
  ctx._pick_step = _pick_step
  ctx._log_info_entry = _log_info_entry
  ctx._info_task_index = _info_task_index
  ctx._text_from_dest = _text_from_dest
  ctx._iter_managed_list = _iter_managed_list
  ctx._task_tree_sources = _task_tree_sources
  ctx._count_cleared_and_last_open = _count_cleared_and_last_open
  ctx._step_from_vi_task = _step_from_vi_task
  ctx._log_objective_from_vi = _log_objective_from_vi
  ctx._journal_step_from_sources = _journal_step_from_sources
  ctx._step_from_active_dests = _step_from_active_dests
  ctx._step_from_decomp_by_index = _step_from_decomp_by_index
  ctx._step_from_decomp_dests = _step_from_decomp_dests
  ctx._step_from_all_tasks_scavenge = _step_from_all_tasks_scavenge
  ctx._step_from_log_info_dict = _step_from_log_info_dict
  ctx._task_from_questlog_vi = _task_from_questlog_vi
  ctx._task_lists_from_vi = _task_lists_from_vi
  ctx._walk_task_list = _walk_task_list
  ctx._walk_journal_current = _walk_journal_current
  ctx._task_title_and_detail = _task_title_and_detail
  ctx._scavenge_object_text = _scavenge_object_text
  ctx._completed_task_count = _completed_task_count
  ctx._resolve_info_dest_step = _resolve_info_dest_step
  ctx._probe_step_api = _probe_step_api
  require("quest_tracker_steps_resolve").install(ctx)
'''
    text = text.replace(marker, inject.strip() + "\n\n  " + marker.split("  ")[1] if False else inject + "\n" + marker)

# Simpler replace: before fingerprint block
old = "  ctx._quest_progress_done_count = _quest_progress_done_count\n\n  function ctx._quest_log_info_fingerprint"
new_block = '''  ctx._is_flavor_text = _is_flavor_text
  ctx._is_weak_step = _is_weak_step
  ctx._pick_step = _pick_step
  ctx._log_info_entry = _log_info_entry
  ctx._info_task_index = _info_task_index
  ctx._text_from_dest = _text_from_dest
  ctx._iter_managed_list = _iter_managed_list
  ctx._task_tree_sources = _task_tree_sources
  ctx._count_cleared_and_last_open = _count_cleared_and_last_open
  ctx._step_from_vi_task = _step_from_vi_task
  ctx._log_objective_from_vi = _log_objective_from_vi
  ctx._journal_step_from_sources = _journal_step_from_sources
  ctx._step_from_active_dests = _step_from_active_dests
  ctx._step_from_decomp_by_index = _step_from_decomp_by_index
  ctx._step_from_decomp_dests = _step_from_decomp_dests
  ctx._step_from_all_tasks_scavenge = _step_from_all_tasks_scavenge
  ctx._step_from_log_info_dict = _step_from_log_info_dict
  ctx._task_from_questlog_vi = _task_from_questlog_vi
  ctx._task_lists_from_vi = _task_lists_from_vi
  ctx._walk_task_list = _walk_task_list
  ctx._walk_journal_current = _walk_journal_current
  ctx._task_title_and_detail = _task_title_and_detail
  ctx._scavenge_object_text = _scavenge_object_text
  ctx._completed_task_count = _completed_task_count
  ctx._resolve_info_dest_step = _resolve_info_dest_step
  ctx._probe_step_api = _probe_step_api
  require("quest_tracker_steps_resolve").install(ctx)

  function ctx._quest_log_info_fingerprint'''

if old in text:
    text = text.replace(old, new_block)
else:
    print("WARN: fingerprint marker not found")

# Remove duplicate ctx assignments at end if resolve moved them
for dup in [
    "  ctx._resolve_ongoing_step = _resolve_ongoing_step\n",
    "  ctx._get_live_quest_step = _get_live_quest_step\n",
    "  ctx._text_blobs_for_step_match = _text_blobs_for_step_match\n",
]:
    if dup in text and "steps_resolve" in text:
        text = text.replace(dup, "")

STEPS.write_text(text, encoding="utf-8")
print("steps lines", len(text.splitlines()))
