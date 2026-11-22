extends ColorRect

signal evaluation_confirmed(score: int)

const MAX_SCORE_TEXT := "9223372036854775807"
const MIN_SCORE_MAGNITUDE_TEXT := "9223372036854775808"
const MIN_SCORE: int = -9223372036854775807 - 1
const NARRATOR_PATH := "res://narrator.json"
const UNITYROOM_CONFIG_PATH := "res://unityroom_local.tres"
const TITLE_SCENE_PATH := "res://title_screen.tscn"
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
@onready var loading_frame: ColorRect = $EndingBlackout/LoadingFrame
@onready var loading_bar: ProgressBar = $EndingBlackout/LoadingFrame/Bar
@onready var loading_error: Label = $EndingBlackout/LoadingError
@onready var score_request: HTTPRequest = $ScoreRequest


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
	$MouseSound.play()


func _confirm_rating() -> void:
	if rating_confirmed:
		return
	if score_digits.is_empty():
		status.text = "点数を入力してください。"
		return

	$MouseSound.play()
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
	_send_unityroom_score(score)
	await _play_narrator_lines(_result_dialogue_key(score))
	await _return_to_title()


func _return_to_title() -> void:
	ending_blackout.show()
	var fade: Tween = create_tween()
	fade.tween_property(ending_blackout, "color:a", 1.0, 1.0)
	await fade.finished
	await get_tree().create_timer(1.0).timeout

	ending_blackout.mouse_default_cursor_shape = Control.CURSOR_WAIT
	loading_frame.show()
	var progress: Tween = create_tween()
	progress.tween_property(loading_bar, "value", loading_bar.max_value, 1.0)
	await progress.finished
	await get_tree().process_frame

	var result: Error = get_tree().change_scene_to_file(TITLE_SCENE_PATH)
	if result != OK:
		ending_blackout.mouse_default_cursor_shape = Control.CURSOR_ARROW
		loading_frame.hide()
		loading_error.show()
		push_error("Could not return to the title screen: %s" % error_string(result))


func _send_unityroom_score(score: int) -> void:
	if not OS.has_feature("web"):
		return

	if not ResourceLoader.exists(UNITYROOM_CONFIG_PATH):
		status.text = "ランキングの送信設定がありません。"
		return
	var config: Resource = ResourceLoader.load(UNITYROOM_CONFIG_PATH)
	if config == null:
		status.text = "ランキングの送信設定を読み込めませんでした。"
		return
	var board_no: int = int(config.get_meta("board_no", 1))
	var key_text: String = str(config.get_meta("hmac_key", ""))
	var key_bytes: PackedByteArray = Marshalls.base64_to_raw(key_text)
	if board_no < 1 or key_bytes.is_empty():
		status.text = "ランキングの送信設定が無効です。"
		return

	# The API uses the same origin as the game and signs the exact form value.
	var origin: String = str(JavaScriptBridge.eval("window.location.origin"))
	if not origin.begins_with("https://"):
		status.text = "ランキング送信はunityroomの公開ページから利用できます。"
		return
	var path: String = "/gameplay_api/v1/scoreboards/%d/scores" % board_no
	var timestamp: String = str(int(Time.get_unix_time_from_system()))
	var score_text: String = str(score)
	var payload: String = "POST\n%s\n%s\n%s" % [path, timestamp, score_text]
	var signature: String = Crypto.new().hmac_digest(
		HashingContext.HASH_SHA256, key_bytes, payload.to_utf8_buffer()
	).hex_encode()
	var headers := PackedStringArray([
		"Content-Type: application/x-www-form-urlencoded",
		"X-Unityroom-Signature: " + signature,
		"X-Unityroom-Timestamp: " + timestamp,
	])

	status.text = "ランキングへ点数を送信しています。"
	var request_error: Error = score_request.request(
		origin + path, headers, HTTPClient.METHOD_POST, "score=" + score_text
	)
	if request_error != OK:
		status.text = "ランキングへの送信を開始できませんでした。"
		return

	var response: Array = await score_request.request_completed
	var result: int = response[0]
	var http_code: int = response[1]
	if result != HTTPRequest.RESULT_SUCCESS or http_code < 200 or http_code >= 300:
		status.text = "ランキングへ点数を送信できませんでした。"
		push_warning("unityroom score upload failed (HTTP %d, result %d)." % [http_code, result])
		return

	var body: PackedByteArray = response[3]
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or not data.has("saved"):
		status.text = "ランキングからの応答を確認できませんでした。"
		return
	status.text = "ランキングに点数を登録しました。" if data["saved"] == true else "ランキングの記録に変更はありません。"


func _result_dialogue_key(score: int) -> String:
	if score <= 0:
		return "evaluation_result_zero"
	if score <= 50:
		return "evaluation_result_low"
	if score <= 100:
		return "evaluation_result_mid"
	return "evaluation_result_high"
