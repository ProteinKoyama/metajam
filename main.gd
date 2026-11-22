extends Control

const NARRATOR_PATH := "res://narrator.json"
const EVALUATION_SCENE: PackedScene = preload("res://evaluation_screen.tscn")
const BGM_FADE_SECONDS: float = 1.0
const ENCOUNTER_INTERVAL: int = 50
const TYPING_STEP_THRESHOLD: int = 500
const TYPING_ANNOUNCEMENT_SECONDS: float = 4.0
const TYPING_COMMENT_MIN_DELAY: float = 4.0
const TYPING_COMMENT_MAX_DELAY: float = 10.0

enum Encounter { NONE, APPROACHING, ATTACKING }

const CHEER_START_PRICE: int = 10
const HOOF_START_PRICE: int = 100
const HOOF_UNLOCK_LEVEL: int = 3
const CHEER_INTERVAL: float = 2.0

@export var walk_frames: Array[Texture2D] = []
@export var battle_frames: Array[Texture2D] = []
@export var slime_hit_texture: Texture2D
@export_range(1.0, 1920.0) var pixels_per_step: float = 60.0
@export_range(0.1, 1.0, 0.01) var step_duration: float = 0.24
@export var hand_push_distance: float = 36.0

var steps: int = 0
var gold: int = 0
var cheer_cost: int = CHEER_START_PRICE
var hoof_cost: int = HOOF_START_PRICE
var hoof_count: int = 0
var flash_tween: Tween
var bgm_tween: Tween
var hands: Array[TextureRect] = []
var next_hand_index: int = 0
var pending_steps: int = 0
var step_progress: float = 0.0
var completed_scroll: float = 0.0
var walked_steps: int = 0
var hero_level: int = 1
var slimes_defeated_this_level: int = 0
var slimes_required: int = 1
var queued_encounters: int = 0
var encounter: Encounter = Encounter.NONE
var narrator_lines: Dictionary = {}
var typing_switch_pending: bool = false
var evaluation_transition_started: bool = false
var key_rewrite_announced: bool = false
var pending_typing_lines: Array[String] = []
var active_typing_line: String = ""

@onready var hero: TextureRect = $Hero
@onready var step_popup_template: Label = $Hero/StepPopupTemplate
@onready var idle_texture: Texture2D = hero.texture
@onready var battle_pose: Sprite2D = $Hero/BattlePose
@onready var slime: TextureRect = $Slime
@onready var slime_idle_texture: Texture2D = slime.texture
@onready var slime_stop_x: float = slime.position.x
@onready var slime_start_x: float = $Shop.position.x
@onready var hand_template: TextureRect = $Hero/Hand
@onready var hand_rest_position: Vector2 = hand_template.position
@onready var auto_step_timer: Timer = $AutoStepTimer
@onready var ground_tiles: Control = $Ground/Tiles
@onready var ground_tile_width: float = $Ground/Tiles/First.size.x
@onready var hero_flash: ColorRect = $Hero/Flash
@onready var step_count: Label = $StepCount
@onready var cheer_button: Button = $CheerFrame
@onready var cheer_price: Label = $CheerFrame/Price
@onready var cheer_quantity: Label = $CheerFrame/Quantity
@onready var hoof_locked: Panel = $LockedFrameOne
@onready var hoof_button: Button = $HoofButton
@onready var hoof_price: Label = $HoofButton/Price
@onready var hoof_quantity: Label = $HoofButton/Quantity
@onready var gold_label: Label = $Gold
@onready var level_status: Label = $LevelStatus
@onready var narrator_panel: Panel = $Narrator
@onready var narrator_line: Label = $Narrator/Line
@onready var typing_narrator: Panel = $TypingNarrator
@onready var typing_narrator_line: Label = $TypingNarrator/Line
@onready var typing_interrupt: Panel = $TypingInterrupt
@onready var typing_interrupt_line: Label = $TypingInterrupt/Line
@onready var typing_comment_timer: Timer = $TypingCommentTimer
@onready var typing_idle_timer: Timer = $TypingIdleTimer
@onready var inactivity_timer: Timer = $InactivityTimer
@onready var typing_overlay: TextureRect = $TypingOverlay
@onready var hero_bgm: AudioStreamPlayer = $HeroBGM
@onready var typing_bgm: AudioStreamPlayer = $TypingBGM

func _ready() -> void:
	set_process(false)
	_update_gold_display()
	_update_cheer_display()
	_update_hoof_display()
	_update_level_status()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(NARRATOR_PATH))
	if data is Dictionary:
		narrator_lines = data


func _input(event: InputEvent) -> void:
	if evaluation_transition_started or typing_switch_pending:
		return
	if event is InputEventMouseButton or event is InputEventKey or event is InputEventScreenTouch:
		if event.is_pressed() and not event.is_echo():
			if typing_overlay.visible:
				typing_idle_timer.start()
			else:
				inactivity_timer.start()


