class_name UiPanelAnimator
extends RefCounted

# Lightweight open animation for overlay panels: quick fade-in.
# (No scale transform: scaling needs a center pivot, and reading panel.size
# before layout settles yields bogus pivots that shift the measured rect.)

const DURATION := 0.14


static func open(panel: Control) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	panel.visible = true
	panel.modulate.a = 0.0
	var tween := panel.create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, DURATION)
