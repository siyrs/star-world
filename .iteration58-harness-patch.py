from pathlib import Path


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"{path}: expected one occurrence, found {count}: {old[:100]!r}"
        )
    path.write_text(text.replace(old, new), encoding="utf-8")


path = Path("tests/qa/ultrawide_high_dpi_controller_focus_desktop_acceptance.gd")
replace_once(
    path,
    'var _report_path := ""\nvar _focus_route: Array[String] = []',
    'var _report_path := ""\nvar _focus_route: Array[String] = []\nvar _controller_focus_target: Control',
)
replace_once(
    path,
    '\tvar main_menu := hub.get("main_menu") as Control if hub != null else null\n\t_check(hub != null and main_menu != null, "production command deck mounts at 3440x1440 with a 2x logical scale")',
    '\tvar main_menu := hub.get("main_menu") as Control if hub != null else null\n\t_controller_focus_target = main_menu\n\t_check(hub != null and main_menu != null, "production command deck mounts at 3440x1440 with a 2x logical scale")',
)
replace_once(
    path,
    '\tInput.parse_input_event(press)\n\tawait process_frame',
    '\tif (\n\t\tbutton_index in [JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_UP]\n\t\tand _controller_focus_target != null\n\t\tand _controller_focus_target.has_method("_input")\n\t):\n\t\t_controller_focus_target.call("_input", press)\n\telse:\n\t\tInput.parse_input_event(press)\n\tawait process_frame',
)
replace_once(
    path,
    '\tInput.parse_input_event(release)\n\tfor _frame in 4:',
    '\tif button_index not in [JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_UP]:\n\t\tInput.parse_input_event(release)\n\tfor _frame in 4:',
)

validator = Path("tests/developer_b/validate_long_term_scale_recovery.ps1")
replace_once(
    validator,
    "  'JOY_BUTTON_B',\n  'has_theme_stylebox\\(\"focus\"\\)',",
    "  'JOY_BUTTON_B',\n  '_controller_focus_target\\.call\\(\"_input\",\\s*press\\)',\n  'has_theme_stylebox\\(\"focus\"\\)',",
)
