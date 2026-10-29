# Changelog — BitBomber

Istotne zmiany widoczne dla gracza i zmiany kompatybilności. Zasady numerów i etapów: `docs/wersjonowanie.md`
w repo hosta (Artefakt Wiedzy). Plany są w roadmapie README / `docs/zadania.md`, nie tutaj.

## [Unreleased]

### Dodano
- `credits.json` z autorami assetów (pole `credits` w manifeście, ekran „Autorzy” w hoście).

## [0.9.0-beta] — 2026-10-24

Pierwsza wersjonowana Beta — punkt odniesienia. Zakres gry meczowej jest kompletny; dalej testy i balans.
Opisuje stan gry, nie zmiany względem poprzedniego wydania (wcześniej moduł miał zastępczy numer `0.1.0`).

### Zawartość
- **Gra:** 1–2 graczy lokalnie + 0–3 botów (do 4), trzy poziomy trudności botów i pytań.
- **Tryby:** Ostatni żywy i Zabójstwa (odradzanie, dogrywka); warunek meczu „pierwszy do X” albo „najwięcej w Y rundach”;
  nagła śmierć po 3 minutach.
- **Mapy:** 28 — 27 układów z Bomb It 7 (9 motywów × 3 warianty) + klasyczna 17×17.
- **Rozgrywka:** reakcja łańcuchowa, kopanie bomb, power-upy (bomba, zasięg, szybkość, życie, kopanie, tarcza, gwiazdka)
  z wagami i dorzucaniem jak w Bomb It.
- **Quizy w grze:** ostatnia szansa (Ostatni żywy), pytanie-bonus ❓ bez pauzy, quiz odrodzenia (Zabójstwa).
- **Boty:** profile zachowań z Bomb It 7 (`resources/ai/bot_profiles.json`), ucieczka z czasem do wybuchu.
- **Oprawa:** grafika, 12 efektów i muzyka (menu, walka) generowane skryptami; UI w stylu arcade (motyw `bb_theme.tres`).
- **Host:** konfiguracja sesji z Artefaktu Wiedzy, wynik i statystyki do historii sesji („Ostatnio: …” w menu hosta).

### Kompatybilność
- Tryb embedded wymaga hosta z `ModuleHostApi.session_config` / `finish_session` i `SessionResults` (host `0.8.0-alpha`).
  Działa też samodzielnie.

### Znane ograniczenia
- Brak dłuższego grania ręcznego — trudność botów, czytelność pytań w biegu i muzyka do sprawdzenia.
- Bot nie kopie bomb celowo; brak kampanii (rozszerzenia po 1.0).
