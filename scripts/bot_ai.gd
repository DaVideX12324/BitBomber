## bot_ai.gd
## Kompletny system AI wzorowany 1:1 na BombIt7 (ActionScript → GDScript).
## Architektura: AIController (skanowanie) + AIEngine (FSM) + AIAction (executor A*)
## Stany (priorytety jak w BombIt): Escape > Attack > GetItem > Box > Idle
##
## Wymagane API areny (Node2D):
##   is_solid(cell: Vector2i) -> bool
##   is_breakable(cell: Vector2i) -> bool
##   has_powerup(cell: Vector2i) -> bool
##   GRID_SIZE : int, COLS : int, ROWS : int
##
## Wymagane API gracza (CharacterBody2D / player.gd):
##   get_grid_pos() -> Vector2i
##   _move_grid(dir: Vector2i) -> void
##   _place_bomb() -> void
##   _active_bombs : int
##   max_bombs     : int
##   bomb_range    : int
##   is_alive      : bool

extends RefCounted
class_name BotAI

# ---------------------------------------------------------------------------
# Stałe trudności
# ---------------------------------------------------------------------------
enum Difficulty { EASY = 0, MEDIUM = 1, HARD = 2 }

const FIND_RANGE_BY_DIFF  : Array[int]   = [3,  5,  7]
const ANSWER_TIME_BY_DIFF : Array[float] = [0.5, 0.25, 0.1]

# ---------------------------------------------------------------------------
# Wewnętrzne klasy
# ---------------------------------------------------------------------------

## ---- A* Pathfinder (RoadSearch.as) ----------------------------------------
class Pathfinder:
	var _w   : int
	var _h   : int
	var _arena  # referencja do areny

	# Node pool: _nodes[x][y] = {g, f, px, py, open, closed}
	var _nodes : Array

	func setup(arena, w: int, h: int) -> void:
		_arena = arena; _w = w; _h = h
		_nodes = []
		for x in range(w):
			_nodes.append([])
			for _y in range(h):
				_nodes[x].append({"g":0,"f":0,"px":-1,"py":-1,"open":false,"closed":false})

	func _reset() -> void:
		for x in range(_w):
			for y in range(_h):
				var n : Dictionary = _nodes[x][y]
				n.g=0; n.f=0; n.px=-1; n.py=-1; n.open=false; n.closed=false

	## Zwraca {"path":[[x,y],...], "cost":int}  |  cost -1 = brak ścieżki  |  cost -2 = już na celu
	func find(sx:int, sy:int, ex:int, ey:int) -> Dictionary:
		if sx==ex and sy==ey:
			return {"path":[[ex,ey]],"cost":-2}
		_reset()
		var open_list : Array = []
		var sn = _nodes[sx][sy]
		sn.g=0; sn.f=_h(sx,sy,ex,ey); sn.open=true
		open_list.append([sx,sy])
		const DIRS := [[1,0],[-1,0],[0,1],[0,-1]]
		while open_list.size() > 0:
			# liniowy wybór min-f (jak BombIt — bez kolejki priorytetowej)
			var bi : int = 0
			for i in range(1, open_list.size()):
				if _nodes[open_list[i][0]][open_list[i][1]].f < _nodes[open_list[bi][0]][open_list[bi][1]].f:
					bi = i
			var cur := open_list[bi]
			var cx:int=cur[0]; var cy:int=cur[1]
			open_list.remove_at(bi)
			_nodes[cx][cy].open=false; _nodes[cx][cy].closed=true
			for d in DIRS:
				var nx:int=cx+d[0]; var ny:int=cy+d[1]
				if nx<0 or nx>=_w or ny<0 or ny>=_h: continue
				# ZMIEŃ_TO jeśli chcesz żeby AI omijało bomby jako blokady
				if _arena.is_solid(Vector2i(nx,ny)) or _arena.is_breakable(Vector2i(nx,ny)): continue
				var nn = _nodes[nx][ny]
				if nn.closed: continue
				if nx==ex and ny==ey:
					nn.px=cx; nn.py=cy
					return _reconstruct(sx,sy,ex,ey)
				var ng:int=_nodes[cx][cy].g+1
				if not nn.open:
					nn.g=ng; nn.f=ng+_h(nx,ny,ex,ey); nn.px=cx; nn.py=cy; nn.open=true
					open_list.append([nx,ny])
				elif ng < nn.g:
					nn.g=ng; nn.f=ng+_h(nx,ny,ex,ey); nn.px=cx; nn.py=cy
			return {"path":[],"cost":-1}
		return {"path":[],"cost":-1}

	func _h(x:int,y:int,ex:int,ey:int) -> int:
		return abs(x-ex)+abs(y-ey)

	func _reconstruct(sx:int, sy:int, ex:int, ey:int) -> Dictionary:
		var path : Array = []
		var cx:int=ex; var cy:int=ey; var cost:int=0
		while not (cx==sx and cy==sy):
			path.append([cx,cy])
			var prev_x:int=_nodes[cx][cy].px
			var prev_y:int=_nodes[cx][cy].py
			cx=prev_x; cy=prev_y; cost+=1
		path.reverse()
		return {"path":path,"cost":cost}


