from __future__ import annotations

from pathlib import Path

TARGET = Path("tests/qa/release_integrity_continuous_campaign_regression.gd")
OLD = '''\tvar rewarded := await _wait_until(
\t\tfunc() -> bool:
\t\t\treturn int(reward_service.get_snapshot().get("reward_grant_count", 0))
\t\t\t== cycle + 1,
\t\t2000
\t)
'''
NEW = '''\tvar reward_ready := func() -> bool:
\t\treturn int(
\t\t\treward_service.get_snapshot().get("reward_grant_count", 0)
\t\t) == cycle + 1
\tvar rewarded := await _wait_until(reward_ready, 2000)
'''

text = TARGET.read_text(encoding="utf-8")
count = text.count(OLD)
if count != 1:
    raise SystemExit(f"expected exactly one campaign wait block, found {count}")
TARGET.write_text(text.replace(OLD, NEW), encoding="utf-8", newline="\n")
Path(__file__).unlink()
