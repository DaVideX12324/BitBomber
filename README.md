# 💣 BitBomber

BitBomber to gra w stylu Bombermana stworzona w **Godot 4** jako samodzielny projekt oraz osadzalny moduł edukacyjny (plug-and-play) dla platformy [Artefakt Wiedzy](https://github.com/DaVideX12324/Artefakt-Wiedzy-modular) (w hoście leży jako submoduł `modules/BitBomber`).

Gracze (i boty) kładą bomby, niszczą skrzynki, zbierają power-upy i rywalizują o wygraną, a quizy są wplecione w rozgrywkę:
ostatnia szansa po śmierci, pytanie-bonus ❓ zbierane z planszy i quiz odrodzenia w trybie Zabójstw.
Mechanika, liczby, układy map i AI botów wzorowane są na **Bomb It 7** — grafika, dźwięki i muzyka są własne, generowane skryptami.

---

## 🎮 Funkcje

- **1–2 graczy lokalnie + 0–3 botów** (razem do 4), 3 poziomy trudności botów i pytań
- Tryby gry: **Ostatni żywy** i **Zabójstwa** (Kill z Bomb It — odradzanie, pierwszy do 5 zabójstw, dogrywka po czasie)
- Warunek wygranej: **pierwszy do X** wygranych rund albo **najwięcej w Y** rundach; wyniki każdego bota osobno
- **28 map**: 27 układów z Bomb It 7 (9 motywów × 3 warianty, 17×15) + klasyczna 17×17; skrzynki losowane z gęstością
- **Nagła śmierć** po 3 minutach — bloki spadają spiralą od krawędzi (czerwone pola ostrzegają)
- Reakcja łańcuchowa bomb, kopanie bomb
- Power-upy: bomba, zasięg, szybkość, życie, kopanie, tarcza, gwiazdka (nietykalność), ❓ pytanie-bonus;
  wagi i dorzucanie po 45 s jak w Bomb It
- Quizy:
  - **Ostatnia szansa** (Ostatni żywy) — po śmierci quiz, dobra odpowiedź = powrót (pojedynek przy 2 graczach)
  - **Pytanie-bonus ❓** bez pauzy — dobrze: tarcza / gwiazdka / +2 zasięgu, źle: 5 s spowolnienia
  - **Quiz odrodzenia** (Zabójstwa) — dobrze: powrót od razu z tarczą, źle: +3 s
- **UI w stylu arcade** — wspólny motyw, HUD z zegarem rundy, celem meczu, gwiazdkami wygranych, koroną lidera
  i odliczaniem odrodzenia; panele pytań w kolorach graczy
- **Muzyka** (menu, walka) i 12 efektów dźwiękowych — generowane
- Tryb **embedded** w Artefakcie Wiedzy: konfiguracja sesji z hosta i wynik / statystyki na koniec

---

## 🕹️ Sterowanie

| | Gracz 1 | Gracz 2 |
|---|---|---|
| Ruch | W, S, A, D | strzałki |
| Bomba | Spacja | Enter / Num 0 |
| Pytanie-bonus ❓ | 1–4 | Num 1–4 |
| Ostatnia szansa / quiz odrodzenia | W, S, A, D | strzałki |
| Pauza | Esc | Esc |

Klawisze można zmienić w opcjach hosta (zakładka „Sterowanie”); panele pytań pokazują aktualne przypisania.

---

## 🧠 Architektura AI

Bot (`scripts/bot_ai.gd`) to maszyna stanów jak `AIEngine` z Bomb It 7: co `answer_time` sekund sprawdza stany
w kolejności z profilu (każdy z szansą `chance`), pierwszy pasujący wygrywa, a gdy żaden — stan domyślny (spacer).
Profile trudności dla obu trybów są w `resources/ai/bot_profiles.json` (liczby z `GameAI` Bomb It: czas reakcji,
zasięg widzenia, szybkość, szanse stanów, unik / bomba w biegu na każdym kroku) — zmiana balansu botów = edycja JSON.

| Stan | Opis |
|------|------|
| `ESCAPE` | Ucieczka: BFS tylko przez pola, które bot zdąży minąć przed ogniem (mapa zagrożenia z czasem do wybuchu i reakcją łańcuchową) |
| `ATTACK` | Dojście na pozycję, z której bomba trafi przeciwnika — tylko jeśli da się potem uciec na czas |
| `BOX` | Niszczenie najbliższej skrzynki w zasięgu widzenia |
| `GET_ITEM` | Zbieranie power-upów |
| `FREE` | Spacer na losowe bezpieczne pole (stan domyślny) |
| `IDLE` | Krótki postój (przerywany, gdy pole robi się groźne) |

Trasy: **`AStarGrid2D`** (pola w zasięgu bomb drogie); zatrzymany między polami bot najpierw wraca na środek pola.
Bot omija spadające bloki nagłej śmierci i tor kopniętych bomb, a pytania-bonus „odpowiada” z szansą wg trudności.
Pomiar: `tests/bench_bots.gd` (4 boty w trybie Zabójstw, zabójstwa / samobójstwa; `BENCH_WHY=1` — stan bota przy
samobójstwie, `BENCH_TRACE=1` — pełny log decyzji). Pojedyncza próbka to szum — porównywać 3 mapy × 600 s.

---

## 🗂️ Struktura projektu

```
BitBomber/
├── module_manifest.json    # Rejestracja modułu w hoście (id, entry_scene, opis sterowania dla opcji hosta)
├── module_root.tscn/.gd    # Wrapper modułu: scena gry, akcje wejścia, sesja z hosta (config / wynik), request_exit()
├── project.godot.off       # Konfiguracja projektu do uruchomienia samodzielnego (zmień nazwę na project.godot)
├── autoloads/              # GameManager, RoundManager, SpriteLoader (także w hoście) + Quiz/Settings/UIScale/WindowManager (tylko samodzielnie)
├── scenes/
│   ├── game.tscn           # Persistentny root gry (HUD, ekran śmierci, pauza, gracze, FieldQuiz)
│   ├── maps/               # Arena
│   ├── objects/            # Bomba, eksplozja, power-up
│   ├── players/            # Gracz
│   └── ui/                 # Menu główne (z instrukcją), pauza, opcje, HUD, ekran śmierci, nakładka quizu, panel pytania
├── scripts/
│   ├── arena.gd            # Mapa z pliku, skrzynki, łup, nagła śmierć, blast_cells (jedyna definicja zasięgu wybuchu)
│   ├── bomb.gd, explosion.gd, powerup.gd
│   ├── player.gd           # Ruch, bomby, życia, power-upy, kopanie, odradzanie (Zabójstwa)
│   ├── bot_ai.gd           # AI bota (profile z JSON, FSM + A* + BFS z czasem)
│   ├── field_quiz.gd       # Quiz w trakcie gry: pytanie-bonus ❓ i quiz odrodzenia
│   ├── bb_questions.gd     # Losowanie pytań wg trudności, tryb „bez quizów”
│   ├── bb_runtime.gd       # Ścieżki modułu: res://modules/BitBomber/… w hoście, res://… samodzielnie
│   ├── bb_sfx.gd, bb_music.gd  # Dźwięki i muzyka (przez AudioService hosta albo własny odtwarzacz)
│   ├── game.gd, game_settings.gd
│   └── hud.gd, main_menu.gd, options_menu.gd, pause_menu.gd, death_screen.gd, quiz_overlay.gd, field_quiz_panel.gd
├── resources/
│   ├── maps/               # Układy map (JSON: rows '#' stały, 'C' środek, 'b' miejsce na skrzynkę, '.' puste)
│   ├── ai/bot_profiles.json  # Profile botów (Bomb It GameAI) dla obu trybów i 3 trudności
│   ├── ui/bb_theme.tres    # Wspólny motyw UI (tekstury sprites/ui, wariacje TitleLabel, HeaderLabel, PrimaryButton, DangerButton, CardPanel)
│   ├── sprites/            # Grafika (generowana): tiles/<motyw>/, players/, objects/, ui/
│   ├── sounds/, music/     # Efekty i muzyka (generowane, muzyka z pętlą w pliku WAV)
│   ├── i18n/               # Tłumaczenia PL / EN (sceny tłumaczone po polskim tekście źródłowym)
│   └── quizzes/, fonts/    # Zestawy pytań (samodzielnie), fonty
├── shaders/                # Shader bomby
├── tools/
│   ├── import_bombit_maps.py  # TMX z Bomb It 7 → resources/maps/*.json
│   ├── gen_sprites.py         # Pillow → resources/sprites/ (kafle, postacie, ogień, power-upy, UI) — zmiany wyglądu tutaj
│   ├── gen_sounds.py          # numpy → resources/sounds/*.wav
│   └── gen_music.py           # numpy → resources/music/*.wav (chiptune, nuty w listach na końcu)
├── tests/                  # Testy headless (uruchamiane z katalogu hosta, patrz niżej)
└── docs/zadania.md         # Lista zadań, decyzje i stan prac
```

Generatory: `python tools/gen_sprites.py`, `python tools/gen_sounds.py`, `python tools/gen_music.py` (numpy, Pillow,
scipy; deterministyczne — ponowne uruchomienie daje te same pliki). Po nowych plikach: `godot --headless --path <host> --import`.

Testy: `godot --headless --path <host> --fixed-fps 60 -s res://modules/BitBomber/tests/<test>.gd`
(`test_blast`, `test_maps`, `test_items`, `test_kick_shield`, `test_kill_mode`, `test_sudden_death`, `test_scores`,
`test_field_quiz`, `test_host_session`, `test_music`, `test_smoke`; benchmark AI `bench_bots`).

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
  korzysta przez nie z `QuizService`. Ustawienie hosta „bez quizów” wyłącza wszystkie quizy (także ❓ i odrodzenie).
- **Audio:** efekty przez `AudioService.play_sfx` (szyna SFX), muzyka przez `AudioService.register_music_track` +
  `play_music` (szyna Music) — głośność z ustawień hosta.

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
- Gra: brak zewnętrznych zależności; generatory zasobów: Python 3 + numpy, Pillow, scipy

---

## 🚧 Roadmap

- [x] Więcej aren (28 map z Bomb It 7)
- [x] Tryb Zabójstw, nagła śmierć, kopanie, tarcza, gwiazdka
- [x] Grafika, dźwięki i muzyka generowane skryptami
- [x] Quiz w trakcie gry (pytanie-bonus ❓, quiz odrodzenia)
- [x] UI w stylu arcade (wspólny motyw, sceny .tscn)
- [x] AI botów wg Bomb It 7 (profile w JSON)
- [x] Konfiguracja sesji przez hosta, wyniki i statystyki do hosta
- [ ] Bot celowo kopiący bomby
- [ ] Kampania (seria map z rosnącą trudnością)

---

## 👤 Autor

Projekt tworzony przez **DaVideX** jako część systemu Artefakt Wiedzy.
