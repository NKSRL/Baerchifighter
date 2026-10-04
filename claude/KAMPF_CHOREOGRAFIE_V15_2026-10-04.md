# Kampf-Choreografie v15 (2026-10-04)

Wunsch: Die Bärchis sollen im Kampf aufeinander zulaufen und sich anspringen. Nur diese Stöße machen Grundschaden. Jeder Stoß lädt die Fähigkeit auf. Ist sie voll, kommt die Fähigkeit mit Show. Außerdem: Die Sounds waren zu laut und zu aggressiv.

## Was jetzt passiert

**Kampf-Logik** (`CombatCalculator`, `SkillConfig`)
- Die Fähigkeit hat keinen Cooldown mehr, sondern eine **Ladung** (`charge`, meist 2 bis 5 Stöße, = alter Cooldown, mindestens 2).
- Jeder normale Stoß lädt um `1 × (1 + PWR)` auf. PWR (Stat) lädt also schneller. Die Zahlen stehen in `SkillConfig.CHARGE`.
- Ist die Leiste voll, ersetzt die Fähigkeit den nächsten Stoß. Danach ist die Leiste leer.
- Die Ladung bleibt über die Stages eines Laufs erhalten.
- Passive Fähigkeiten (Phantom-Omen, Phoenix, Letzte Chance) laden nicht.

**Wiedergabe in der Arena** (`PitArenaService`, `FigureFX`, neu: `FightTimeline`)
- Jede Stage wird **Zug um Zug** gezeigt:
  - Der Angreifer rennt los und springt den Gegner an. Der Gegner kommt ihm ein Stück entgegen.
  - Beim Aufprall gibt es Funken, einen leisen dumpfen Ton und einen Treffer-Blitz. Der Getroffene wird zurückgestoßen.
  - Danach gehen beide an ihre Plätze zurück.
- Unter dem eigenen HP-Balken ist eine **Ladeleiste**: blau beim Laden, gold wenn sie voll ist.
- **Fähigkeit:** Die Leiste leuchtet gold, die Show läuft (beim ersten Mal im Lauf voll, danach als kurzes Echo). Danach kommt ein wuchtiger Stoß mit höherem Sprung und weiterem Rückstoß.
- Betäubt: Die Figur taumelt, statt zu stoßen.
- Ein besiegter Gegner kippt um, bevor der nächste erscheint.

**Zeitbudget** (`FightTimeline`, `MapConfig` Abschnitt „KAMPF-CHOREOGRAFIE“)
- Ziel: etwa 30 Sekunden pro Lauf, ohne die eine volle Show.
- Pro Stage: 0,5 bis 6 Sekunden.
- **Wenige Stages:** Du siehst fast jeden Stoß.
- **Viele Stages:** Gezeigt werden der entscheidende Stoß und die Fähigkeiten. Wird es eng, läuft das Tempo bis gut doppelt so schnell (Montage). Fähigkeiten und der letzte Zug fallen nie weg. Die Leisten springen bei ausgelassenen Zügen einfach weiter.
- Gemessen (`tools/sim/fight_timeline.lua`): 30 bis 45 Sekunden für einen Lauf mit 30 bis 60 Stages.

**Sound** (`SkillFXConfig.SOUND`, `SkillFXController`)
- Besitzer 0,35 statt 0,8, Zuschauer 0,12 statt 0,35, Echo noch einmal ×0,6.
- Jeder Ton wird nach 1,6 Sekunden ausgeblendet.
- Kürzere Reichweite (90 statt 200 Studs).
- Aufprall-Ton: `action_jump_land.mp3`, Lautstärke 0,25, Reichweite 70 Studs. In Studio geladen und geprüft.

## Architektur

- `FightTimeline` (Modules) rechnet nur: Welche Züge passen in welches Tempo. Kein Model, kein Warten, offline testbar.
- `FigureFX` entscheidet, wie ein Stoß aussieht (`clash`, `stagger`, `soundAt`). `PitArenaService` entscheidet, wann.
- `CombatService` baut aus dem Server-Log die Züge (`Types.FightBeat`). Die Züge bleiben auf dem Server, der Client bekommt wie bisher nur das Ergebnis.
- Alle Zahlen stehen in `MapConfig`, `SkillConfig` und `SkillFXConfig`. Die alten Konstanten (`FIGHT_TOTAL_SECONDS`, `FIGHT_LUNGE_*`) sind entfernt.

## Annahmen (änderbar)

- **Laufdauer:** Ein Lauf dauert jetzt deutlich länger, etwa 30 Sekunden statt etwa 3 bis 10. Änderbar mit `MapConfig.FIGHT_RUN_TARGET_SECONDS`.
- **Ladung = alter Cooldown:** Ein Bärchi mit Cooldown 3 braucht also etwa 3 Stöße, mit hoher PWR weniger.
- **Balance:** Skill-Bärchis kommen im PIT 3 bis 6 Stages weniger weit als in v14. In v14 lief die Fähigkeit zu Beginn jeder Stage, weil der Cooldown pro Stage zurückgesetzt wurde. `path_balance` ist weiter grün. Falls zu schwach: `SkillConfig.CHARGE.PER_HIT` erhöhen.

## Tests

- Syntax: 90 Dateien, keine Fehler.
- Grün: `client.test`, `loc.test`, `egg_tree_check`, `path_balance`, `fight_timeline` (neu), `check_loc`, `check_consistency`, `check_members`.
- **Studio-Playtest steht noch aus.** Beim Commit lief gerade deine Play-Session, die wollte ich nicht stoppen.

## Wichtig: Rojo

Rojo hatte zwei Dateien auf der Festplatte mit dem Studio-Stand überschrieben (`DebugService`, `SkillFXConfig`; Zwei-Wege-Sync). Die richtigen Versionen sind jetzt wieder auf dem PC. Falls bei dir in Rojo „two-way sync“ an ist: am besten ausschalten. Sonst können Änderungen, die nur in Studio liegen, die Dateien zurückdrehen.
