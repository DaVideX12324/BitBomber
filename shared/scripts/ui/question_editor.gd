extends CanvasLayer

## Edytor pytań (menu główne -> Pytania), dwa ekrany: lista zestawów (przełącznik „w grze”, import, nowy zestaw) i pytania
## wybranego zestawu (szukaj / filtr typu, przełącznik „w grze”, menu „⋯” przy pytaniu i zestawu, dwuklik = edycja).
## Wiersze: sceny question_editor_set_row / question_editor_question_row; wygląd: resources/ui/question_editor_theme.tres.
## Dane: QuestionBank (user://quizzes, user://quiz_selection.json); po każdej zmianie QuizService.reload_all(), więc gra
## od razu używa nowych pytań.
## Bez autoloadów hosta w kodzie (usługi szukane w drzewie, ścieżki względne): kopia w modules/BitBomber/shared/
## (tools/sync_shared_question_editor.gd) działa też w BitBomberze uruchomionym samodzielnie — wtedy skala z
## UIScaleManager, teksty PL z resources/i18n/pl.json (QuestionBank), przeładowanie przez QuizManager.reload_all().

signal closed

const Bank = preload("../core/question_bank.gd")
const SetRowScene = preload("../../scenes/ui/question_editor_set_row.tscn")
const QuestionRowScene = preload("../../scenes/ui/question_editor_question_row.tscn")

@onready var _root: Control = $Root
@onready var _sets_page: Control = $Root/Margin/VBox/SetsPage
@onready var _title: Label = $Root/Margin/VBox/SetsPage/Header/TitleBox/Title
@onready var _btn_close: Button = $Root/Margin/VBox/SetsPage/Header/BtnClose
@onready var _btn_import: MenuButton = $Root/Margin/VBox/SetsPage/Header/BtnImport
@onready var _btn_new_set: Button = $Root/Margin/VBox/SetsPage/Header/BtnNewSet
@onready var _sets_list: VBoxContainer = $Root/Margin/VBox/SetsPage/SetsCard/Scroll/SetsList

@onready var _questions_page: Control = $Root/Margin/VBox/QuestionsPage
@onready var _btn_back: Button = $Root/Margin/VBox/QuestionsPage/Header/BtnBack
@onready var _set_name: Label = $Root/Margin/VBox/QuestionsPage/Header/TitleBox/SetName
@onready var _set_count: Label = $Root/Margin/VBox/QuestionsPage/Header/TitleBox/SetCount
@onready var _set_menu: MenuButton = $Root/Margin/VBox/QuestionsPage/Header/SetMenu
@onready var _btn_add: Button = $Root/Margin/VBox/QuestionsPage/Header/BtnAdd
@onready var _search: LineEdit = $Root/Margin/VBox/QuestionsPage/Filters/Search
@onready var _type_filter: OptionButton = $Root/Margin/VBox/QuestionsPage/Filters/TypeFilter
@onready var _q_list: VBoxContainer = $Root/Margin/VBox/QuestionsPage/QuestionsCard/Scroll/QuestionsList
@onready var _q_empty: Label = $Root/Margin/VBox/QuestionsPage/QuestionsCard/Scroll/QuestionsList/Empty
@onready var _status: Label = $Root/Margin/VBox/Status

@onready var _edit_dialog: Control = $Root/EditDialog
@onready var _dlg_panel: Control = $Root/EditDialog/Center/Panel
@onready var _dlg_title: Label = $Root/EditDialog/Center/Panel/VBox/DlgTitle
@onready var _type_option: OptionButton = $Root/EditDialog/Center/Panel/VBox/Common/TypeOption
@onready var _diff_spin: SpinBox = $Root/EditDialog/Center/Panel/VBox/Common/DiffSpin
@onready var _category_edit: LineEdit = $Root/EditDialog/Center/Panel/VBox/Common/CategoryEdit
@onready var _explanation_edit: TextEdit = $Root/EditDialog/Center/Panel/VBox/ExplanationEdit
@onready var _form: VBoxContainer = $Root/EditDialog/Center/Panel/VBox/Scroll/Form
@onready var _error: Label = $Root/EditDialog/Center/Panel/VBox/Error
@onready var _btn_save: Button = $Root/EditDialog/Center/Panel/VBox/DlgButtons/BtnSave
@onready var _btn_cancel: Button = $Root/EditDialog/Center/Panel/VBox/DlgButtons/BtnCancel

@onready var _import_dialog: FileDialog = $ImportDialog
@onready var _export_dialog: FileDialog = $ExportDialog
@onready var _confirm_dialog: ConfirmationDialog = $ConfirmDialog
@onready var _name_dialog: ConfirmationDialog = $NameDialog
@onready var _name_edit: LineEdit = $NameDialog/NameEdit
@onready var _report_dialog: AcceptDialog = $ReportDialog

const MAX_ANSWERS := 6
const MAX_PAIRS := 8
const COLOR_OK := Color(0.6, 0.85, 0.6)
const COLOR_ERR := Color(1.0, 0.5, 0.5)
const ACCENT := Color(0.35, 0.72, 1.0)

## Menu „Importuj…” i „⋯” zestawu / pytania (identyfikatory pozycji).
enum ImportItem { FILE, TEMPLATE }
enum SetItem { RENAME, EXPORT, ALL_ON, ALL_OFF, DELETE }
enum QuestionItem { EDIT, DUPLICATE, DELETE }

var _theme: Theme   # resources/ui/question_editor_theme.tres (Root.theme w scenie): warianty przycisków, karty, wiersze
var _set_id := ""
var _set: Dictionary = {}          # bieżący zestaw (kopia; zapis przez Bank.save_set)
var _edit_index := -1              # indeks edytowanego pytania w _set.questions, -1 = nowe
var _edit_original: Dictionary = {}
var _confirm_action: Callable
var _name_action: Callable
var _selected_question := -1       # podświetlony wiersz pytania (po edycji / duplikacji)

