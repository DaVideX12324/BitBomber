extends Node

## Quiz w trakcie gry, bez pauzy:
##  - pytanie-bonus: power-up „quiz” (❓) — dobra odpowiedź = tarcza / gwiazdka / zasięg +2, zła = spowolnienie,
##    brak odpowiedzi = nic;
##  - odrodzenie przez quiz (tryb KILL, ludzie): dobra = powrót od razu z tarczą, zła = 3 s czekania,
##    brak odpowiedzi = powrót po czasie pytania bez tarczy.
## Ludzie odpowiadają w panelu HUD: pytanie-bonus klawiszami quiz_pN_a..d (gracz 1: 1–4, gracz 2: Num 1–4, bo
## gracz biega), odrodzenie klawiszami ruchu jak ostatnia szansa (W/S/A/D, strzałki — martwy się nie rusza).
## Boty „odpowiadają” po chwili z szansą zależną od trudności.

const BbQuestions = preload("bb_questions.gd")
const BbSfx = preload("bb_sfx.gd")

enum Kind { BONUS, RESPAWN }

const BONUS_TIME   : float = 12.0
const RESPAWN_TIME : float = 8.0
## Panel z wynikiem znika po tylu sekundach
const RESULT_SHOW  : float = 1.6
const SLOW_TIME    : float = 5.0
const WRONG_RESPAWN_DELAY : float = 3.0
## Boty: szansa na dobrą odpowiedź (łatwe / średnie / trudne) i czas „namysłu”
const BOT_ACCURACY : Array[float] = [0.5, 0.65, 0.8]
const BOT_THINK    := Vector2(2.0, 5.0)
## Akcje odpowiedzi 1–4: pytanie-bonus / odrodzenie (kolejność jak w quiz_overlay: W, S, A, D)
const BONUS_ACTIONS   := ["quiz_p%d_a", "quiz_p%d_b", "quiz_p%d_c", "quiz_p%d_d"]
const RESPAWN_ACTIONS := ["p%d_up", "p%d_down", "p%d_left", "p%d_right"]
const KEY_NAMES := {"Up": "↑", "Down": "↓", "Left": "←", "Right": "→"}

var hud : CanvasLayer = null

## player_id → {kind, q, left, total, player, bot_at, bot_correct}
var _active  : Dictionary = {}
## player_id → sekundy do schowania panelu z wynikiem
var _closing : Dictionary = {}


func _ready() -> void:
	RoundManager.round_started.connect(func(_r: int) -> void: clear())
	RoundManager.round_ended.connect(func(_w: int) -> void: clear())


func connect_player(p: Node) -> void:
	p.powerup_collected.connect(_on_powerup.bind(p))
	p.killed.connect(_on_killed.bind(p))
	p.died.connect(func(pid: int) -> void: cancel(pid))


func is_asking(pid: int) -> bool:
	return _active.has(pid)


func clear() -> void:
	for pid in _active.keys() + _closing.keys():
		cancel(pid)


func cancel(pid: int) -> void:
	_active.erase(pid)
	_closing.erase(pid)
	var panel := _panel(pid)
	if panel:
		panel.visible = false


func _on_powerup(_pid: int, type: String, p: Node) -> void:
	if type == "quiz" and not _active.has(p.player_id):
		ask(p, Kind.BONUS)


func _on_killed(_victim: int, _killer: int, p: Node) -> void:
	cancel(p.player_id)   # przepada niedokończone pytanie-bonus
	if p.is_bot or BbQuestions.quizless_mode():
		return
	if ask(p, Kind.RESPAWN):
		p.set_respawn_in(RESPAWN_TIME + 0.2)   # bez odpowiedzi wraca po czasie pytania


func ask(p: Node, kind: Kind) -> bool:
	var q := BbQuestions.pick(BbQuestions.CHOICE_TYPES)
	if q.is_empty():
		return false
	var pid: int = p.player_id
	var total := BONUS_TIME if kind == Kind.BONUS else RESPAWN_TIME
	var e := {"kind": kind, "q": q, "left": total, "total": total, "player": p}
	if p.is_bot:
		e["bot_at"] = total - randf_range(BOT_THINK.x, BOT_THINK.y)
		e["bot_correct"] = randf() < BOT_ACCURACY[clampi(GameManager.bot_difficulty, 0, BOT_ACCURACY.size() - 1)]
	_active[pid] = e
	_closing.erase(pid)
	var panel := _panel(pid)
	if panel:
		var title := BbI18n.tf("bb.fq.title_bonus" if kind == Kind.BONUS else "bb.fq.title_respawn",
				{"name": GameManager.player_name(pid)},
				"❓ Pytanie-bonus · {name}" if kind == Kind.BONUS else "💀 Odrodzenie · {name}")
		var keys: Array = answer_actions(pid, kind).map(_key_label)
		panel.show_question(title, BbQuestions.text_of(q), BbQuestions.answers_of(q), keys,
				BbQuestions.correct_index(q), hud.player_color(pid))
	return true