func _on_inactivity_timer_timeout() -> void:
	_announce_typing_switch()


func _announce_typing_switch() -> void:
	if typing_switch_pending or typing_overlay.visible:
		return
	typing_switch_pending = true
	inactivity_timer.stop()
	await _play_narrator_lines("typing_transition", narrator_panel, narrator_line)
	_switch_to_typing()


func _play_narrator_lines(key: String, panel: Panel, subtitle: Label) -> void:
	var lines: Variant = narrator_lines.get(key)
	if lines is Array:
		for line in lines:
			if line is String and not line.is_empty():
				subtitle.text = line
				panel.show()
				await get_tree().create_timer(TYPING_ANNOUNCEMENT_SECONDS).timeout
				if evaluation_transition_started and key != "typing_outro":
					return
				if panel == typing_narrator and not pending_typing_lines.is_empty():
					await _play_pending_typing_lines()
					if evaluation_transition_started:
						return
	panel.hide()


func _switch_to_typing() -> void:
	if typing_overlay.visible:
		return

	typing_switch_pending = false
	inactivity_timer.stop()
	cheer_button.release_focus()
	cheer_button.focus_mode = Control.FOCUS_NONE
	hoof_button.release_focus()
	hoof_button.focus_mode = Control.FOCUS_NONE
	narrator_panel.hide()
	typing_overlay.show()
	typing_idle_timer.start()
	_crossfade_to_typing_bgm()
	await _play_narrator_lines("typing_intro", typing_narrator, typing_narrator_line)
	if not evaluation_transition_started:
		_schedule_typing_comment()


func _schedule_typing_comment() -> void:
	typing_comment_timer.start(randf_range(TYPING_COMMENT_MIN_DELAY, TYPING_COMMENT_MAX_DELAY))


func _on_typing_comment_timer_timeout() -> void:
	if typing_narrator.visible:
		typing_narrator.hide()
		await _play_pending_typing_lines()
		if not evaluation_transition_started:
			_schedule_typing_comment()
		return

	var comments: Variant = narrator_lines.get("typing_comments")
	if not comments is Array or comments.is_empty():
		return
	var comment: Variant = comments.pick_random()
	if not comment is String or comment.is_empty():
		_schedule_typing_comment()
		return

	typing_narrator_line.text = comment
	typing_narrator.show()
	typing_comment_timer.start(TYPING_ANNOUNCEMENT_SECONDS)


func _on_typing_idle_timer_timeout() -> void:
	_queue_typing_line("typing_idle")


func _on_typing_key_rewritten() -> void:
	if key_rewrite_announced or evaluation_transition_started:
		return
	key_rewrite_announced = true

	var line: Variant = narrator_lines.get("typing_key_rewritten")
	if not line is String or line.is_empty():
		return

	typing_interrupt_line.text = line
	typing_narrator.modulate.a = 0.0
	typing_interrupt.show()
	await get_tree().create_timer(TYPING_ANNOUNCEMENT_SECONDS).timeout
	typing_interrupt.hide()
	typing_narrator.modulate.a = 1.0


func _queue_typing_line(key: String) -> void:
	if evaluation_transition_started or key == active_typing_line or pending_typing_lines.has(key):
		return

	pending_typing_lines.append(key)
	if typing_narrator.visible:
		return

	typing_comment_timer.stop()
	await _play_pending_typing_lines()
	if not evaluation_transition_started:
		_schedule_typing_comment()


func _play_pending_typing_lines() -> void:
	while not pending_typing_lines.is_empty() and not evaluation_transition_started:
		active_typing_line = pending_typing_lines.pop_front()
		var line: Variant = narrator_lines.get(active_typing_line)
		if line is String and not line.is_empty():
			typing_narrator_line.text = line
			typing_narrator.show()
			await get_tree().create_timer(TYPING_ANNOUNCEMENT_SECONDS).timeout
			if not evaluation_transition_started:
				typing_narrator.hide()
		active_typing_line = ""


func _show_evaluation_screen() -> void:
	if evaluation_transition_started:
		return
	evaluation_transition_started = true
	typing_comment_timer.stop()
	typing_idle_timer.stop()
	pending_typing_lines.clear()
	typing_interrupt.hide()
	typing_narrator.modulate.a = 1.0
	typing_narrator.hide()
	await _play_narrator_lines("typing_outro", typing_narrator, typing_narrator_line)
	await _fade_out_bgm()
	var result: Error = get_tree().change_scene_to_packed(EVALUATION_SCENE)
	if result != OK:
		push_error("Could not open the evaluation screen: %s" % error_string(result))


