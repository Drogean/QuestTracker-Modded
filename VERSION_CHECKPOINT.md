# VERSION CHECKPOINT v1.4.0

Base: v1.3.2 (commit 57d2088) — last known good, journal pin via setupQuestTargetMarker
Patches: P1 EndChild tracking+ensure_closed | P2 blob dedupe guard never wiped outside layer-change | P3 label FAIL per-qid logging | P4 pin_all_ongoing journal-one-pin only | P5 on_journal_progress_bump force_marker_refresh | P6 _resolve_ongoing_step live-first order
Pass criteria: zero "label FAIL summary want=1 labels=0" spam | sculpt reinject blob ONE log per qid per layer change (not dozens/sec) | child window no ImGui EndChild errors on minimize | step src=game not wiki_progress for active journal quest
