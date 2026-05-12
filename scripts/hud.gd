extends CanvasLayer

@onready var _lbl_p1_bombs  : Label = $HBoxHUD/P1Info/LblBombs
@onready var _lbl_p1_range  : Label = $HBoxHUD/P1Info/LblRange
@onready var _lbl_p1_lives  : Label = $HBoxHUD/P1Info/LblLives
@onready var _lbl_p2_bombs  : Label = $HBoxHUD/P2Info/LblBombs
@onready var _lbl_p2_range  : Label = $HBoxHUD/P2Info/LblRange
@onready var _lbl_p2_lives  : Label = $HBoxHUD/P2Info/LblLives
@onready var _lbl_round     : Label = $HBoxHUD/LblRound


func _ready() -> void:
	UIScaleManager.scale_changed.connect(_on_scale_changed)
	_on_scale_changed(UIScaleManager.scale_factor)


func _on_scale_changed(_s: float) -> void:
	var fs := UIScaleManager.px(24)
	for lbl in [_lbl_p1_bombs, _lbl_p1_range, _lbl_p1_lives,
				_lbl_p2_bombs, _lbl_p2_range, _lbl_p2_lives, _lbl_round]:
		if is_instance_valid(lbl):
			lbl.add_theme_font_size_override("font_size", fs)


func update_player(player_idx: int, bombs: int, range_val: int, lives: int) -> void:
	if player_idx == 0:
		_lbl_p1_bombs.text = "Bomby: %d" % bombs
		_lbl_p1_range.text = "Zasięg: %d" % range_val
		_lbl_p1_lives.text = "Życia: %d" % lives
	else:
		_lbl_p2_bombs.text = "Bomby: %d" % bombs
		_lbl_p2_range.text = "Zasięg: %d" % range_val
		_lbl_p2_lives.text = "Życia: %d" % lives


func update_round(round_num: int) -> void:
	_lbl_round.text = "Runda %d" % round_num
