# 💣 BitBomber

BitBomber to gra w stylu Bombermana stworzona w **Godot 4** jako samodzielny projekt oraz osadzalny moduł edukacyjny (plug-and-play) dla platformy [Artefakt Wiedzy](https://github.com/DaVideX12324/Artefakt-Wiedzy-modular) (w hoście leży jako submoduł `modules/BitBomber`).

Gracze (i boty) kładą bomby, niszczą skrzynki, zbierają power-upy i rywalizują o wygraną. Po śmierci gracza aktywuje się tryb **Last Chance** — krótki quiz, który daje szansę na respawn.
Mechanika, liczby i układy map wzorowane są na **Bomb It 7** (grafika i dźwięki są własne, generowane skryptami).

---

## 🎮 Funkcje

- Tryb **1 gracz vs bot** oraz **2 graczy lokalnie**
- **3 poziomy trudności bota** (Easy / Medium / Hard) z odrębnym zachowaniem AI
- System **Last Chance Quiz** — odpowiedz poprawnie, żeby wrócić do gry
- Tryb **pojedynku quizowego** między dwoma graczami (Versus)
- Tryby gry: **Ostatni żywy** i **Zabójstwa** (Kill z Bomb It — odradzanie, pierwszy do 5 zabójstw, dogrywka)
- **28 map**: 27 układów z Bomb It 7 (9 motywów × 3 warianty, 17×15) + klasyczna 17×17; skrzynki losowane z gęstością
- **Nagła śmierć** po 3 minutach — bloki spadają spiralą od krawędzi
- Reakcja łańcuchowa bomb, kopanie bomb
- Power-upy: bomba, zasięg, szybkość, życie, kopanie, tarcza, gwiazdka (nietykalność); wagi i dorzucanie po 45 s jak w Bomb It
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

Dodatkowo:

```
├── resources/maps/         # Układy map (JSON: rows '#' stały, 'C' środek, 'b' miejsce na skrzynkę, '.' puste)
├── resources/sprites/      # Grafika (generowana): tiles/<motyw>/, players/, objects/
├── resources/sounds/       # Efekty dźwiękowe (generowane)
├── tools/
│   ├── import_bombit_maps.py  # TMX z Bomb It 7 → resources/maps/*.json
│   ├── gen_sprites.py         # Pillow → resources/sprites/ (zmiany wyglądu tutaj, nie w PNG)
│   └── gen_sounds.py          # numpy → resources/sounds/*.wav
├── tests/                  # Testy headless (uruchamiane z katalogu hosta, patrz niżej)
└── docs/zadania.md         # Lista zadań i decyzji
```

Testy: `godot --headless --path <host> --fixed-fps 60 -s res://modules/BitBomber/tests/<test>.gd`
(`test_blast`, `test_maps`, `test_items`, `test_kick_shield`, `test_kill_mode`, `test_sudden_death`, `test_scores`, `test_host_session`, `test_smoke`).

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

### Sesja z hosta

Host może uruchomić BitBombera z gotowymi ustawieniami (`ModuleHost.start_module(manifest, parent, config)`, opis
w `docs/module_contract.md` hosta). Z niepustym configiem gra startuje od razu, bez menu modułu, a „Menu główne”
po sesji wraca do hosta. Klucze (wszystkie opcjonalne):

| klucz | wartość | domyślnie |
|---|---|---|
| `humans` | 1–2 | 1 |
| `bots` | 0–3 (razem max 4 graczy, min 2) | 1 |
| `mode` | `"last_standing"` / `"kill"` | `"last_standing"` |
| `rounds_to_win` | wygrane rundy do zwycięstwa | 3 |
| `max_rounds` | zamiast `rounds_to_win`: tyle rund, wygrywa najlepszy | — |
| `kills_to_win` | zabójstwa wygrywające rundę (Kill) | 5 |
| `map` | id mapy z `resources/maps` (`""` = losowa) | `""` |
| `difficulty` | boty 0 łatwe – 2 trudne | 0 |
| `quiz_id` | zestaw pytań | ostatni |
| `box_density` | szansa na skrzynkę | 0,7 (Kill 0,5) |

Na koniec każdej sesji (także zaczętej z menu modułu) `module_root.report_session()` oddaje hostowi wynik
(`host_api.finish_session`): `completed`, `mode`, `rounds_played`, `winner` (`id`, `name`, `is_bot`; `null` przy remisie),
`players` (per gracz: `round_wins`, `correct`, `wrong`), `answers` (suma odpowiedzi w quizach), `duration_s` i `summary`
(np. „Gracz 1 wygrał · rundy: 4 · quiz 3/5”), który menu hosta pokazuje jako „Ostatnio: …”.

---

## 🛠️ Wymagania

- **Godot 4.7** (projekt hosta; `project.godot.off` zapisano w 4.6 — po otwarciu w 4.7 Godot przestawi wersję)
- Brak zewnętrznych zależności

---

## 🚧 Roadmap

- [x] Więcej aren (28 map)
- [x] Power-up: tarcza (oraz kopanie i gwiazdka)
- [x] Tryb Kill, nagła śmierć, grafika i dźwięki
- [ ] Obsługa pytań dostarczanych przez hosta (tryb embedded)
- [x] Wyniki i statystyki sesji do hosta
- [x] Konfiguracja sesji przez hosta (patrz „Sesja z hosta”)

---

## 👤 Autor

Projekt tworzony przez **DaVideX** jako część systemu Artefakt Wiedzy.
