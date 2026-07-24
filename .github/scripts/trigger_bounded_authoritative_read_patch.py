from pathlib import Path
import textwrap

workflow_path = Path('.github/workflows/apply-bounded-authoritative-read-patch.yml')
text = workflow_path.read_text(encoding='utf-8')
marker = "          python - <<'PY'\n"
tail = "\n          PY\n"
if marker not in text or tail not in text:
    raise RuntimeError('PATCH_ERROR: unable to extract committed patch script')
script = text.split(marker, 1)[1].split(tail, 1)[0]
# The committed YAML contains PowerShell paths inside Python string literals.
# Double the only escape sequence that Python would reinterpret as vertical-tab.
script = script.replace('\\validate_', '\\\\validate_')
try:
    exec(compile(textwrap.dedent(script), str(workflow_path), 'exec'))
except Exception as error:
    diagnostic = Path('build/bounded-authoritative-read-patch-error.txt')
    diagnostic.parent.mkdir(parents=True, exist_ok=True)
    diagnostic.write_text(f'PATCH_ERROR: {error}\n', encoding='utf-8')
    raise RuntimeError(f'PATCH_ERROR: {error}') from error
Path('.github/workflows/trigger-bounded-authoritative-read-patch.yml').unlink()
Path('.github/scripts/trigger_bounded_authoritative_read_patch.py').unlink()
