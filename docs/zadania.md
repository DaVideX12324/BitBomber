# BitBomber — lista zadań (2026-10-23)

Kopia robocza: submoduł `Artefakt Wiedzy modular/modules/BitBomber` (HEAD `d4dac98`).
Wzór: `F:/Programy/GitHub/bomb-it-7` (SWF + zdekompilowane AS3; logika gry w `scripts/zlong/bombIt/`,
mapy i konfiguracja jako XML/TMX w `scripts/_assets/`).

Oznaczenia: **[S]** proste, do delegowania (Sonnet / Antigravity) · **[O]** projekt / debug, robię sam ·
**[?]** wymaga decyzji usera.

> Grafiki i dźwięki Bomb It 7 są cudze (Spil / zlong) — bierzemy z nich mechanikę, liczby i układ map,
> a nie pliki do wydanej gry.

## Stan po nocy 2026-10-23

✅ = zrobione (commity w historii modułu, testy w `tests/`). Zostało:
- **czeka na decyzję:** A9 (boty jako jeden „gracz 999”), D3 (quiz w mechanice), G1–G2 (API hosta na
  konfigurację sesji i wynik — trzeba dopisać w hoście), muzyka (F3);
- **do zrobienia:** C1 (bot sam kopie celowo), C3 (profile trudności z pliku),
  D4 (kampania), F5 (UI w .tscn).

## Decyzje usera (2026-10-23)

- Tryby: dodajemy **Kill** (obok obecnego „ostatni żywy”).
- Grafika: później albo generowana — ale ma być ładna, nie ColorRecty.
- Koniec czasu: **Sudden Death** zamiast remisu.
- Gracze: na razie **4**.
- Bronie / pojazdy / elementy map (E): na razie **żadne**.

---

## A. Błędy i dług techniczny (najpierw)

1. ✅ **[S] Zasięg bomby o 1 za krótki** — `bomb.gd` ma `range(1, explosion_range)`, więc domyślny zasięg 2
   daje 1 pole, a HUD pokazuje 2. Bot liczy raz tak (`_mark_danger`), raz z `+1` (`_plant_bomb_possible`).
   Ujednolicić: zasięg N = N pól w każdą stronę, wszędzie tą samą funkcją.
2. ✅ **[O] Brak reakcji łańcuchowej** — ogień nie odpala innych bomb (bomba nie ma `take_hit`, eksplozja
   nie widzi warstwy bomb). W Bomb It bomby trafione ogniem wybuchają od razu.
3. ✅ **[O] Ogień trwa 0,2 s** i rani tylko przy `area_entered` — wejście w ogień chwilę później nie zabija.
   Wydłużyć (~0,5 s) i sprawdzać nakładanie co klatkę.
4. ✅ **[S] Prędkość** — `MOVE_SPEED 250 + speed_addition`, gdzie domyślne `speed_addition = 1.0`
   (dopisywane do px/s), a limit +500 daje 750 px/s. Przejść na mnożnik jak w Bomb It
   (`robotSpeed min 1.3 / max 2.1`, start 1.5–1.7) z jedną stałą bazową.
