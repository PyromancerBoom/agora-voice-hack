extends Control

@export_range(5.0, 300.0, 1.0) var round_duration_seconds := 60.0
@export_range(3.0, 60.0, 1.0) var warning_threshold_seconds := 15.0
@export var auto_start := true

@onready var timer_value: Label = $TimerFrame/TimerMargin/TimerLayout/ClockRow/TimerValue
@onready var timer_caption: Label = $TimerFrame/TimerMargin/TimerLayout/ClockRow/TimerCaption
@onready var phase_text: Label = $TimerFrame/TimerMargin/TimerLayout/StatusRow/PhaseText
@onready var progress_fill: ColorRect = $TimerFrame/TimerMargin/TimerLayout/ProgressTrack/ProgressFill
@onready var frame: PanelContainer = $TimerFrame
@onready var left_beam: ColorRect = $TimerFrame/LeftBeam
@onready var right_beam: ColorRect = $TimerFrame/RightBeam

const NORMAL_TIME_COLOR := Color("1a1411")
const WARNING_TIME_COLOR := Color("f6e6bc")
const NORMAL_CAPTION_COLOR := Color("5c4530")
const WARNING_CAPTION_COLOR := Color("b99162")
const NORMAL_PHASE_COLOR := Color("493728")
const WARNING_PHASE_COLOR := Color("f0d0a3")
const NORMAL_FILL_COLOR := Color("87603b")
const WARNING_FILL_COLOR := Color("b24d34")
const NORMAL_PANEL_COLOR := Color("d5ba8b")
const WARNING_PANEL_COLOR := Color("4b241e")

var time_remaining := 0.0
var running := false
var default_scale := Vector2.ONE


func _ready() -> void:
	default_scale = timer_value.scale
	reset(round_duration_seconds)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not running:
		return

	time_remaining = maxf(time_remaining - delta, 0.0)
	_update_display()

	if is_zero_approx(time_remaining):
		running = false


func reset(duration_seconds: float = round_duration_seconds) -> void:
	round_duration_seconds = maxf(duration_seconds, 1.0)
	time_remaining = round_duration_seconds
	running = auto_start
	_update_display()


func start() -> void:
	running = true


func stop() -> void:
	running = false


func _update_display() -> void:
	var total_seconds := int(ceil(time_remaining))
	var minutes := int(total_seconds / 60.0)
	var seconds := total_seconds % 60
	var progress := clampf(time_remaining / round_duration_seconds, 0.0, 1.0)
	var warning_active := time_remaining <= warning_threshold_seconds
	var pulse := 1.0

	if warning_active and running:
		pulse = 0.88 + (sin(Time.get_ticks_msec() / 115.0) + 1.0) * 0.09

	timer_value.text = "%02d:%02d" % [minutes, seconds]
	progress_fill.scale.x = progress
	timer_value.scale = default_scale * pulse

	if total_seconds <= 0:
		timer_caption.text = "BLACKOUT"
		phase_text.text = "The manor goes dark. Expect movement, panic, and one narrow chance for the killer."
	elif warning_active:
		timer_caption.text = "BLACKOUT IMMINENT"
		phase_text.text = "Your final seconds before the lights fail. Lock your route and pressure the weakest alibi."
	else:
		timer_caption.text = "INVESTIGATION WINDOW"
		phase_text.text = "Use the lit rooms to interrogate suspects, track noise, and build the case before blackout."

	_apply_palette(warning_active, pulse)


func _apply_palette(warning_active: bool, pulse: float) -> void:
	if warning_active:
		frame.self_modulate = Color(1.0, 0.95, 0.92, 1.0)
		progress_fill.color = WARNING_FILL_COLOR
		timer_value.modulate = WARNING_TIME_COLOR
		timer_caption.modulate = WARNING_CAPTION_COLOR
		phase_text.modulate = WARNING_PHASE_COLOR
		left_beam.modulate = Color(1.0, 0.84, 0.77, 0.86 + pulse * 0.08)
		right_beam.modulate = Color(1.0, 0.84, 0.77, 0.86 + pulse * 0.08)
		(frame.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = WARNING_PANEL_COLOR
	else:
		frame.self_modulate = Color.WHITE
		progress_fill.color = NORMAL_FILL_COLOR
		timer_value.modulate = NORMAL_TIME_COLOR
		timer_caption.modulate = NORMAL_CAPTION_COLOR
		phase_text.modulate = NORMAL_PHASE_COLOR
		left_beam.modulate = Color.WHITE
		right_beam.modulate = Color.WHITE
		(frame.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = NORMAL_PANEL_COLOR
