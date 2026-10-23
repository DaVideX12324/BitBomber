extends PanelContainer

## Panel pytania w trakcie gry (pytanie-bonus / odrodzenie przez quiz) — wygląd w field_quiz_panel.tscn,
## logikę prowadzi field_quiz.gd.

const ANSWER_COLOR := Color(1, 1, 1, 1)
const GOOD_COLOR   := Color(0.3, 1.0, 0.4)
const BAD_COLOR    := Color(1.0, 0.35, 0.35)

# Bazy z field_quiz_panel.tscn (skalowane przez UIScaleManager)
const BASE_WIDTH    := 380.0
const BASE_FONTS    := {"Title": 18, "Question": 22, "Answer": 19, "Result": 22}

@onready var _title    : Label       = $VBox/Title
@onready var _question : Label       = $VBox/Question
@onready var _answers  : Array[Label] = [$VBox/Answer1, $VBox/Answer2, $VBox/Answer3, $VBox/Answer4]
@onready var _time_bar : ProgressBar = $VBox/TimeBar
@onready var _result   : Label       = $VBox/Result

var _correct_index := -1


func _ready() -> void:
	visible = false
	var sm := get_node_or_null("/root/UIScaleManager")
	if sm and sm.has_signal("scale_changed"):
		sm.scale_changed.connect(_on_scale_changed)
		_on_scale_changed(float(sm.get("scale_factor")))


func _on_scale_changed(_s: float) -> void:
	var sm := get_node_or_null("/root/UIScaleManager")
	if sm == null:
		return
	custom_minimum_size.x = float(sm.call("sz", BASE_WIDTH))
	_question.custom_minimum_size.x = custom_minimum_size.x - float(sm.call("sz", 28.0))
	_title.add_theme_font_size_override("font_size", int(sm.call("px", BASE_FONTS["Title"])))
	_question.add_theme_font_size_override("font_size", int(sm.call("px", BASE_FONTS["Question"])))
	_result.add_theme_font_size_override("font_size", int(sm.call("px", BASE_FONTS["Result"])))
	for a in _answers:
		a.add_theme_font_size_override("font_size", int(sm.call("px", BASE_FONTS["Answer"])))


## keys: nazwy klawiszy kolejnych odpowiedzi („W”, „↑”, „1”…).
func show_question(title: String, text: String, answers: Array, keys: Array, correct_index: int, border: Color) -> void:
	_title.text = title
	_question.text = text
	_correct_index = correct_index
	for i in _answers.size():
		_answers[i].visible = i < answers.size()
		if i < answers.size():
			_answers[i].text = "[%s]  %s" % [keys[i] if i < keys.size() else str(i + 1), str(answers[i])]
			_answers[i].add_theme_color_override("font_color", ANSWER_COLOR)
	_result.visible = false
	_time_bar.visible = true
	_time_bar.value = 1.0
	var style := (get_theme_stylebox("panel") as StyleBoxFlat).duplicate() as StyleBoxFlat
	style.border_color = border
	add_theme_stylebox_override("panel", style)
	visible = true


func set_time_fraction(frac: float) -> void:
	_time_bar.value = clampf(frac, 0.0, 1.0)


## Zaznacza wybraną (chosen < 0 = brak odpowiedzi) i poprawną odpowiedź, pokazuje wynik.
func show_result(chosen: int, text: String, good: bool) -> void:
	for i in _answers.size():
		if i == _correct_index:
			_answers[i].add_theme_color_override("font_color", GOOD_COLOR)
		elif i == chosen:
			_answers[i].add_theme_color_override("font_color", BAD_COLOR)
	_time_bar.visible = false
	_result.text = text
	_result.add_theme_color_override("font_color", GOOD_COLOR if good else BAD_COLOR)
	_result.visible = true