# Pola formularza bieżącego typu (budowane w _build_form).
var _f: Dictionary = {}


func _ready() -> void:
	_theme = _root.theme
	for d: Window in [_import_dialog, _export_dialog, _confirm_dialog, _name_dialog, _report_dialog]:
		d.theme = _theme
	_apply_scale()
	var scale_svc := _ui_scale()
	if scale_svc and scale_svc.has_signal("scale_changed") and not scale_svc.is_connected("scale_changed", _on_scale_changed):
		scale_svc.connect("scale_changed", _on_scale_changed)
	_update_type_dropdowns()
	_update_menus()
	_update_dialog_titles()
	var i18n := _i18n()
	if i18n and not i18n.is_connected("language_changed", _on_language_changed):
		i18n.connect("language_changed", _on_language_changed)
	_btn_close.pressed.connect(close)
	_btn_back.pressed.connect(_show_sets)
	_btn_new_set.pressed.connect(_on_new_set)
	_btn_import.get_popup().id_pressed.connect(_on_import_menu)
	_set_menu.get_popup().id_pressed.connect(_on_set_menu)
	_export_dialog.canceled.connect(func() -> void: _saving_template = false)
	_btn_add.pressed.connect(func() -> void: _open_edit(-1))
	_search.text_changed.connect(func(_text: String) -> void: _refresh_questions())
	_type_filter.item_selected.connect(func(_i: int) -> void: _refresh_questions())
	_import_dialog.file_selected.connect(_import_file)
	_import_dialog.files_selected.connect(func(paths: PackedStringArray) -> void:
		for p in paths:
			_import_file(p))
	_export_dialog.file_selected.connect(_on_export_path)
	_confirm_dialog.confirmed.connect(func() -> void:
		if _confirm_action.is_valid():
			_confirm_action.call())
	_name_dialog.confirmed.connect(func() -> void:
		if _name_action.is_valid():
			_name_action.call(_name_edit.text.strip_edges()))
	_name_edit.text_submitted.connect(func(_text: String) -> void:
		_name_dialog.hide()
		if _name_action.is_valid():
			_name_action.call(_name_edit.text.strip_edges()))
	_type_option.item_selected.connect(func(i: int) -> void: _build_form(Bank.TYPES[i], {}))
	_btn_save.pressed.connect(_on_save_question)
	_btn_cancel.pressed.connect(func() -> void: _edit_dialog.visible = false)
	get_tree().root.files_dropped.connect(_on_files_dropped)


func open() -> void:
	visible = true
	_edit_dialog.visible = false
	_show_sets()


func close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if _edit_dialog.visible:
			_edit_dialog.visible = false
		elif _questions_page.visible:
			_show_sets()
		else:
			close()
		get_viewport().set_input_as_handled()


func _show_sets() -> void:
	_questions_page.visible = false
	_sets_page.visible = true
	_refresh_sets()


func _open_set(id: String) -> void:
	_set_id = id
	_set = Bank.get_set(id)
	_selected_question = -1
	_search.text = ""
	_type_filter.select(0)
	_sets_page.visible = false
	_questions_page.visible = true
	_refresh_questions()


# --- Wygląd ------------------------------------------------------------------------------------------

func _on_scale_changed(_s: float) -> void:
	_apply_scale()


func _apply_scale() -> void:
	_theme.default_font_size = _px(22)
	_apply_check_icons(_px(22))
	_title.add_theme_font_size_override("font_size", _px(36))
	_set_name.add_theme_font_size_override("font_size", _px(34))
	_dlg_title.add_theme_font_size_override("font_size", _px(28))
	# okno pytania: duże, ale w granicach ekranu
	var vp := _root.get_viewport_rect().size if _root.is_inside_tree() else Vector2(1920, 1080)
	_dlg_panel.custom_minimum_size = Vector2(minf(_px(1150), vp.x * 0.94), minf(_px(780), vp.y * 0.92))


## Wyraźne pola wyboru (domyślne niezaznaczone giną na ciemnym tle): kwadrat / kółko z jasną ramką, zaznaczone —
## wypełnione kolorem akcentu; przełącznik „w grze” (CheckButton): włączony — niebieski z gałką po prawej, wyłączony —
## szara ramka z gałką po lewej.
func _apply_check_icons(size: int) -> void:
	var on := _check_icon(size, true, false)
	var off := _check_icon(size, false, false)
	var r_on := _check_icon(size, true, true)
	var r_off := _check_icon(size, false, true)
	for t in [&"Tree", &"CheckBox"]:
		_theme.set_icon(&"checked", t, on)
		_theme.set_icon(&"unchecked", t, off)
	_theme.set_icon(&"radio_checked", &"CheckBox", r_on)
	_theme.set_icon(&"radio_unchecked", &"CheckBox", r_off)
	var sw_on := _switch_icon(size, true)
	var sw_off := _switch_icon(size, false)
	for state in [&"checked", &"checked_disabled", &"checked_mirrored", &"checked_disabled_mirrored"]:
		_theme.set_icon(state, &"CheckButton", sw_on)
	for state in [&"unchecked", &"unchecked_disabled", &"unchecked_mirrored", &"unchecked_disabled_mirrored"]:
		_theme.set_icon(state, &"CheckButton", sw_off)


func _check_icon(size: int, checked: bool, round: bool) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var border := Color(0.85, 0.87, 0.95)
	var fill := ACCENT
	var c := (size - 1) * 0.5
	var b := maxf(1.5, size / 10.0)
	for y in range(size):
		for x in range(size):
			var col := Color(0, 0, 0, 0)
			if round:
				var d := Vector2(x - c, y - c).length()
				if d <= c and d > c - b:
					col = border
				elif checked and d <= c - b * 2.0:
					col = fill
			else:
				var edge := minf(minf(x, y), minf(size - 1 - x, size - 1 - y))
				if edge < b:
					col = border
				elif checked and edge >= b * 2.0:
					col = fill
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


