from __future__ import annotations

import base64
import zlib
from pathlib import Path

PARTS_DIR = Path("tools/iteration_59_payload")
encoded = "".join(
    path.read_text(encoding="ascii").strip()
    for path in sorted(PARTS_DIR.glob("part*.txt"))
)
source = zlib.decompress(base64.b64decode(encoded)).decode("utf-8")
exec(compile(source, "tools/iteration_59_apply.py", "exec"))
