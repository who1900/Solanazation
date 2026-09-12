extends Control
class_name TechTreeView
## Horizontal era tree for portrait play. Cards expose strategy; `i` owns education.

signal research_requested(tech_id: String)
signal info_requested(tech_id: String)

const BrandTheme = preload("res://scripts/ui/BrandTheme.gd")

const CARD_SIZE := Vector2(284, 210)
const ERA_STEP := 310.0
const LANE_STEP := 250.0
const ORIGIN := Vector2(142, 72)
const BRANCH_ORDER := ["validator", "program", "transaction"]
const BRANCH_SHORT := {
	"validator": "VALIDATOR",
	"program": "PROGRAM",
	"transaction": "TRANSACTION",
}
const EXTRA_COLUMNS := {"firedancer": 4}

var _cards: Dictionary = {}
var _research_buttons: Dictionary = {}
var _state: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(ORIGIN.x + ERA_STEP * 5.0, ORIGIN.y + LANE_STEP * 3.0)
	_build_cards()
	queue_redraw()


func _build_cards() -> void:
	for tech_id in Data.TECHS:
		var td: Dictionary = Data.TECHS[tech_id]
		var column: int = int(EXTRA_COLUMNS.get(tech_id, int(td.era) - 1))
		var lane: int = BRANCH_ORDER.find(str(td.branch))
		var panel := PanelContainer.new()
		panel.name = "TechCard_%s" % tech_id
		panel.position = ORIGIN + Vector2(float(column) * ERA_STEP, float(lane) * LANE_STEP)
		panel.size = CARD_SIZE
		panel.custom_minimum_size = CARD_SIZE
		add_child(panel)
		_cards[tech_id] = panel

		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 5)
		panel.add_child(box)
		var meta := Label.new()
		meta.name = "Meta"
		meta.theme_type_variation = "ResourceLabel"
		meta.text = "ERA %s  ·  %s" % [_roman(int(td.era)), BRANCH_SHORT[td.branch]]
		meta.modulate = BrandTheme.MUTED_FOREGROUND
		box.add_child(meta)
		var title := Label.new()
		title.name = "Title"
		title.theme_type_variation = "SectionLabel"
		title.text = str(td.name)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.max_lines_visible = 2
		title.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(title)
		var effect := Label.new()
		effect.name = "Effect"
		effect.text = str(EducationData.TECHS[tech_id].card_effect)
		effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		effect.max_lines_visible = 2
		effect.modulate = BrandTheme.MUTED_FOREGROUND
		effect.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(effect)
		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", 6)
		box.add_child(actions)
		var research := Button.new()
		research.name = "Research"
		research.custom_minimum_size.y = 48.0
		research.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		research.pressed.connect(func(): research_requested.emit(tech_id))
		actions.add_child(research)
		_research_buttons[tech_id] = research
		var info := Button.new()
		info.name = "Info"
		info.text = "i"
		info.tooltip_text = "Learn the real Solana technology"
		info.custom_minimum_size = Vector2(48, 48)
		info.pressed.connect(func(): info_requested.emit(tech_id))
		actions.add_child(info)
		_refresh_card(tech_id)


func refresh() -> void:
	for tech_id in _cards:
		_refresh_card(str(tech_id))
	queue_redraw()