## Przełącznik (pigułka 2:1 wysokości `size`): włączony — wypełniony akcentem, biała gałka po prawej; wyłączony — szare
## tło z jaśniejszą ramką, szara gałka po lewej.
func _switch_icon(size: int, on: bool) -> ImageTexture:
	var h := size
	var w := size * 2
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var r := (h - 1) * 0.5
	var b := maxf(1.5, h / 10.0)
	var knob_x := (w - 1) - r if on else r
	var bg := ACCENT if on else Color(0.16, 0.18, 0.24)
	var border := ACCENT if on else Color(0.45, 0.5, 0.62)
	var knob := Color.WHITE if on else Color(0.62, 0.66, 0.76)
	for y in range(h):
		for x in range(w):
			var cx := clampf(x, r, (w - 1) - r)
			var d := Vector2(x - cx, y - r).length()
			var col := Color(0, 0, 0, 0)
			if d <= r:
				col = border if d > r - b else bg
			if Vector2(x - knob_x, y - r).length() <= r - b * 2.0:
				col = knob
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


func _update_dialog_titles() -> void:
	_import_dialog.title = _t("host.question_editor.import_dlg_title")
	_export_dialog.title = _t("host.question_editor.export_dlg_title")
	_confirm_dialog.title = _t("host.question_editor.confirm_dlg_title")
	_name_dialog.title = _t("host.question_editor.name_dlg_title")
	_report_dialog.title = _t("host.question_editor.report_dlg_title")


## Pozycje menu „Importuj…” i „⋯” zestawu (tekst z i18n; „Usuń zestaw” / „Przywróć oryginał” wg źródła zestawu).
func _update_menus() -> void:
	var imp := _btn_import.get_popup()
	imp.clear()
	imp.add_item(_t("host.question_editor.menu_import_file"), ImportItem.FILE)
	imp.add_item(_t("host.question_editor.menu_template"), ImportItem.TEMPLATE)
	imp.set_item_tooltip(imp.get_item_index(ImportItem.TEMPLATE), _t("host.question_editor.template_tip"))
	var sm := _set_menu.get_popup()
	sm.clear()
	sm.add_item(_t("host.question_editor.btn_rename"), SetItem.RENAME)
	sm.add_item(_t("host.question_editor.menu_export"), SetItem.EXPORT)
	sm.add_separator()
	sm.add_item(_t("host.question_editor.menu_all_on"), SetItem.ALL_ON)
	sm.add_item(_t("host.question_editor.menu_all_off"), SetItem.ALL_OFF)
	sm.add_separator()
	var source := str(_set.get("source", ""))
	sm.add_item(_t("host.question_editor.btn_revert_original") if source == "edited" else _t("host.question_editor.btn_delete_set"), SetItem.DELETE)
	sm.set_item_disabled(sm.get_item_index(SetItem.DELETE), source == "builtin")
	if source == "builtin":
		sm.set_item_tooltip(sm.get_item_index(SetItem.DELETE), _t("host.question_editor.cannot_delete_builtin"))


func _update_type_dropdowns() -> void:
	var sel_filter := _type_filter.get_selected_id()
	_type_filter.clear()
	_type_filter.add_item(_t("host.question_editor.all_types"), 0)
	for i in range(Bank.TYPES.size()):
		_type_filter.add_item(Bank.get_type_name(Bank.TYPES[i]), i + 1)
	if sel_filter >= 0 and sel_filter < _type_filter.item_count:
		_type_filter.select(sel_filter)

	var sel_opt := _type_option.selected
	_type_option.clear()
	for i in range(Bank.TYPES.size()):
		_type_option.add_item(Bank.get_type_name(Bank.TYPES[i]), i)
	if sel_opt >= 0 and sel_opt < _type_option.item_count:
		_type_option.select(sel_opt)


func _on_language_changed(_lang: String) -> void:
	_update_type_dropdowns()
	_update_menus()
	_update_dialog_titles()
	if _questions_page.visible:
		_refresh_questions()
	else:
		_refresh_sets()


func _say(text: String, ok: bool = true) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", COLOR_OK if ok else COLOR_ERR)


## Rozmiary czcionek wiersza: wartości ze sceny wiersza (theme_override_font_sizes) przeskalowane jak reszta UI.
func _scale_row(row: Control) -> void:
	for l in row.find_children("*", "Label", true, false):
		var label := l as Label
		if label.has_theme_font_size_override("font_size"):
			label.add_theme_font_size_override("font_size", _px(label.get_theme_font_size("font_size")))


## Podświetlenie wiersza pod myszą (wariant motywu ListRowHover), zaznaczony — ListRowSelected.
func _hook_row_hover(row: PanelContainer, selected: bool) -> void:
	row.theme_type_variation = &"ListRowSelected" if selected else &"ListRow"
	row.mouse_entered.connect(func() -> void:
		if row.theme_type_variation != &"ListRowSelected":
			row.theme_type_variation = &"ListRowHover")
	row.mouse_exited.connect(func() -> void:
		if row.theme_type_variation != &"ListRowSelected":
			row.theme_type_variation = &"ListRow")


# --- Zestawy -----------------------------------------------------------------------------------------

