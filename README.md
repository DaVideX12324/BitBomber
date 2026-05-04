# 💣 BitBomber

BitBomber to gra w stylu Bombermana stworzona w **Godot 4** jako samodzielny projekt oraz osadzalny moduł edukacyjny (plug-and-play) dla systemu [Artefakt Wiedzy](https://github.com/DaVideX12324/Artefakt-Wiedzy).

Gracze (i boty) kładą bomby, niszczą skrzynki, zbierają power-upy i rywalizują o wygraną. Po śmierci gracza aktywuje się tryb **Last Chance** — krótki quiz, który daje szansę na respawn.

---

## 🎮 Funkcje

- Tryb **1 gracz vs bot** oraz **2 graczy lokalnie**
- **3 poziomy trudności bota** (Easy / Medium / Hard) z odrębnym zachowaniem AI
- System **Last Chance Quiz** — odpowiedz poprawnie, żeby wrócić do gry
- Tryb **pojedynku quizowego** między dwoma graczami (Versus)
- Power-upy: zwiększenie zasięgu bomby, liczby bomb, prędkości
- System rund — wygrywa ten, kto jako pierwszy zbierze wymaganą liczbę zwycięstw
- Obsługa **trybu embedded** — BitBomber może działać jako moduł wewnątrz innej aplikacji Godot

---

## 🧠 Architektura AI

Bot korzysta z autorskiego systemu FSM (`BombItAI`) z pięcioma stanami:

| Stan | Opis |
|------|------|
| `IDLE` | Bot czeka lub wykonuje losowy bezpieczny krok |
| `ESCAPE` | Ucieczka przed eksplozją (BFS do bezpiecznej kratki) |
| `ATTACK` | Atak na przeciwnika (A* + symulacja zasięgu bomby) |
| `BOX` | Niszczenie skrzynek w pobliżu |
| `GET_ITEM` | Zbieranie power-upów |

AI używa **Godot `AStarGrid2D`** do pathfindingu oraz **BFS** do wykrywania bezpiecznych cel. Każda decyzja bota uwzględnia aktualną `danger_map` obliczaną na podstawie aktywnych bomb i eksplozji.

---

## 🗂️ Struktura projektu

```
BitBomber/
├── autoloads/          # Singletony: GameManager, RoundManager, QuizManager
├── scenes/
│   ├── maps/           # Sceny aren
│   └── menus/          # Menu główne, UI
├── scripts/
│   ├── arena.gd        # Logika mapy (siatka, skrzynki, spawny)
│   ├── bomb.gd         # Zachowanie bomby i eksplozji
│   ├── bot_ai.gd       # System AI bota (FSM + A* + BFS)
│   ├── BitBomberModule.gd  # API trybu embedded
│   ├── death_screen.gd # Overlay śmierci / końca rundy / quizu
│   ├── explosion.gd    # Obszar eksplozji
│   ├── game.gd         # Persistentny root gry (zarządza mapą i graczami)
│   ├── game_manager.gd # Globalny menedżer stanów gry
│   ├── hud.gd          # HUD (życia, wyniki, ikony)
│   ├── main_menu.gd    # Logika menu głównego
│   ├── pause_menu.gd   # Menu pauzy
│   ├── player.gd       # Logika gracza (ruch, bomby, życia, last chance)
│   ├── powerup.gd      # Power-upy
│   ├── quiz_overlay.gd # Nakładka quizowa (DUEL / VERSUS)
│   └── room_base.gd    # Bazowa klasa mapy
└── resources/          # Dane quizów (JSON), style, motywy
```

---

## 🔌 Tryb Embedded (Artefakt Wiedzy)

BitBomber może działać jako osadzony moduł w innej aplikacji Godot. W trybie standalone zachowuje się identycznie jak normalna gra.

### Integracja:

```gdscript
var bb = preload("res://scripts/BitBomberModule.gd").new()
add_child(bb)
bb.exit_requested.connect(_on_bb_exit)
bb.session_finished.connect(_on_bb_done)
bb.start_session({
    "players":      1,
    "bots":         1,
    "rounds_to_win": 3,
    "difficulty":   1   # 0=Easy, 1=Medium, 2=Hard
})
```

### Sygnały modułu:

| Sygnał | Opis |
|--------|------|
| `exit_requested` | Gracz wcisnął "Menu główne" — host decyduje co dalej |
| `session_finished(result)` | Sesja zakończona, `result` zawiera `winner_id`, `rounds_p1`, `rounds_p2` |

---

## 🛠️ Wymagania

- **Godot 4.3+**
- Brak zewnętrznych zależności

---

## 🚧 Roadmap

- [ ] Więcej aren
- [ ] Power-up: tarcza / freeze
- [ ] Obsługa pytań dostarczanych przez hosta (tryb embedded)
- [ ] Eksport na Android
- [ ] Wyniki i statystyki sesji

---

## 👤 Autor

Projekt tworzony przez **DaVideX** jako część systemu Artefakt Wiedzy.
