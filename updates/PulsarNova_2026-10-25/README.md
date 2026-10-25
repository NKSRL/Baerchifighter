# Pulsar-Nova (PulsarNova) – Code-Paket vom 25.10.2026

Die Fähigkeit ist in Studio eingebaut und getestet. Die Fähigkeiten-Skripte im Repo
(`SkillFXController`, `SkillFXConfig`, `SkillConfig`, `BaerchiConfig`, `Strings`) stehen
noch auf dem Stand vom 20./21.10. (offener Punkt „Gesamtabgleich Studio → Repo“). Damit der
Code nicht nur in Studio liegt, steht er hier als Paket. Beim Gesamtabgleich einfach die
Studio-Fassung exportieren; dieses Paket ist dann nur noch Nachweis.

Einrückung hier: 4 Leerzeichen (Studio: Tabs, je 4 Leerzeichen ein Tab).

| Datei | Ziel | Anker |
|---|---|---|
| `blocks.luau` | `StarterPlayerScripts/Controllers/SkillFXController` | vor dem Kopf `-- Abspielen` (Strichzeile davor) |
| `ctxfields.luau` | dort, `type Ctx` | vor der schließenden `}` des Typs |
| `cinematic.luau` | dort, `BLOCKS.cinematic` | vor `else` / `local a = k * math.pi * 0.9` |
| `fxdoc.txt` | `ReplicatedStorage/Config/SkillFXConfig`, Dateikopf | vor `--\n-- Fuer jeden Schritt:` |
| `textures.luau` | dort, `TEXTURES` | hinter dem Eintrag `OmegaWorldsEnd` |
| `fxentry.luau` | dort, FX-Tabelle | vor `\n}\n\n-- Unbekannte Faehigkeit` |
| `skillentry.luau` | `ReplicatedStorage/Config/SkillConfig` | vor dem Kopf `-- v15: AUFLADEN STATT COOLDOWN` |
| `strings.luau` | `Localization/Strings/de/en/es/fr`, `BaerchiConfig` | hinter `["skill.PulsarPulse.name"]` |

Prüfsumme: `blocks.luau` nach Umwandlung in Tabs = 63448 Bytes, Hash (h*31+byte) mod 2^31 =
1800950562 (gleich dem Abschnitt in Studio am 25.10., 18:30).

Bericht: `docs/HBB_PULSAR_NOVA_UMGESETZT_2026-10-25.md`.
