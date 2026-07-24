from __future__ import annotations

from pathlib import Path
import re


def read(path: str) -> str:
    return Path(path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    Path(path).write_text(text, encoding="utf-8", newline="\n")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one exact match, found {count}")
    return text.replace(old, new, 1)


def replace_regex(text: str, pattern: str, replacement: str, label: str) -> str:
    result, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise RuntimeError(f"{label}: expected one regex match, found {count}")
    return result


def patch_save_service() -> None:
    path = "src/save/save_service.gd"
    text = read(path)
    text = replace_once(
        text,
        'const MAX_AUTHORITATIVE_READS_PER_LIST := 32\n',
        'const MAX_AUTHORITATIVE_READS_PER_LIST := 32\n'
        'const MAX_STAGED_CATALOG_ENTRIES := 64\n',
        "insert stage capacity",
    )
    text = replace_once(
        text,
        'var _last_catalog_authoritative_read_budget_used := 0\n',
        'var _last_catalog_authoritative_read_budget_used := 0\n'
        'var _catalog_authoritative_read_count := 0\n'
        'var _catalog_stage_hit_count := 0\n'
        'var _catalog_stage_invalidation_count := 0\n'
        'var _last_catalog_stage_hit_count := 0\n'
        'var _last_catalog_stage_invalidation_count := 0\n'
        'var _catalog_stage_peak_count := 0\n'
        'var _staged_catalog_entries: Dictionary = {}\n',
        "insert stage state",
    )
    text = replace_once(
        text,
        '\tif not _write_catalog_entry(world_id, payload, save_bytes):\n'
        '\t\t# The catalog is derived and self-healing. A catalog failure must never turn\n'
        '\t\t# a successful authoritative world write into a false save failure.\n'
        '\t\t_catalog_write_failure_count += 1\n',
        '\tif not _write_catalog_entry(world_id, payload, save_bytes):\n'
        '\t\t# The catalog is derived and self-healing. A catalog failure must never turn\n'
        '\t\t# a successful authoritative world write into a false save failure.\n'
        '\t\t_catalog_write_failure_count += 1\n'
        '\t\t_stage_catalog_entry(\n'
        '\t\t\tworld_id,\n'
        '\t\t\tWorldCatalogPolicyScript.build_entry(world_id, payload, save_bytes),\n'
        '\t\t\tsave_bytes\n'
        '\t\t)\n',
        "stage failed save sidecar",
    )

    list_worlds = '''func list_worlds() -> Array:
\t_ensure_directory(WORLDS_DIR)
\tvar started_at := Time.get_ticks_usec()
\tvar result: Array = []
\tvar hit_count := 0
\tvar fallback_count := 0
\tvar repair_count := 0
\tvar deferred_recovery_count := 0
\tvar repair_budget_used := 0
\tvar deferred_catalog_rebuild_count := 0
\tvar catalog_rebuild_budget_used := 0
\tvar deferred_authoritative_read_count := 0
\tvar authoritative_read_budget_used := 0
\tvar stage_hit_count := 0
\tvar stage_invalidations_before := _catalog_stage_invalidation_count
\tvar avoided_world_bytes := 0
\tvar directory := DirAccess.open(WORLDS_DIR)
\tif directory == null:
\t\t_record_catalog_list(
\t\t\t0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
\t\t\tTime.get_ticks_usec() - started_at
\t\t)
\t\treturn result
\tvar world_ids: PackedStringArray = directory.get_directories()
\tworld_ids.sort()
\t_prune_staged_catalog_entries(world_ids)
\tfor raw_world_id: String in world_ids:
\t\tvar world_id := str(raw_world_id)
\t\tvar metadata: Dictionary = {}
\t\tvar catalog_read: Dictionary = _read_catalog_entry(world_id)
\t\tif not catalog_read.is_empty():
\t\t\t_staged_catalog_entries.erase(world_id)
\t\t\tvar entry: Dictionary = catalog_read.get("entry", {})
\t\t\tmetadata = WorldCatalogPolicyScript.metadata_for_list(entry, "catalog")
\t\t\thit_count += 1
\t\t\tavoided_world_bytes += int(catalog_read.get("world_bytes", 0))
\t\telse:
\t\t\tfallback_count += 1
\t\t\tvar staged_read: Dictionary = _read_staged_catalog_entry(world_id)
\t\t\tif not staged_read.is_empty():
\t\t\t\tstage_hit_count += 1
\t\t\t\tvar staged_entry: Dictionary = staged_read.get("entry", {})
\t\t\t\tvar staged_bytes := maxi(0, int(staged_read.get("world_bytes", 0)))
\t\t\t\tmetadata = WorldCatalogPolicyScript.metadata_for_list(
\t\t\t\t\tstaged_entry, "catalog_stage"
\t\t\t\t)
\t\t\t\tmetadata["catalog_staged"] = true
\t\t\t\tvar allow_staged_write := (
\t\t\t\t\tcatalog_rebuild_budget_used < MAX_CATALOG_REBUILDS_PER_LIST
\t\t\t\t)
\t\t\t\tif allow_staged_write:
\t\t\t\t\tcatalog_rebuild_budget_used += 1
\t\t\t\t\tif _write_catalog_value(world_id, staged_entry, staged_bytes):
\t\t\t\t\t\trepair_count += 1
\t\t\t\t\t\tmetadata["catalog_staged"] = false
\t\t\t\t\t\tmetadata["catalog_rebuild_deferred"] = false
\t\t\t\t\telse:
\t\t\t\t\t\t_catalog_write_failure_count += 1
\t\t\t\t\t\tdeferred_catalog_rebuild_count += 1
\t\t\t\t\t\tmetadata["catalog_rebuild_deferred"] = true
\t\t\t\telse:
\t\t\t\t\tdeferred_catalog_rebuild_count += 1
\t\t\t\t\tmetadata["catalog_rebuild_deferred"] = true
\t\t\t\tif not metadata.is_empty():
\t\t\t\t\tresult.append(metadata)
\t\t\t\tcontinue
\t\t\tvar can_retain_catalog := (
\t\t\t\tcatalog_rebuild_budget_used < MAX_CATALOG_REBUILDS_PER_LIST
\t\t\t\tor _staged_catalog_entries.size() < MAX_STAGED_CATALOG_ENTRIES
\t\t\t)
\t\t\tvar allow_authoritative_read := (
\t\t\t\tauthoritative_read_budget_used < MAX_AUTHORITATIVE_READS_PER_LIST
\t\t\t\tand can_retain_catalog
\t\t\t)
\t\t\tif not allow_authoritative_read:
\t\t\t\tdeferred_authoritative_read_count += 1
\t\t\t\tdeferred_catalog_rebuild_count += 1
\t\t\t\tmetadata = _deferred_world_metadata(world_id)
\t\t\t\tif not metadata.is_empty():
\t\t\t\t\tresult.append(metadata)
\t\t\t\tcontinue
\t\t\tauthoritative_read_budget_used += 1
\t\t\tvar allow_primary_repair := (
\t\t\t\trepair_budget_used < MAX_PRIMARY_REPAIRS_PER_LIST
\t\t\t)
\t\t\tvar world_read := _read_world_result(
\t\t\t\tworld_id, false, allow_primary_repair
\t\t\t)
\t\t\tif bool(world_read.get("repair_attempted", false)):
\t\t\t\trepair_budget_used += 1
\t\t\tvar source := str(world_read.get("source", "primary"))
\t\t\tvar primary_ready := bool(world_read.get("primary_ready", false))
\t\t\tif source != "primary" and not primary_ready:
\t\t\t\tdeferred_recovery_count += 1
\t\t\tvar payload: Dictionary = world_read.get("payload", {})
\t\t\tif payload.is_empty():
\t\t\t\tcontinue
\t\t\tvar world_bytes := maxi(
\t\t\t\t0, int(world_read.get("authoritative_bytes", 0))
\t\t\t)
\t\t\tif world_bytes <= 0:
\t\t\t\tworld_bytes = maxi(
\t\t\t\t\t0, int(world_read.get("candidate_bytes", 0))
\t\t\t\t)
\t\t\tvar entry := WorldCatalogPolicyScript.build_entry(
\t\t\t\tworld_id, payload, world_bytes
\t\t\t)
\t\t\tmetadata = WorldCatalogPolicyScript.metadata_for_list(
\t\t\t\tentry, "world_fallback"
\t\t\t)
\t\t\tmetadata["recovery_deferred"] = source != "primary" and not primary_ready
\t\t\tmetadata["catalog_staged"] = false
\t\t\tmetadata["catalog_rebuild_deferred"] = false
\t\t\tif primary_ready:
\t\t\t\tvar allow_catalog_rebuild := (
\t\t\t\t\tcatalog_rebuild_budget_used < MAX_CATALOG_REBUILDS_PER_LIST
\t\t\t\t)
\t\t\t\tif allow_catalog_rebuild:
\t\t\t\t\tcatalog_rebuild_budget_used += 1
\t\t\t\t\tif _write_catalog_value(world_id, entry, world_bytes):
\t\t\t\t\t\trepair_count += 1
\t\t\t\t\telse:
\t\t\t\t\t\t_catalog_write_failure_count += 1
\t\t\t\t\t\tmetadata["catalog_staged"] = _stage_catalog_entry(
\t\t\t\t\t\t\tworld_id, entry, world_bytes
\t\t\t\t\t\t)
\t\t\t\t\t\tmetadata["catalog_rebuild_deferred"] = true
\t\t\t\t\t\tdeferred_catalog_rebuild_count += 1
\t\t\t\telse:
\t\t\t\t\tmetadata["catalog_staged"] = _stage_catalog_entry(
\t\t\t\t\t\tworld_id, entry, world_bytes
\t\t\t\t\t)
\t\t\t\t\tmetadata["catalog_rebuild_deferred"] = true
\t\t\t\t\tdeferred_catalog_rebuild_count += 1
\t\tif not metadata.is_empty():
\t\t\tresult.append(metadata)
\tresult.sort_custom(
\t\tfunc(a: Dictionary, b: Dictionary) -> bool:
\t\t\treturn str(a.get("updated_at", "")) > str(b.get("updated_at", ""))
\t)
\tvar stage_invalidation_count := maxi(
\t\t0, _catalog_stage_invalidation_count - stage_invalidations_before
\t)
\t_record_catalog_list(
\t\tresult.size(),
\t\thit_count,
\t\tfallback_count,
\t\trepair_count,
\t\tdeferred_recovery_count,
\t\trepair_budget_used,
\t\tdeferred_catalog_rebuild_count,
\t\tcatalog_rebuild_budget_used,
\t\tdeferred_authoritative_read_count,
\t\tauthoritative_read_budget_used,
\t\tstage_hit_count,
\t\tstage_invalidation_count,
\t\tavoided_world_bytes,
\t\tTime.get_ticks_usec() - started_at
\t)
\treturn result'''
    text = replace_regex(
        text,
        r'func list_worlds\(\) -> Array:\n.*?\n\nfunc get_catalog_diagnostics\(\) -> Dictionary:',
        list_worlds + '\n\n\nfunc get_catalog_diagnostics() -> Dictionary:',
        "replace list_worlds",
    )

    diagnostics = '''func get_catalog_diagnostics() -> Dictionary:
\tvar hit_ratio := 0.0
\tif _last_catalog_world_count > 0:
\t\thit_ratio = (
\t\t\tfloat(_last_catalog_hit_count) / float(_last_catalog_world_count)
\t\t)
\treturn {
\t\t"catalog_version": WorldCatalogPolicyScript.CATALOG_VERSION,
\t\t"list_count": _catalog_list_count,
\t\t"hit_count": _catalog_hit_count,
\t\t"fallback_count": _catalog_fallback_count,
\t\t"repair_count": _catalog_repair_count,
\t\t"write_failure_count": _catalog_write_failure_count,
\t\t"last_world_count": _last_catalog_world_count,
\t\t"last_hit_count": _last_catalog_hit_count,
\t\t"last_fallback_count": _last_catalog_fallback_count,
\t\t"last_repair_count": _last_catalog_repair_count,
\t\t"last_avoided_world_bytes": _last_catalog_avoided_world_bytes,
\t\t"last_elapsed_usec": _last_catalog_elapsed_usec,
\t\t"last_elapsed_milliseconds": (
\t\t\tfloat(_last_catalog_elapsed_usec) / 1000.0
\t\t),
\t\t"last_hit_ratio": hit_ratio,
\t\t"primary_repair_budget": MAX_PRIMARY_REPAIRS_PER_LIST,
\t\t"deferred_recovery_count": _catalog_deferred_recovery_count,
\t\t"last_deferred_recovery_count": (
\t\t\t_last_catalog_deferred_recovery_count
\t\t),
\t\t"last_repair_budget_used": _last_catalog_repair_budget_used,
\t\t"catalog_rebuild_budget": MAX_CATALOG_REBUILDS_PER_LIST,
\t\t"deferred_catalog_rebuild_count": (
\t\t\t_catalog_deferred_rebuild_count
\t\t),
\t\t"last_deferred_catalog_rebuild_count": (
\t\t\t_last_catalog_deferred_rebuild_count
\t\t),
\t\t"last_catalog_rebuild_budget_used": (
\t\t\t_last_catalog_rebuild_budget_used
\t\t),
\t\t"authoritative_read_budget": MAX_AUTHORITATIVE_READS_PER_LIST,
\t\t"authoritative_read_count": _catalog_authoritative_read_count,
\t\t"deferred_authoritative_read_count": (
\t\t\t_catalog_deferred_authoritative_read_count
\t\t),
\t\t"last_deferred_authoritative_read_count": (
\t\t\t_last_catalog_deferred_authoritative_read_count
\t\t),
\t\t"last_authoritative_read_budget_used": (
\t\t\t_last_catalog_authoritative_read_budget_used
\t\t),
\t\t"catalog_stage_capacity": MAX_STAGED_CATALOG_ENTRIES,
\t\t"staged_catalog_entry_count": _staged_catalog_entries.size(),
\t\t"staged_catalog_peak_count": _catalog_stage_peak_count,
\t\t"stage_hit_count": _catalog_stage_hit_count,
\t\t"last_stage_hit_count": _last_catalog_stage_hit_count,
\t\t"stage_invalidation_count": _catalog_stage_invalidation_count,
\t\t"last_stage_invalidation_count": (
\t\t\t_last_catalog_stage_invalidation_count
\t\t),
\t}'''
    text = replace_regex(
        text,
        r'func get_catalog_diagnostics\(\) -> Dictionary:\n.*?\n\nfunc reset_catalog_diagnostics\(\) -> void:',
        diagnostics + '\n\n\nfunc reset_catalog_diagnostics() -> void:',
        "replace diagnostics",
    )

    reset = '''func reset_catalog_diagnostics() -> void:
\t_catalog_list_count = 0
\t_catalog_hit_count = 0
\t_catalog_fallback_count = 0
\t_catalog_repair_count = 0
\t_catalog_write_failure_count = 0
\t_last_catalog_world_count = 0
\t_last_catalog_hit_count = 0
\t_last_catalog_fallback_count = 0
\t_last_catalog_repair_count = 0
\t_last_catalog_avoided_world_bytes = 0
\t_last_catalog_elapsed_usec = 0
\t_catalog_deferred_recovery_count = 0
\t_last_catalog_deferred_recovery_count = 0
\t_last_catalog_repair_budget_used = 0
\t_catalog_deferred_rebuild_count = 0
\t_last_catalog_deferred_rebuild_count = 0
\t_last_catalog_rebuild_budget_used = 0
\t_catalog_deferred_authoritative_read_count = 0
\t_last_catalog_deferred_authoritative_read_count = 0
\t_last_catalog_authoritative_read_budget_used = 0
\t_catalog_authoritative_read_count = 0
\t_catalog_stage_hit_count = 0
\t_catalog_stage_invalidation_count = 0
\t_last_catalog_stage_hit_count = 0
\t_last_catalog_stage_invalidation_count = 0
\t_catalog_stage_peak_count = _staged_catalog_entries.size()'''
    text = replace_regex(
        text,
        r'func reset_catalog_diagnostics\(\) -> void:\n.*?\n\nfunc get_recovery_diagnostics\(\) -> Dictionary:',
        reset + '\n\n\nfunc get_recovery_diagnostics() -> Dictionary:',
        "replace reset diagnostics",
    )

    text = replace_once(
        text,
        '\tif error == OK:\n\t\tworld_deleted.emit(world_id)\n',
        '\tif error == OK:\n\t\t_staged_catalog_entries.erase(world_id)\n\t\tworld_deleted.emit(world_id)\n',
        "erase stage on delete",
    )
    text = replace_once(
        text,
        '\tif source != "primary":\n\t\t_record_recovery_result(world_id, source, result, world_path)\n',
        '\tif source != "primary":\n\t\t_invalidate_staged_catalog_entry(world_id)\n\t\t_record_recovery_result(world_id, source, result, world_path)\n',
        "invalidate stage on recovery",
    )

    catalog_helpers = '''func _write_catalog_entry(
\tworld_id: String,
\tpayload: Dictionary,
\tsave_bytes: int
) -> bool:
\tif not _is_safe_id(world_id):
\t\treturn false
\tvar safe_bytes := save_bytes
\tif safe_bytes <= 0:
\t\tsafe_bytes = _file_size(_world_path(world_id))
\tif safe_bytes <= 0:
\t\treturn false
\tvar entry := WorldCatalogPolicyScript.build_entry(world_id, payload, safe_bytes)
\treturn _write_catalog_value(world_id, entry, safe_bytes)


func _write_catalog_value(
\tworld_id: String,
\tentry: Dictionary,
\tsave_bytes: int
) -> bool:
\tif not _is_safe_id(world_id):
\t\treturn false
\tvar safe_bytes := maxi(0, save_bytes)
\tif safe_bytes <= 0:
\t\tsafe_bytes = _file_size(_world_path(world_id))
\tif safe_bytes <= 0:
\t\treturn false
\tvar normalized := WorldCatalogPolicyScript.normalize_entry(
\t\tentry, world_id, safe_bytes
\t)
\tif normalized.is_empty():
\t\treturn false
\tvar written := _store.write_dictionary(_catalog_path(world_id), normalized)
\tif written:
\t\t_staged_catalog_entries.erase(world_id)
\treturn written


func _read_staged_catalog_entry(world_id: String) -> Dictionary:
\tif not _is_safe_id(world_id) or not _staged_catalog_entries.has(world_id):
\t\treturn {}
\tvar raw_staged: Variant = _staged_catalog_entries.get(world_id, {})
\tif raw_staged is not Dictionary:
\t\t_invalidate_staged_catalog_entry(world_id)
\t\treturn {}
\tvar staged: Dictionary = raw_staged
\tvar world_path := _world_path(world_id)
\tvar world_bytes := _file_size(world_path)
\tvar modified_unix := (
\t\tint(FileAccess.get_modified_time(world_path))
\t\tif FileAccess.file_exists(world_path)
\t\telse 0
\t)
\tif (
\t\tworld_bytes <= 0
\t\tor world_bytes != int(staged.get("world_bytes", -1))
\t\tor modified_unix != int(staged.get("modified_unix", -1))
\t):
\t\t_invalidate_staged_catalog_entry(world_id)
\t\treturn {}
\tvar entry := WorldCatalogPolicyScript.normalize_entry(
\t\tstaged.get("entry", {}), world_id, world_bytes
\t)
\tif entry.is_empty():
\t\t_invalidate_staged_catalog_entry(world_id)
\t\treturn {}
\treturn {
\t\t"entry": entry,
\t\t"world_bytes": world_bytes,
\t}


func _stage_catalog_entry(
\tworld_id: String,
\tentry: Dictionary,
\tsave_bytes: int
) -> bool:
\tif not _is_safe_id(world_id):
\t\treturn false
\tvar world_path := _world_path(world_id)
\tvar safe_bytes := maxi(0, save_bytes)
\tif safe_bytes <= 0:
\t\tsafe_bytes = _file_size(world_path)
\tif safe_bytes <= 0 or not FileAccess.file_exists(world_path):
\t\treturn false
\tvar normalized := WorldCatalogPolicyScript.normalize_entry(
\t\tentry, world_id, safe_bytes
\t)
\tif normalized.is_empty():
\t\treturn false
\tif (
\t\tnot _staged_catalog_entries.has(world_id)
\t\tand _staged_catalog_entries.size() >= MAX_STAGED_CATALOG_ENTRIES
\t):
\t\treturn false
\t_staged_catalog_entries[world_id] = {
\t\t"entry": normalized,
\t\t"world_bytes": safe_bytes,
\t\t"modified_unix": int(FileAccess.get_modified_time(world_path)),
\t}
\t_catalog_stage_peak_count = maxi(
\t\t_catalog_stage_peak_count, _staged_catalog_entries.size()
\t)
\treturn true


func _invalidate_staged_catalog_entry(world_id: String) -> void:
\tif _staged_catalog_entries.erase(world_id):
\t\t_catalog_stage_invalidation_count += 1


func _prune_staged_catalog_entries(world_ids: PackedStringArray) -> void:
\tvar valid_world_ids: Dictionary = {}
\tfor world_id: String in world_ids:
\t\tvalid_world_ids[world_id] = true
\tfor raw_world_id: Variant in _staged_catalog_entries.keys():
\t\tvar world_id := str(raw_world_id)
\t\tif not valid_world_ids.has(world_id):
\t\t\t_invalidate_staged_catalog_entry(world_id)


func _record_catalog_list(
\tworld_count: int,
\thit_count: int,
\tfallback_count: int,
\trepair_count: int,
\tdeferred_recovery_count: int,
\trepair_budget_used: int,
\tdeferred_catalog_rebuild_count: int,
\tcatalog_rebuild_budget_used: int,
\tdeferred_authoritative_read_count: int,
\tauthoritative_read_budget_used: int,
\tstage_hit_count: int,
\tstage_invalidation_count: int,
\tavoided_world_bytes: int,
\telapsed_usec: int
) -> void:
\t_catalog_list_count += 1
\t_catalog_hit_count += hit_count
\t_catalog_fallback_count += fallback_count
\t_catalog_repair_count += repair_count
\t_catalog_deferred_recovery_count += deferred_recovery_count
\t_catalog_deferred_rebuild_count += deferred_catalog_rebuild_count
\t_catalog_deferred_authoritative_read_count += (
\t\tdeferred_authoritative_read_count
\t)
\t_catalog_authoritative_read_count += authoritative_read_budget_used
\t_catalog_stage_hit_count += stage_hit_count
\t_last_catalog_world_count = world_count
\t_last_catalog_hit_count = hit_count
\t_last_catalog_fallback_count = fallback_count
\t_last_catalog_repair_count = repair_count
\t_last_catalog_deferred_recovery_count = maxi(
\t\t0, deferred_recovery_count
\t)
\t_last_catalog_repair_budget_used = clampi(
\t\trepair_budget_used, 0, MAX_PRIMARY_REPAIRS_PER_LIST
\t)
\t_last_catalog_deferred_rebuild_count = maxi(
\t\t0, deferred_catalog_rebuild_count
\t)
\t_last_catalog_rebuild_budget_used = clampi(
\t\tcatalog_rebuild_budget_used, 0, MAX_CATALOG_REBUILDS_PER_LIST
\t)
\t_last_catalog_deferred_authoritative_read_count = maxi(
\t\t0, deferred_authoritative_read_count
\t)
\t_last_catalog_authoritative_read_budget_used = clampi(
\t\tauthoritative_read_budget_used, 0, MAX_AUTHORITATIVE_READS_PER_LIST
\t)
\t_last_catalog_stage_hit_count = maxi(0, stage_hit_count)
\t_last_catalog_stage_invalidation_count = maxi(0, stage_invalidation_count)
\t_last_catalog_avoided_world_bytes = maxi(0, avoided_world_bytes)
\t_last_catalog_elapsed_usec = maxi(0, elapsed_usec)'''
    text = replace_regex(
        text,
        r'func _write_catalog_entry\(\n.*?\n\nfunc _deferred_world_metadata\(world_id: String\) -> Dictionary:',
        catalog_helpers + '\n\n\nfunc _deferred_world_metadata(world_id: String) -> Dictionary:',
        "replace catalog helpers",
    )
    write(path, text)


def patch_save_browser() -> None:
    path = "src/ui/save_browser_panel.gd"
    text = read(path)
    text = replace_once(
        text,
        '\t\tvar metadata_pending := bool(\n\t\t\tmetadata.get("authoritative_read_deferred", false)\n\t\t)\n',
        '\t\tvar metadata_pending := bool(\n\t\t\tmetadata.get("authoritative_read_deferred", false)\n\t\t)\n'
        '\t\tvar catalog_staged := bool(metadata.get("catalog_staged", false))\n',
        "add staged row flag",
    )
    text = replace_once(
        text,
        '\t\t\tselect_button.text = "%s\\n%s  Seed %s  更新 %s  存档 %s" % [\n'
        '\t\t\t\tmetadata.get("name", "未命名"),\n'
        '\t\t\t\tmetadata.get("map_id", ""),\n'
        '\t\t\t\tmetadata.get("seed", 0),\n'
        '\t\t\t\tmetadata.get("updated_at", ""),\n'
        '\t\t\t\t_format_bytes(int(metadata.get("save_bytes", 0))),\n'
        '\t\t\t]\n',
        '\t\t\tselect_button.text = "%s\\n%s  Seed %s  更新 %s  存档 %s%s" % [\n'
        '\t\t\t\tmetadata.get("name", "未命名"),\n'
        '\t\t\t\tmetadata.get("map_id", ""),\n'
        '\t\t\t\tmetadata.get("seed", 0),\n'
        '\t\t\t\tmetadata.get("updated_at", ""),\n'
        '\t\t\t\t_format_bytes(int(metadata.get("save_bytes", 0))),\n'
        '\t\t\t\t" · 目录待写" if catalog_staged else "",\n'
        '\t\t\t]\n',
        "show staged row",
    )
    text = replace_once(
        text,
        '\tvar read_budget := maxi(\n\t\t0, int(diagnostics.get("authoritative_read_budget", 0))\n\t)\n',
        '\tvar read_budget := maxi(\n\t\t0, int(diagnostics.get("authoritative_read_budget", 0))\n\t)\n'
        '\tvar staged_catalogs := maxi(\n'
        '\t\t0, int(diagnostics.get("staged_catalog_entry_count", 0))\n'
        '\t)\n'
        '\tvar stage_capacity := maxi(\n'
        '\t\t0, int(diagnostics.get("catalog_stage_capacity", 0))\n'
        '\t)\n'
        '\tvar stage_hits := maxi(\n'
        '\t\t0, int(diagnostics.get("last_stage_hit_count", 0))\n'
        '\t)\n',
        "add browser stage diagnostics",
    )
    text = replace_once(
        text,
        '\tif deferred_catalogs > 0:\n\t\tstatus += " · 待建目录 %d（每次最多 %d）" % [\n\t\t\tdeferred_catalogs, catalog_budget\n\t\t]\n',
        '\tif deferred_catalogs > 0:\n\t\tstatus += " · 待建目录 %d（每次最多 %d）" % [\n\t\t\tdeferred_catalogs, catalog_budget\n\t\t]\n'
        '\tif staged_catalogs > 0:\n'
        '\t\tstatus += " · 暂存目录 %d/%d" % [staged_catalogs, stage_capacity]\n'
        '\tif stage_hits > 0:\n'
        '\t\tstatus += " · 暂存命中 %d" % stage_hits\n',
        "show browser stage status",
    )
    write(path, text)


def patch_health_policy() -> None:
    path = "src/diagnostics/runtime_health_report_policy.gd"
    text = read(path)
    catalog_row = '''static func _catalog_row(catalog: Dictionary) -> Dictionary:
\tvar severity := 0
\tvar issue := ""
\tvar write_failures := maxi(
\t\t0, int(catalog.get("write_failure_count", 0))
\t)
\tvar fallback_count := maxi(
\t\t0, int(catalog.get("last_fallback_count", 0))
\t)
\tvar repair_count := maxi(
\t\t0, int(catalog.get("last_repair_count", 0))
\t)
\tvar deferred_recovery := maxi(
\t\t0, int(catalog.get("last_deferred_recovery_count", 0))
\t)
\tvar primary_budget := maxi(
\t\t0, int(catalog.get("primary_repair_budget", 0))
\t)
\tvar deferred_reads := maxi(
\t\t0, int(catalog.get("last_deferred_authoritative_read_count", 0))
\t)
\tvar read_budget := maxi(
\t\t0, int(catalog.get("authoritative_read_budget", 0))
\t)
\tvar deferred_catalogs := maxi(
\t\t0, int(catalog.get("last_deferred_catalog_rebuild_count", 0))
\t)
\tvar catalog_budget := maxi(
\t\t0, int(catalog.get("catalog_rebuild_budget", 0))
\t)
\tvar staged_catalogs := maxi(
\t\t0, int(catalog.get("staged_catalog_entry_count", 0))
\t)
\tvar stage_capacity := maxi(
\t\t0, int(catalog.get("catalog_stage_capacity", 0))
\t)
\tvar stage_hits := maxi(
\t\t0, int(catalog.get("last_stage_hit_count", 0))
\t)
\tvar stage_invalidations := maxi(
\t\t0, int(catalog.get("last_stage_invalidation_count", 0))
\t)
\tif write_failures > 0:
\t\tseverity = 1
\t\tissue = "轻量世界目录写入失败累计 %d 次" % write_failures
\telif deferred_recovery > 0 or deferred_reads > 0 or deferred_catalogs > 0:
\t\tseverity = 1
\t\tissue = (
\t\t\t"主文件待修复 %d（预算 %d）· 待读世界 %d（权威读取预算 %d）· "
\t\t\t+ "暂存目录 %d/%d · 待建目录 %d（目录写入预算 %d）"
\t\t) % [
\t\t\tdeferred_recovery,
\t\t\tprimary_budget,
\t\t\tdeferred_reads,
\t\t\tread_budget,
\t\t\tstaged_catalogs,
\t\t\tstage_capacity,
\t\t\tdeferred_catalogs,
\t\t\tcatalog_budget,
\t\t]
\telif fallback_count > 0:
\t\tseverity = 1
\t\tissue = "世界目录本次回退 %d 个并自愈 %d 个" % [
\t\t\tfallback_count, repair_count
\t\t]
\treturn _informational_row(
\t\t"catalog",
\t\t"世界目录",
\t\t(
\t\t\t"命中 %d/%d · 回退 %d · 修复目录 %d · 待读 %d · "
\t\t\t+ "暂存目录 %d/%d · 暂存命中 %d · 失效 %d · 待建 %d · %.2f ms"
\t\t) % [
\t\t\tmaxi(0, int(catalog.get("last_hit_count", 0))),
\t\t\tmaxi(0, int(catalog.get("last_world_count", 0))),
\t\t\tfallback_count,
\t\t\trepair_count,
\t\t\tdeferred_reads,
\t\t\tstaged_catalogs,
\t\t\tstage_capacity,
\t\t\tstage_hits,
\t\t\tstage_invalidations,
\t\t\tdeferred_catalogs,
\t\t\tfloat(catalog.get("last_elapsed_milliseconds", 0.0)),
\t\t],
\t\tseverity,
\t\tissue
\t)'''
    text = replace_regex(
        text,
        r'static func _catalog_row\(catalog: Dictionary\) -> Dictionary:\n.*?\n\nstatic func _save_row\(save: Dictionary\) -> Dictionary:',
        catalog_row + '\n\n\nstatic func _save_row(save: Dictionary) -> Dictionary:',
        "replace health catalog row",
    )
    projection_insert = '''\t\t"last_authoritative_read_budget_used": maxi(
\t\t\t0, int(snapshot.get("last_authoritative_read_budget_used", 0))
\t\t),
\t\t"authoritative_read_count": maxi(
\t\t\t0, int(snapshot.get("authoritative_read_count", 0))
\t\t),
\t\t"catalog_stage_capacity": maxi(
\t\t\t0, int(snapshot.get("catalog_stage_capacity", 0))
\t\t),
\t\t"staged_catalog_entry_count": maxi(
\t\t\t0, int(snapshot.get("staged_catalog_entry_count", 0))
\t\t),
\t\t"staged_catalog_peak_count": maxi(
\t\t\t0, int(snapshot.get("staged_catalog_peak_count", 0))
\t\t),
\t\t"stage_hit_count": maxi(
\t\t\t0, int(snapshot.get("stage_hit_count", 0))
\t\t),
\t\t"last_stage_hit_count": maxi(
\t\t\t0, int(snapshot.get("last_stage_hit_count", 0))
\t\t),
\t\t"stage_invalidation_count": maxi(
\t\t\t0, int(snapshot.get("stage_invalidation_count", 0))
\t\t),
\t\t"last_stage_invalidation_count": maxi(
\t\t\t0, int(snapshot.get("last_stage_invalidation_count", 0))
\t\t),'''
    text = replace_once(
        text,
        '\t\t"last_authoritative_read_budget_used": maxi(\n'
        '\t\t\t0, int(snapshot.get("last_authoritative_read_budget_used", 0))\n'
        '\t\t),\n',
        projection_insert + '\n',
        "project stage diagnostics",
    )
    write(path, text)


def patch_scale_regression() -> None:
    path = "tests/qa/bounded_authoritative_read_regression.gd"
    text = read(path)
    text = replace_once(
        text,
        'const OVERRIDES_PER_WORLD := 16\n',
        'const OVERRIDES_PER_WORLD := 16\n'
        'const STAGE_CAPACITY := 64\n'
        'const LEGACY_FULL_READ_COUNT := 176\n',
        "add scale constants",
    )
    function = '''func _run_progressive_scans(save: Node) -> void:
\tsave.reset_catalog_diagnostics()
\tsave.reset_recovery_diagnostics()
\tvar expected_hits := [0, 16, 32, 48, 64, 80, 96]
\tvar expected_fallbacks := [96, 80, 64, 48, 32, 16, 0]
\tvar expected_reads := [32, 32, 32, 0, 0, 0, 0]
\tvar expected_deferred_reads := [64, 32, 0, 0, 0, 0, 0]
\tvar expected_rebuilds := [16, 16, 16, 16, 16, 16, 0]
\tvar expected_deferred_catalogs := [80, 64, 48, 32, 16, 0, 0]
\tvar expected_catalogs := [16, 32, 48, 64, 80, 96, 96]
\tvar expected_stage_hits := [0, 16, 32, 48, 32, 16, 0]
\tvar expected_staged_entries := [16, 32, 48, 32, 16, 0, 0]
\tfor scan_index in 7:
\t\tvar worlds: Array = save.list_worlds()
\t\tvar catalog: Dictionary = save.get_catalog_diagnostics()
\t\t_check(
\t\t\t_matching_count(worlds) == WORLD_COUNT,
\t\t\t"scan %d keeps all worlds visible before metadata is resolved"
\t\t\t% (scan_index + 1)
\t\t)
\t\t_check(
\t\t\tint(catalog.get("authoritative_read_budget", 0))
\t\t\t== AUTHORITATIVE_READ_BUDGET,
\t\t\t"scan %d exposes the fixed authoritative read budget" % (scan_index + 1)
\t\t)
\t\t_check(
\t\t\tint(catalog.get("catalog_stage_capacity", 0)) == STAGE_CAPACITY,
\t\t\t"scan %d exposes the fixed transient stage capacity" % (scan_index + 1)
\t\t)
\t\t_check(
\t\t\tint(catalog.get("last_authoritative_read_budget_used", -1))
\t\t\t== expected_reads[scan_index],
\t\t\t"scan %d uses the exact expected full-read slots" % (scan_index + 1)
\t\t)
\t\t_check(
\t\t\tint(catalog.get("last_deferred_authoritative_read_count", -1))
\t\t\t== expected_deferred_reads[scan_index],
\t\t\t"scan %d reports the exact deferred metadata count" % (scan_index + 1)
\t\t)
\t\t_check(
\t\t\t_pending_metadata_count(worlds) == expected_deferred_reads[scan_index],
\t\t\t"scan %d exposes placeholders for every deferred full read" % (scan_index + 1)
\t\t)
\t\t_check(
\t\t\tint(catalog.get("last_stage_hit_count", -1))
\t\t\t== expected_stage_hits[scan_index],
\t\t\t"scan %d reuses the exact expected staged catalog entries" % (scan_index + 1)
\t\t)
\t\t_check(
\t\t\tint(catalog.get("staged_catalog_entry_count", -1))
\t\t\t== expected_staged_entries[scan_index],
\t\t\t"scan %d retains the exact bounded staging backlog" % (scan_index + 1)
\t\t)
\t\t_check(
\t\t\tint(catalog.get("last_catalog_rebuild_budget_used", -1))
\t\t\t== expected_rebuilds[scan_index],
\t\t\t"scan %d preserves the independent sidecar write budget" % (scan_index + 1)
\t\t)
\t\t_check(
\t\t\tint(catalog.get("last_deferred_catalog_rebuild_count", -1))
\t\t\t== expected_deferred_catalogs[scan_index],
\t\t\t"scan %d reports every sidecar waiting behind reads or writes" % (scan_index + 1)
\t\t)
\t\t_check(
\t\t\tint(catalog.get("last_hit_count", -1)) == expected_hits[scan_index]
\t\t\tand int(catalog.get("last_fallback_count", -1))
\t\t\t== expected_fallbacks[scan_index],
\t\t\t"scan %d converges through the expected hit and miss counts"
\t\t\t% (scan_index + 1)
\t\t)
\t\t_check(
\t\t\tint(catalog.get("last_authoritative_read_budget_used", 0))
\t\t\t<= AUTHORITATIVE_READ_BUDGET,
\t\t\t"scan %d never exceeds the authoritative JSON read budget"
\t\t\t% (scan_index + 1)
\t\t)
\t\t_check(
\t\t\tint(catalog.get("staged_catalog_entry_count", 0)) <= STAGE_CAPACITY,
\t\t\t"scan %d never exceeds the transient catalog stage capacity"
\t\t\t% (scan_index + 1)
\t\t)
\t\t_check(
\t\t\tint(catalog.get("last_repair_budget_used", -1)) == 0
\t\t\tand int(catalog.get("last_deferred_recovery_count", -1)) == 0,
\t\t\t"scan %d never consumes primary repair capacity" % (scan_index + 1)
\t\t)
\t\t_check(
\t\t\t_catalog_count() == expected_catalogs[scan_index],
\t\t\t"scan %d creates only the expected number of sidecars" % (scan_index + 1)
\t\t)
\t\tif scan_index == 0:
\t\t\tvar report: Dictionary = HealthPolicyScript.build({"catalog": catalog})
\t\t\t_check(
\t\t\t\tstr(report.get("status", "")) == "warning"
\t\t\t\tand int(report.get("catalog", {}).get(
\t\t\t\t\t"last_deferred_authoritative_read_count", -1
\t\t\t\t)) == 64
\t\t\t\tand int(report.get("catalog", {}).get(
\t\t\t\t\t"staged_catalog_entry_count", -1
\t\t\t\t)) == 16,
\t\t\t\t"F3 projection preserves transient catalog staging evidence"
\t\t\t)
\tvar final_catalog: Dictionary = save.get_catalog_diagnostics()
\tvar actual_reads := int(final_catalog.get("authoritative_read_count", -1))
\t_check(
\t\tactual_reads == WORLD_COUNT
\t\tand LEGACY_FULL_READ_COUNT - actual_reads == 80,
\t\t"transient staging eliminates eighty redundant full reads"
\t)
\t_check(
\t\tint(final_catalog.get("staged_catalog_peak_count", -1)) == 48
\t\tand int(final_catalog.get("staged_catalog_peak_count", 0)) <= STAGE_CAPACITY,
\t\t"stage cache peak remains inside the fixed sixty-four entry capacity"
\t)
\t_check(
\t\tint(final_catalog.get("stage_hit_count", -1)) == 144
\t\tand int(final_catalog.get("stage_invalidation_count", -1)) == 0,
\t\t"unchanged primaries reuse staged entries without invalidation"
\t)
\tvar recovery: Dictionary = save.get_recovery_diagnostics()
\t_check(
\t\tint(recovery.get("recovery_count", 0)) == 0
\t\tand int(recovery.get("repair_attempt_count", 0)) == 0,
\t\t"healthy primaries never enter backup recovery"
\t)
\t_check(
\t\tint(final_catalog.get("write_failure_count", 0)) == 0,
\t\t"all bounded sidecar writes succeed"
\t)
\tfor world_id: String in world_ids:
\t\t_check(
\t\t\t_read_text(_world_path(world_id))
\t\t\t== str(primary_text_by_world.get(world_id, "")),
\t\t\t"deferred metadata reads never mutate authoritative primary %s" % world_id
\t\t)
\t\t_check(
\t\t\tFileAccess.file_exists(_catalog_path(world_id)),
\t\t\t"final sidecar exists for %s" % world_id
\t\t)'''
    text = replace_regex(
        text,
        r'func _run_progressive_scans\(save: Node\) -> void:\n.*?\n\nfunc _overrides\(index: int\) -> Dictionary:',
        function + '\n\n\nfunc _overrides(index: int) -> Dictionary:',
        "replace scale regression",
    )
    write(path, text)


def patch_desktop_acceptance() -> None:
    path = "tests/qa/bounded_authoritative_read_desktop_acceptance.gd"
    text = read(path)
    run_function = '''func _run() -> void:
\tcapture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
\thealth_capture_path = capture_path.get_basename() + "-health.png"
\treport_path = capture_path.get_basename() + ".json"
\troot.size = Vector2i(1280, 720)
\troot.content_scale_size = Vector2i(1280, 720)
\tvar game = GameScene.instantiate()
\troot.add_child(game)
\tfor _frame in 8:
\t\tawait process_frame
\tvar hub: Node = game.get("service_hub")
\tvar save: Node = hub.get("save_service") if hub != null else null
\tvar main_menu: Control = hub.get("main_menu") if hub != null else null
\tvar diagnostics: Node = game.get("runtime_diagnostics")
\t_check(
\t\tsave != null and main_menu != null and diagnostics != null,
\t\t"production game exposes save browser and runtime diagnostics"
\t)
\tif save == null or main_menu == null or diagnostics == null:
\t\tawait _finish(game, save)
\t\treturn
\tawait _create_fixture(save)
\tvar save_panel: Control = main_menu.get("_save_panel")
\tvar status_label: Label = save_panel.get("_status") if save_panel != null else null
\tvar list_node: VBoxContainer = save_panel.get("_list") if save_panel != null else null
\t_check(
\t\tsave_panel != null and status_label != null and list_node != null,
\t\t"production save browser exposes status and world rows"
\t)
\tif save_panel == null or status_label == null or list_node == null:
\t\tawait _finish(game, save)
\t\treturn

\tsave.reset_catalog_diagnostics()
\tsave.reset_recovery_diagnostics()
\tsave_panel.call("refresh")
\tmain_menu.call("_show_panel", save_panel)
\tfor _frame in 5:
\t\tawait process_frame
\tvar first: Dictionary = save.get_catalog_diagnostics()
\t_check(
\t\t_visible_fixture_rows(list_node) == WORLD_COUNT,
\t\t"first desktop refresh renders every world before full metadata resolution"
\t)
\t_check(
\t\t_pending_fixture_rows(list_node) == 8,
\t\t"first desktop refresh renders eight explicit metadata placeholders"
\t)
\t_check(
\t\tint(first.get("last_authoritative_read_budget_used", -1))
\t\t== AUTHORITATIVE_READ_BUDGET,
\t\t"first desktop refresh uses exactly thirty-two authoritative reads"
\t)
\t_check(
\t\tint(first.get("last_deferred_authoritative_read_count", -1)) == 8,
\t\t"first desktop refresh defers the remaining eight metadata reads"
\t)
\t_check(
\t\tint(first.get("last_catalog_rebuild_budget_used", -1))
\t\t== CATALOG_REBUILD_BUDGET,
\t\t"first desktop refresh independently writes sixteen sidecars"
\t)
\t_check(
\t\tint(first.get("staged_catalog_entry_count", -1)) == 16
\t\tand int(first.get("staged_catalog_peak_count", -1)) == 16,
\t\t"first desktop refresh stages sixteen exact catalog entries"
\t)
\t_check(
\t\tint(first.get("last_repair_budget_used", -1)) == 0,
\t\t"catalog-only metadata loading does not consume primary repair slots"
\t)
\t_check(
\t\tstatus_label.text.contains("待读世界 8")
\t\tand status_label.text.contains("每次最多 32"),
\t\t"save browser visibly explains deferred authoritative metadata reads"
\t)
\t_check(
\t\tstatus_label.text.contains("暂存目录 16/64"),
\t\t"save browser visibly reports the transient catalog stage"
\t)
\tawait _capture(capture_path, "save browser placeholder screenshot is saved")

\tvar warning_snapshot: Dictionary = diagnostics.call("sample_now")
\tvar operations: Dictionary = warning_snapshot.get("operations", {})
\tvar projected_catalog: Dictionary = operations.get("catalog", {})
\t_check(
\t\tint(projected_catalog.get("last_deferred_authoritative_read_count", -1)) == 8
\t\tand int(projected_catalog.get("authoritative_read_budget", -1))
\t\t== AUTHORITATIVE_READ_BUDGET,
\t\t"runtime health keeps the bounded authoritative-read backlog"
\t)
\t_check(
\t\tint(projected_catalog.get("staged_catalog_entry_count", -1)) == 16
\t\tand int(projected_catalog.get("catalog_stage_capacity", -1)) == 64,
\t\t"runtime health keeps the bounded transient staging backlog"
\t)
\t_check(
\t\tstr(operations.get("primary_bottleneck", {}).get("id", "")) == "catalog",
\t\t"deferred authoritative reads become the deterministic health bottleneck"
\t)
\tvar overlay := diagnostics.get("overlay") as CanvasLayer
\t_check(overlay != null, "production diagnostics exposes the F3 overlay")
\tawait _press_f3()
\t_check(
\t\toverlay != null and bool(overlay.call("is_overlay_visible")),
\t\t"real F3 input opens the bounded authoritative-read view"
\t)
\tvar display := str(overlay.call("get_display_text")) if overlay != null else ""
\t_check(
\t\tdisplay.contains("待读世界 8") and display.contains("权威读取预算 32"),
\t\t"F3 visibly reports deferred worlds and the full-read budget"
\t)
\t_check(
\t\tdisplay.contains("暂存目录 16/64") and display.contains("暂存命中 0"),
\t\t"F3 visibly reports staged entries and stage hits"
\t)
\tawait _capture(health_capture_path, "F3 authoritative-read health screenshot is saved")
\tawait _press_f3()

\tsave_panel.call("refresh")
\tfor _frame in 4:
\t\tawait process_frame
\tvar second: Dictionary = save.get_catalog_diagnostics()
\t_check(
\t\tint(second.get("last_hit_count", -1)) == 16
\t\tand int(second.get("last_deferred_authoritative_read_count", -1)) == 0,
\t\t"second refresh resolves every remaining world metadata payload"
\t)
\t_check(
\t\t_pending_fixture_rows(list_node) == 0,
\t\t"second desktop refresh replaces all placeholders with exact metadata"
\t)
\t_check(
\t\tint(second.get("last_authoritative_read_budget_used", -1)) == 8
\t\tand int(second.get("last_stage_hit_count", -1)) == 16,
\t\t"second refresh reuses sixteen staged entries and reads only eight new worlds"
\t)
\t_check(
\t\tint(second.get("last_catalog_rebuild_budget_used", -1)) == 16
\t\tand int(second.get("last_deferred_catalog_rebuild_count", -1)) == 8,
\t\t"second refresh preserves the independent sidecar budget"
\t)
\t_check(
\t\tint(second.get("staged_catalog_entry_count", -1)) == 8,
\t\t"second refresh stages only the eight newly read entries waiting for writes"
\t)

\tsave_panel.call("refresh")
\tfor _frame in 4:
\t\tawait process_frame
\tvar third: Dictionary = save.get_catalog_diagnostics()
\t_check(
\t\tint(third.get("last_hit_count", -1)) == 32
\t\tand int(third.get("last_authoritative_read_budget_used", -1)) == 0
\t\tand int(third.get("last_stage_hit_count", -1)) == 8
\t\tand int(third.get("last_catalog_rebuild_budget_used", -1)) == 8
\t\tand int(third.get("last_deferred_catalog_rebuild_count", -1)) == 0,
\t\t"third refresh flushes eight staged entries without another full read"
\t)
\t_check(
\t\tint(third.get("staged_catalog_entry_count", -1)) == 0,
\t\t"third refresh empties the transient catalog stage"
\t)

\tsave_panel.call("refresh")
\tfor _frame in 4:
\t\tawait process_frame
\tvar steady: Dictionary = save.get_catalog_diagnostics()
\t_check(
\t\tint(steady.get("last_hit_count", -1)) == WORLD_COUNT
\t\tand int(steady.get("last_fallback_count", -1)) == 0,
\t\t"steady desktop refresh is a pure sidecar hit"
\t)
\t_check(
\t\tint(steady.get("last_authoritative_read_budget_used", -1)) == 0
\t\tand int(steady.get("last_catalog_rebuild_budget_used", -1)) == 0
\t\tand int(steady.get("staged_catalog_entry_count", -1)) == 0,
\t\t"steady desktop refresh performs zero full reads and zero sidecar writes"
\t)
\t_check(
\t\tint(steady.get("authoritative_read_count", -1)) == WORLD_COUNT
\t\tand int(steady.get("stage_hit_count", -1)) == 24,
\t\t"desktop convergence parses every authoritative world exactly once"
\t)
\t_check(
\t\t_visible_fixture_rows(list_node) == WORLD_COUNT,
\t\t"all world rows remain visible after complete convergence"
\t)
\tvar recovery: Dictionary = save.get_recovery_diagnostics()
\t_check(
\t\tint(recovery.get("recovery_count", 0)) == 0,
\t\t"desktop authoritative-read convergence never enters backup recovery"
\t)
\tfor world_id: String in world_ids:
\t\t_check(
\t\t\t_read_text(_world_path(world_id))
\t\t\t== str(primary_text_by_world.get(world_id, "")),
\t\t\t"desktop metadata convergence preserves primary %s" % world_id
\t\t)

\treport = {
\t\t"schema_version": 2,
\t\t"world_count": WORLD_COUNT,
\t\t"authoritative_read_budget": AUTHORITATIVE_READ_BUDGET,
\t\t"catalog_rebuild_budget": CATALOG_REBUILD_BUDGET,
\t\t"catalog_stage_capacity": 64,
\t\t"first_scan": first,
\t\t"second_scan": second,
\t\t"third_scan": third,
\t\t"steady_scan": steady,
\t\t"warning_operations": operations,
\t\t"recovery": recovery,
\t}
\t_write_report()
\tawait _finish(game, save)'''
    text = replace_regex(
        text,
        r'func _run\(\) -> void:\n.*?\n\nfunc _create_fixture\(save: Node\) -> void:',
        run_function + '\n\n\nfunc _create_fixture(save: Node) -> void:',
        "replace desktop run",
    )
    write(path, text)


def main() -> None:
    patch_save_service()
    patch_save_browser()
    patch_health_policy()
    patch_scale_regression()
    patch_desktop_acceptance()


if __name__ == "__main__":
    main()