## ---- Action (Action.as) — executor ścieżki krok po kroku ----------------
class Action:
	const STUCK_LIMIT : int = 40

	var aim_x      : int = -1
	var aim_y      : int = -1
	var next_step  : Array = []
	var path_cost  : int = 0

	var _ctrl      # AIController
	var _step      : int = 0
	var _path      : Array = []
	var _end_x     : int = -1
	var _end_y     : int = -1
	var _cur_dir   : Vector2i = Vector2i.ZERO
	var _stuck     : int = 0
	var _on_arrive : Callable
	var _on_step   : Callable
	var _on_cancel : Callable
	var _active    : bool = false

	func setup(ctrl) -> void:
		_ctrl = ctrl

	## Główna metoda — zleca przejście do (tx,ty).
	## Zwraca false jeśli cel w danger_map lub A* nie znalazł ścieżki.
	func set_action(tx:int, ty:int, on_arrive:Callable, on_step:Callable, on_cancel:Callable) -> bool:
		if _ctrl.is_danger(tx, ty, 60):
			return false
		_on_arrive=on_arrive; _on_step=on_step; _on_cancel=on_cancel
		_end_x=tx; _end_y=ty
		var gp := _ctrl._player.get_grid_pos()
		if gp.x==tx and gp.y==ty:
			_deferred(on_arrive); return true
		return _start_move(tx, ty)

	func _start_move(tx:int, ty:int) -> bool:
		stop(); _step=0; _path=[]; _stuck=0
		var gp  := _ctrl._player.get_grid_pos()
		var res := _ctrl._pf.find(gp.x, gp.y, tx, ty)
		_path    = res.get("path", [])
		path_cost = res.get("cost", -1)
		if _path.size() > 0:
			_active = true
			_step_to_next()
			return true
		return false

	## Wywoływane każdą klatką przez AIController.think()
	func tick() -> void:
		if not _active or _path.is_empty():
			return
		var gp := _ctrl._player.get_grid_pos()
		if gp.x == aim_x and gp.y == aim_y:
			_stuck = 0
			if gp.x == _end_x and gp.y == _end_y:
				_active = false; _path = []
				_ctrl._player._move_grid(Vector2i.ZERO)  # stop
				_deferred(_on_arrive)
			else:
				_step_to_next()
		else:
			_stuck += 1
			if _stuck > STUCK_LIMIT:
				cancel()

	func _step_to_next() -> void:
		if _step >= _path.size():
			return
		var gp  := _ctrl._player.get_grid_pos()
		var tx  : int = _path[_step][0]
		var ty  : int = _path[_step][1]
		_cur_dir = Vector2i(tx - gp.x, ty - gp.y).sign()
		aim_x = tx; aim_y = ty
		if _step + 1 < _path.size():
			next_step = [_path[_step+1][0], _path[_step+1][1]]
		else:
			next_step = []
		_ctrl._player._move_grid(_cur_dir)
		if _on_step.is_valid(): _on_step.call()
		_step += 1

	func stop() -> void:
		_active=false; _stuck=0; _path=[]

	func cancel() -> void:
		stop()
		if _on_cancel.is_valid(): _deferred(_on_cancel)

	func _deferred(cb: Callable) -> void:
		if cb.is_valid():
			Engine.get_main_loop().process_frame.connect(func(): cb.call(), CONNECT_ONE_SHOT)