func _process(delta: float) -> void:
	for pid in _active.keys():
		var e: Dictionary = _active[pid]
		e["left"] -= delta
		var panel := _panel(pid)
		if panel:
			panel.set_time_fraction(e["left"] / e["total"])
		if e.has("bot_at") and e["left"] <= e["bot_at"]:
			_resolve(pid, e["bot_correct"], -1)
		elif e["left"] <= 0.0:
			_resolve(pid, false, -1)
	for pid in _closing.keys():
		_closing[pid] -= delta
		if _closing[pid] <= 0.0:
			cancel(pid)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	for pid in _active.keys():
		var e: Dictionary = _active[pid]
		if e["player"].is_bot:
			continue
		var actions := answer_actions(pid, e["kind"])
		for i in mini(BbQuestions.answers_of(e["q"]).size(), actions.size()):
			var action: String = actions[i]
			if InputMap.has_action(action) and event.is_action_pressed(action):
				get_viewport().set_input_as_handled()
				_resolve(pid, BbQuestions.is_correct(e["q"], i), i)
				return


func answer_actions(pid: int, kind: Kind) -> Array:
	return (BONUS_ACTIONS if kind == Kind.BONUS else RESPAWN_ACTIONS).map(func(a: String) -> String: return a % pid)


## Nazwa pierwszego klawisza akcji (po ewentualnej zmianie w ustawieniach): „W”, „↑”, „1”, „Num 1”.
func _key_label(action: String) -> String:
	for ev in InputMap.action_get_events(action) if InputMap.has_action(action) else []:
		if ev is InputEventKey:
			var code: Key = ev.keycode if ev.keycode != KEY_NONE else DisplayServer.keyboard_get_keycode_from_physical(ev.physical_keycode)
			var name := OS.get_keycode_string(code)
			return KEY_NAMES.get(name, name.replace("Kp ", "Num "))
	return "?"


func _resolve(pid: int, correct: bool, chosen: int) -> void:
	var e: Dictionary = _active[pid]
	_active.erase(pid)
	var p: Node = e["player"]
	if not is_instance_valid(p):
		cancel(pid)
		return
	if not p.is_bot:
		RoundManager.record_answer(pid, correct)
	var text: String
	var timeout: bool = chosen < 0 and not p.is_bot
	if timeout and e["kind"] == Kind.BONUS:
		text = BbI18n.t("bb.fq.timeout_bonus", "⏱ Czas minął — bez bonusu")
	elif timeout:
		p.set_respawn_in(0.1)   # czas pytania już minął — bez dodatkowej kary
		text = BbI18n.t("bb.fq.timeout_respawn", "⏱ Czas minął — wracasz bez tarczy")
	elif e["kind"] == Kind.BONUS:
		if correct:
			text = _reward(p)
		else:
			p.apply_slow(SLOW_TIME)
			text = BbI18n.t("bb.fq.slow", "❌ Spowolnienie na 5 s")
	elif correct:
		p.set_respawn_in(0.4, true)
		text = BbI18n.t("bb.fq.respawn_now", "✅ Wracasz z tarczą!")
	else:
		p.set_respawn_in(WRONG_RESPAWN_DELAY)
		text = BbI18n.t("bb.fq.respawn_late", "❌ Odrodzenie za 3 s")
	BbSfx.play("quiz_right" if correct else "quiz_wrong", -4.0)
	if p.visible:
		_float_text(p, "✅" if correct else "❌")
	var panel := _panel(pid)
	if panel:
		panel.show_result(chosen, text, correct)
		_closing[pid] = RESULT_SHOW


## Nagroda za dobrą odpowiedź: tarcza (jeśli jeszcze nie ma), gwiazdka albo zasięg +2.
func _reward(p: Node) -> String:
	var options := ["star", "range"]
	if not p.has_shield:
		options.append("shield")
	match options.pick_random():
		"shield":
			p.apply_powerup("shield")
			return BbI18n.t("bb.fq.reward_shield", "✅ Tarcza!")
		"star":
			p.apply_powerup("star")
			return BbI18n.t("bb.fq.reward_star", "✅ Gwiazdka!")
		_:
			p.apply_powerup("range_up")
			p.apply_powerup("range_up")
			return BbI18n.t("bb.fq.reward_range", "✅ Zasięg +2!")


## ✅ / ❌ nad postacią — widać też wynik botów.
func _float_text(p: Node2D, text: String) -> void:
	var parent := p.get_parent()
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 34)
	label.z_index = 10
	parent.add_child(label)
	label.global_position = p.global_position + Vector2(-18, -80)
	var tw := label.create_tween().set_parallel()
	tw.tween_property(label, "position:y", label.position.y - 40.0, 1.1)
	tw.tween_property(label, "modulate:a", 0.0, 1.1).set_delay(0.4)
	tw.chain().tween_callback(label.queue_free)


func _panel(pid: int) -> Control:
	if hud == null or GameManager.is_bot_id(pid):
		return null
	return hud.get_quiz_panel(pid)
