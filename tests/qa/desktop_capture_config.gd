class_name DesktopCaptureConfig
extends RefCounted

const ARGUMENT_PREFIX := "--capture-output="


static func resolve(arguments: PackedStringArray, fallback_path: String) -> String:
	for argument in arguments:
		if not argument.begins_with(ARGUMENT_PREFIX):
			continue
		var configured := argument.trim_prefix(ARGUMENT_PREFIX).strip_edges()
		if configured.is_empty():
			break
		return (
			configured
			if configured.is_absolute_path()
			else ProjectSettings.globalize_path(configured)
		)
	return ProjectSettings.globalize_path(fallback_path)