# ---------------------------------------------------------------------------
# AIController — skanuje świat (updateSense z BombIt7)
# ---------------------------------------------------------------------------
var _player   # CharacterBody2D (player.gd)
var _arena    # Node2D (arena.gd)
var _pf       : Pathfinder
var _action   : Action
var _engine   # _FSM
var _diff     : int
var _find_range  : int   = 5
var _answer_time : float = 0.25
var _time_acc    : float = 0.0

# Dane o świecie — odświeżane przez _sense()
var free_arr    : Array = []
var box_arr     : Array = []
var prop_arr    : Array = []
var bomb_arr    : Array = []  # węzły bomb (grupa "bomb")
var enemy_arr   : Array = []  # [[x,y]]
var danger_map  : Dictionary = {}  # Vector2i → risk (int 0..99; brak wpisu = bezpieczne)
var danger_arr  : Array = []       # [[x,y,risk]]

func setup(player, arena, difficulty: int) -> void:
	_player = player
	_arena  = arena
	_diff   = difficulty
	_find_range  = FIND_RANGE_BY_DIFF[difficulty]
	_answer_time = ANSWER_TIME_BY_DIFF[difficulty]
	_pf     = Pathfinder.new()
	# ZMIEŃ_TO jeśli arena nie ma COLS/ROWS — podaj szerokość i wysokość gridu
	_pf.setup(arena, arena.COLS, arena.ROWS)
	_action = Action.new()
	_action.setup(self)
	_engine = _FSM.new()
	_engine.setup(self)

## Wywoływane przez player.gd: _ai.think(delta)
func think(delta: float) -> void:
	if not _player.is_alive:
		return
	_action.tick()
	_time_acc += delta
	if _time_acc >= _answer_time:
		_time_acc = 0.0
		_sense()
		_engine.update()

## Skanowanie terenu — 4 kierunki × find_range kratek
func _sense() -> void:
	var gp   := _player.get_grid_pos()
	var rx   : int = gp.x
	var ry   : int = gp.y

	var new_free  : Array = []
	var new_box   : Array = []
	var new_prop  : Array = []
	var new_enemy : Array = []
	var new_dmap  : Dictionary = {}
	var new_darr  : Array = []

	const DIRS := [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]
	for d in DIRS:
		for dist in range(1, _find_range):
			var sx : int = rx + d.x * dist
			var sy : int = ry + d.y * dist
			var cell := Vector2i(sx, sy)
			if sx<0 or sx>=_arena.COLS or sy<0 or sy>=_arena.ROWS:
				break
			if _arena.is_solid(cell):
				break
			if _arena.is_breakable(cell):
				if not new_box.any(func(b): return b[0]==sx and b[1]==sy):
					new_box.append([sx, sy])
				break
			if _arena.has_powerup(cell):
				new_prop.append([sx, sy])
			new_free.append([sx, sy])

	# Wrogowie (wszyscy gracze poza sobą)
	var tree := _player.get_tree()
	if tree:
		for p in tree.get_nodes_in_group("player"):
			if p != _player and p.is_alive:
				var ep := p.get_grid_pos()
				new_enemy.append([ep.x, ep.y])

	# Danger map — z bomb na planszy
	for bomb in tree.get_nodes_in_group("bomb") if tree else []:
		var bx  : int = int(bomb.global_position.x / _arena.GRID_SIZE)
		var by  : int = int(bomb.global_position.y / _arena.GRID_SIZE)
		# ZMIEŃ_TO jeśli Twoja bomba nie ma właściwości explosion_range / get_fuse_time_left()
		var bpow : int   = bomb.get("explosion_range") if bomb.get("explosion_range") != null else 2
		var fuse : float = bomb.get("_timer") if bomb.get("_timer") != null else 3.0
		var risk : int   = clampi(int(fuse * 20.0), 0, 99)
		_reg_danger(new_dmap, new_darr, bx, by, risk)
		const DDIRS := [[1,0],[-1,0],[0,1],[0,-1]]
		for dd in DDIRS:
			for i in range(1, bpow+1):
				var cx:int=bx+dd[0]*i; var cy:int=by+dd[1]*i
				if cx<0 or cx>=_arena.COLS or cy<0 or cy>=_arena.ROWS: break
				var dc := Vector2i(cx,cy)
				if _arena.is_solid(dc): break
				_reg_danger(new_dmap, new_darr, cx, cy, risk)
				if _arena.is_breakable(dc): break

	# Usuń niebezpieczne pola z free i prop
	new_free = new_free.filter(func(p): return not is_danger(p[0],p[1]))
	new_prop = new_prop.filter(func(p): return not is_danger(p[0],p[1]))

	free_arr   = new_free
	box_arr    = new_box
	prop_arr   = new_prop
	enemy_arr  = new_enemy
	danger_map = new_dmap
	danger_arr = new_darr