func _refresh_sets() -> void:
	for c in _sets_list.get_children():
		_sets_list.remove_child(c)
		c.queue_free()
	var sel := Bank.load_selection()
	for s in Bank.list_sets():
		var id := str(s["id"])
		var row := SetRowScene.instantiate() as PanelContainer
		_scale_row(row)
		_sets_list.add_child(row)
		var toggle := row.get_node("HBox/Toggle") as CheckButton
		toggle.button_pressed = Bank.is_set_enabled(id, sel)
		toggle.tooltip_text = _t("host.question_editor.toggle_set_tip")
		toggle.toggled.connect(func(on: bool) -> void: _on_set_toggled(id, str(s["name"]), on))
		var name_label := row.get_node("HBox/Name") as Label
		name_label.text = str(s["name"])
		var tag: String = {"edited": _t("host.options.set_edited"), "user": _t("host.options.set_user")}.get(str(s["source"]), "")
		(row.get_node("HBox/Tag") as Label).text = tag.strip_edges()
		(row.get_node("HBox/Count") as Label).text = _tf("host.question_editor.count_short", {"count": (s["questions"] as Array).size()})
		row.tooltip_text = "%s\nid: %s" % [str(s.get("description", "")), id] if str(s.get("description", "")) != "" else "id: " + id
		_hook_row_hover(row, false)
		row.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_open_set(id))


func _on_set_toggled(id: String, set_name: String, on: bool) -> void:
	Bank.set_set_enabled(id, on)
	_reload_game()
	var status_str: String = _t("host.question_editor.status_used") if on else _t("host.question_editor.status_unused")
	_say(_tf("host.question_editor.set_status", {"name": set_name, "status": status_str}))


func _on_import_menu(id: int) -> void:
	match id:
		ImportItem.FILE:
			_import_dialog.popup_centered()
		ImportItem.TEMPLATE:
			_on_template()


func _on_set_menu(id: int) -> void:
	match id:
		SetItem.RENAME:
			_on_rename()
		SetItem.EXPORT:
			_on_export()
		SetItem.ALL_ON:
			_set_all_questions(true)
		SetItem.ALL_OFF:
			_set_all_questions(false)
		SetItem.DELETE:
			_on_delete_set()


func _on_new_set() -> void:
	_ask_name(_t("host.question_editor.btn_new_set"), "", func(name: String) -> void:
		if name == "":
			return
		var id := Bank.new_set_id(name)
		Bank.save_set(id, {"name": name, "description": "", "questions": []})
		_reload_game()
		_open_set(id)
		_say(_tf("host.question_editor.set_created", {"name": name})))


func _on_rename() -> void:
	if _set.is_empty():
		return
	_ask_name(_t("host.question_editor.rename_title"), str(_set["name"]), func(name: String) -> void:
		if name == "":
			return
		_set["name"] = name
		_save_current(_tf("host.question_editor.renamed", {"name": name})))


func _on_delete_set() -> void:
	if _set.is_empty():
		return
	var source := str(_set["source"])
	if source == "builtin":
		_say(_t("host.question_editor.cannot_delete_builtin"), false)
		return
	var name := str(_set["name"])
	var question := _tf("host.question_editor.confirm_delete", {"name": name, "count": (_set["questions"] as Array).size()})
	if source == "edited":
		question = _tf("host.question_editor.confirm_revert", {"name": name})
	_ask_confirm(question, func() -> void:
		var id := _set_id
		Bank.delete_user_file(id)
		if source == "user":
			Bank.forget_set(id)
		_reload_game()
		if source == "edited":
			_open_set(id)
		else:
			_set_id = ""
			_set = {}
			_show_sets()
		_say(_tf("host.question_editor.reverted", {"name": name}) if source == "edited" else _tf("host.question_editor.deleted", {"name": name})))


## Szablon zestawu (po jednym pytaniu każdego typu) do zapisania i wypełnienia — potem „Importuj JSON”.
const TEMPLATE_FILE := "../../resources/data/question_set_template.json"
var _saving_template := false


func _on_template() -> void:
	_saving_template = true
	_export_dialog.current_file = "szablon_pytan.json"
	_export_dialog.popup_centered()


func _on_export() -> void:
	if _set.is_empty():
		return
	_export_dialog.current_file = _set_id + ".json"
	_export_dialog.popup_centered()


func _on_export_path(path: String) -> void:
	if _saving_template:
		_saving_template = false
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(FileAccess.get_file_as_string(_local_path(TEMPLATE_FILE)))
			f.close()
			_say(_tf("host.question_editor.template_saved", {"path": path}))
		else:
			_say(_tf("host.question_editor.save_failed", {"path": path}), false)
		return
	if Bank.export_set(_set_id, path):
		_say(_tf("host.question_editor.exported_status", {"name": _set["name"], "path": path}))
	else:
		_say(_tf("host.question_editor.save_failed", {"path": path}), false)


func _on_files_dropped(files: PackedStringArray) -> void:
	if not visible:
		return
	for f in files:
		if f.to_lower().ends_with(".json"):
			_import_file(f)


func _import_file(path: String) -> void:
	var r := Bank.import_file(path)
	if not r["ok"]:
		_say(_tf("host.question_editor.import_failed_msg", {"file": path.get_file(), "error": r["error"]}), false)
		_report(_t("host.question_editor.import_failed_title"), "%s\n\n%s" % [path.get_file(), r["error"]] + _skipped_text(r["skipped"]))
		return
	_reload_game()
	_open_set(str(r["id"]))
	var skipped: Array = r["skipped"]
	var skipped_str := _tf("host.question_editor.skipped_part", {"count": skipped.size()}) if not skipped.is_empty() else ""
	_say(_tf("host.question_editor.imported_status", {"name": r["name"], "count": r["imported"], "skipped": skipped_str}))
	if not skipped.is_empty():
		_report(_t("host.question_editor.import_report_title"), _tf("host.question_editor.import_report_msg", {"count": r["imported"], "name": r["name"], "skipped": _skipped_text(skipped)}))


