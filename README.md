# 💣 BitBomber

BitBomber to gra w stylu Bombermana stworzona w **Godot 4** jako samodzielny projekt oraz osadzalny moduł edukacyjny (plug-and-play) dla platformy [Artefakt Wiedzy](https://github.com/DaVideX12324/Artefakt-Wiedzy-modular) (w hoście leży jako submoduł `modules/BitBomber`).

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
├── module_manifest.json    # Rejestracja modułu w hoście (id, entry_scene, opis sterowania dla opcji hosta)
├── module_root.tscn/.gd    # Cienki wrapper modułu: otwiera scenę gry, rejestruje akcje wejścia, request_exit()
├── project.godot.off       # Konfiguracja projektu do uruchomienia samodzielnego (zmień nazwę na project.godot)
├── autoloads/              # GameManager, RoundManager, SpriteLoader (także w hoście) + Quiz/Settings/UIScale/WindowManager (tylko samodzielnie)
├── scenes/
│   ├── game.tscn           # Persistentny root gry
│   ├── maps/               # Sceny aren
│   ├── objects/            # Bomba, eksplozja, power-up
│   ├── players/            # Gracz
│   └── ui/                 # Menu główne, pauza, opcje, HUD, ekran śmierci, nakładka quizu
├── scripts/
│   ├── arena.gd            # Logika mapy (siatka, skrzynki, spawny)
│   ├── bomb.gd, explosion.gd, powerup.gd
│   ├── bot_ai.gd           # System AI bota (FSM + A* + BFS)
│   ├── bb_runtime.gd       # Ścieżki modułu: res://modules/BitBomber/… w hoście, res://… samodzielnie
│   ├── game.gd, game_settings.gd
│   ├── player.gd           # Ruch, bomby, życia, last chance
│   ├── hud.gd, main_menu.gd, options_menu.gd, pause_menu.gd, death_screen.gd, quiz_overlay.gd
├── resources/              # Quizy (JSON), fonty (kopia fontów hosta, ukryta .gdignore), ikona
└── shaders/                # Shader bomby
```

---

## 🔌 Tryb Embedded (Artefakt Wiedzy)

BitBomber jest modułem platformy [Artefakt Wiedzy](https://github.com/DaVideX12324/Artefakt-Wiedzy-modular): host znajduje
go po `module_manifest.json`, ładuje `module_root.tscn` i wywołuje `embedded_start(host_api, manifest)`.
Samodzielnie ta sama gra działa jako zwykły projekt Godota (`project.godot.off` → `project.godot`).

- **Wyjście do hosta:** `module_root.gd` — `request_exit()` woła `host_api.request_exit()`, a bez hosta emituje sygnał
  `exit_requested`.
- **Ścieżki:** przez `BBRuntime.path("…")` (`scripts/bb_runtime.gd`), nigdy na twardo `res://modules/BitBomber/…`.
- **Sterowanie:** akcje wejścia rejestruje `module_root.gd`, a ich opis dla zakładki „Sterowanie” w opcjach hosta jest
  w manifeście (`controls`, `action_labels`).
- **Quizy:** samodzielnie `QuizManager` BitBombera ładuje zestawy z `resources/quizzes`; w hoście `QuizManager`,
  `SettingsManager`, `UIScaleManager` i `WindowManager` to usługi / adaptery hosta (`autoloads/compat/`), a BitBomber
  korzysta przez nie z `QuizService`.

---

## 🛠️ Wymagania

- **Godot 4.7** (projekt hosta; `project.godot.off` zapisano w 4.6 — po otwarciu w 4.7 Godot przestawi wersję)
- Brak zewnętrznych zależności

---

## 🚧 Roadmap

- [ ] Więcej aren
- [ ] Power-up: tarcza / freeze
- [ ] Obsługa pytań dostarczanych przez hosta (tryb embedded)
- [ ] Wyniki i statystyki sesji
- [ ] Konfiguracja sesji przez hosta i wynik na koniec (dawne `BitBomberModule.start_session(config)` z liczbą graczy, botów, rund i trudnością oraz sygnał `session_finished(result)` z `winner_id` i wygranymi rundami — wycofane przy przejściu na `module_root.gd`, maj 2026)

---

## 👤 Autor

Projekt tworzony przez **DaVideX** jako część systemu Artefakt Wiedzy.