func _crossfade_to_typing_bgm() -> void:
	var target_volume: float = typing_bgm.volume_linear
	typing_bgm.volume_linear = 0.0
	typing_bgm.play()

	bgm_tween = create_tween().set_parallel()
	bgm_tween.tween_property(hero_bgm, "volume_linear", 0.0, BGM_FADE_SECONDS)
	bgm_tween.tween_property(typing_bgm, "volume_linear", target_volume, BGM_FADE_SECONDS)
	bgm_tween.chain().tween_callback(hero_bgm.stop)


func _fade_out_bgm() -> void:
	if bgm_tween != null and bgm_tween.is_valid():
		bgm_tween.kill()

	bgm_tween = create_tween().set_parallel()
	bgm_tween.tween_property(hero_bgm, "volume_linear", 0.0, BGM_FADE_SECONDS)
	bgm_tween.tween_property(typing_bgm, "volume_linear", 0.0, BGM_FADE_SECONDS)
	bgm_tween.chain().tween_callback(hero_bgm.stop)
	bgm_tween.parallel().tween_callback(typing_bgm.stop)
	await bgm_tween.finished


func _on_hero_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if encounter != Encounter.ATTACKING:
			var added_steps: int = 1 + hoof_count
			_push_hero(added_steps)
			if hoof_count > 0:
				_show_step_popup(event.position, hoof_count)
		accept_event()


func _show_step_popup(click_position: Vector2, bonus_steps: int) -> void:
	var popup: Label = step_popup_template.duplicate() as Label
	hero.add_child(popup)
	popup.text = "+%s" % _comma(bonus_steps)
	popup.position = click_position + Vector2(18.0, -58.0)
	popup.show()

	var animation: Tween = popup.create_tween().set_parallel()
	animation.tween_property(popup, "position:y", popup.position.y - 60.0, 0.65)
	animation.tween_property(popup, "modulate:a", 0.0, 0.65)
	animation.chain().tween_callback(popup.queue_free)


func _start_encounter() -> void:
	queued_encounters -= 1
	encounter = Encounter.APPROACHING
	slime.texture = slime_idle_texture
	slime.position.x = slime_start_x
	slime.show()
	var approach: Tween = create_tween()
	approach.tween_property(slime, "position:x", slime_stop_x, 0.7)
	approach.tween_callback(_attack_slime)


func _attack_slime() -> void:
	encounter = Encounter.ATTACKING
	set_process(false)
	auto_step_timer.paused = true
	hero.texture = idle_texture
	hero.self_modulate.a = 0.0
	battle_pose.show()
	for frame in battle_frames:
		battle_pose.texture = frame
		battle_pose.position.y = hero.size.y - frame.get_height()
		await get_tree().create_timer(0.14).timeout

	for i in range(6):
		slime.texture = slime_hit_texture if i % 2 == 0 else slime_idle_texture
		await get_tree().create_timer(0.08).timeout

	slime.hide()
	_record_slime_defeat()
	battle_pose.hide()
	hero.self_modulate.a = 1.0
	encounter = Encounter.NONE
	auto_step_timer.paused = false
	set_process(pending_steps > 0)
	if queued_encounters > 0:
		_start_encounter()


func _record_slime_defeat() -> void:
	slimes_defeated_this_level += 1
	if slimes_defeated_this_level >= slimes_required:
		hero_level += 1
		slimes_defeated_this_level = 0
		slimes_required = _increase_by_fifteen_percent(slimes_required)
		if hero_level == HOOF_UNLOCK_LEVEL:
			_update_hoof_display()
			_update_gold_display()
	_update_level_status()


func _update_level_status() -> void:
	level_status.text = "レベル %s   とうばつ %s / %s" % [
		_comma(hero_level), _comma(slimes_defeated_this_level), _comma(slimes_required)
	]


func _push_hero(step_amount: int = 1) -> void:
	var previous_steps: int = steps
	steps += step_amount
	if not typing_overlay.visible and not typing_switch_pending:
		if previous_steps < TYPING_STEP_THRESHOLD and steps >= TYPING_STEP_THRESHOLD:
			_announce_typing_switch()
		else:
			for reached_step in range(previous_steps + 1, steps + 1):
				_show_narrator_line(str(reached_step))
	gold += step_amount
	pending_steps += step_amount
	if pending_steps == step_amount:
		set_process(true)
		if not walk_frames.is_empty():
			hero.texture = walk_frames[0]
	step_count.text = "%s / 1,000,000 ほ" % _comma(steps)
	_update_gold_display()

	if flash_tween != null:
		flash_tween.kill()
	hero_flash.color.a = 0.18
	flash_tween = create_tween()
	flash_tween.tween_property(hero_flash, "color:a", 0.0, 0.28)


func _show_narrator_line(key: String) -> void:
	var line: Variant = narrator_lines.get(key)
	if line is String and not line.is_empty():
		narrator_line.text = line
		narrator_panel.show()


