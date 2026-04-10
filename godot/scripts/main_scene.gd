extends Node2D

@export var interact_distance := 104.0
@export var hold_duration := 0.8

@onready var player: CharacterBody2D = $World/Actors/Player
@onready var player_sprite: AnimatedSprite2D = $World/Actors/Player/AnimatedSprite2D
@onready var overlay: Control = $UI/Overlay
@onready var item: Node2D = $World/Actors/InteractableItem
@onready var item_lid: Node2D = $World/Actors/InteractableItem/Lid
@onready var item_glow: CanvasItem = $World/Actors/InteractableItem/ClueGlow
@onready var item_badge: Node2D = $World/Actors/InteractableItem/Badge
@onready var prompt = $UI/Overlay/InteractPrompt

const PROMPT_FONT := preload("res://assets/fonts/LilitaOne-Regular.ttf")
const VOICE_PROMPT_SCRIPT := preload("res://scripts/voice_prompt.gd")

var _hold_time := 0.0
var _item_open := false
var _interaction_tween: Tween
var _voice_prompt: Control
var minimap: Control


func _ready() -> void:
	prompt.set_prompt_visible(false)
	prompt.set_progress(0.0)
	player_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_setup_voice_prompt()
	_setup_npcs()
	var glow_modulate := item_glow.modulate
	glow_modulate.a = 0.0
	item_glow.modulate = glow_modulate
	minimap = find_child("Minimap", true, false) as Control

	if minimap and minimap.has_method("configure"):
		minimap.call(
			"configure",
			player,
			$World/WalkPlane,
			[item],
			PackedStringArray(["Clue"])
		)


func _process(delta: float) -> void:
	if _voice_prompt != null and _voice_prompt.has_method("set_active"):
		_voice_prompt.call("set_active", Input.is_key_pressed(KEY_M))

	var near_item := player.global_position.distance_to(item.global_position) <= interact_distance
	var can_interact := near_item and not _is_animating()
	var is_holding := can_interact and Input.is_key_pressed(KEY_E)

	if is_holding:
		_hold_time = min(_hold_time + delta, hold_duration)
	else:
		_hold_time = move_toward(_hold_time, 0.0, delta * 1.9)

	var progress := 0.0 if hold_duration <= 0.0 else _hold_time / hold_duration
	prompt.set_prompt_visible(near_item)
	prompt.set_progress(progress)
	_position_prompt()
	_update_item_idle(delta, near_item)

	if can_interact and progress >= 1.0:
		_hold_time = 0.0
		prompt.set_progress(0.0)
		_trigger_item()


func _position_prompt() -> void:
	var screen_position: Vector2 = get_viewport().get_canvas_transform() * item.global_position
	prompt.position = screen_position + Vector2(-prompt.size.x * 0.5, -132.0 + prompt.bob_offset)


func _update_item_idle(delta: float, near_item: bool) -> void:
	if _is_animating():
		return

	var hover_strength := 1.0 if near_item else 0.35
	item.rotation = lerpf(item.rotation, sin(Time.get_ticks_msec() / 280.0) * 0.02 * hover_strength, delta * 5.0)
	item.scale = item.scale.lerp(Vector2.ONE * (1.05 if near_item else 1.0), delta * 6.0)
	item_badge.scale = item_badge.scale.lerp(Vector2.ONE * (1.14 if _item_open else 1.0), delta * 6.0)
	item_badge.rotation = lerpf(item_badge.rotation, 0.16 if _item_open else 0.0, delta * 6.0)

	var target_alpha := 0.92 if _item_open else (0.22 if near_item else 0.0)
	var glow_modulate := item_glow.modulate
	glow_modulate.a = move_toward(glow_modulate.a, target_alpha, delta * 1.8)
	item_glow.modulate = glow_modulate


func _trigger_item() -> void:
	if _interaction_tween != null and _interaction_tween.is_valid():
		_interaction_tween.kill()

	_item_open = not _item_open
	prompt.flash()

	_interaction_tween = create_tween()
	_interaction_tween.set_parallel(true)
	_interaction_tween.tween_property(item, "scale", Vector2(1.13, 0.9), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_interaction_tween.chain().tween_property(item, "scale", Vector2.ONE * (1.05 if _item_open else 1.0), 0.26).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_interaction_tween.tween_property(item_lid, "rotation", -0.52 if _item_open else 0.0, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_interaction_tween.finished.connect(_finish_interaction)


func _finish_interaction() -> void:
	_interaction_tween = null


func _is_animating() -> bool:
	return _interaction_tween != null and _interaction_tween.is_valid() and _interaction_tween.is_running()


func _setup_voice_prompt() -> void:
	_voice_prompt = Control.new()
	_voice_prompt.name = "VoicePrompt"
	_voice_prompt.set_script(VOICE_PROMPT_SCRIPT)
	_voice_prompt.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_voice_prompt.offset_left = 22.0
	_voice_prompt.offset_top = -118.0
	_voice_prompt.offset_right = 114.0
	_voice_prompt.offset_bottom = -26.0

	var label := Label.new()
	label.name = "PromptLabel"
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_override("font", PROMPT_FONT)
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_color", Color(0.988235, 0.956863, 0.835294, 1))
	label.add_theme_color_override("font_outline_color", Color(0.164706, 0.145098, 0.133333, 1))
	label.add_theme_constant_override("outline_size", 6)
	label.text = "M"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.position = Vector2(0.0, 6.0)

	_voice_prompt.add_child(label)
	overlay.add_child(_voice_prompt)


func _setup_npcs() -> void:
	var room_points := {
		"library": Vector2(300.0, 222.0),
		"parlor": Vector2(522.0, 224.0),
		"study": Vector2(850.0, 226.0),
		"kitchen": Vector2(298.0, 418.0),
		"atrium": Vector2(618.0, 408.0),
		"dining": Vector2(932.0, 418.0),
		"hall_west": Vector2(330.0, 382.0),
		"hall_center": Vector2(618.0, 386.0),
		"hall_east": Vector2(892.0, 382.0),
		"ballroom": Vector2(640.0, 590.0),
	}

	for npc_path in [
		^"World/Actors/Chef",
		^"World/Actors/Butler",
		^"World/Actors/Maid",
		^"World/Actors/Gardener",
	]:
		var npc := get_node_or_null(npc_path)
		if npc != null and npc.has_method("configure"):
			npc.call("configure", room_points)
