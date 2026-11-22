extends ColorRect

signal evaluation_confirmed(score: int)

const MAX_SCORE_TEXT := "9223372036854775807"
const NARRATOR_PATH := "res://narrator.json"
var score_digits: String = ""

@onready var score_value: Label = $Form/Score/Value
@onready var keypad: GridContainer = $Keypad
@onready var status: Label = $Form/Status
@onready var confirm: Button = $Confirm
@onready var narrator: Panel = $Narrator
@onready var narrator_line: Label = $Narrator/Line
@onready var ending_blackout: ColorRect = $EndingBlackout


func _ready() -> void:
	for child in keypad.get_children():
		if child is Button:
			child.pressed.connect(_on_key_pressed.bind(child))
	confirm.pressed.connect(_confirm_rating)
	var lines: Variant = JSON.parse_string(FileAccess.get_file_as_string(NARRATOR_PATH))
	if lines is Dictionary:
		var request: Variant = lines.get("evaluation_request")
		if request is String and not request.is_empty():
			narrator_line.text = request
			narrator.show()


func _on_key_pressed(key: Button) -> void:
	match key.name:
		&"Clear":
			score_digits = ""
		&"Erase":
			score_digits = score_digits.substr(0, maxi(0, score_digits.length() - 1))
		_:
			var candidate: String = key.text if score_digits == "0" else score_digits + key.text
			# Compare before conversion to avoid overflowing the integer.
			if candidate.length() > MAX_SCORE_TEXT.length() or (
				candidate.length() == MAX_SCORE_TEXT.length() and candidate > MAX_SCORE_TEXT
			):
				status.text = "入力できる最大の点数は 9,223,372,036,854,775,807 です。"
				return
			score_digits = candidate

	score_value.text = score_digits
	status.text = ""


func _confirm_rating() -> void:
	if ending_blackout.visible:
		return
	if score_digits.is_empty():
		status.text = "点数を入力してください。"
		return

	status.text = "評価を受け付けました。"
	var focused_control: Control = get_viewport().gui_get_focus_owner()
	if focused_control != null:
		focused_control.release_focus()
	ending_blackout.show()
	var fade: Tween = create_tween()
	fade.tween_property(ending_blackout, "color:a", 1.0, 1.0)
	evaluation_confirmed.emit(score_digits.to_int())
