class_name UiPanelAnimator
extends RefCounted

# Restrained entrance motion that never changes measured layout rectangles.
# Scale and translation are intentionally avoided because panel sizes settle
# after containers lay out and tests treat the final rect as a product contract.
const DURATION := 0.18


static func open(panel: Control) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	panel.visible = true
	panel.modulate.a = 0.0
	var tween := panel.create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "modulate:a", 1.0, DURATION)