func _skipped_text(skipped: Array) -> String:
	if skipped.is_empty():
		return ""
	var lines := PackedStringArray()
	for s in skipped.slice(0, 20):
		lines.append(_tf("host.question_editor.skipped_item", {"index": s["index"], "reason": s["reason"]}))
	if skipped.size() > 20:
		lines.append(_tf("host.question_editor.skipped_more", {"count": skipped.size() - 20}))
	return "\n\n" + _tf("host.question_editor.skipped_header", {"count": skipped.size(), "list": "\n".join(lines)})


# --- Pytania -----------------------------------------------------------------------------------------

## Nazwa zestawu w nagłówku ekranu pytań i liczba pytań (w tym używanych w grze).
func _update_set_header() -> void:
	_btn_add.disabled = _set.is_empty()
	if _set.is_empty():
		_set_name.text = _t("host.question_editor.no_set")
		_set_count.text = ""
		return
	_set_name.text = str(_set.get("name", _set_id))
	var questions: Array = _set.get("questions", [])
	var sel := Bank.load_selection()
	var on := 0
	for q in questions:
		if Bank.is_question_enabled(_set_id, str(q.get("id", "")), sel):
			on += 1
	_set_count.text = _tf("host.question_editor.set_count", {"count": questions.size(), "on": on})


## Wiersze pytań wg szukanego tekstu i filtra typu: przełącznik „w grze”, treść, typ, trudność (●○), menu „⋯”.
## Klik zaznacza wiersz, dwuklik otwiera edycję.
func _refresh_questions() -> void:
	_update_set_header()
	_update_menus()
	for c in _q_list.get_children():
		if c != _q_empty:
			_q_list.remove_child(c)
			c.queue_free()
	var questions: Array = _set.get("questions", [])
	var sel := Bank.load_selection()
	var needle := _search.text.strip_edges().to_lower()
	var type_idx := _type_filter.get_selected_id()
	var selected_row: Control = null
	var shown := 0
	for i in range(questions.size()):
		var q: Dictionary = questions[i]
		var t := str(q.get("type", "multiple_choice"))
		if type_idx > 0 and Bank.TYPES[type_idx - 1] != t:
			continue
		var text := Bank.question_text(q)
		if needle != "" and not (text.to_lower().contains(needle) or str(q.get("category", "")).to_lower().contains(needle)):
			continue
		shown += 1
		var index := i
		var qid := str(q.get("id", ""))
		var row := QuestionRowScene.instantiate() as PanelContainer
		row.set_meta(&"index", i)
		_scale_row(row)
		_q_list.add_child(row)
		var toggle := row.get_node("HBox/Toggle") as CheckButton
		toggle.button_pressed = Bank.is_question_enabled(_set_id, qid, sel)
		toggle.tooltip_text = _t("host.question_editor.toggle_question_tip")
		toggle.toggled.connect(func(on: bool) -> void: _on_question_toggled(qid, on))
		var text_label := row.get_node("HBox/Text") as Label
		text_label.text = text.replace("\n", " ")
		var category := str(q.get("category", ""))
		text_label.tooltip_text = text + ("\n\n" + _t("host.question_editor.lbl_category") + " " + category if category != "" else "")
		(row.get_node("HBox/Chip/Type") as Label).text = Bank.get_type_name(t)
		var diff := clampi(int(q.get("difficulty", 1)), 1, 5)
		var diff_label := row.get_node("HBox/Diff") as Label
		diff_label.text = "●".repeat(diff) + "○".repeat(5 - diff)
		diff_label.tooltip_text = _t("host.question_editor.lbl_diff") + " %d / 5" % diff
		var menu := (row.get_node("HBox/Menu") as MenuButton).get_popup()
		menu.add_item(_t("host.question_editor.btn_edit"), QuestionItem.EDIT)
		menu.add_item(_t("host.question_editor.btn_duplicate"), QuestionItem.DUPLICATE)
		menu.add_separator()
		menu.add_item(_t("host.question_editor.btn_delete"), QuestionItem.DELETE)
		menu.id_pressed.connect(func(item: int) -> void: _on_question_menu(index, item))
		_hook_row_hover(row, i == _selected_question)
		if i == _selected_question:
			selected_row = row
		row.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				if e.double_click:
					_open_edit(index)
				else:
					_select_question(index))
	_q_list.move_child(_q_empty, _q_list.get_child_count() - 1)
	_q_empty.visible = shown == 0
	_q_empty.text = _t("host.question_editor.empty_set") if questions.is_empty() else _t("host.question_editor.empty_filter")
	if selected_row:
		(_q_list.get_parent() as ScrollContainer).ensure_control_visible.call_deferred(selected_row)


## Zaznaczenie wiersza (bez przebudowy listy): wiersz `index` — ListRowSelected, pozostałe — ListRow.
func _select_question(index: int) -> void:
	_selected_question = index
	var questions: Array = _set.get("questions", [])
	for row in _q_list.get_children():
		if row != _q_empty:
			row.theme_type_variation = &"ListRowSelected" if int(row.get_meta(&"index", -1)) == index else &"ListRow"
	if index >= 0 and index < questions.size():
		_say(Bank.question_text(questions[index]).left(120).replace("\n", " "))


func _on_question_toggled(question_id: String, on: bool) -> void:
	Bank.set_question_enabled(_set_id, question_id, on)
	_reload_game()
	_update_set_header()


func _on_question_menu(index: int, item: int) -> void:
	match item:
		QuestionItem.EDIT:
			_open_edit(index)
		QuestionItem.DUPLICATE:
			_on_duplicate(index)
		QuestionItem.DELETE:
			_on_delete_question(index)


