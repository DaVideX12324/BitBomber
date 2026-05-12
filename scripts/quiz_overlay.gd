extends CanvasLayer

## QuizOverlay — wyświetla pytanie quizowe w trakcie rozgrywki.
## Tryby: SOLO, VERSUS, DUEL_P1, DUEL_P2

enum Mode { SOLO, VERSUS, DUEL_P1, DUEL_P2 }

@onready var _panel          : PanelContainer = $Panel
@onready var _lbl_question   : Label          = $Panel/VBox/LblQuestion
@onready var _lbl_timer      : Label          = $Panel/VBox/LblTimer
@onready var _lbl_mode       : Label          = $Panel/VBox/LblMode
@onready var _container_mc   : VBoxContainer  = $Panel/VBox/ContainerMC
@onready var _container_tf   : HBoxContainer  = $Panel/VBox/ContainerTF
@onready var _container_fill : VBoxContainer  = $Panel/VBox/ContainerFill
@onready var _input_fill     : LineEdit        = $Panel/VBox/ContainerFill/InputFill
@onready var _btn_tf_true    : Button          = $Panel/VBox/ContainerTF/BtnTrue
@onready var _btn_tf_false   : Button          = $Panel/VBox/ContainerTF/BtnFalse
@onready var _lbl_explanation: Label          = $Panel/VBox/LblExplanation

var _mode        : Mode    = Mode.SOLO
var _timer_left  : float   = 0.0
var _active      : bool    = false
var _base_diff   : float   = 3.0

const BASE_TIME  : float   = 30.0


func _ready() -> void:
	visible = false
	QuizManager.quiz_started.connect(_on_quiz_started)
	QuizManager.quiz_ended.connect(_on_quiz_ended)
	UIScaleManager.scale_changed.connect(_on_scale_changed)
	_on_scale_changed(UIScaleManager.scale_factor)


func _process(delta: float) -> void:
	if not _active:
		return
	_timer_left -= delta
	if _timer_left <= 0.0:
		_timer_left = 0.0
		_active = false
		QuizManager.answer_current(-1)
	_lbl_timer.text = "%.1f s" % _timer_left


# ---------------------------------------------------------------------------
# Skalowanie UI
# ---------------------------------------------------------------------------

func _on_scale_changed(_s: float) -> void:
	_lbl_question.add_theme_font_size_override("font_size", UIScaleManager.px(26))
	_lbl_timer.add_theme_font_size_override("font_size", UIScaleManager.px(22))
	_lbl_mode.add_theme_font_size_override("font_size", UIScaleManager.px(18))
	_lbl_explanation.add_theme_font_size_override("font_size", UIScaleManager.px(18))
	_btn_tf_true.add_theme_font_size_override("font_size", UIScaleManager.px(22))
	_btn_tf_false.add_theme_font_size_override("font_size", UIScaleManager.px(22))
	_input_fill.add_theme_font_size_override("font_size", UIScaleManager.px(22))
	_panel.custom_minimum_size = Vector2(UIScaleManager.px(700), UIScaleManager.px(400))
	# Przyciski MC
	for child in _container_mc.get_children():
		if child is Button:
			child.add_theme_font_size_override("font_size", UIScaleManager.px(22))


# ---------------------------------------------------------------------------
# Wyświetlanie pytania
# ---------------------------------------------------------------------------

func _on_quiz_started() -> void:
	var q := QuizManager.get_current_question()
	if not q:
		return
	_base_diff = QuizManager.get_player_difficulty(0)
	_timer_left = calculate_time(q, BASE_TIME, _base_diff)
	_active = true
	visible = true
	_lbl_explanation.visible = false
	_display_question(q)


func _on_quiz_ended(_correct: bool) -> void:
	_active = false
	await get_tree().create_timer(1.5).timeout
	visible = false


func _display_question(q: Dictionary) -> void:
	_lbl_question.text = q.get("question", q.get("statement", q.get("prompt", "")))
	_container_mc.visible   = false
	_container_tf.visible   = false
	_container_fill.visible = false

	match q.get("type", ""):
		"multiple_choice":
			_show_mc(q)
		"true_false":
			_container_tf.visible = true
		"fill_text", "fill_tiles":
			_container_fill.visible = true
			_input_fill.text = ""
			_input_fill.grab_focus()


func _show_mc(q: Dictionary) -> void:
	_container_mc.visible = true
	for child in _container_mc.get_children():
		child.queue_free()
	var answers : Array = q.get("answers", [])
	for i in answers.size():
		var btn := Button.new()
		btn.text = answers[i]
		btn.add_theme_font_size_override("font_size", UIScaleManager.px(22))
		var idx := i
		btn.pressed.connect(func(): _answer(idx))
		_container_mc.add_child(btn)


func _answer(idx: int) -> void:
	_active = false
	var correct := QuizManager.answer_current(idx)
	_show_explanation(correct)


func _show_explanation(correct: bool) -> void:
	var q := QuizManager.get_current_question()
	if q and q.has("explanation"):
		_lbl_explanation.text    = ("✔ " if correct else "✘ ") + q["explanation"]
		_lbl_explanation.visible = true


# ---------------------------------------------------------------------------
# Statyczna kalkulacja czasu
# ---------------------------------------------------------------------------

static func calculate_time(question: Dictionary, base_time: float, base_difficulty: float) -> float:
	var text  : String = question.get("question", question.get("statement", question.get("prompt", "")))
	var words : int    = text.split(" ").size()
	var diff  : int    = question.get("difficulty", 3)
	var qtype : String = question.get("type", "")

	var time := base_time
	time += clampf(words - 10, 0, 20) * 0.5
	time *= 1.0 + (diff - base_difficulty) * 0.15
	match qtype:
		"fill_text", "fill_tiles": time *= 1.3
		"matching":                time *= 1.4
	return clampf(time, 10.0, 90.0)
