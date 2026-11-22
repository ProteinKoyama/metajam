extends ColorRect

signal evaluation_confirmed(score: int, ratings: Dictionary)

const MAX_SCORE_TEXT := "9223372036854775807"
const STAR_YELLOW := Color("d48e00")
const STAR_INK := Color("262626")

var ratings: Dictionary = {}
var accepted_score_text: String = ""

@onready var rating_rows: Array[Control] = [
	$Form/Illustration, $Form/Sound, $Form/Scenario, $Form/Fun
]
@onready var score_input: LineEdit = $Form/Score
@onready var status: Label = $Form/Status
@onready var confirm: Button = $Form/Confirm


func _ready() -> void:
	for row in rating_rows:
		for value in range(1, 6):
			var star: Button = row.get_node("Star%d" % value)
			star.pressed.connect(_set_rating.bind(row, value))
		_set_rating(row, 1)
	confirm.pressed.connect(_confirm_rating)
	score_input.text_changed.connect(_on_score_changed)
	score_input.text_submitted.connect(_on_score_submitted)


func _set_rating(row: Control, value: int) -> void:
	ratings[row.name] = value
	for index in range(1, 6):
		var star: Button = row.get_node("Star%d" % index)
		var selected: bool = index <= value
		star.text = "★" if selected else "☆"
		var color: Color = STAR_YELLOW if selected else STAR_INK
		star.add_theme_color_override("font_color", color)
		star.add_theme_color_override("font_hover_color", color)
		star.add_theme_color_override("font_pressed_color", color)


func _on_score_changed(value: String) -> void:
	var caret: int = score_input.caret_column
	var digits: String = ""
	var filtered_caret: int = 0
	for index in range(value.length()):
		var codepoint: int = value.unicode_at(index)
		if codepoint >= 0xFF10 and codepoint <= 0xFF19:
			codepoint -= 0xFF10 - 0x30
		if codepoint >= 0x30 and codepoint <= 0x39:
			digits += String.chr(codepoint)
			if index < caret:
				filtered_caret += 1

	# Compare the digits before converting so an overflowing value cannot be parsed.
	if digits.length() > MAX_SCORE_TEXT.length() or (
		digits.length() == MAX_SCORE_TEXT.length() and digits > MAX_SCORE_TEXT
	):
		score_input.text = accepted_score_text
		score_input.caret_column = mini(caret, accepted_score_text.length())
		status.text = "入力できる最大の点数は 9,223,372,036,854,775,807 です。"
		return

	accepted_score_text = digits
	if digits != value:
		score_input.text = digits
		score_input.caret_column = filtered_caret
	status.text = ""


func _on_score_submitted(_value: String) -> void:
	_confirm_rating()


func _confirm_rating() -> void:
	if accepted_score_text.is_empty():
		status.text = "点数を入力してください。"
		return

	var score: int = accepted_score_text.to_int()
	status.text = "評価を受け付けました。"
	evaluation_confirmed.emit(score, ratings.duplicate())
