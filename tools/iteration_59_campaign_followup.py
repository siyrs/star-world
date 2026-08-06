from __future__ import annotations

from pathlib import Path

TARGET = Path("tests/qa/release_integrity_continuous_campaign_regression.gd")

PARSE_OLD = '''\tvar rewarded := await _wait_until(
\t\tfunc() -> bool:
\t\t\treturn int(reward_service.get_snapshot().get("reward_grant_count", 0))
\t\t\t== cycle + 1,
\t\t2000
\t)
'''
PARSE_NEW = '''\tvar reward_ready := func() -> bool:
\t\treturn int(
\t\t\treward_service.get_snapshot().get("reward_grant_count", 0)
\t\t) == cycle + 1
\tvar rewarded := await _wait_until(reward_ready, 2000)
'''

CONNECTION_OLD = '''\t_check(
\t\tConnectionPolicyScript.resolve_mask(
\t\t\tblock_id, _connection_neighbors(world, global_position)
\t\t) & ConnectionPolicyScript.EAST == 0,
\t\t"stream cycle %02d rebuild removes the stale cross-chunk connection"
\t\t% (cycle + 1)
\t)
'''
CONNECTION_NEW = '''\tvar rebuilt_neighbors := _connection_neighbors(world, global_position)
\tvar rebuilt_mask := ConnectionPolicyScript.resolve_mask(
\t\tblock_id, rebuilt_neighbors
\t)
\t_check(
\t\tnot ConnectionPolicyScript.connected_face(
\t\t\tblock_id,
\t\t\trebuilt_mask,
\t\t\t0,
\t\t\tstr(rebuilt_neighbors.get("east", "air"))
\t\t),
\t\t"stream cycle %02d rebuild removes the stale cross-chunk connection"
\t\t% (cycle + 1)
\t)
'''

text = TARGET.read_text(encoding="utf-8")
parse_count = text.count(PARSE_OLD)
connection_count = text.count(CONNECTION_OLD)
if parse_count != 1:
    raise SystemExit(f"expected exactly one campaign wait block, found {parse_count}")
if connection_count != 1:
    raise SystemExit(
        f"expected exactly one stale-connection assertion, found {connection_count}"
    )
text = text.replace(PARSE_OLD, PARSE_NEW)
text = text.replace(CONNECTION_OLD, CONNECTION_NEW)
TARGET.write_text(text, encoding="utf-8", newline="\n")
Path(__file__).unlink()