func _set_all_questions(enabled: bool) -> void:
	for q in _set.get("questions", []):
		Bank.set_question_enabled(_set_id, str(q.get("id", "")), enabled)
	_reload_game()
	_refresh_questions()
	var status_str: String = _t("host.question_editor.enabled") if enabled else _t("host.question_editor.disabled")
	_say(_tf("host.question_editor.all_questions_status", {"status": status_str}))


func _on_duplicate(i: int) -> void:
	var questions: Array = _set["questions"]
	if i < 0 or i >= questions.size():
		return
	var copy: Dictionary = (questions[i] as Dictionary).duplicate(true)
	copy["id"] = Bank.next_question_id(questions, str(copy.get("type", "multiple_choice")))
	questions.insert(i + 1, copy)
	_save_current(_t("host.question_editor.duplicated_q"), i + 1)


func _on_delete_question(i: int) -> void:
	var questions: Array = _set["questions"]
	if i < 0 or i >= questions.size():
		return
	var q: Dictionary = questions[i]
	_ask_confirm(_tf("host.question_editor.confirm_delete_q", {"text": Bank.question_text(q).left(80)}), func() -> void:
		(_set["questions"] as Array).remove_at(i)
		Bank.set_question_enabled(_set_id, str(q.get("id", "")), true)  # porządek w wyborze
		_save_current(_t("host.question_editor.deleted_q"), mini(i, (_set["questions"] as Array).size() - 1)))


## Zapis bieżącego zestawu (wbudowany -> wersja edytowana w user://), odświeżenie gry i listy pytań.
func _save_current(message: String, select_question: int = -1) -> void:
	if not Bank.save_set(_set_id, _set):
		_say(_t("host.question_editor.save_set_failed"), false)
		return
	_reload_game()
	_set = Bank.get_set(_set_id)   # źródło mogło się zmienić (wbudowany -> edytowany)
	_selected_question = select_question
	_refresh_questions()
	_say(message)


## Pula pytań gry od nowa: QuizService hosta, a w BitBomberze bez hosta jego QuizManager.
func _reload_game() -> void:
	for service_name in ["QuizService", "QuizManager"]:
		var service := get_node_or_null("/root/" + service_name)
		if service and service.has_method("reload_all"):
			service.call("reload_all")
			return


# --- Usługi (bez autoloadów w kodzie — patrz nagłówek) ----------------------------------------------

func _i18n() -> Node:
	return get_node_or_null("/root/I18nService")


func _ui_scale() -> Node:
	var service := get_node_or_null("/root/UIScaleService")
	return service if service else get_node_or_null("/root/UIScaleManager")


## Ścieżka względem folderu tego skryptu (scripts/ui) — ta sama w hoście, kopiach _host/ i shared/.
func _local_path(relative: String) -> String:
	return (get_script() as Script).resource_path.get_base_dir().path_join(relative).simplify_path()


## Teksty przez I18nService, bez niego — teksty PL QuestionBank (resources/i18n/pl.json).
func _t(key: String, fallback: String = "") -> String:
	return Bank._t(key, fallback)


func _tf(key: String, args: Dictionary, fallback: String = "") -> String:
	return Bank._tf(key, args, fallback)


func _px(value: float) -> int:
	var service := _ui_scale()
	return int(service.call("px", value)) if service and service.has_method("px") else roundi(value)


# --- Okna pomocnicze ---------------------------------------------------------------------------------

func _ask_confirm(text: String, action: Callable) -> void:
	_confirm_action = action
	_confirm_dialog.dialog_text = text
	_confirm_dialog.popup_centered(Vector2i(_px(620), _px(200)))


func _ask_name(title: String, current: String, action: Callable) -> void:
	_name_action = action
	_name_dialog.title = title
	_name_edit.text = current
	_name_dialog.popup_centered(Vector2i(_px(620), _px(170)))
	_name_edit.grab_focus()
	_name_edit.select_all()


func _report(title: String, text: String) -> void:
	_report_dialog.title = title
	_report_dialog.dialog_text = text
	_report_dialog.popup_centered(Vector2i(_px(760), _px(460)))


# --- Formularz pytania -------------------------------------------------------------------------------

func _open_edit(index: int) -> void:
	if _set.is_empty():
		return
	_edit_index = index
	var questions: Array = _set["questions"]
	var q: Dictionary = (questions[index] as Dictionary).duplicate(true) if index >= 0 and index < questions.size() else {}
	_edit_original = q
	var t := str(q.get("type", "multiple_choice"))
	_dlg_title.text = _tf("host.question_editor.edit_q_title", {"id": q.get("id", "")}) if index >= 0 else _tf("host.question_editor.new_q_title", {"name": _set["name"]})
	_type_option.select(maxi(Bank.TYPES.find(t), 0))
	_diff_spin.value = int(q.get("difficulty", 1))
	_category_edit.text = str(q.get("category", ""))
	_explanation_edit.text = str(q.get("explanation", ""))
	# Pole nie tłumaczy się samo (treść gracza), więc podpowiedź ustawiamy z i18n.
	_explanation_edit.placeholder_text = _t("host.question_editor.ph_explanation")
	_build_form(t, q)
	_error.text = ""
	_edit_dialog.visible = true


func _clear_form() -> void:
	for c in _form.get_children():
		_form.remove_child(c)
		c.queue_free()
	_f = {"type": ""}


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.75, 0.78, 0.9))
	_form.add_child(l)
	return l


func _text_edit(value: String, height: int = 90) -> TextEdit:
	var te := TextEdit.new()
	te.text = value
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.custom_minimum_size = Vector2(0, _px(height))
	_form.add_child(te)
	return te


func _line_edit(value: String, placeholder: String = "") -> LineEdit:
	var le := LineEdit.new()
	le.text = value
	le.placeholder_text = placeholder
	_form.add_child(le)
	return le