bomb_arr = []

func _reg_danger(dmap:Dictionary, darr:Array, x:int, y:int, risk:int) -> void:
	var k := Vector2i(x,y)
	if not dmap.has(k) or dmap[k] > risk:
		dmap[k] = risk
		darr.append([x,y,risk])

## is_danger(x,y,margin) — odpowiednik isInDangerMap() z BombIt7
## margin=100 → niebezpieczne jeśli risk < 100 (czyli cokolwiek)
## margin=30  → tylko jeśli zaraz wybucha
func is_danger(x:int, y:int, margin:int=100) -> bool:
	var k := Vector2i(x,y)
	if danger_map.has(k):
		return danger_map[k] < margin
	return false


# ---------------------------------------------------------------------------
# Helpers wspólne dla stanów
# ---------------------------------------------------------------------------

## Najbliższa pozycja z listy (A* cost), max_cost = 9999 = brak limitu
func best_in(list:Array, max_cost:int=9999) -> Array:
	var best:Array=[]; var bc:int=max_cost
	var gp := _player.get_grid_pos()
	for pos in list:
		var r := _pf.find(gp.x, gp.y, pos[0], pos[1])
		var c : int = r.get("cost",-1)
		if c>=0 and c<bc: bc=c; best=[pos[0],pos[1]]
	return best

## Czy można bezpiecznie postawić bombę na (x,y) i jest pole ucieczki?
func can_bomb(x:int, y:int) -> bool:
	var bpow : int = _player.bomb_range
	var blast := _blast_cells(x, y, bpow)
	for fp in free_arr:
		if [fp[0],fp[1]] in blast: continue
		var r := _pf.find(x, y, fp[0], fp[1])
		if r.get("cost",-1) >= 0: return true
	return false

func _blast_cells(bx:int,by:int,bpow:int) -> Array:
	var cells:Array=[[bx,by]]
	const DDIRS := [[1,0],[-1,0],[0,1],[0,-1]]
	for d in DDIRS:
		for i in range(1,bpow+1):
			var cx:int=bx+d[0]*i; var cy:int=by+d[1]*i
			if cx<0 or cx>=_arena.COLS or cy<0 or cy>=_arena.ROWS: break
			var dc:=Vector2i(cx,cy)
			if _arena.is_solid(dc): break
			cells.append([cx,cy])
			if _arena.is_breakable(dc): break
	return cells


# ---------------------------------------------------------------------------
# FSM — AIEngine (AIEngine.as)
# ---------------------------------------------------------------------------
class _FSM:
	var _c  # AIController
	var _states : Array
	var _cur    # _State

	func setup(ctrl) -> void:
		_c = ctrl
		# Kolejność = priorytet (jak BombIt: Escape > Attack > GetItem > Box > Idle)
		_states = [
			_StateEscape.new(ctrl),
			_StateAttack.new(ctrl),
			_StateGetItem.new(ctrl),
			_StateBox.new(ctrl),
			_StateIdle.new(ctrl),
		]
		_cur = _states[-1]
		_cur.enter()

	func update() -> void:
		var nxt = _pick()
		if nxt != _cur:
			_cur.exit(); _cur = nxt; _cur.enter()
		_cur.update()

	func _pick():
		for s in _states:
			if s.check(): return s
		return _states[-1]  # Idle jako fallback