func _refresh_card(tech_id: String) -> void:
	if not _cards.has(tech_id) or Game.tech == null:
		return
	var panel: PanelContainer = _cards[tech_id]
	var research: Button = _research_buttons[tech_id]
	var status := _tech_state(tech_id)
	_state[tech_id] = status
	var style: StyleBoxFlat
	match status:
		"researched":
			style = BrandTheme.panel_style(BrandTheme.ACCENT, BrandTheme.PRIMARY_SOFT, 12)
			research.text = "✓  RESEARCHED"
			research.disabled = true
		"current":
			style = BrandTheme.panel_style(BrandTheme.CARD, BrandTheme.WARNING, 0)
			var cost: int = Game.tech.research_cost(tech_id)
			research.text = "▶  ACTIVE  %d/%d" % [mini(Game.tech.points, cost), cost]
			research.disabled = true
		"available":
			style = BrandTheme.panel_style(BrandTheme.CARD, BrandTheme.PRIMARY, 4)
			research.text = "RESEARCH  ·  ◎%d" % int(Data.TECHS[tech_id].sol_cost)
			research.disabled = false
		"need_sol":
			style = BrandTheme.panel_style(BrandTheme.MUTED, BrandTheme.WARNING, 4)
			research.text = "NEEDS ◎%d" % int(Data.TECHS[tech_id].sol_cost)
			research.disabled = true
		_:
			style = BrandTheme.panel_style(BrandTheme.MUTED, BrandTheme.BORDER, 0)
			research.text = "◇  LOCKED"
			research.disabled = true
	panel.add_theme_stylebox_override("panel", style)


func _tech_state(tech_id: String) -> String:
	if Game.tech.researched.has(tech_id):
		return "researched"
	if Game.tech.current == tech_id:
		return "current"
	if Game.tech.current != "":
		return "locked"
	for required_id in Data.TECHS[tech_id].requires:
		if not Game.tech.researched.has(required_id):
			return "locked"
	if int(Game.resources.sol) < int(Data.TECHS[tech_id].sol_cost):
		return "need_sol"
	return "available"


func _draw() -> void:
	for column in range(5):
		var x := ORIGIN.x + float(column) * ERA_STEP
		draw_string(BrandTheme.GEIST_MONO_MEDIUM, Vector2(x, 30),
			_era_header(column),
			HORIZONTAL_ALIGNMENT_LEFT, CARD_SIZE.x, 16, BrandTheme.MUTED_FOREGROUND)
	for branch_index in BRANCH_ORDER.size():
		var y := ORIGIN.y + float(branch_index) * LANE_STEP - 18.0
		draw_string(BrandTheme.GEIST_SEMIBOLD, Vector2(12, y),
			BRANCH_SHORT[BRANCH_ORDER[branch_index]], HORIZONTAL_ALIGNMENT_LEFT,
			120, 14, BrandTheme.MUTED_FOREGROUND)
	for tech_id in Data.TECHS:
		for required_id in Data.TECHS[tech_id].requires:
			_draw_dependency(str(required_id), str(tech_id))


func _draw_dependency(from_id: String, to_id: String) -> void:
	if not _cards.has(from_id) or not _cards.has(to_id):
		return
	var from_panel: PanelContainer = _cards[from_id]
	var to_panel: PanelContainer = _cards[to_id]
	var start := from_panel.position + Vector2(CARD_SIZE.x, CARD_SIZE.y * 0.5)
	var finish := to_panel.position + Vector2(0, CARD_SIZE.y * 0.5)
	var midpoint := (start.x + finish.x) * 0.5
	var points := PackedVector2Array([
		start, Vector2(midpoint, start.y), Vector2(midpoint, finish.y), finish,
	])
	var edge_state: String = str(_state.get(to_id, "locked"))
	var color := BrandTheme.BORDER
	var width := 2.0
	if edge_state == "researched":
		color = BrandTheme.PRIMARY_SOFT
		width = 4.0
	elif edge_state == "current":
		color = BrandTheme.WARNING
		width = 4.0
	elif edge_state in ["available", "need_sol"]:
		color = BrandTheme.PRIMARY
		width = 3.0
	if edge_state == "locked":
		for segment in range(points.size() - 1):
			draw_dashed_line(points[segment], points[segment + 1], color, width, 8.0)
	else:
		draw_polyline(points, color, width, true)


func _roman(value: int) -> String:
	return ["", "I", "II", "III", "IV"][clampi(value, 1, 4)]


func _era_header(column: int) -> String:
	if column == 4:
		return "ERA IV · CONTINUED"
	var era := clampi(column + 1, 1, 4)
	return "ERA %s · %s" % [_roman(era), EducationData.ERA_NAMES[era]]