func _build_form(t: String, q: Dictionary) -> void:
	_clear_form()
	_f["type"] = t
	match t:
		"multiple_choice":
			_label(_t("host.question_editor.lbl_question"))
			_f["question"] = _text_edit(str(q.get("question", "")))
			_label(_t("host.question_editor.lbl_answers_mc"))
			var box := VBoxContainer.new()
			_form.add_child(box)
			_f["answers_box"] = box
			_f["group"] = ButtonGroup.new()
			var answers: Array = q.get("answers", ["", "", "", ""])
			for i in range(answers.size()):
				_add_answer_row(str(answers[i]), i == int(q.get("correct_index", 0)))
			var add := Button.new()
			add.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			add.text = _t("host.question_editor.btn_add_answer")
			add.pressed.connect(func() -> void:
				if box.get_child_count() < MAX_ANSWERS:
					_add_answer_row("", false))
			_form.add_child(add)
		"true_false":
			_label(_t("host.question_editor.lbl_statement"))
			_f["statement"] = _text_edit(str(q.get("statement", "")))
			_label(_t("host.question_editor.lbl_correct_answer"))
			var opt := OptionButton.new()
			opt.add_item(_t("host.quiz.true"), 0)
			opt.add_item(_t("host.quiz.false"), 1)
			opt.select(0 if bool(q.get("correct_answer", true)) else 1)
			opt.custom_minimum_size = Vector2(_px(220), 0)
			opt.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			_form.add_child(opt)
			_f["correct"] = opt
		"fill_text":
			_label(_t("host.question_editor.lbl_question"))
			_f["prompt"] = _text_edit(str(q.get("prompt", "")))
			_label(_t("host.question_editor.lbl_answer"))
			_f["answer"] = _line_edit(str(q.get("answer", "")))
			_label(_t("host.question_editor.lbl_accepted_alts"))
			_f["alts"] = _line_edit(", ".join(PackedStringArray((q.get("accepted_alternatives", []) as Array).map(func(x): return str(x)))), _t("host.question_editor.alts_placeholder"))
			_label(_t("host.question_editor.lbl_hint_pattern"))
			_f["pattern"] = _line_edit(str(q.get("prefilled_pattern", "")))
			var cs := CheckBox.new()
			cs.text = _t("host.question_editor.case_sensitive")
			cs.button_pressed = bool(q.get("case_sensitive", false))
			_form.add_child(cs)
			_f["case"] = cs
		"fill_tiles":
			_label(_tf("host.question_editor.lbl_gaps", {"gap": Bank.GAP_MARK}))
			var te := _text_edit(str(q.get("text_with_gaps", "")))
			_f["text"] = te
			_label(_t("host.question_editor.lbl_gap_answers"))
			var gaps_box := VBoxContainer.new()
			_form.add_child(gaps_box)
			_f["gaps_box"] = gaps_box
			var corrects: Array = []
			for g in q.get("gaps", []):
				corrects.append(str(g.get("correct", "")))
			_f["gap_values"] = corrects
			_rebuild_gap_rows()
			te.text_changed.connect(_rebuild_gap_rows)
			_label(_t("host.question_editor.lbl_extra_tiles"))
			var extras: Array = []
			for tile in q.get("tiles", []):
				if not corrects.has(str(tile)):
					extras.append(str(tile))
			_f["extras"] = _line_edit(", ".join(PackedStringArray(extras)), _t("host.question_editor.extras_placeholder"))
		"matching":
			_label(_t("host.question_editor.lbl_matching_pairs"))
			var pairs_box := VBoxContainer.new()
			_form.add_child(pairs_box)
			_f["pairs_box"] = pairs_box
			var left: Array = q.get("left_items", [])
			var right: Array = q.get("right_items", [])
			var pairs: Array = q.get("pairs", [])
			if pairs.is_empty():
				for i in range(3):
					_add_pair_row("", "")
			for p in pairs:
				var li := int(p.get("left_index", -1))
				var ri := int(p.get("right_index", -1))
				_add_pair_row(str(left[li]) if li >= 0 and li < left.size() else "", str(right[ri]) if ri >= 0 and ri < right.size() else "")
			var add := Button.new()
			add.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			add.text = _t("host.question_editor.btn_add_pair")
			add.pressed.connect(func() -> void:
				if pairs_box.get_child_count() < MAX_PAIRS:
					_add_pair_row("", ""))
			_form.add_child(add)


func _add_answer_row(text: String, correct: bool) -> void:
	var box: VBoxContainer = _f["answers_box"]
	var row := HBoxContainer.new()
	var radio := CheckBox.new()
	radio.button_group = _f["group"]
	radio.button_pressed = correct
	radio.tooltip_text = _t("host.question_editor.tooltip_correct")
	var le := LineEdit.new()
	le.text = text
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.placeholder_text = _t("host.question_editor.placeholder_answer")
	var del := Button.new()
	del.theme_type_variation = &"GhostButton"
	del.text = "✕"
	del.tooltip_text = _t("host.question_editor.tooltip_delete_answer")
	del.pressed.connect(func() -> void:
		if box.get_child_count() > 2:
			box.remove_child(row)
			row.queue_free())
	row.add_child(radio)
	row.add_child(le)
	row.add_child(del)
	box.add_child(row)


func _add_pair_row(left: String, right: String) -> void:
	var box: VBoxContainer = _f["pairs_box"]
	var row := HBoxContainer.new()
	var l := LineEdit.new()
	l.text = left
	l.placeholder_text = _t("host.question_editor.placeholder_left")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var arrow := Label.new()
	arrow.text = "↔"
	var r := LineEdit.new()
	r.text = right
	r.placeholder_text = _t("host.question_editor.placeholder_right")
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var del := Button.new()
	del.theme_type_variation = &"GhostButton"
	del.text = "✕"
	del.pressed.connect(func() -> void:
		if box.get_child_count() > 2:
			box.remove_child(row)
			row.queue_free())
	for c: Control in [l, arrow, r, del]:
		row.add_child(c)
	box.add_child(row)


