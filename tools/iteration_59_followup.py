from __future__ import annotations

from pathlib import Path

TARGET = Path("src/save/protected_save_service.gd")
OLD = '''\tif not bool(entry.get("valid", false)):
\t\treturn _trash_failure(
\t\t\t"restore", trash_id, str(entry.get("reason", "trash_missing_or_invalid"))
\t\t)
'''
NEW = '''\tif not bool(entry.get("valid", false)):
\t\t_restore_integrity_check_count += 1
\t\t_restore_integrity_failure_count += 1
\t\t_last_restore_source = str(
\t\t\tentry.get("integrity_source", "missing_or_invalid")
\t\t).left(32)
\t\t_last_restore_integrity_reason = str(
\t\t\tentry.get("reason", "world_payload_unrecoverable")
\t\t).left(64)
\t\treturn _trash_failure(
\t\t\t"restore", trash_id, str(entry.get("reason", "trash_missing_or_invalid"))
\t\t)
'''

text = TARGET.read_text(encoding="utf-8")
count = text.count(OLD)
if count != 1:
    raise SystemExit(f"expected exactly one diagnostic branch, found {count}")
TARGET.write_text(text.replace(OLD, NEW), encoding="utf-8", newline="\n")
Path(__file__).unlink()