5. ✅ **[S] `bomb.tscn`** (ścieżki względne; oba shadery zostały — jeden dla sprite'a, drugi dla prostokąta zastępczego) — dwa shadery: wbudowany i `ExtResource` na sztywno `res://shaders/bomb.gdshader`
   (w hoście ta ścieżka nie istnieje, ratuje tylko UID). Zostawić jeden, ścieżką względną.
6. ✅ **[S] `SpriteLoader`** (teraz `resources/sprites` modułu) szuka w `res://assets/sprites/` na sztywno, bez `BBRuntime` — w hoście trafia
   w prywatne assety hosta. Ustalić, gdzie mają leżeć sprite'y modułu.
7. ✅ **[S] Martwy kod** — `room_base.gd` (stary „adventure mode”, nic go nie używa), `QUIZ_POWERUP` /
   `trigger_powerup_quiz` (nigdzie nie wywoływane), `reset_for_new_game()` w `player.gd`. Usunąć albo
   podpiąć (patrz D3).
8. ✅ **[S] `arena.gd`** (spawny z pliku mapy) — `_CORNER_SPAWNS` miesza `ROWS`/`COLS` (działa tylko dla kwadratowej mapy).
9. **[O] Kod 999 = „wygrały boty”** — boty liczone razem, nie da się mieć 2+ botów jako osobnych
   rywali w tabeli wyników. Do przemyślenia przy trybach z D.
10. ✅ **[S] Stary klon `F:/Programy/GitHub/BitBomber`** jest 1 commit za originem — zsynchronizować albo
    usunąć, żeby nie pracować na dwóch kopiach.

## B. Rdzeń rozgrywki (jak w Bomb It)

1. ✅ **[O] Mapy z danych zamiast wzoru** — dziś skrzynki stoją na stałym wzorze (tylko między dwoma
   ścianami). Bomb It: 17×15 pól, gęstość skrzynek wg trybu i trudności (0,5–0,8), mapy w TMX.
   Plan: format mapy (TMX z Bomb It albo własny JSON / TileMapLayer), losowanie skrzynek wg gęstości.
2. ✅ **[O] Import 9 map Bomb It** (Classroom, Forest, Race, Ranch, Christmas, Sand, Cake, FashionShop,
   ToyShop × 3 warianty) — parser TMX (base64 + zlib) → nasz format. Same układy, własna grafika.
3. ✅ **[S] Tabela łupu z wagami** (+ dorzucanie po 45 s) — szansa na przedmiot ze skrzynki 0,4–0,6 wg trudności, wagi z
   `XmlManager_xmlClass.bin` (Num 0,28, Pow 0,24, Speed 0,25, kopnięcie 0,1, reszta ~0,01).
4. ✅ **[O] Kopanie bomb** (BombShoes) — bomba sunie do przeszkody; bot musi to rozumieć.
5. ✅ **[S] Tarcza i nieśmiertelność** (Shield, Invincibility) — prosty licznik + efekt na graczu.
6. ✅ **[O] Sudden Death po 180 s** (przy okazji: runda po 180 s wcześniej wisiała) (decyzja) — dziś koniec czasu = remis. Spadające bloki spiralą od
   krawędzi (klasyczny Bomberman).
7. ~~Więcej niż 4 graczy~~ — na razie 4 (decyzja).

## C. Bot

1. ✅ (częściowo: unik przed kopniętą bombą; bot sam nie kopie celowo) **[O] Porównać z AI Bomb It** (`gameEngine/ai/state`): oni mają 13 stanów (m.in. Defence, Evade,
   Follow, Kick, Flag), my 5. Dołożyć przynajmniej Evade (unik przed kopniętą bombą) i Kick.
2. ✅ **[O] Rozumienie reakcji łańcuchowej** (+ bomby i ogień jako przeszkody w A*; samobójstwa 40% → ~20% zgonów) w mapie zagrożeń (po A2) — inaczej boty zaczną ginąć seriami.
3. **[S] Profile trudności z danych** — Bomb It koduje je ciągami `010101|010201|010301`; u nas
   `StateSettings` w kodzie. Przenieść do jednego pliku konfiguracyjnego.

## D. Tryby gry (decyzja: dodajemy Kill)

Bomb It 7 ma: **Arcade** (kampania poziomów vs boty, 180 s, gracz 3 życia, bot 1),
**Kill** (deathmatch z odradzaniem, do N zabójstw), **Collect** (zbieranie monet),
**PacMan**, **Frozen** (zamrażanie zamiast zabijania).

Obecny BitBomber odpowiada **Arcade** (ostatni żywy wygrywa, zabici nie wracają — poza Last Chance), tylko
bez kampanii. **Kill** w Bomb It: zabici odradzają się, wygrywa pierwszy z 10 zabójstwami, a po 180 s ten,
kto ma ich najwięcej. W obu trybach po 45 s co 15 s pojawiają się na mapie nowe przedmioty.

1. ✅ **[O] Szkielet trybów** (`GameManager.game_mode`, na razie enum, nie zasób) — `GameMode` jako zasób/klasa z warunkiem wygranej, odradzaniem, licznikiem.
   Obecny „ostatni żywy + rundy” staje się jednym z trybów.
2. ✅ **[O] Kill** (5 zabójstw, dogrywka przy remisie) — najprostszy do dodania po szkielecie (odradzanie, licznik zabójstw).
3. **[O] Quiz w mechanice** — skrzynka-pytajnik (dobra odpowiedź = rzadki przedmiot) albo Collect,
   gdzie monety to odpowiedzi. To spina grę z edukacją bardziej niż sam Last Chance. **[?]**
4. **[O] Arcade / kampania** — sekwencja map z rosnącą trudnością (to, czym był `room_base`).

## E. Przedmioty specjalne — na razie NIE (decyzja)

- Bronie: Hammer, TerminalHammer, Flamer, Laser, Lightning, ShotGun (zamrażanie), SuperBomb,
  PackageBomb (bomba dzieląca się), Boxing.
- Pojazdy: car, moto (×1,5 prędkości), dragon, frog (×1,2–1,3) — chronią przed jednym trafieniem.
- Elementy map (`maps/platform`): lód, ruchome piaski, odbijacze/strzałki, przyspieszacze, pociąg,
  trampolina, krab. Dobre na urozmaicenie map z B2.

## F. Grafika, dźwięk, UI

1. ✅ **[O] Grafika** (`tools/gen_sprites.py`) — dziś wszystko to ColorRecty. Decyzja: później albo generowana, ale ładna. Potrzebne: postać (4 kierunki × chód + śmierć), bomba, ogień (środek / ramię / koniec),
   ściana, skrzynka, podłoga, przedmioty.
2. ✅ **[S] Animacja ognia segmentami** (środek, ramię, końcówka) zamiast kwadratów.
3. ✅ **[S] Dźwięki** (`tools/gen_sounds.py`; muzyki brak) i muzyka — zero audio teraz. Wybuch, kładzenie bomby, podniesienie przedmiotu,
   śmierć, start rundy, muzyka.
4. ✅ **[S] HUD** (licznik czasu, ikony power-upów w kartach) — licznik czasu rundy (jest w `RoundManager`, nie ma na ekranie), ikony zamiast liczb.
5. **[O] Sceny UI jako .tscn (WYSIWYG)** — `quiz_overlay`, `death_screen`, `main_menu`, `hud` budują UI
   w kodzie (~1700 linii). Przenieść do scen edytowalnych w edytorze.

## G. Integracja z Artefaktem Wiedzy

1. **[O] Konfiguracja sesji z hosta + wynik** (roadmapa z README): `embedded_start(config)` z liczbą
   graczy / botów / rund / trybem, sygnał `session_finished(result)`.
2. **[O] Statystyki sesji** do hosta (poprawne / błędne odpowiedzi, wygrane).
3. ✅ **[S] Test headless** — start areny, wybuch, łańcuch, koniec rundy (smoke test jak w quiz_rpg).
4. ✅ **[S] README** — zaktualizować po zmianach (roadmapa, nowe tryby).

---

### Proponowana kolejność

A1–A10 → B1 (format mapy) → C2 → B3–B6 → D1–D2 (Kill) → F1 (grafika) → reszta.