## Wiersze luk = liczba „___” w tekście (wartości zachowane przy zmianie tekstu).
func _rebuild_gap_rows() -> void:
	var box: VBoxContainer = _f["gaps_box"]
	var values: Array = _f.get("gap_values", [])
	for i in range(box.get_child_count()):
		var le := box.get_child(i).get_child(1) as LineEdit
		if i < values.size():
			values[i] = le.text
		else:
			values.append(le.text)
	var count := (_f["text"] as TextEdit).text.count(Bank.GAP_MARK)
	if count == box.get_child_count():
		return
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	for i in range(count):
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = _tf("host.question_editor.lbl_gap_num", {"n": i + 1})
		l.custom_minimum_size = Vector2(_px(90), 0)
		var le := LineEdit.new()
		le.text = str(values[i]) if i < values.size() else ""
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(le)
		box.add_child(row)
	_f["gap_values"] = values


func _split_list(text: String) -> Array:
	var out: Array = []
	for part in text.split(","):
		var p := part.strip_edges()
		if p != "" and not out.has(p):
			out.append(p)
	return out


## Pytanie z formularza (pola innych typów usunięte; pozostałe pola oryginału zachowane).
func _question_from_form() -> Dictionary:
	var t: String = _f["type"]
	var q: Dictionary = _edit_original.duplicate(true) if str(_edit_original.get("type", "")) == t else {}
	for k in ["question", "answers", "correct_index", "statement", "correct_answer", "prompt", "answer",
			"accepted_alternatives", "prefilled_pattern", "case_sensitive", "text_with_gaps", "gaps", "tiles",
			"left_items", "right_items", "pairs"]:
		q.erase(k)
	q["id"] = str(_edit_original.get("id", "")) if _edit_index >= 0 else Bank.next_question_id(_set["questions"], t)
	q["type"] = t
	q["difficulty"] = int(_diff_spin.value)
	q["category"] = _category_edit.text.strip_edges()
	match t:
		"multiple_choice":
			q["question"] = (_f["question"] as TextEdit).text.strip_edges()
			var answers: Array = []
			var correct := -1
			for row in (_f["answers_box"] as VBoxContainer).get_children():
				if (row.get_child(0) as CheckBox).button_pressed:
					correct = answers.size()
				answers.append((row.get_child(1) as LineEdit).text.strip_edges())
			q["answers"] = answers
			q["correct_index"] = correct
		"true_false":
			q["statement"] = (_f["statement"] as TextEdit).text.strip_edges()
			q["correct_answer"] = (_f["correct"] as OptionButton).selected == 0
		"fill_text":
			q["prompt"] = (_f["prompt"] as TextEdit).text.strip_edges()
			var answer := (_f["answer"] as LineEdit).text.strip_edges()
			q["answer"] = answer
			var alts := _split_list((_f["alts"] as LineEdit).text)
			if not alts.is_empty():
				q["accepted_alternatives"] = alts
			var pattern := (_f["pattern"] as LineEdit).text.strip_edges()
			if pattern == "" and answer.length() >= 3:
				pattern = answer.left(1) + "_".repeat(answer.length() - 2) + answer.right(1)
			q["prefilled_pattern"] = pattern
			q["case_sensitive"] = (_f["case"] as CheckBox).button_pressed
		"fill_tiles":
			q["text_with_gaps"] = (_f["text"] as TextEdit).text.strip_edges()
			var gaps: Array = []
			var tiles: Array = []
			var box: VBoxContainer = _f["gaps_box"]
			for i in range(box.get_child_count()):
				var v := (box.get_child(i).get_child(1) as LineEdit).text.strip_edges()
				gaps.append({"index": i, "correct": v})
				if v != "" and not tiles.has(v):
					tiles.append(v)
			for extra in _split_list((_f["extras"] as LineEdit).text):
				if not tiles.has(extra):
					tiles.append(extra)
			tiles.shuffle()
			q["gaps"] = gaps
			q["tiles"] = tiles
		"matching":
			var lefts: Array = []
			var rights: Array = []
			for row in (_f["pairs_box"] as VBoxContainer).get_children():
				var l := (row.get_child(0) as LineEdit).text.strip_edges()
				var r := (row.get_child(2) as LineEdit).text.strip_edges()
				if l == "" and r == "":
					continue
				lefts.append(l)
				rights.append(r)
			var order: Array = range(rights.size())
			order.shuffle()
			var right_items: Array = []
			for idx in order:
				right_items.append(rights[idx])
			var pairs: Array = []
			for i in range(lefts.size()):
				pairs.append({"left_index": i, "right_index": order.find(i)})
			q["left_items"] = lefts
			q["right_items"] = right_items
			q["pairs"] = pairs
	if q["category"] == "":
		q.erase("category")
	# Wyjaśnienie wspólne dla typów (zostaje przy zmianie typu); puste = bez klucza w JSON.
	var explanation := _explanation_edit.text.strip_edges()
	if explanation == "":
		q.erase("explanation")
	else:
		q["explanation"] = explanation
	return q


func _on_save_question() -> void:
	var q := _question_from_form()
	var err := Bank.validate_question(q)
	if err != "":
		_error.text = _tf("host.question_editor.cannot_save_error", {"err": err})
		return
	var questions: Array = _set["questions"]
	var index := _edit_index
	if index >= 0 and index < questions.size():
		questions[index] = q
	else:
		questions.append(q)
		index = questions.size() - 1
	_edit_dialog.visible = false
	_save_current(_tf("host.question_editor.saved_q", {"text": Bank.question_text(q).left(60)}), index)