# ---------------------------------------------------------------------------
# Stany (AbstractState.as / StateXxx.as)
# ---------------------------------------------------------------------------
class _State:
	var c        # AIController
	var done : bool = true     # actionComplete z BombIt
	var tgt  : Array = []      # targetedPosition

	func _init(ctrl) -> void: c = ctrl
	func check() -> bool:     return false
	func enter() -> void:     done = true
	func exit()  -> void:     c._action.stop()
	func update()-> void:     pass

	func _on_arrive() -> void: done = true
	func _on_step()   -> void: _guard_danger()
	func _on_cancel() -> void: done = true

	## Anuluje ruch jeśli następny krok jest w strefie wybuchu
	func _guard_danger() -> void:
		var ns := c._action.next_step
		if ns.size()==2 and c.is_danger(ns[0],ns[1],30):
			c._action.cancel()

	## Szuka sąsiada skrzynki/wroga z którego można postawić bombę
	func _adj_bomb_pos(targets:Array) -> Array:
		const DIRS:=[[1,0],[-1,0],[0,1],[0,-1]]
		var best:Array=[]; var bc:int=9999
		var gp := c._player.get_grid_pos()
		for t in targets:
			for d in DIRS:
				var px:int=t[0]+d[0]; var py:int=t[1]+d[1]
				if px<0 or px>=c._arena.COLS or py<0 or py>=c._arena.ROWS: continue
				if c._arena.is_solid(Vector2i(px,py)):    continue
				if c._arena.is_breakable(Vector2i(px,py)): continue
				if c.is_danger(px,py): continue
				if not c.can_bomb(px,py): continue
				var r := c._pf.find(gp.x,gp.y,px,py)
				var cost:int=r.get("cost",-1)
				if cost>=0 and cost<bc: bc=cost; best=[px,py]
		return best


## ---- StateEscape (StateEscape.as) ----------------------------------------
class _StateEscape extends _State:
	func _init(ctrl)->void: super._init(ctrl)

	func check() -> bool:
		var gp := c._player.get_grid_pos()
		return c.is_danger(gp.x, gp.y, 100)

	func update() -> void:
		if not done: return
		var ep := _find_escape()
		if ep.is_empty(): done=true; return
		if c._action.set_action(ep[0],ep[1], _on_arrive, _no_step, _on_cancel):
			done = false

	func _no_step() -> void: pass  # podczas ucieczki nie sprawdzamy następnego kroku

	func _find_escape() -> Array:
		var best:Array=[]; var bc:int=9999
		for fp in c.free_arr:
			var gp := c._player.get_grid_pos()
			var r  := c._pf.find(gp.x,gp.y,fp[0],fp[1])
			var cost:int=r.get("cost",-1)
			if cost>=0 and cost<bc: bc=cost; best=[fp[0],fp[1]]
		return best


## ---- StateAttack (StateAttack.as) ----------------------------------------
class _StateAttack extends _State:
	func _init(ctrl)->void: super._init(ctrl)

	func check() -> bool:
		if c.enemy_arr.is_empty(): return false
		if c._player._active_bombs >= c._player.max_bombs: return false
		if randf() > 0.8: return false
		tgt = _adj_bomb_pos(c.enemy_arr)
		return tgt.size() > 0

	func update() -> void:
		if not done: return
		if c._action.set_action(tgt[0],tgt[1], _bomb_and_done, _on_step, _on_cancel):
			done = false

	func _bomb_and_done() -> void:
		c._player._place_bomb()
		done = true


## ---- StateGetItem (StateGetItem.as) ----------------------------------------
class _StateGetItem extends _State:
	func _init(ctrl)->void: super._init(ctrl)

	func check() -> bool:
		if c.prop_arr.is_empty(): return false
		tgt = c.best_in(c.prop_arr, 200)
		return tgt.size() > 0

	func update() -> void:
		if not done: return
		if c._action.set_action(tgt[0],tgt[1], _on_arrive, _on_step, _on_cancel):
			done = false


## ---- StateBox (StateBox.as) -----------------------------------------------
class _StateBox extends _State:
	func _init(ctrl)->void: super._init(ctrl)

	func check() -> bool:
		if c.box_arr.is_empty(): return false
		if c._player._active_bombs >= c._player.max_bombs: return false
		if randf() > 0.8: return false
		tgt = _adj_bomb_pos(c.box_arr)
		return tgt.size() > 0

	func update() -> void:
		if not done: return
		if c._action.set_action(tgt[0],tgt[1], _bomb_and_done, _on_step, _on_cancel):
			done = false

	func _bomb_and_done() -> void:
		c._player._place_bomb()
		done = true


## ---- StateIdle (StateFree.as) ---------------------------------------------
class _StateIdle extends _State:
	func _init(ctrl)->void: super._init(ctrl)

	func check() -> bool:
		if randf() > 0.8: return false
		tgt = c.best_in(c.free_arr, 300)
		return tgt.size() > 0

	func update() -> void:
		if not done: return
		if c._action.set_action(tgt[0],tgt[1], _on_arrive, _on_step, _on_cancel):
			done = false
