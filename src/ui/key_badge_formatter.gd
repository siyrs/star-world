class_name KeyBadgeFormatter
extends RefCounted

# Converts key tokens like [鼠标左键], W, A, S, D, F1 into rounded
# keycap badges via RichTextLabel bbcode background spans.

const BADGE_BG := "#24384C"
const BADGE_FG := "#D9ECFA"

const KEY_TOKENS: Array[String] = [
	"[按住鼠标左键]",
	"[鼠标左键]",
	"[鼠标右键]",
	"[按住鼠标右键]",
	"[空格]",
	"[Shift]",
	"[E]",
	"[F]",
	"[J]",
	"[I]",
	"[Tab]",
	"[Esc]",
]


static func badge(token: String) -> String:
	return "[bgcolor=%s][color=%s] %s [/color][/bgcolor]" % [BADGE_BG, BADGE_FG, token]


static func format(text: String) -> String:
	var result := text
	for token in KEY_TOKENS:
		result = result.replace(token, badge(token.trim_prefix("[").trim_suffix("]")))
	return _format_letter_keys(result)


static func _format_letter_keys(text: String) -> String:
	# Bare single-letter keys (W A S D F1 ...) separated by spaces, as in the
	# tutorial hint line, also deserve keycaps.
	var parts := text.split(" ")
	var rebuilt: Array[String] = []
	for part in parts:
		if _is_key_token(part):
			rebuilt.append(badge(part))
		else:
			rebuilt.append(part)
	return " ".join(rebuilt)


static func _is_key_token(part: String) -> bool:
	if part.length() == 1 and part.to_upper() in "WASDEFJQZXCVBNM":
		return true
	if part.length() == 2 and part.begins_with("F") and part.substr(1).is_valid_int():
		return true
	return false
