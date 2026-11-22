extends ColorRect

signal evaluation_confirmed(score: int)

const MAX_SCORE_TEXT := "9223372036854775807"
const MIN_SCORE_MAGNITUDE_TEXT := "9223372036854775808"
const MIN_SCORE: int = -9223372036854775807 - 1
const NARRATOR_PATH := "res://narrator.json"
const SUBTITLE_SECONDS: float = 4.0
var score_digits: String = ""
var score_negative: bool = false
var rating_confirmed: bool = false
var narrator_lines: Dictionary = {}

@onready var score_value: Label = $Form/Score/Value
@onready var keypad: GridContainer = $Keypad
@onready var minus_key: Button = $Minus
@onready var status: Label = $Form/Status
@onready var confirm: Button = $Confirm
@onready var narrator: Panel = $Narrator
@onready var narrator_line: Label = $Narrator/Line
@onready var ending_blackout: ColorRect = $EndingBlackout


func _ready() -> void:
	for child in keypad.get_children():
		if child is Button:
			child.pressed.connect(_on_key_pressed.bind(child))
	minus_key.pressed.connect(_on_key_pressed.bind(minus_key))
	confirm.pressed.connect(_confirm_rating)
	var lines: Variant = JSON.parse_string(FileAccess.get_file_as_string(NARRATOR_PATH))
	if lines is Dictionary:
		narrator_lines = lines
	_play_narrator_lines("evaluation_request")


func _play_narrator_lines(key: String) -> void:
	var lines: Variant = narrator_lines.get(key)
	if not lines is Array:
		return

	for line in lines:
		if line is String and not line.is_empty():
			narrator_line.text = line
			narrator.show()
			await get_tree().create_timer(SUBTITLE_SECONDS).timeout
			if key == "evaluation_request" and rating_confirmed:
				return
	narrator.hide()


func _on_key_pressed(key: Button) -> void:
	if rating_confirmed:
		return
	match key.name:
		&"Clear":
			score_digits = ""
			score_negative = false
		&"Erase":
			if score_digits.is_empty():
				score_negative = false
			else:
				score_digits = score_digits.left(-1)
		&"Minus":
			if score_negative and score_digits == MIN_SCORE_MAGNITUDE_TEXT:
				status.text = "入力できる最大の点数は 9,223,372,036,854,775,807 です。"
				return
			score_negative = not score_negative
		_:
			var candidate: String = key.text if score_digits == "0" else score_digits + key.text
			var limit: String = MIN_SCORE_MAGNITUDE_TEXT if score_negative else MAX_SCORE_TEXT
			# Compare before conversion to avoid overflowing the integer.
			if candidate.length() > limit.length() or (
				candidate.length() == limit.length() and candidate > limit
			):
				status.text = "入力できる範囲は −9,223,372,036,854,775,808 ～ 9,223,372,036,854,775,807 です。"
				return
			score_digits = candidate

	score_value.text = ("−" if score_negative else "") + score_digits
	status.text = ""


func _confirm_rating() -> void:
	if rating_confirmed:
		return
	if score_digits.is_empty():
		status.text = "点数を入力してください。"
		return

	var score: int
	if score_negative:
		score = MIN_SCORE if score_digits == MIN_SCORE_MAGNITUDE_TEXT else -score_digits.to_int()
	else:
		score = score_digits.to_int()
	rating_confirmed = true
	confirm.disabled = true
	status.text = "評価を受け付けました。"
	var focused_control: Control = get_viewport().gui_get_focus_owner()
	if focused_control != null:
		focused_control.release_focus()
	narrator.hide()
	evaluation_confirmed.emit(score)
	await _play_narrator_lines(_result_dialogue_key(score))
	ending_blackout.show()
	var fade: Tween = create_tween()
	fade.tween_property(ending_blackout, "color:a", 1.0, 1.0)


func _result_dialogue_key(score: int) -> String:
	if score <= 0:
		return "evaluation_result_zero"
	if score <= 50:
		return "evaluation_result_low"
	if score <= 100:
		return "evaluation_result_mid"
	return "evaluation_result_high"