func _on_buy_cheer_pressed() -> void:
	if gold < cheer_cost:
		return
	gold -= cheer_cost
	cheer_cost = _increase_by_fifteen_percent(cheer_cost)
	var remaining_fraction: float = 1.0
	if not auto_step_timer.is_stopped():
		remaining_fraction = auto_step_timer.time_left / auto_step_timer.wait_time
	_add_hand()
	var interval: float = CHEER_INTERVAL / hands.size()
	auto_step_timer.start(maxf(interval * remaining_fraction, 0.001))
	auto_step_timer.wait_time = interval
	_update_cheer_display()
	_update_gold_display()


func _add_hand() -> void:
	var new_hand: TextureRect = hand_template
	if not hands.is_empty():
		new_hand = hand_template.duplicate() as TextureRect
		hero.add_child(new_hand)
		new_hand.position = hand_rest_position
	hands.append(new_hand)
	new_hand.show()

	# Keep the hands together beside the hero as the inventory grows.
	var gaps: int = hands.size() - 1
	var spacing: float = minf(hand_template.size.y * 0.7, 400.0 / maxi(gaps, 1))
	for i in range(hands.size()):
		hands[i].position.y = hand_rest_position.y + (i - gaps * 0.5) * spacing


func _on_auto_step_timer_timeout() -> void:
	if encounter == Encounter.ATTACKING:
		return
	_push_hero()
	var hand: TextureRect = hands[next_hand_index]
	next_hand_index = (next_hand_index + 1) % hands.size()

	var push_duration: float = _current_step_duration()
	var hand_tween: Tween = create_tween()
	hand_tween.tween_property(hand, "position:x", hand_rest_position.x + hand_push_distance, push_duration * 0.4)
	hand_tween.tween_property(hand, "position:x", hand_rest_position.x, push_duration * 0.6)


func _on_buy_hoof_pressed() -> void:
	if hero_level < HOOF_UNLOCK_LEVEL or gold < hoof_cost:
		return
	gold -= hoof_cost
	hoof_count += 1
	hoof_cost = _increase_by_fifteen_percent(hoof_cost)
	_update_hoof_display()
	_update_gold_display()


func _update_gold_display() -> void:
	gold_label.text = "%s ゴールド" % _comma(gold)
	cheer_button.disabled = gold < cheer_cost
	hoof_button.disabled = hero_level < HOOF_UNLOCK_LEVEL or gold < hoof_cost


func _update_cheer_display() -> void:
	cheer_price.text = "%s ゴールド" % _comma(cheer_cost)
	cheer_quantity.text = "しょじ %sこ" % _comma(hands.size())


func _update_hoof_display() -> void:
	hoof_button.visible = hero_level >= HOOF_UNLOCK_LEVEL
	hoof_locked.visible = not hoof_button.visible
	hoof_price.text = "%s ゴールド" % _comma(hoof_cost)
	hoof_quantity.text = "しょじ %sこ" % _comma(hoof_count)


func _increase_by_fifteen_percent(value: int) -> int:
	# Adding 99 before integer division rounds a positive increase up.
	@warning_ignore("integer_division")
	var increase: int = (value * 15 + 99) / 100
	return value + increase


func _current_step_duration() -> float:
	if hands.is_empty():
		return step_duration
	return minf(step_duration, auto_step_timer.wait_time)


func _process(delta: float) -> void:
	step_progress += delta / _current_step_duration()
	var finished_steps: int = mini(floori(step_progress), pending_steps)
	if finished_steps > 0:
		pending_steps -= finished_steps
		step_progress -= finished_steps
		completed_scroll = fposmod(completed_scroll + finished_steps * pixels_per_step, ground_tile_width)
		for i in range(finished_steps):
			walked_steps += 1
			if walked_steps % ENCOUNTER_INTERVAL == 0:
				queued_encounters += 1
		if encounter == Encounter.NONE and queued_encounters > 0:
			_start_encounter()

	if pending_steps == 0:
		step_progress = 0.0
		ground_tiles.position.x = -completed_scroll
		hero.texture = idle_texture
		set_process(false)
		return

	ground_tiles.position.x = -fposmod(completed_scroll + step_progress * pixels_per_step, ground_tile_width)
	if not walk_frames.is_empty():
		var frame_index: int = mini(floori(step_progress * walk_frames.size()), walk_frames.size() - 1)
		var next_texture: Texture2D = walk_frames[frame_index]
		if hero.texture != next_texture:
			hero.texture = next_texture


func _comma(value: int) -> String:
	var raw := str(value)
	var result := ""
	for i in range(raw.length()):
		if i > 0 and (raw.length() - i) % 3 == 0:
			result += ","
		result += raw[i]
	return result
