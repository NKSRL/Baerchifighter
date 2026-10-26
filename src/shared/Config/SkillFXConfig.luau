--!strict
-- SkillFXConfig.luau
-- ReplicatedStorage/Config/SkillFXConfig.luau
--
-- v14 (Mega Egg Tree, WP8/WP9): WIE jede Faehigkeit aussieht.
--
-- Was ein Skill TUT, steht in SkillConfig. Hier steht nur die Show — als
-- reine DATEN. Der Client (Controllers/SkillFXController) kennt eine Handvoll
-- Bausteine und spielt eine Faehigkeit ab, indem er ihre Schritte der Reihe
-- nach ausfuehrt. Eine neue Faehigkeit = ein neuer Eintrag hier, kein Code.
--
-- ============================================================
-- AUFBAU EINES EINTRAGS
-- ============================================================
--   tier      Spektakel-Stufe 1..4 (siehe TIERS): steuert, wie viel erlaubt
--             ist (Himmel faerben, Kamerafahrt) und wie lange die Show ist.
--   duration  Sekunden, die der PIT fuer die volle Show anhaelt.
--   color     Hauptfarbe, color2 Zweitfarbe.
--   sounds    { charge = id, strike = id, impact = id } (siehe SOUNDS).
--   steps     Liste { t = Startzeit, fx = Baustein, ...Parameter }.
--             Drei Phasen nach Konzept: Aufladen (t klein), Schlag (Mitte),
--             Einschlag (Ende). `at` sagt, wo: "self" (der Baerchi),
--             "target" (der Gegner), "between", "arena" (Mitte zwischen beiden).
--
-- BAUSTEINE (Client):
--   aura      Leuchtkugel + Licht um eine Figur        size, dur
--   ring      flacher Ring, der sich ausbreitet          radius, dur
--   pillar    Lichtsaeule                                 height, width, dur
--   projectile Kugel mit Schweif von self zu target       size, dur
--   meteor    Kugel faellt von oben auf target            size, height, dur
--   beam      Strahl zwischen self und target             width, dur
--   wave      Kugel-Schockwelle                           radius, dur
--   shards    Splitter fliegen auseinander                count, size, dur
--   sparks    Funken-Partikel                             count, dur
--   bubble    Schild-Blase um eine Figur                  size, dur
--   rise      aufsteigende Lichter (Heilung, Buff)        count, dur
--   spiral    Partikel werden eingesaugt (Vortex)         radius, count, dur
--   frost     Eiskristalle auf einer Figur                count, dur
--   starfield Sternenhimmel ueber der Arena               count, dur
--   sky       Farbfilter (nur Besitzer)                   tint, brightness, saturation, dur
--   spectrum  Farbspektrum laeuft durch (nur Besitzer)    dur
--   flash     weisser Bildschirmblitz (nur Besitzer)      dur
--   shake     Kamerawackeln (nur Besitzer)                power, dur
--   hitstop   Treffer-Stillstand ("Zeitlupe")            dur
--   cinematic kurze Kamerafahrt (nur Besitzer, Stufe 4)  dur
--   sound     ein Sound-Slot                              slot = "charge"|"strike"|"impact"
--
-- v16 (Gletscher-Show) — neue Bausteine, alle relativ zu den Figuren (Fuesse
-- aus der Bounding-Box), stimmen also auf dem Tower in jeder Hoehe:
--   breath     Atemwolke vor dem Maul, 2 Stoesse (1 Emitter)  count, dur, tex
--   groundmark Boden friert im Kreis, Adern kriechen raus     radius, dur, veins, tex
--   crack      Zickzack-Riss am Boden von self zu target      dur, linger, segments, amp, width, tex
--   spikes     schraege Dornen brechen nacheinander entlang   count, dur, rise, minHeight, maxHeight, linger, tex
--              des letzten `crack` aus, jeder hoeher (Welle)
--   snowfall   Nachgluehen: Reifschimmer + sinkende Flocken  count, dur, tex
--              (1 Emitter)
-- Erweiterte Parameter bestehender Bausteine (v16):
--   frost  legs = true   Kristalle wachsen von den Fuessen bis zur Huefte
--          perch = true  kleine Kristalle auf Ohren und Schultern, glint = true
--                        laesst jede Kante EINMAL weiss aufleuchten
--   ring   ground = true flacher Ring auf dem Boden unter der Figur; tex
--
-- v16 (Seraph-Show) — neue Bausteine:
--   wings      Lichtfluegel hinter der Figur, Feder fuer Feder  count, span, dur, foldAt, tex, sparkTex
--              von innen nach aussen; bei foldAt falten und
--              in Funken zerfallen (1 Emitter, Beiwerk)
--   halo       Heiligenschein ueber dem Kopf, dreht langsam,    radius, lift, count, dur, tex
--              folgt der Figur
--   honeycomb  Wabenmuster laeuft Fuesse -> Kopf, zieht ein,  cols, rows, sweep, pull, hold, tex
--              warmer Schein bleibt `hold` s an der Figur
--              (folgt ihr auch beim Anlauf zum Stoss)
-- Erweiterte Parameter (v16):
--   ring     lift = n     Ring n Studs ueber der Figur (Wolkenloch), mit tex
--                        auch von unten sichtbar
--   pillar   feet = true  Fuss der Saeule unter der Figur; soft = true
--                        halbdurchsichtig; tex = Bild als Beam (weicher Verlauf)
--   snowfall noShell = true nur Emitter (z. B. rieselnde Federn); lift, size
--   alle     second = true Zweitfarbe (color2) statt Hauptfarbe
--
-- v16 (Kometen-Show) — neue Bausteine:
--   shadow  dunkler Kreis am Boden, waechst beschleunigt       from, radius, dur, fadeOut, toArena
--   comet   Punkt funkelt oben und waechst (`charge`), dann    height, size, charge, fall, cloudY,
--           faellt der Komet (Kopf, Kern, Schweif, Funken =     tex, tailTex, sparkTex
--           1 Emitter) auf den Gegner, letzte 30 % langsam;
--           Wolkenfetzen bei cloudY (Beiwerk)
--   crater  Glut-Risse im Boden, kuehlen Orange -> Violett ab  radius, count, dur, tex
--   dust    Sternstaub im Bogen (1 Emitter, Schwerkraft)       count, speed, dur, tex
-- Erweiterte Parameter (v16):
--   radius = "tower" | "fence"  Turmspitze bzw. bis zum Arena-Zaun (MapConfig),
--            gemessen ab der Arena-Mitte (ring, shadow, crater)
--   ring     toArena = true  Bodenring startet an der Figur, waechst um die
--            Arena-Mitte (Schockwelle bis zum Zaun)
--   shards   arc = true      Truemmer fliegen im Bogen und landen am Boden; tex
--   sky      fade = s        so lange dauert das Einfaerben (Standard 0,35)
--   cinematic style "chase"  Kamera schraeg hinter dem laufenden `comet`
--   alle     ownerOnly = true Schritt nur fuer den Besitzer (z. B. Sterne
--            als Teil seines Nachthimmels)
--
-- v16 (Schemen-Show) — neue Bausteine:
--   silhouette Schatten der Figur richtet sich als flache Tinten-       behind, rise, hold, dissolve,
--              Silhouette hinter ihr auf, zerfaellt in Rauch           tex, smokeTex
--              (Tinten-Klon der Figur, Tiefe gestaucht; 1 Emitter)
--   shades     Pfuetzen rund um die Figur, aus jeder steigt ein       count, distance, pool, rise,
--              Schatten-Baerchi (Tinten-Klon), loest sich auf        fadeAt, dissolve, tex, smokeTex
--   vanish     Figur wird blasser (LocalTransparencyModifier, nur     to, fadeIn, back
--              lokal) und steht bei `back` schlagartig wieder da
--   silence    der Ton geht ganz aus (nur Besitzer)                   dur
--   cut        ein duenner weisser Schnitt quer durchs Bild (an der   length, width, draw, tearAt,
--              Kamera jedes Clients ausgerichtet), reisst auf          angle, tex
-- Erweiterte Parameter (v16):
--   shards   tex  Bild auf beiden grossen Flaechen (Schattenfetzen)
--
-- v16 (Omega-Show) — neue Bausteine:
--   omega     Omega-Zeichen Strich fuer Strich. mode "sky": hoch     mode, radius, lift, segments, draw,
--             ueber der Arena, zur Kamera gedreht, zieht sich bei    pullAt, jerk, burnFor, fade, tex
--             `pullAt` mit einem Ruck auf die Pfote. mode "brand":
--             flach am Boden eingebrannt, verblasst.
--   converge  Lichtpunkte aus vier Himmelsrichtungen (eine Farbe     colors, perSide, from, lift,
--             je Richtung) fliegen in einen Punkt ueber der Arena    flight, stagger, tex
--   spotlight Figur leuchtet (Highlight, nur Besitzer)               dur, fill, strength
--   wipe      Spektrum laeuft als Welle durchs Bild, dahinter        dur, tex
--             kommt die Farbe zurueck (nur Besitzer)
-- Erweiterte Parameter (v16):
--   alle      color = Color3  feste Farbe fuer diesen Schritt
--   alle      global = true   auch Spieler AUSSERHALB der Zuschauer-
--             Reichweite sehen diesen Schritt (nur volle Show)
--   alle      bonus = true    Schritt laeuft nur, wenn der Server `bonus`
--             mitschickt (Finisher/Opener hat gegriffen, SkillFXPlay)
--   silence   level = 0..1    statt stumm nur leiser (0,15 = ganz leise)
--   cinematic style "orbitSelf"  langsamer Halbkreis um den eigenen Baerchi
-- 23.10. (Leerenkrone) — neue Bausteine:
--   ascend    der Baerchi SELBST: holt aus, steigt mit Drehung auf und      height, crouch, rise, spins, grow,
--             waechst, schwebt bebend, stuerzt kopfueber auf den Gegner,   diveAt, dive, hold, back
--             Rueckwaerts-Salto nach Hause. Tanzt als echter Klon (das
--             Original ist lokal unsichtbar, der Server bewegt es weiter);
--             crown, voidorb und cinematic "lowHero" folgen dem Klon.
--   crown     Obsidian-Dornenkrone mit leuchtendem Reif ueber dem Kopf,     count, radius, lift, height, grow, dur,
--             Dorn fuer Dorn, dreht sich; zerspringt nach `dur`            spin, shatter
--   sigil     Zauberkreis am Boden (Ringe, Runen, Stern) auf dunkler       at, radius, draw, dur, runes, points,
--             Scheibe, dreht gegenlaeufig, gleisst bei `pulseAt` auf       spin, pulseAt
--   eyes      leuchtende Augen rund um die Arena, oeffnen sich, blinzeln   at, count, radius, lift, size, open,
--                                                                        blinkAt, dur
--   voidorb   Kugel aus Leere ueber der Krone, saugt Licht ein, Blitze;   size, lift, grow, fireAt, fly, arcs
--             schiesst bei `fireAt` auf den Gegner und kollabiert
--   eruption  Obsidian-Dornen brechen ringfoermig aus dem Boden (innen     at, count, rings, radius, minHeight,
--             zuerst), bleiben stehen, ziehen sich zurueck; `open` laesst  maxHeight, rise, stagger, linger, sink,
--             zur Seite des Angreifers eine Luecke (dort landet er)        open
-- Erweiterte Parameter:
--   cinematic style "lowHero"  Untersicht auf den aufsteigenden Baerchi
--   sounds    eigene Slots je Faehigkeit erlaubt (z. B. rise, eyes, dive),
--             im Schritt per `slot = "<name>"`
-- 25.10. (Entfuehrungsstrahl) — neue Bausteine:
--   saucer     der UFO-Baerchi SELBST (Klon wie `ascend`): duckt sich,      height, crouch, rise, spins, grow,
--              hebt mit Drehung ab, Zickzack ueber den Gegner, schwebt;    travel, zigs, zig, hover, fireAt,
--              Randlichter als Lauflicht; bei `fireAt` Rueckstoss, Fass-   jolt, hold, back, land
--              rolle, Zickzack nach Hause, Landung. Setzt avatarCf
--              (tractor und Kamera "beamUp" folgen ihm).
--   tractor    Traktorstrahl (3 FaceCamera-Beams) vom UFO zum Boden,       at, width, base, open, zapAt, zap,
--              Lichtringe laufen hoch, Funken; bei `zapAt` weisser         dur, rings, lift
--              Todesstrahl, trifft nach `zap` den Boden. Ohne saucer:
--              kleine Neon-Untertasse `lift` ueber dem Gegner (Echo).
--   abduct     der GEGNER als Klon (Original lokal unsichtbar) wird hoch-  height, lift, dropAt, drop, spin
--              gezogen, zappelt, haengt, stuerzt bei `dropAt` zurueck
--              (Landung = Einschlag, dann Original + Server-Rueckstoss)
--   cropcircle Kornkreis am Boden (SurfaceGui): Ringe, Speichen,          at, radius, draw, dur, spin, pulseAt, sats
--              Trabanten; dreht langsam, gleisst bei `pulseAt`
-- Erweiterte Parameter:
--   cinematic style "beamUp"  tief neben dem Gegner, Blick hoch zu Strahl und UFO
-- 25.10. (Zeitstillstand) — neue Bausteine:
--   timewalk   der Chronos-Baerchi SELBST (Klon wie `ascend`): duckt sich,  height, crouch, rise, spins, grow,
--              steigt mit Drehung auf, die Stirn-Uhr rast (Teile mit       stopAt, blinkAt, appear, lift, slam,
--              clock_face/hand_h/hand_m im Namen), Zeitsand rieselt; bei    hold, back, ghosts
--              `stopAt` Uhr auf XII, Sand erstarrt (TimeScale 0); bei
--              `blinkAt` Sprung durch die Zeit (Nachbilder-Spur), haengt
--              ueber dem Gegner, Stampfer mit zwei Drehungen, spult
--              rueckwaerts heim (blaue Nachbilder). Setzt avatarCf.
--              trailLife (optional): Lebensdauer der Spur (Test-Buehnen).
--   clockface  Zifferblatt (SurfaceGui: Ringe, 60 Striche, roemische        at, radius, lift, back, draw, stopAt,
--              Ziffern, Zeiger) `back` Studs hinter der Arena-Mitte (von    ticks, crackAt, shatterAt, dur
--              der Kamera jedes Clients aus), zur Kamera gedreht; Zeiger
--              rasen bis `stopAt`, jeder Eintrag in `ticks` = eine Minute,
--              der letzte = XII; Risse, Scherben. at = "target": klein
--              ueber dem Gegner (Echo; stopAt = 0 = ohne Rasen).
--   timebubble treibender Staub (1 Emitter); bei `stopAt` waechst die       at, radius, stopAt, grow, popAt, dust
--              Zeitblase (Kraftfeld + Neon-Huelle) aus dem Baerchi, der
--              Staub erstarrt; bei `popAt` platzt sie, der Staub faellt.
--   timefreeze der GEGNER als Klon erstarrt (grau-blau), goldene Uhrwerk-   hold, linger, rings, segs, step
--              Ringe mit Elfenbein-Strichen (wie eine Luenette) ruecken
--              ruckweise; bei `hold` ist das Original wieder
--              da (= Einschlag), die Ringe zerspringen.
--   Helfer: chronoGhost (Nachbild einer Pose als Kraftfeld), headClock
--              (Zeiger eines Modells um das Zifferblatt drehen).
-- 25.10. (Sternenfall) — neue Bausteine:
--   starfall   der Unendlichkeits-Baerchi SELBST (Klon wie `ascend`): duckt   height, crouch, rise, spins, grow,
--              sich, steigt mit Drehung auf; Kopf-Reif dreht sich, die       loopAt, loop, span, tall, lift,
--              Sterne rasen auf der Acht (Teile acc_loop/acc_star); fliegt   diveAt, dive, flips, hold, back, segs
--              ab `loopAt` ein riesiges Unendlichkeitszeichen (`lift` ueber
--              der Arena, zur Kamera jedes Clients gedreht, beim Start fest)
--              und laesst ein Lichtband stehen; haengt bebend im Kreuzungs-
--              punkt; bei `diveAt` faellt das Band in ihn zusammen, Sturz als
--              Komet mit Vorwaerts-Saltos (Landung = Einschlag), Rueckwaerts-
--              Salto heim. Setzt avatarCf und infCenter/infRight/infNormal/infSpan.
--   gridweb    Energienetz am Boden (SurfaceGui): verwackelte Speichen und    at, radius, draw, dur, spokes, rings,
--              Ringe, Querstreben, flackernde Knoten; gleisst bei `pulseAt`  spin, pulseAt
--   shootingstars Sternschnuppen nacheinander aus der Bahn des Klons (sonst  at, count, every, fall, radius, size,
--              von oben) auf einen Ring um den Gegner (Luecke zur Seite des  crystals, breakAt, linger
--              Angreifers; radius = 0: auf den Gegner); Kristall-Busch am
--              Einschlag, zerspringt bei `breakAt`
--   crystalgeyser Glas-Kristalle mit Leuchtkern brechen in Ringen aus dem    at, count, rings, radius, minHeight,
--              Boden (innen hoch und steil), Fontaene aus Lichtsplittern,    maxHeight, rise, stagger, linger, sink,
--              Kristall-Nadeln (`needles`), kurze Lichtsaeule; `open`;       shatterAt, spray, needles, open
--              zerspringen bei `shatterAt` (Test: sprayFor, freezeAt)
--   Helfer: lemniscate (Punkt auf der Acht), headInfinity (Kopf-Reif + Sterne
--              eines Modells), addCrystal (Glas-Kristall als Rig).
-- Erweiterte Parameter:
--   cinematic style "infinity"  tief vor dem Unendlichkeitszeichen, Blick wandert zum Gegner
-- 25.10. (Weltenende) — neue Bausteine:
--   worldsend  der Omega-Baerchi SELBST (Klon wie `ascend`): duckt sich,     crouch, rise, spins, grow, lift, radius,
--              Fluegel schlagen (Teile acc_wing), steigt mit Drehung ueber    ring, birthAt, birth, settleAt, crashAt,
--              die Arena; ab `birthAt` waechst unter ihm ein Planet (Kon-     windAt, hopAt, stompAt, fall, bounce,
--              tinente, Polkappen, Atmosphaere), sein Orbit-Ring (acc_orbit)  settle, shock, chunks, cracks, steps
--              wird zum Planetenring (zur Kamera jedes Clients geneigt, beim
--              Start fest), die Sterne (acc_orbitstar) fliegen als Monde auf
--              den Ring; bei `settleAt` landet er auf dem Planeten; die Monde
--              krachen nacheinander hinein (`crashAt`: Risse, Beben, Gluehen);
--              Sprung mit Vorwaerts-Salto, Stampfer bei `stompAt`: er reitet
--              den Planeten in `fall` s auf den Gegner (Landung = Einschlag),
--              der Planet zerbirst, der Ring rast als Bodenwelle bis `shock`;
--              Rueckwaerts-Salto heim, die Sterne kehren zurueck. Setzt
--              avatarCf und worldCenter/worldNormal/worldRadius.
--              Test: freezeAt (haelt alles an), burstFreeze (haelt Brocken
--              und Bodenwelle n s nach dem Einschlag an).
--   miniworld  kleiner Planet mit Ring faellt auf den Gegner und zerbirst    at, radius, height, drop, shock, chunks,
--              nach `drop` s, der Ring rast als Bodenwelle davon (Echo)       power (Test: freezeAt, burstFreeze)
--   supernova  Finisher-Bonus: riesige Lichtkugel (Kraftfeld + Neon-Huelle)  at, radius, dur, rays (Test: freezeAt)
--              waechst aus dem Einschlag, Lichtstrahlen, Funken in den
--              Mondfarben
--   Helfer: omegaParts (Fluegel, Orbit-Ring + Sterne, Krone eines Modells),
--              makeWorld (Planet: Risse, Gluehen, zerbirst), makeRing
--              (Planetenring als SurfaceGui, wird zur Bodenwelle).
--   worldglobe Explosion als Weltkugel aus Licht (25.10., Wunsch des Nutzers): at, radius, grow, dur, lift, tilt, spin,
--              waechst aus dem Einschlag (ctx.worldCenter) in `grow` s auf     meridians, parallels (Test: freezeAt)
--              `radius` ("fence" = ganzes Pit), Mitte `lift` x Radius ueber
--              dem Boden, Achse `tilt` Grad zur Kamera; Laengen-/Breitengrade
--              als Bezier-Beams (auch von innen sichtbar), Kontinente des
--              Planeten + Polkappen halbtransparent, Kraftfeld-Huelle; dreht
--              sich beim Aufgehen schnell (`spin`), dann langsam; zerfaellt ab
--              `dur` - 0,6 in Sternenstaub. Setzt globeT0/globeCenter/
--              globeRadius (Kamera "worldsEnd" faehrt zurueck).
-- Erweiterte Parameter:
--   cinematic style "worldsEnd"  tief auf der Seite der Spielkamera, Blick hoch zu Planet und Baerchi, folgt dem Sturz, faehrt beim Einschlag zurueck auf die ganze Weltkugel (`worldglobe`)
-- 25.10. (Fragenlawine) — neue Bausteine:
--   riddler    der Raetsel-Baerchi SELBST (Klon wie `ascend`): lueftet den    tipAt, crouchAt, crouch, rise, spins, grow,
--              Hut (Teile acc_hat/acc_brim/acc_hatband), steigt mit Drehung   height, glintAt, ahaAt, diveAt, dive, flips,
--              ueber den Landepunkt vor dem Gegner, gruebelt, Monokel blitzt  gap, curlAt, curl, hold, back, bow
--              (acc_monocle_glass); bei `ahaAt` zuckt er hoch, bei `diveAt`   (Test: freezeAt)
--              Vorwaerts-Salto und Sturz (Landung = Einschlag): sein Weg wird
--              zum Strich eines riesigen "!", er selbst ist der Punkt; ab
--              `curlAt` biegt sich das "!" zum "?"; Rueckwaerts-Salto heim, er
--              zieht den Hut und das "?" schrumpft hinein. Setzt avatarCf,
--              riddleHatTop, riddleLand, riddleLandT. Laeuft auch ohne Hut.
--   questionmarks die Lawine: ein "?" springt aus dem Hut, waechst ueber dem  at, count, appear, fly, big, high, splitAt,
--              Gegner, teilt sich bei jedem `splitAt` (1 -> 2 -> 4 -> 8;      split, radius, lift, small, whirl, stopAt,
--              niedrige Grafik 4) und wirbelt immer schneller um ihn (Luecke  ahaAt, aha, dropAt, every, fall, inward,
--              zu Angreifer und Kamera, beim Start fest), steht bei `stopAt`  flashAt, curlAt, curl, popAt, popEvery, gap
--              still; bei `ahaAt` biegen sich alle zu "!" und rammen sich    (Test: freezeAt)
--              nacheinander als Kaefig in den Boden; `flashAt` alle leuchten;
--              ab `curlAt` wieder "?" und abheben, ab `popAt` zerplatzen sie
--              in kleine Fragezeichen. Setzt riddleGap, riddleRing.
--   puzzled    der GEGNER als Klon schaut sich verwirrt um, zuckt bei `ahaAt`  ahaAt, hold, look (Test: freezeAt)
--              zusammen; bei `hold` ist das Original zurueck (= Einschlag)
--   riddlebonk Echo: ein "?" ueber dem Gegner wird "!" und faellt ihm auf den  at, size, ahaAt, aha, dropAt, fall, curlAt,
--              Kopf, federt, wird wieder "?" und zerplatzt                   popAt, life (Test: freezeAt)
--   Helfer: makeGlyph/glyphSet (Zeichen aus Gold-Zylindern mit dunklem Umriss,
--              "?" <-> "!" stufenlos), riddleHat (Hut + Monokel eines Modells),
--              riddleConfetti (kleine Fragezeichen als BillboardGui), twinkle
--              (Funkeln), camFace (Richtung zur Kamera).
-- Erweiterte Parameter:
--   cinematic style "riddle"  tief auf der Seite der Luecke, Blick hoch auf den Wirbel, folgt dem Sturz, faehrt nach der Landung zurueck auf das riesige "!" samt Kaefig
--
-- 25.10. (Hoellensiegel, Teufel) - neue Bausteine:
--   hellsigil  Hoellensiegel am Boden: Flammenkranz, Ringe, Runen, Penta-     at, radius, draw, dur, spin, runes, points,
--              gramm Strich fuer Strich, violetter Wulst (Beam-Kreis).       blades, bladeLen, discs, burstAt, markFrom,
--              Eigenes Siegel: Orbit-Linien, Lichtklingen, Feuerringe,       mark, glowAt, pulseAt
--              Wirbelscheibe; `burstAt` Implosion + Sternbruch, Indigo-Ring.
--              `markFrom = "avatar"`: rotes Mal fliegt von der Dreizack-
--              spitze herueber, erst dann zeichnet sich der Kreis; `glowAt`
--              heller, `pulseAt` gleisst. Setzt ctx.hellCircle (target).
--   hellwings  der Teufel selbst: ausholen, Aufstieg mit Fluegelschlag und    height, crouch, rise, spins, grow, raiseAt,
--              Drehung, Dreizack recken, Schwung holen, Dreizack-Stoss       windAt, throwAt, homeAt, back (Test: freezeAt)
--              (Wurf), Rueckwaerts-Salto heim. Setzt avatarCf, hellTip.
--   cursed     der GEGNER als Klon: zuckt, Runenfesseln steigen hoch, er      hold, look, rings (Test: freezeAt)
--              zittert, schaut hoch; bei `hold` Original zurueck (Einschlag)
--   blacksun   schwarze Sonne ueber dem Dreizack: Pop, Glutstrahlen, Akkre-   size, lift, windAt, throwAt, fly, sink, arc,
--              tionsring, Flammenkranz, Sicheln; Wurf im Bogen mit Feuer-    echo, height (Test: freezeAt)
--              schweif in ctx.hellCircle, gestaucht, versinkt. echo = klein,
--              faellt von `height` auf den Gegner.
--   impactframe Anime-Impact-Frame (nur Besitzer): je Zeichen von `pattern`   pattern ("dld"), hold, lines
--              ein Bild ("d" dunkel-rot, "l" hell mit schwarzen Silhouetten),
--              Speedlines; eigener ColorCorrection (beruehrt sky nicht)
--   hellfire   Einschlag im Siegel: Feuersaeule (Beams mit Feuer-Textur),     at, height, radius, dur, widenAt, crownAt,
--              Windhiebe, Funkelsterne, Kronen-Schockwelle (hohe Zacken      crownR0, crownR, fanAt, slashes, stars, small
--              seitlich zur Kamera), pinker Flammenfaecher, Rauch;           (Test: freezeAt)
--              small = Echo
-- Erweiterte Parameter:
--   flash    tint = Color3   Farbe des Blitzes (Standard weiss)
-- 25.10. (Pulsar-Nova) — neue Bausteine:
--   pulsar     der Pulsar-Baerchi SELBST (Klon wie `ascend`): Bodenblitz, ein    ring, draw, crouchAt, crouch, rise, height,
--              Lichtpunkt zeichnet den Ring um ihn (12 Tick-Striche); er duckt  spins, grow, beamAt, beamLen, ticks,
--              sich, das Jetpack zuendet (Teile acc_flame/acc_nozzle/acc_visor), collapseAt, pulseAt, windAt, launchAt,
--              Aufstieg mit Drehung, der Ring wird sein Orbit-Ring; ab `beamAt`  fly, emergeAt, emerge, back, settle
--              Leuchtturm: Lichtkegel aus Visier und Jetpack, er dreht immer     (Test: freezeAt, trailLife)
--              schneller, der Visier-Kegel fegt zu den Zeiten in `ticks` durch
--              die Kamera jedes Clients (Blitz; Besitzer: Schleier, F22); bei
--              `collapseAt` wird er zum Neutronenstern (Anime-Sternbruch), pulst
--              (`pulseAt`), schiesst bei `launchAt` als Komet in den Gegner
--              (Landung = Einschlag); ab `emergeAt` rollt er sich aus dem Krater
--              auf, Rueckwaerts-Salto heim. Setzt avatarCf, pulsarHover, pulsarCam.
--   firedome   Feuerkuppel am Einschlag: kleine Kuppel (`mini`, "IFrameDome"),  at, radius, mini, miniFor, grow, pulseAt,
--              dann die grosse (flach weissgluehend: SmoothPlastic + Highlight,  flareAt, fade, burn, holes, skirt,
--              pinker Umriss), laufende Flammenbaender mit Luecken (Beams),      chunks (Test: freezeAt)
--              dunkle Loecher, Flammenkranz, Truemmer, Brandfleck; Pulse
--              (`pulseAt`, Besitzer: rosa), bei `flareAt` Aufflammen (Besitzer:
--              Weissblende -> Rosa), danach `burn` s Flammen am Gegner (Brand).
--              Setzt novaT0/novaCenter/novaRadius.
--   novaframe  Impact-Frames (nur Besitzer): invertiertes Bild - rosa Grund,     invert, white, fade, lines
--              tintenschwarze Silhouetten (ViewportFrame: Gegner + Teile, deren
--              Name mit "IFrame" beginnt), Speedlines zum Einschlag -, dann
--              Weiss, dann ausblenden; jedes Bild mindestens ein gerendertes Bild.
--   novabolt   Echo: kleiner Neutronenstern schiesst in den Gegner, eine kleine  at, fly, radius, life, size (Test: freezeAt)
--              Feuerkuppel ploppt auf.
--   Helfer: novaRing (Kreis aus 4 Bezier-Beams: zeichnen, Luecken-Muster),
--              novaVeil (Bildschirm-Schleier nur Besitzer), novaFlames (Flammen-
--              zungen als Beams), pulsarJet (Jetpack-Flammen + Visier), novaInk
--              (tintenschwarzer Klon fuer den Impact-Frame).
-- Erweiterte Parameter:
--   cinematic style "pulsar"  tief auf der Seite der Spielkamera, Blick hoch auf den Leuchtturm (die Kegel fegen ueber die Kamera), folgt dem Flug, faehrt nach dem Einschlag zurueck auf die ganze Feuerkuppel
-- 25.10.2026 (Erste Baerchis: Bauchrutscher, Tigersprung, Brennglas, Bass-Drop;
-- Stufe 2, ohne Kamerafahrt) — neue Bausteine:
--   moves      der Baerchi SELBST (Klon wie `ascend`) folgt Posen aus den       keys, hat, outline, hold, gap
--              DATEN: je Pose t, at ("home"|"land"|"target"|"arena"), dx/dy/dz    (Test: freezeAt)
--              (seitlich/hoch/vorwaerts), u + h (+ from/to: Punkt auf einem
--              Bogen, z. B. ein Regenbogen), pitch/yaw/roll in Umdrehungen
--              (pitch < 0 = Kopf nach vorn), scale, ease ("inout"|"in"|"out"|
--              "back"|"linear"), arc (Sprunghoehe), trail, burst/smoke
--              (Funken/Rauch beim Erreichen), hidden (Puff), tip (0..1 Hut
--              gelueftet, Teile aus `hat`), dxc (seitlich relativ zur Kamera-
--              Seite, + = zur Kamera hin). Drehung, Groesse, Hut und Sicht-
--              barkeit erben von der Pose davor, Ort und Versatz nicht.
--              Setzt avatarCf/avatarScale/avatarModel.
--   icepath    Eisbahn gefriert von den eigenen Fuessen bis vor den Gegner        draw, width, plates, spikes, over,
--              (Eisplatten, Reifkanten, Eiszacken, Glitzer), Schneefahne hinter  slideAt, slideEnd, meltAt, dur
--              dem rutschenden Klon, taut ab `meltAt`                             (Test: freezeAt)
--   iceblock   Gegner im Eisblock (folgt ihm, Leuchtumriss, Frosthauch),          at, appear, breakAt, dur, pad, small
--              zerspringt bei `breakAt` in Eissplitter                            (Test: freezeAt)
--   clawmarks  Krallenhiebe: je Hieb `claws` gluehende Streifen ueber die         at, count, every, claws, len, draw,
--              Vorderseite der Figur (folgen ihr), werden zu schwelenden          fade, dur (Test: freezeAt)
--              Kratzern (Brand)
--   pawprints  leuchtende Pfotenspuren von self zum Landeplatz (`gap` wie      count, every, sway, gap, pulseAt,
--              moves), blitzen bei                                                dur
--              `pulseAt`, verblassen am Ende                                      (Test: freezeAt)
--   lensbeam   Brennglas: grosse Lupe waechst aus der Pfote des Klons (seine      lens, appear, beamAt, burnAt, away,
--              kleine Lupe acc_lupe* verschwindet so lange), Lichtsaeule von      dur, small (Test: freezeAt)
--              oben, Brennkegel auf den Gegner (wandernder Punkt, Rauch),
--              `burnAt` Flammenstoss, Lupe zurueck in die Pfote
--   djset      Bass-Drop: Schallplatte unter dem DJ (SurfaceGui), Equalizer-      beats, buildAt, dropAt, dur, bars,
--              Balken um die Arena (Luecke zur Kamera, F44), Beats (Bodenring,    radius, disc (Test: freezeAt)
--              Kopfhoerer-Muscheln leuchten), Build-up, Drop (Welle, Bodenring
--              bis zum Zaun, Streusel am Gegner)
--   Helfer (Tabelle LOW): ease, groundY, fxAnchor (Funken/Rauch/Schweif-Anker),
--              sprinkles (bunte Staebchen als Rig).
-- 25.10.2026 (Erste Baerchis, Schub 2: Muenzregen, Shuriken-Sturm, Wurzelwall,
-- Regenbogenbruecke; Stufe 3, ohne Kamerafahrt) — neue Bausteine:
--   coinshower Muenzregen: Goldmuenzen spritzen bei `burstAt` aus den Fuessen     count, burstAt, rise, fly, every, dur,
--              des Gegners und fliegen nacheinander im Bogen zum Angreifer,      small (Test: freezeAt)
--              tuermen sich zum Haufen; Medaille/Rubin des Klons blitzen
--   ninjaclones Schattenklone (inkBear, rotes Stirnband) erscheinen in Puffs     count, radius, appearAt, every,
--              auf einem Ring um den Gegner (hinten/seitlich, F44), werfen      throwAt, flight, dashAt, dash,
--              Shuriken (Viersterne), die sich rund um ihn in den Boden        flashAt, dur, single (Test: freezeAt)
--              bohren; bei `dashAt` stuermen alle durch ihn (Lichtstreifen,
--              Puffs); `flashAt` blitzen die Shuriken und sinken ein;
--              `single`: ein Shuriken von self (Echo)
--   katana     sichelfoermiger Lichtschnitt ueber dem Oberkoerper des Gegners,     at, radius, draw, fade, lift
--              zur Kamera gedreht, Funken (Test: freezeAt)
--   roots      Wurzelwall: Wurzeln brechen rund um self aus dem Boden, winden     count, segs, radius, height, grow,
--              sich als Bogen ueber den Kopf zum Kaefig (Rinde, Moosknoten),    stagger, closeAt, sinkAt, dur
--              `closeAt` Puls + Blaetter + Gluehwuermchen, Blattkrone des       (Test: freezeAt)
--              Klons leuchtet (acc_leaf*), ab `sinkAt` zurueck in den Boden
--   rainbow    Regenbogenbruecke aus `bands` Bezier-Beams von self zum Lande-    bands, width, curve, tilt, lift, draw,
--              platz (gleicher Bogen wie `moves`-Posen mit `curve`/`tilt`),     dissolveAt, dur, gap, echo
--              zeichnet sich vom Baerchi weg, loest sich ab `dissolveAt` auf   (Test: freezeAt)
--   paintsplash Farbkleckse in Regenbogenfarben rund um die Figur am Boden       at, count, radius, dur (Test: freezeAt)
-- Erweiterte Parameter:
--   moves      Pose mit `u` + `curve` (+ `tilt`): Punkt auf der Bruecke LOW.bridge
--              (kubische Bezier wie ein Beam), sonst `u` + `h` = Parabel
--   Helfer (LOW): bridge (Bruecken-Punkt), tube (Zylinder-Stueck), shuriken (Vierstern).
-- 26.10.2026 (Himmelsgericht, Seraph-Baerchi; Stufe 4, Kamerafahrt "seraph") —
-- neue Bausteine (Helfer in EINER Tabelle SER, F51):
--   quake      Camera-Shake mit Wucht (Besitzer): Trauma-Modell (Staerke =        power, decay, angle, offset, freq,
--              Trauma^2, klingt linear ab), Drehung per Perlin-Rauschen auf       fov, fovIn, fovOut
--              Nick/Gier/Rollen (angle Grad bei Trauma 1), kleiner Versatz;
--              als LETZTER Offset je Bild (nach Spielkamera, Fahrt und shake,
--              F46); `fov` = optionaler FOV-Stoss (nicht zusammen mit hitstop)
--   seraphwings die sechs Fluegel (acc_wing*) und der Heiligenschein (acc_halo)   snapAt {3}, haloAt, launchAt, diveAt,
--              des `moves`-Klons: Paare schnappen bei snapAt auf (Funken,         landAt, foldAt, dur, ghosts
--              Lichtfedern = Beams mit Feder-Bild, ForceField), schlagen, im      (Test: freezeAt)
--              Flug Nachbilder (chronoGhost), beim Schweben weit und hoch, im
--              Sturz angelegt, nach landAt gespreizt, ab foldAt angelegt;
--              Heiligenschein ab haloAt Neon, dreht, pulst, blitzt bei landAt
--   seraphspear Speer aus Licht: entsteht klein am Himmelstor, sinkt in die        formAt, form, grabAt, plantAt, pullAt,
--              Pfoten (folgt avatarCf), zielt auf die Fuesse des Gegners, im      length, dur (Test: freezeAt)
--              Sturz voraus, steckt ab plantAt im Boden (setzt seraphHit),
--              zerfaellt ab pullAt zu Federn und Funken
--   halogate   Himmelstor ueber der Arena (lift): drei Ringe aus Bezier-Beams    at, lift, radius, open, raysAt,
--              (novaRing: aussen weiss breit, Honigring, Gold gestrichelt),       ticks {}, offAt, fallAt, fallFor,
--              oeffnet klein -> gross (F43), Lichtschaefte ab raysAt (drehen),   popAt, dur (Test: freezeAt)
--              pulsen bei ticks, reissen bei offAt ab; bei fallAt stuerzen die
--              Ringe zur Lichtsaeule (seraphHit) und werden zu Kondensringen;
--              die kleine Krone landet schief auf dem Gegner, ploppt bei popAt.
--              Setzt seraphGate, seraphGateR
--   seraphmark Zielmarke unter dem Gegner (Decal `halo`, schrumpft radius ->      at, radius, shrinkTo, ticks {},
--              shrinkTo, blitzt bei ticks), Lichtfaden vom Tor; Gegner-Klon     releaseAt, dur (Test: freezeAt)
--              schaut hoch, zittert, hopst; releaseAt: Klon weg (Rueckstoss, F15)
--   lightnuke  Nuke in himmlischer Haut (2.5) am seraphHit: kleiner Kern (F36),   at, core, columnAt, height, waveAt,
--              Lichtsaeule (zwei Beams `column`, bis height), Lichtwand bis zum   domeAt, dome, domeFor, scorch, dur
--              Zaun (hellRing, heller Rand) + zweite Welle, Brandfleck mit       (Test: freezeAt)
--              goldenem Siegel (`halo`) und sechs Rissen bis dur, goldene Kuppel
--              (ForceField, zwei Schalen) ab domeAt, Glut; `far`: nur Kern + Saeule
-- Erweiterte Parameter:
--   impactframe dark / light / fill (Color3): Palette der dunklen und hellen Bilder
--              (Standard Hoellensiegel-Rot; Himmelsgericht Indigo/Warmweiss)
--   cinematic style "seraph"  tief vorn-seitlich, folgt dem Klon in die Hoehe (Blick kippt hoch,
--              Tor im Bild), Push-in beim Zielen, Peitsche im Sturz, harter Schnitt in die
--              Untersicht am Einschlag, Ende Custom
--
-- Fuer jeden Schritt:
--   extra = true  Beiwerk — faellt auf niedriger Grafikstufe weg
--                 (PARTICLE_BUDGET.EXTRAS_MIN), der Kernmoment bleibt.
--   tex = "<key>" Bild aus TEXTURES[<Faehigkeit>][key]. Ist keine ID
--                 eingetragen (0), laeuft der Rueckfall (Neon-Teile,
--                 Standard-Partikel).
-- Fuer einen Eintrag:
--   echo     eigene Schritt-Liste fuer das Echo (ab dem 2. Einsatz im Lauf,
--            Laenge TIERS[tier].echo). Ohne `echo`: die ersten zwei
--            Welt-Effekte der Show, verkuerzt.
--   impactAt Sekunde, in der die Show den Gegner trifft (sonst geschaetzt,
--            siehe getImpactTime).
--
-- Jede Faehigkeit ist eine EIGENE Komposition (andere Bausteine, Reihenfolge,
-- Formen und Farben). Geprueft: tools/sim/egg_tree_check.lua meldet doppelte
-- Kompositionen.
--
-- ============================================================
-- KAMERA (offene Entscheidung 1 aus dem Konzept)
-- ============================================================
-- ANNAHME: Der Spieler behaelt seine Kamera. Nur auf Stufe 4 (Cosmic bis
-- Omega) gibt es eine KURZE Kamerafahrt (hoechstens 2,5 s), danach springt
-- die Kamera zurueck. Abschaltbar ueber CINEMATIC_CAMERA. Zuschauer (andere
-- Spieler) sehen nur die Effekte in der Welt, nie Kamera oder Farbfilter.

local CINEMATIC_CAMERA = true

-- Spektakel-Stufen. `echo` = wie lange die kurze Wiederholung dauert, wenn
-- der Skill im selben Lauf noch einmal kommt (die volle Show laeuft nur beim
-- ersten Einsatz eines Laufs — sonst wuerde ein Lauf mit 40 Stages Minuten
-- dauern).
local TIERS = {
	[1] = { name = "Sauber",     maxDuration = 1.5, sky = false, cinematic = false, echo = 0.35 },
	[2] = { name = "Gross",      maxDuration = 3.0, sky = false, cinematic = false, echo = 0.45 },
	[3] = { name = "Himmel",     maxDuration = 4.0, sky = true,  cinematic = false, echo = 0.55 },
	[4] = { name = "Kosmisch",   maxDuration = 6.0, sky = true,  cinematic = true,  echo = 0.65 },
}

-- Partikel-Budget: Faktor auf alle Stueckzahlen je Grafikstufe (1..10 in
-- Roblox). Auf Handys mit niedriger Stufe bleibt die Show erkennbar, aber
-- leichter. Unter MIN_COUNT faellt keine Zahl.
local PARTICLE_BUDGET = {
	low    = 0.35,  -- Grafikstufe 1..3
	medium = 0.65,  -- 4..6
	high   = 1.0,   -- 7..10
	MIN_COUNT = 2,
	-- v16: unter diesem Faktor fallen Schritte mit `extra = true` und das
	-- Beiwerk der Bausteine (Adern, Glitzer) weg. Niedrig = 0,35 (Besitzer);
	-- Zuschauer bekommen x0,6, sehen also nur auf hoher Stufe Beiwerk.
	EXTRAS_MIN = 0.5,
}

-- v16: Bilder je Faehigkeit (Asset-IDs). 0 = noch nicht hochgeladen -> der
-- Baustein nimmt seinen Rueckfall. Die PNGs liegen unter assets/vfx/<faehigkeit>/
-- (gezeichnet von tools/render_vfx_glacier.py).
local TEXTURES: { [string]: { [string]: number } } = {
	GlacierFrost = {
		breath    = 128701191651763,  -- assets/vfx/glacier_frost/breath.png     (breath)
		veins     = 108102700609452,  -- assets/vfx/glacier_frost/veins.png      (groundmark)
		crack     = 83712175066666,  -- assets/vfx/glacier_frost/crack.png      (crack)
		spike     = 108620496348253,  -- assets/vfx/glacier_frost/spike.png      (spikes)
		frostring = 122675729761295,  -- assets/vfx/glacier_frost/frostring.png  (ring)
		flake     = 131706213425867,  -- assets/vfx/glacier_frost/flake.png      (snowfall)
	},
	SeraphGrace = {
		feather   = 118911033478580,  -- assets/vfx/seraph_grace/feather.png     (wings, snowfall)
		halo      = 76906350593962,  -- assets/vfx/seraph_grace/halo.png        (halo)
		comb      = 83718216641782,  -- assets/vfx/seraph_grace/comb.png        (honeycomb)
		column    = 71806259051383,  -- assets/vfx/seraph_grace/column.png      (pillar, Beam)
		cloudrim  = 127806895070731,  -- assets/vfx/seraph_grace/cloudrim.png    (ring lift)
		spark     = 106826574005325,  -- assets/vfx/seraph_grace/spark.png       (wings: Funken)
	},
	CometImpact = {
		glow      = 78155128670440,  -- assets/vfx/comet_impact/glow.png        (comet: Glut des Kopfs)
		tail      = 101351895284831,  -- assets/vfx/comet_impact/tail.png        (comet: Schweif-Streifen)
		crater    = 91967482890855,  -- assets/vfx/comet_impact/crater.png      (crater: Bodenbild)
		stardust  = 90923615677992,  -- assets/vfx/comet_impact/stardust.png    (dust, comet-Funken)
		shockring = 94175665045126,  -- assets/vfx/comet_impact/shockring.png   (ring)
		debris    = 109358680968881,  -- assets/vfx/comet_impact/debris.png      (shards)
	},
	ShadeSlash = {
		silhouette = 125015870422458, -- assets/vfx/shade_slash/silhouette.png   (silhouette)
		shred      = 94910203650752, -- assets/vfx/shade_slash/shred.png        (shards: Schattenfetzen)
		cut        = 119530388511860, -- assets/vfx/shade_slash/cut.png          (cut: Schnittlinie)
		pool       = 138683105162589, -- assets/vfx/shade_slash/pool.png         (shades: Pfuetze)
		smoke      = 84950422585772, -- assets/vfx/shade_slash/smoke.png        (silhouette/shades: Rauch)
	},
	OmegaStrike = {
		omega     = 74052847419711,  -- assets/vfx/omega_strike/omega.png       (omega sky: Ω-Ring)
		spectrum  = 130680123382821,  -- assets/vfx/omega_strike/spectrum.png    (wipe: Spektrum-Verlauf)
		orb       = 108821180032706,  -- assets/vfx/omega_strike/orb.png         (converge: Lichtpunkt, je Pfadfarbe eingefaerbt)
		brand     = 99596249189534,  -- assets/vfx/omega_strike/brand.png       (omega brand: Ω-Brandzeichen)
		shockring = 113660680485949,  -- assets/vfx/omega_strike/shockring.png   (ring)
		column    = 88556419138916,  -- assets/vfx/omega_strike/column.png      (pillar: Lichtsaeule, Beam)
	},
	OmegaWorldsEnd = {
		column    = 88556419138916,  -- wie OmegaStrike (pillar: Lichtsaeule im Finisher-Bonus)
	},
	PulsarNova = {
		-- 25.10.2026: wiederverwendete Bilder (keine neuen Uploads noetig)
		orb       = 108821180032706,  -- wie OmegaStrike.orb (pulsar: Schein des Neutronensterns)
		glow      = 78155128670440,  -- wie CometImpact.glow (pulsar: Leuchtturm-Blitz)
		tail      = 101351895284831,  -- wie CometImpact.tail (pulsar: Schweif)
		crater    = 91967482890855,  -- wie CometImpact.crater (firedome: Brandfleck)
		stardust  = 90923615677992,  -- wie CometImpact.stardust (dust)
		shockring = 94175665045126,  -- wie CometImpact.shockring (ring)
	},
	SeraphJudgment = {
		-- 26.10.2026: wiederverwendete Bilder (keine neuen Uploads noetig)
		feather   = 118911033478580,  -- wie SeraphGrace.feather (seraphwings: Lichtfedern, snowfall, shards)
		halo      = 76906350593962,  -- wie SeraphGrace.halo (ring: Marke, seraphmark, lightnuke: Siegel)
		column    = 71806259051383,  -- wie SeraphGrace.column (lightnuke: Lichtsaeule, pillar im Echo)
		spark     = 106826574005325,  -- wie SeraphGrace.spark
		stardust  = 90923615677992,  -- wie CometImpact.stardust (dust)
	},
}

-- ============================================================
-- SOUNDS
-- ============================================================
-- Sound-Slots je Faehigkeit. Die Werte sind Asset-IDs (Zahl) oder ein
-- eingebauter Roblox-Sound ("rbxasset://..."). Fehlt ein Eintrag, bleibt
-- der Slot still — der Baukasten kennt die Slots trotzdem (Konzept: Platz-
-- halter erlaubt). Die Bibliothek unten ist in SOUND_LIBRARY benannt, die
-- Faehigkeiten verweisen nur auf Namen.
local SOUND_LIBRARY: { [string]: string } = {
	-- Audio-Rework 16.10.: Namen aus ReplicatedStorage/Audio (Audio.SFX). Die Id
	-- eines Klangs aendert man dort, nicht hier.
	whoosh    = "fx_whoosh",
	hit       = "fx_hit",
	ping      = "fx_ping",
	boom      = "fx_boom",
	glass     = "fx_glass",
	splat     = "fx_splat",
	snap      = "fx_snap",
	rocket    = "fx_rocket",
	rumble    = "fx_rumble",
	slash     = "fx_slash",
	lunge     = "fx_lunge",
	thunder   = "fx_thunder",
	ghost     = "fx_ghost",
	bass      = "fx_bass",
	flash     = "fx_flash",
}

-- v15: Lautstaerke. Die eingebauten Klaenge sind laut und hart (Donner,
-- Rakete, Glas) — in v14 klangen manche Shows aggressiv. Deshalb leiser,
-- jeder Ton wird nach MAX_SECONDS ausgeblendet (FADE_SECONDS lang), und ein
-- Echo (jeder weitere Einsatz im Lauf) ist noch einmal leiser.
-- Zuschauer hoeren deutlich leiser als der Besitzer, ROLLOFF_* sorgt dafuer,
-- dass ein Kampf auf der Nachbar-Insel kaum durchdringt.
local SOUND = {
	OWNER_VOLUME     = 1.0,    -- Faktor auf die Lautstaerke des Klangs (Audio.SFX)
	SPECTATOR_VOLUME = 0.4,    -- Faktor fuer Zuschauer
	ECHO_FACTOR      = 0.6,
	MAX_SECONDS      = 1.6,
	FADE_SECONDS     = 0.4,
	ROLLOFF_MIN      = 10,
	ROLLOFF_MAX      = 90,
}

export type Step = { [string]: any }
export type SkillFX = {
	tier     : number,
	duration : number,
	color    : Color3,
	color2   : Color3,
	sounds   : { [string]: string },   -- Slots charge/strike/impact (+ eigene, z. B. rise)
	-- Tonhoehe je Slot, damit dieselbe Datei je Faehigkeit anders klingt.
	pitch    : number?,
	steps    : { Step },
	echo     : { Step }?,   -- v16: eigenes Echo (siehe oben)
	impactAt : number?,     -- v16: Treffer-Sekunde der vollen Show
}

local C = Color3.fromRGB

local FX: { [string]: SkillFX } = {

	----------------------------------------------------------------------------
	-- Welle 1: Common bis Rare — sauber und kurz (1 bis 1,5 s)
	----------------------------------------------------------------------------

	BasicPunch = {
		tier = 1, duration = 1.0, color = C(255, 236, 200), color2 = C(255, 180, 120),
		sounds = { strike = "lunge", impact = "hit" }, pitch = 1.1,
		steps = {
			{ t = 0.00, fx = "aura",  at = "self", size = 3, dur = 0.35 },
			{ t = 0.35, fx = "sound", slot = "strike" },
			{ t = 0.45, fx = "ring",  at = "target", radius = 4, dur = 0.35 },
			{ t = 0.45, fx = "sound", slot = "impact" },
			{ t = 0.50, fx = "sparks", at = "target", count = 10, dur = 0.4 },
		},
	},

	GummyShield = {
		tier = 1, duration = 1.2, color = C(110, 230, 120), color2 = C(200, 255, 200),
		sounds = { charge = "ping", strike = "splat" }, pitch = 0.9,
		steps = {
			{ t = 0.00, fx = "sound",  slot = "charge" },
			{ t = 0.00, fx = "rise",   at = "self", count = 8, dur = 0.5 },
			{ t = 0.40, fx = "bubble", at = "self", size = 6, dur = 0.8 },
			{ t = 0.45, fx = "sound",  slot = "strike" },
			{ t = 0.50, fx = "ring",   at = "self", radius = 5, dur = 0.4 },
		},
	},

	SugarRush = {
		tier = 1, duration = 1.2, color = C(255, 220, 60), color2 = C(255, 120, 200),
		sounds = { charge = "whoosh", strike = "ping" }, pitch = 1.4,
		steps = {
			{ t = 0.00, fx = "sound", slot = "charge" },
			{ t = 0.00, fx = "spiral", at = "self", radius = 4, count = 10, dur = 0.5, outward = true },
			{ t = 0.30, fx = "aura",   at = "self", size = 4, dur = 0.8 },
			{ t = 0.45, fx = "sound", slot = "strike" },
			{ t = 0.50, fx = "rise",   at = "self", count = 12, dur = 0.6 },
		},
	},

	IceSlam = {
		tier = 1, duration = 1.4, color = C(150, 220, 255), color2 = C(230, 250, 255),
		sounds = { charge = "whoosh", strike = "glass", impact = "boom" }, pitch = 1.2,
		steps = {
			{ t = 0.00, fx = "sound",  slot = "charge" },
			{ t = 0.00, fx = "aura",   at = "self", size = 3.5, dur = 0.45 },
			{ t = 0.40, fx = "meteor", at = "target", size = 2.2, height = 14, dur = 0.35 },
			{ t = 0.75, fx = "sound",  slot = "strike" },
			{ t = 0.75, fx = "frost",  at = "target", count = 8, dur = 0.6 },
			{ t = 0.78, fx = "shards", at = "target", count = 8, size = 0.6, dur = 0.5 },
		},
	},

	FireBite = {
		tier = 1, duration = 1.3, color = C(255, 110, 30), color2 = C(255, 220, 80),
		sounds = { strike = "snap", impact = "rumble" }, pitch = 1.1,
		steps = {
			{ t = 0.00, fx = "aura",   at = "self", size = 3, dur = 0.4 },
			{ t = 0.35, fx = "sound",  slot = "strike" },
			{ t = 0.40, fx = "projectile", size = 1.2, dur = 0.3 },
			{ t = 0.70, fx = "sparks", at = "target", count = 16, dur = 0.6 },
			{ t = 0.70, fx = "sound",  slot = "impact" },
			{ t = 0.75, fx = "rise",   at = "target", count = 8, dur = 0.55 },
		},
	},

	SugarStorm = {
		tier = 1, duration = 1.5, color = C(255, 160, 210), color2 = C(255, 255, 255),
		sounds = { charge = "rumble", impact = "splat" }, pitch = 1.3,
		steps = {
			{ t = 0.00, fx = "sound",  slot = "charge" },
			{ t = 0.00, fx = "spiral", at = "self", radius = 6, count = 14, dur = 0.7, outward = true },
			{ t = 0.60, fx = "wave",   at = "self", radius = 10, dur = 0.5 },
			{ t = 0.75, fx = "shards", at = "target", count = 12, size = 0.4, dur = 0.6 },
			{ t = 0.75, fx = "sound",  slot = "impact" },
		},
	},

	ShardBlast = {
		tier = 1, duration = 1.4, color = C(120, 220, 255), color2 = C(200, 140, 255),
		sounds = { charge = "ping", strike = "rocket", impact = "glass" }, pitch = 1.5,
		steps = {
			{ t = 0.00, fx = "sound",  slot = "charge" },
			{ t = 0.00, fx = "shards", at = "self", count = 6, size = 0.5, dur = 0.4, inward = true },
			{ t = 0.40, fx = "sound",  slot = "strike" },
			{ t = 0.40, fx = "projectile", size = 0.8, dur = 0.25, count = 3 },
			{ t = 0.70, fx = "shards", at = "target", count = 14, size = 0.6, dur = 0.6 },
			{ t = 0.70, fx = "sound",  slot = "impact" },
		},
	},

	----------------------------------------------------------------------------
	-- Welle 2: Epic und Legendary — Bodenringe, Lichtsaeulen, Wackeln (2 bis 3 s)
	----------------------------------------------------------------------------

	GoldRush = {
		tier = 2, duration = 2.2, color = C(255, 200, 50), color2 = C(255, 250, 200),
		sounds = { charge = "ping", strike = "rumble", impact = "boom" }, pitch = 0.9,
		steps = {
			{ t = 0.00, fx = "sound",  slot = "charge" },
			{ t = 0.00, fx = "ring",   at = "self", radius = 7, dur = 0.7 },
			{ t = 0.20, fx = "pillar", at = "self", height = 18, width = 3, dur = 0.9 },
			{ t = 0.90, fx = "beam",   width = 1.2, dur = 0.7 },
			{ t = 0.90, fx = "sound",  slot = "strike" },
			{ t = 1.20, fx = "rise",   at = "target", count = 14, dur = 0.8, toSelf = true },
			{ t = 1.50, fx = "shake",  power = 0.4, dur = 0.3 },
			{ t = 1.50, fx = "sound",  slot = "impact" },
		},
	},

	BlackHole = {
		tier = 2, duration = 2.8, color = C(80, 30, 140), color2 = C(10, 5, 20),
		sounds = { charge = "rumble", strike = "boom" }, pitch = 0.6,
		steps = {
			{ t = 0.00, fx = "sound",  slot = "charge" },
			{ t = 0.00, fx = "aura",   at = "target", size = 2, dur = 1.6, dark = true },
			{ t = 0.10, fx = "spiral", at = "target", radius = 12, count = 30, dur = 1.6 },
			{ t = 0.20, fx = "ring",   at = "target", radius = 9, dur = 1.4, shrink = true },
			{ t = 1.70, fx = "wave",   at = "target", radius = 12, dur = 0.5 },
			{ t = 1.70, fx = "shake",  power = 0.7, dur = 0.5 },
			{ t = 1.70, fx = "sound",  slot = "strike" },
			{ t = 1.75, fx = "shards", at = "target", count = 18, size = 0.5, dur = 0.8 },
		},
	},

	ChromaBlast = {
		tier = 2, duration = 2.6, color = C(255, 60, 120), color2 = C(60, 200, 255),
		sounds = { charge = "ping", strike = "rocket", impact = "boom" }, pitch = 1.2,
		steps = {
			{ t = 0.00, fx = "sound",  slot = "charge" },
			{ t = 0.00, fx = "aura",   at = "self", size = 5, dur = 1.0, rainbow = true },
			{ t = 0.10, fx = "ring",   at = "self", radius = 8, dur = 0.9, rainbow = true },
			{ t = 1.00, fx = "beam",   width = 2.2, dur = 0.8, rainbow = true },
			{ t = 1.00, fx = "sound",  slot = "strike" },
			{ t = 1.30, fx = "pillar", at = "target", height = 22, width = 4, dur = 0.8, rainbow = true },
			{ t = 1.30, fx = "shake",  power = 0.5, dur = 0.35 },
			{ t = 1.30, fx = "sound",  slot = "impact" },
		},
	},

	TitanMode = {
		tier = 2, duration = 2.4, color = C(200, 170, 110), color2 = C(255, 240, 200),
		sounds = { charge = "rumble", strike = "boom" }, pitch = 0.7,
		steps = {
			{ t = 0.00, fx = "sound",  slot = "charge" },
			{ t = 0.00, fx = "shake",  power = 0.3, dur = 0.8 },
			{ t = 0.00, fx = "ring",   at = "self", radius = 10, dur = 0.8 },
			{ t = 0.30, fx = "pillar", at = "self", height = 26, width = 6, dur = 1.0 },
			{ t = 1.00, fx = "bubble", at = "self", size = 9, dur = 1.3, hex = true },
			{ t = 1.00, fx = "sound",  slot = "strike" },
			{ t = 1.10, fx = "shards", at = "self", count = 12, size = 0.9, dur = 0.7, stone = true },
		},
	},

	----------------------------------------------------------------------------
	-- Welle 3: Mythic und Divine — Himmel verfaerbt sich, Zeitlupe (3 bis 4 s)
	----------------------------------------------------------------------------

	BigBang = {
		tier = 3, duration = 3.6, color = C(255, 255, 255), color2 = C(140, 120, 255),
		sounds = { charge = "rumble", strike = "boom", impact = "rocket" }, pitch = 0.8,
		steps = {
			{ t = 0.00, fx = "sound",  slot = "charge" },
			{ t = 0.00, fx = "sky",    tint = C(150, 140, 255), brightness = -0.15, saturation = -0.3, dur = 3.0 },
			{ t = 0.00, fx = "spiral", at = "arena", radius = 18, count = 36, dur = 1.4 },
			{ t = 1.40, fx = "flash",  dur = 0.35 },
			{ t = 1.40, fx = "hitstop", dur = 0.3 },
			{ t = 1.70, fx = "wave",   at = "arena", radius = 30, dur = 0.8 },
			{ t = 1.70, fx = "sound",  slot = "strike" },
			{ t = 1.75, fx = "sparks", at = "arena", count = 50, dur = 1.2, stars = true },
			{ t = 1.75, fx = "shake",  power = 1.0, dur = 0.6 },
		},
	},

	PhoenixRebirth = {
		tier = 3, duration = 3.4, color = C(255, 120, 30), color2 = C(255, 230, 100),
		sounds = { charge = "rumble", strike = "rocket", impact = "boom" }, pitch = 1.0,
		steps = {
			{ t = 0.00, fx = "sky",    tint = C(255, 170, 120), brightness = 0.05, saturation = 0.2, dur = 3.0 },
			{ t = 0.00, fx = "sound",  slot = "charge" },
			{ t = 0.00, fx = "pillar", at = "self", height = 30, width = 5, dur = 1.4 },
			{ t = 0.20, fx = "rise",   at = "self", count = 24, dur = 1.4, wings = true },
			{ t = 1.50, fx = "hitstop", dur = 0.25 },
			{ t = 1.70, fx = "projectile", size = 2.5, dur = 0.4, flame = true },
			{ t = 1.70, fx = "sound",  slot = "strike" },
			{ t = 2.10, fx = "wave",   at = "target", radius = 12, dur = 0.6 },
			{ t = 2.10, fx = "sound",  slot = "impact" },
			{ t = 2.10, fx = "shake",  power = 0.7, dur = 0.4 },
		},
	},

	GlacierFrost = {
		-- v16 (Show-Paket, Prompt 1): klar, kalt, unaufhaltsam.
		-- Aufladen: Atem, Boden friert, Reif-Adern, Kristalle auf Ohren und
		--   Schultern, Himmel kuehlt zu blassem Blaugrau (nur Besitzer).
		-- Schlag: Aufstampfen, Zickzack-Riss zum Gegner, Dornen-Welle.
		-- Einschlag (2,25 s): letzter Dorn trifft, Kristalle bis zur Huefte,
		--   Zeitlupe, Frostring, danach Reifschimmer und Schneeflocken.
		-- Farben: Gletscherblau, Eisweiss, tiefes Tuerkis (Dorn-Mix im
		--   Baustein), reines Weiss auf Kanten und Spitzen.
		tier = 3, duration = 3.6, color = C(150, 215, 245), color2 = C(235, 250, 255),
		sounds = { charge = "whoosh", strike = "boom", impact = "glass" }, pitch = 0.8,
		impactAt = 2.25,
		steps = {
			-- 1. Aufladen
			{ t = 0.00, fx = "sky",        tint = C(205, 220, 235), brightness = 0.02, saturation = -0.45, dur = 3.3 },
			{ t = 0.00, fx = "sound",      slot = "charge" },
			{ t = 0.00, fx = "breath",     at = "self", count = 10, dur = 1.0, tex = "breath", extra = true },
			{ t = 0.10, fx = "groundmark", at = "self", radius = 6, dur = 3.2, veins = 7, tex = "veins" },
			{ t = 0.45, fx = "frost",      at = "self", perch = true, count = 8, dur = 1.6, glint = true, extra = true },
			-- 2. Schlag (Aufstampfen bei 1,30)
			{ t = 1.30, fx = "ring",       at = "self", ground = true, radius = 3.5, dur = 0.35, tex = "frostring" },
			{ t = 1.30, fx = "shake",      power = 0.35, dur = 0.2 },
			{ t = 1.30, fx = "sound",      slot = "strike" },
			{ t = 1.35, fx = "crack",      dur = 0.45, linger = 1.9, segments = 7, amp = 0.9, tex = "crack" },
			{ t = 1.40, fx = "spikes",     count = 7, dur = 0.7, rise = 0.16, minHeight = 1.0, maxHeight = 3.4, linger = 1.6, tex = "spike" },
			-- 3. Einschlag (letzter Dorn: 1,40 + 0,7 x 6/7 + 0,16 = 2,16 .. 2,25)
			{ t = 2.25, fx = "frost",      at = "target", legs = true, count = 14, dur = 1.3 },
			{ t = 2.25, fx = "hitstop",    dur = 0.35 },
			{ t = 2.25, fx = "sound",      slot = "impact" },
			{ t = 2.28, fx = "ring",       at = "target", ground = true, radius = 11, dur = 0.9, tex = "frostring" },
			{ t = 2.45, fx = "snowfall",   at = "target", count = 16, dur = 1.15, tex = "flake", extra = true },
		},
		-- Echo (0,55 s): Aufstampfen, Zickzack-Riss, Kristalle am Gegner.
		echo = {
			{ t = 0.00, fx = "ring",  at = "self", ground = true, radius = 3, dur = 0.25 },
			{ t = 0.00, fx = "sound", slot = "strike" },
			{ t = 0.03, fx = "crack", dur = 0.2, linger = 0.4, segments = 5, amp = 0.7 },
			{ t = 0.23, fx = "frost", at = "target", legs = true, count = 8, dur = 0.6 },
			{ t = 0.23, fx = "sound", slot = "impact" },
		},
	},

	PhantomOmen = {
		-- Passiv: im Kampf nie ausgeloest. Die Show laeuft beim Legen eines
		-- aufgestiegenen Eis (EggLayService feuert SkillFXPlay).
		tier = 3, duration = 2.0, color = C(150, 90, 230), color2 = C(40, 20, 70),
		sounds = { charge = "ghost", strike = "ping" }, pitch = 0.6,
		steps = {
			{ t = 0.00, fx = "sound",  slot = "charge" },
			{ t = 0.00, fx = "aura",   at = "self", size = 6, dur = 1.2, dark = true },
			{ t = 0.30, fx = "spiral", at = "self", radius = 5, count = 16, dur = 1.0, outward = true },
			{ t = 1.20, fx = "pillar", at = "self", height = 12, width = 1.5, dur = 0.7 },
			{ t = 1.20, fx = "sound",  slot = "strike" },
		},
	},

	SeraphGrace = {
		-- v16 (Show-Paket, Prompt 2): warm, feierlich, ruhig.
		-- Aufladen: Lichtfluegel entfalten sich Feder fuer Feder, Heiligenschein
		--   aus Honiggold dreht sich ueber dem Kopf, das Licht wird waermer
		--   (nur Besitzer).
		-- Schlag: rundes Wolkenloch mit leuchtendem Rand, breite Lichtsaeule
		--   faellt auf den Baerchi (nicht auf den Gegner), Federn rieseln.
		-- Einschlag: Wabenmuster laeuft von den Fuessen zum Kopf und zieht ein
		--   (fertig bei 3,4 s = Show-Ende), warmer Lichtpuls ueber den Boden,
		--   Fluegel falten sich und zerfallen in Funken.
		-- HP-Balken: seit 10.10. setzt PitArenaService ihn im Einschlag-
		--   Moment (impactAt = 3,4 s = Show-Ende), es gibt keinen Stoss danach
		--   mehr. Der warme Schein bleibt `hold` = 1,0 s an der Figur.
		tier = 3, duration = 3.4, color = C(255, 196, 70), color2 = C(255, 246, 225),
		sounds = { charge = "whoosh", strike = "ping", impact = "ping" }, pitch = 1.3,
		impactAt = 3.4,
		steps = {
			-- 1. Aufladen
			{ t = 0.00, fx = "sky",       tint = C(255, 236, 205), brightness = 0.08, saturation = 0.15, dur = 3.3 },
			{ t = 0.00, fx = "sound",     slot = "charge" },
			{ t = 0.00, fx = "wings",     at = "self", count = 7, span = 2.6, dur = 3.4, foldAt = 3.05, tex = "feather", sparkTex = "spark" },
			{ t = 0.30, fx = "halo",      at = "self", radius = 0.9, lift = 0.7, count = 14, dur = 3.0, tex = "halo" },
			-- 2. Schlag
			{ t = 1.15, fx = "ring",      at = "self", lift = 26, radius = 5, dur = 2.1, tex = "cloudrim", extra = true },
			{ t = 1.35, fx = "pillar",    at = "self", fromSky = true, feet = true, soft = true, second = true, height = 26, width = 4.5, dur = 1.5, tex = "column" },
			{ t = 1.35, fx = "sound",     slot = "strike" },
			{ t = 1.60, fx = "snowfall",  at = "self", noShell = true, lift = 3, size = 0.45, count = 8, dur = 1.6, tex = "feather", extra = true },
			-- 3. Einschlag (Waben fertig eingezogen bei 2,55 + 0,5 + 0,35 = 3,40)
			{ t = 2.55, fx = "honeycomb", at = "self", cols = 9, rows = 6, sweep = 0.5, pull = 0.35, hold = 1.0, tex = "comb" },
			{ t = 3.30, fx = "ring",      at = "self", ground = true, radius = 14, dur = 0.8 },
			{ t = 3.35, fx = "sound",     slot = "impact" },
		},
		-- Echo (0,55 s): schmale, kurze Lichtsaeule und das einziehende Wabenmuster.
		echo = {
			{ t = 0.00, fx = "pillar",    at = "self", fromSky = true, feet = true, soft = true, second = true, height = 18, width = 2.2, dur = 0.45, tex = "column" },
			{ t = 0.00, fx = "sound",     slot = "strike" },
			{ t = 0.12, fx = "honeycomb", at = "self", cols = 7, rows = 4, sweep = 0.18, pull = 0.18, hold = 0.9, tex = "comb" },
			{ t = 0.45, fx = "sound",     slot = "impact" },
		},
	},

	AuroraVeil = {
		tier = 3, duration = 3.3, color = C(90, 255, 180), color2 = C(170, 110, 255),
		sounds = { charge = "whoosh", strike = "ping" }, pitch = 1.2,
		steps = {
			{ t = 0.00, fx = "sky",    tint = C(170, 255, 220), brightness = -0.05, saturation = 0.4, dur = 3.0 },
			{ t = 0.00, fx = "sound",  slot = "charge" },
			{ t = 0.00, fx = "beam",   width = 6, dur = 2.0, curtain = true },
			{ t = 0.40, fx = "spiral", at = "self", radius = 6, count = 22, dur = 1.4, outward = true },
			{ t = 1.60, fx = "aura",   at = "self", size = 6, dur = 1.4, rainbow = true },
			{ t = 1.60, fx = "sound",  slot = "strike" },
			{ t = 1.70, fx = "rise",   at = "self", count = 16, dur = 1.0 },
		},
	},

	EclipseShroud = {
		tier = 3, duration = 3.5, color = C(30, 20, 50), color2 = C(255, 180, 80),
		sounds = { charge = "ghost", strike = "bass" }, pitch = 0.5,
		steps = {
			{ t = 0.00, fx = "sky",    tint = C(110, 90, 140), brightness = -0.35, saturation = -0.5, dur = 3.2 },
			{ t = 0.00, fx = "sound",  slot = "charge" },
			{ t = 0.20, fx = "meteor", at = "target", size = 7, height = 30, dur = 1.4, dark = true, slow = true },
			{ t = 1.60, fx = "ring",   at = "target", radius = 7, dur = 1.0, corona = true },
			{ t = 1.60, fx = "hitstop", dur = 0.35 },
			{ t = 1.70, fx = "aura",   at = "target", size = 5, dur = 1.4, dark = true },
			{ t = 1.70, fx = "sound",  slot = "strike" },
		},
	},

	----------------------------------------------------------------------------
	-- Welle 4: Cosmic bis Omega — reine Schaden-Show (4 bis 6 s)
	----------------------------------------------------------------------------

	CometImpact = {
		-- v16 (Show-Paket, Prompt 3): gewaltig, schnell, triumphal, nicht
		-- chaotisch — der Komet ist die ganze Zeit klar zu sehen.
		-- Aufladen: Himmel wird in 1 s zur Nacht, Sterne an (nur Besitzer);
		--   hoch oben funkelt ein Punkt und waechst; um den Gegner waechst ein
		--   dunkler Schattenkreis mit.
		-- Schlag (1,5 s): der Komet faellt, bricht durch die Wolkendecke,
		--   Funken vom Schweif, Kamera schraeg hinterher; kurz vor dem
		--   Aufprall Zeitlupe, der Schatten ist so gross wie der Turm.
		-- Einschlag (2,4 s): weisser Blitz (Besitzer), Krater aus Glut-Rissen,
		--   Truemmer und Sternstaub im Bogen, Schockwelle bis zum Arena-Zaun,
		--   Wackeln; der Krater glueht in Orange und Violett aus.
		-- Turm: alles relativ zu den Kaempfern bzw. zur Arena-Mitte. Alle
		--   Effekte sind spaetestens bei 4,8 s weg (Show 5,0 s), bevor der
		--   Turm zur naechsten Stage waechst.
		tier = 4, duration = 5.0, color = C(255, 150, 60), color2 = C(140, 90, 255),
		sounds = { charge = "rumble", strike = "rocket", impact = "boom" }, pitch = 0.9,
		impactAt = 2.4,
		steps = {
			-- 1. Aufladen
			{ t = 0.00, fx = "sky",       tint = C(70, 80, 150), brightness = -0.35, saturation = -0.3, dur = 4.4, fade = 1.0 },
			{ t = 0.00, fx = "starfield", count = 60, dur = 4.4, ownerOnly = true },
			{ t = 0.00, fx = "sound",     slot = "charge" },
			{ t = 0.25, fx = "shadow",    at = "target", from = 1.5, radius = "tower", dur = 2.15, fadeOut = 0.3, toArena = true },
			{ t = 0.30, fx = "comet",     height = 90, size = 3, charge = 1.2, fall = 0.9, cloudY = 45, tex = "glow", tailTex = "tail", sparkTex = "stardust" },
			-- 2. Schlag (Fall ab 1,5; Zeitlupe die letzten 0,27 s + Bild)
			{ t = 1.50, fx = "sound",     slot = "strike" },
			{ t = 1.50, fx = "cinematic", dur = 1.6, style = "chase" },
			{ t = 2.10, fx = "hitstop",   dur = 0.3 },
			-- 3. Einschlag
			{ t = 2.40, fx = "flash",     dur = 0.35 },
			{ t = 2.40, fx = "sound",     slot = "impact" },
			{ t = 2.40, fx = "shake",     power = 1.1, dur = 0.6 },
			{ t = 2.40, fx = "crater",    at = "target", radius = 7, count = 10, dur = 2.4, tex = "crater" },
			{ t = 2.42, fx = "ring",      at = "target", ground = true, toArena = true, radius = "fence", dur = 0.9, tex = "shockring" },
			{ t = 2.42, fx = "shards",    at = "target", arc = true, count = 16, size = 1.0, dur = 1.1, stone = true, tex = "debris" },
			{ t = 2.45, fx = "dust",      at = "target", count = 40, speed = 14, dur = 1.2, tex = "stardust", extra = true },
			-- Opener-Bonus (erster, starker Einschlag; nur mit `bonus` vom
			-- Server): zweite, violette Schockwelle, staerkeres Wackeln und ein
			-- Glutring direkt am Gegner.
			{ t = 2.40, fx = "shake",     power = 0.6, dur = 0.4, bonus = true },
			{ t = 2.40, fx = "ring",      at = "target", ground = true, radius = 5, dur = 0.45, color = C(255, 220, 140), bonus = true },
			{ t = 2.55, fx = "ring",      at = "target", ground = true, toArena = true, radius = "fence", dur = 1.1, second = true, bonus = true },
		},
		-- Echo (0,65 s): Komet von oben (ohne Nacht und Kamera) und gluehender Krater.
		echo = {
			{ t = 0.00, fx = "comet",  height = 40, size = 2.2, charge = 0, fall = 0.3, tex = "glow", tailTex = "tail" },
			{ t = 0.00, fx = "sound",  slot = "strike" },
			{ t = 0.30, fx = "crater", at = "target", radius = 5, count = 8, dur = 0.55, tex = "crater" },
			{ t = 0.30, fx = "sound",  slot = "impact" },
			-- Opener-Bonus: violette Schockwelle
			{ t = 0.30, fx = "ring",   at = "target", ground = true, radius = 9, dur = 0.35, second = true, bonus = true },
		},
	},

	NebulaBurn = {
		tier = 4, duration = 4.6, color = C(255, 90, 200), color2 = C(90, 120, 255),
		sounds = { charge = "whoosh", strike = "rumble", impact = "snap" }, pitch = 0.8,
		steps = {
			{ t = 0.00, fx = "sky",       tint = C(230, 150, 255), brightness = -0.1, saturation = 0.5, dur = 4.2 },
			{ t = 0.00, fx = "starfield", count = 50, dur = 4.2, nebula = true },
			{ t = 0.00, fx = "sound",     slot = "charge" },
			{ t = 0.20, fx = "spiral",    at = "arena", radius = 20, count = 40, dur = 2.0, outward = true, cloud = true },
			{ t = 0.40, fx = "cinematic", dur = 2.0, style = "orbit" },
			{ t = 2.30, fx = "wave",      at = "target", radius = 10, dur = 1.0, cloud = true },
			{ t = 2.30, fx = "sound",     slot = "strike" },
			{ t = 2.60, fx = "sparks",    at = "target", count = 40, dur = 1.8, ember = true },
			{ t = 2.60, fx = "sound",     slot = "impact" },
		},
	},

	PulsarPulse = {
		tier = 4, duration = 4.2, color = C(80, 240, 255), color2 = C(255, 255, 255),
		sounds = { charge = "ping", strike = "boom" }, pitch = 1.3,
		steps = {
			{ t = 0.00, fx = "sky",       tint = C(160, 240, 255), brightness = -0.2, saturation = 0.1, dur = 3.8 },
			{ t = 0.00, fx = "starfield", count = 40, dur = 3.8 },
			{ t = 0.00, fx = "sound",     slot = "charge" },
			{ t = 0.00, fx = "pillar",    at = "self", height = 50, width = 1.4, dur = 3.4, beacon = true },
			{ t = 0.40, fx = "ring",      at = "self", radius = 8, dur = 0.5 },
			{ t = 1.00, fx = "ring",      at = "self", radius = 12, dur = 0.5 },
			{ t = 1.60, fx = "ring",      at = "self", radius = 16, dur = 0.5 },
			{ t = 1.60, fx = "cinematic", dur = 1.6, style = "side" },
			{ t = 2.20, fx = "beam",      width = 3, dur = 0.8 },
			{ t = 2.20, fx = "sound",     slot = "strike" },
			{ t = 2.20, fx = "shake",     power = 0.9, dur = 0.5 },
			{ t = 2.30, fx = "wave",      at = "target", radius = 14, dur = 0.6 },
		},
	},

	ShadeSlash = {
		-- v16 (Show-Paket, Prompt 4): lautlos, scharf, unheimlich; kein Blut.
		-- Aufladen: Licht kalt und grau (Besitzer); der Schatten des
		--   Baerchis richtet sich als flache Tinten-Silhouette hinter ihm auf;
		--   der Baerchi selbst wird fast durchsichtig (nur lokal).
		-- Schlag: Silhouette zerfaellt in Rauch; aus drei Schattenpfuetzen um
		--   den Gegner steigen drei Schatten-Baerchis; 0,3 s Stillstand, der
		--   Ton geht ganz aus (Besitzer); EIN duenner weisser Schnitt quer
		--   durchs Bild.
		-- Einschlag (2,65 s): Schnitt reisst auf, Schattenfetzen flattern weg,
		--   der Ton kommt mit einem scharfen Hieb zurueck, die Schatten loesen
		--   sich auf, der echte Baerchi steht schlagartig wieder voll da.
		-- Finisher-Bonus: kommt als `bonus` vom Server (SkillFXPlay); dann
		--   reisst der Schnitt violett statt weiss auf (Baustein `cut`).
		tier = 4, duration = 4.2, color = C(18, 14, 26), color2 = C(85, 50, 135),
		sounds = { charge = "ghost", strike = "whoosh", impact = "slash" }, pitch = 0.7,
		impactAt = 2.65,
		steps = {
			-- 1. Aufladen
			{ t = 0.00, fx = "sky",        tint = C(165, 165, 185), brightness = -0.25, saturation = -0.85, dur = 3.4, fade = 0.6 },
			{ t = 0.00, fx = "sound",      slot = "charge" },
			{ t = 0.10, fx = "silhouette", at = "self", behind = 1.4, rise = 1.0, hold = 0.45, dissolve = 0.4, tex = "silhouette", smokeTex = "smoke" },
			{ t = 0.20, fx = "vanish",     at = "self", to = 0.85, fadeIn = 1.1, back = 2.55 },
			-- 2. Schlag
			{ t = 1.55, fx = "shades",     at = "target", count = 3, distance = 3.4, pool = 1.7, rise = 0.5, fadeAt = 1.15, dissolve = 0.35, tex = "pool", smokeTex = "smoke" },
			{ t = 1.60, fx = "sound",      slot = "strike" },
			{ t = 2.20, fx = "silence",    dur = 0.45 },
			{ t = 2.20, fx = "hitstop",    dur = 0.3 },
			{ t = 2.25, fx = "cut",        at = "target", length = 22, width = 0.12, draw = 0.08, tearAt = 0.4, tex = "cut" },
			-- 3. Einschlag
			{ t = 2.65, fx = "sound",      slot = "impact" },
			{ t = 2.65, fx = "shards",     at = "target", count = 18, size = 0.5, dur = 0.9, tex = "shred" },
			{ t = 2.65, fx = "shake",      power = 0.4, dur = 0.25 },
		},
		-- Echo (0,65 s): nur die Stille (0,15 s) und der weisse Schnitt.
		echo = {
			{ t = 0.00, fx = "silence", dur = 0.15 },
			{ t = 0.02, fx = "cut",     at = "target", length = 16, width = 0.1, draw = 0.05, tearAt = 0.13, tex = "cut" },
			{ t = 0.15, fx = "sound",   slot = "impact" },
		},
	},

	VoidCrown = {
		-- 23.10. Krone der Leere (Schemen-Baerchi): majestaetisch, bedrohlich,
		-- dann ein brutaler Sturz. Vorbild: violette Dornenkrone ueber einem
		-- Zauberkreis, Augen in der Dunkelheit.
		-- Aufladen: Welt wird violett-dunkel (Besitzer), Zauberkreis zeichnet
		--   sich unter dem Baerchi; er holt aus und steigt mit Drehung 7 Studs
		--   hoch (wird dabei groesser); eine Obsidian-Krone waechst Dorn fuer
		--   Dorn ueber seinem Kopf; Kamera in Untersicht.
		-- Sammeln: rund um die Arena oeffnen sich Augen und blinzeln, ueber der
		--   Krone waechst eine Kugel aus Leere mit Blitzboegen; unter dem
		--   Gegner zeichnet sich ein Zielkreis; kurz wird es still.
		-- Schlag (2,45 s): die Kugel schiesst auf den Gegner, der Baerchi
		--   stuerzt kopfueber hinterher (Sturz 2,55 .. 2,80).
		-- Einschlag (2,80 s): Blitz, Zeitlupe, Obsidian-Dornen brechen als
		--   Krone um den Gegner aus dem Boden, Schockwellen bis zum Zaun, der
		--   Zauberkreis gleisst auf; Rueckwaerts-Salto nach Hause, danach
		--   zerspringt die Krone (3,9 s).
		-- Finisher-Bonus (`bonus`): Lichtsaeule aus dem Himmel, zweiter,
		--   groesserer Dornenring, mehr Wackeln.
		tier = 4, duration = 5.2, color = C(160, 80, 255), color2 = C(22, 8, 42),
		sounds = { charge = "bass", strike = "whoosh", impact = "thunder", rise = "rumble", eyes = "ghost", dive = "lunge" },
		pitch = 0.6,
		impactAt = 2.8,
		steps = {
			-- 1. Aufladen
			{ t = 0.00, fx = "sky",       tint = C(170, 130, 255), brightness = -0.22, saturation = -0.2, dur = 4.8, fade = 0.8 },
			{ t = 0.00, fx = "starfield", count = 40, dur = 4.6, ownerOnly = true, extra = true },
			{ t = 0.00, fx = "sound",     slot = "charge" },
			{ t = 0.00, fx = "sigil",     at = "self", radius = 7, draw = 1.0, dur = 4.4, runes = 18, points = 6, spin = 0.45, pulseAt = 2.8 },
			{ t = 0.05, fx = "ascend",    height = 7, crouch = 0.35, rise = 0.9, spins = 1.25, grow = 1.3, diveAt = 2.5, dive = 0.25, hold = 0.4, back = 0.55 },
			{ t = 0.10, fx = "shake",     power = 0.25, dur = 0.4 },
			{ t = 0.40, fx = "sound",     slot = "rise" },
			{ t = 0.45, fx = "crown",     count = 12, lift = 0.45, grow = 0.9, dur = 3.45, spin = 0.9 },
			{ t = 0.55, fx = "cinematic", dur = 2.0, style = "lowHero" },
			-- 2. Sammeln
			{ t = 1.00, fx = "eyes",      at = "arena", count = 10, radius = 21, lift = 7, size = 3.2, open = 0.3, blinkAt = 0.9, dur = 2.6 },
			{ t = 1.00, fx = "sound",     slot = "eyes" },
			{ t = 1.20, fx = "voidorb",   size = 3.2, lift = 3.4, grow = 0.8, fireAt = 1.25, fly = 0.3 },
			{ t = 2.15, fx = "sigil",     at = "target", radius = 3.4, draw = 0.3, dur = 1.3, runes = 10, points = 5, spin = -1.2 },
			{ t = 2.25, fx = "silence",   level = 0.2, dur = 0.3 },
			-- 3. Schlag
			{ t = 2.45, fx = "sound",     slot = "strike" },
			{ t = 2.55, fx = "sound",     slot = "dive" },
			-- 4. Einschlag (Klon landet 2,55 + 0,25 = 2,80; Kugel 2,45 + 0,30 = 2,75)
			{ t = 2.80, fx = "flash",     dur = 0.3 },
			{ t = 2.80, fx = "hitstop",   dur = 0.3 },
			{ t = 2.80, fx = "sound",     slot = "impact" },
			{ t = 2.80, fx = "shake",     power = 1.4, dur = 0.7 },
			{ t = 2.80, fx = "eruption",  at = "target", open = true, count = 18, rings = 2, radius = 3.6, minHeight = 1.6, maxHeight = 4.6, rise = 0.16, stagger = 0.05, linger = 1.0, sink = 0.4 },
			{ t = 2.82, fx = "ring",      at = "target", ground = true, toArena = true, radius = "fence", dur = 0.9 },
			{ t = 2.90, fx = "ring",      at = "target", ground = true, toArena = true, radius = "fence", dur = 1.0, second = true },
			{ t = 2.82, fx = "wave",      at = "target", radius = 12, dur = 0.55 },
			{ t = 2.85, fx = "shards",    at = "target", arc = true, count = 16, size = 0.9, dur = 1.1, stone = true },
			-- Finisher-Bonus (Server: `bonus`)
			{ t = 2.80, fx = "pillar",    at = "target", fromSky = true, feet = true, soft = true, height = 70, width = 3.2, dur = 1.0, bonus = true },
			{ t = 2.95, fx = "eruption",  at = "target", count = 20, rings = 1, radius = 6.2, minHeight = 2.4, maxHeight = 5.5, rise = 0.18, stagger = 0.03, linger = 0.8, sink = 0.4, bonus = true },
			{ t = 2.95, fx = "shake",     power = 0.7, dur = 0.4, bonus = true },
		},
		-- Echo (0,65 s): Krone blitzt ueber dem Baerchi auf und zerspringt,
		-- Dornen brechen um den Gegner aus.
		echo = {
			{ t = 0.00, fx = "crown",    count = 8, lift = 0.3, grow = 0.18, dur = 0.4, spin = 2, shatter = 10 },
			{ t = 0.00, fx = "sound",    slot = "strike" },
			{ t = 0.20, fx = "eruption", at = "target", count = 7, rings = 1, radius = 2.2, minHeight = 1.2, maxHeight = 2.8, rise = 0.1, stagger = 0.02, linger = 0.2, sink = 0.2 },
			{ t = 0.22, fx = "ring",     at = "target", ground = true, radius = 8, dur = 0.35 },
			{ t = 0.22, fx = "sound",    slot = "impact" },
			{ t = 0.22, fx = "ring",     at = "target", ground = true, radius = 10, dur = 0.4, second = true, bonus = true },
		},
	},

	UfoAbduction = {
		-- 25.10. Entfuehrungsstrahl (UFO-Baerchi): verspielt-unheimlich, dann ein
		-- harter Schlag. Hauptmotiv: Traktorstrahl unter der Untertasse.
		-- Aufladen (0 .. 1,8): Welt kuehl-mintig (Besitzer), Sterne; die
		--   Untertasse duckt sich, hebt mit 2 Drehungen ab und waechst
		--   (0,05 .. 0,9), Randlichter als Lauflicht; Zickzack in 3 Rucken ueber
		--   den Gegner (0,9 .. 1,8).
		-- Strahl (1,75 .. 2,75): Traktorstrahl oeffnet sich nach unten (bis
		--   1,95), Kornkreis brennt sich unter dem Gegner ein (ab 1,85), der
		--   Gegner (Klon) wird taumelnd hochgezogen (1,95 .. 2,55) und haengt
		--   bebend unter dem UFO; Kamera tief neben dem Gegner (1,6 .. 3,9).
		-- Spannung: Stille 2,55 .. 2,75, das UFO bebt.
		-- Schlag (2,75): Strahl erlischt, weisser Todesstrahl faellt, UFO ruckt
		--   hoch, der Gegner stuerzt (2,75 .. 2,95).
		-- Einschlag (2,95 = impactAt): Landung, Blitz, Zeitlupe, Kornkreis
		--   gleisst, Schockwellen bis zum Zaun, Erdbrocken; das Original ist
		--   wieder da (Server: Rueckstoss).
		-- Nachklang: Fassrolle (2,95 .. 3,3), Zickzack nach Hause (3,3 .. 4,0),
		--   Landung (4,0 .. 4,3); Kornkreis verblasst bis 4,25.
		-- Kein Bonus: Stun meldet nie `bonus`.
		tier = 4, duration = 4.9, color = C(110, 255, 205), color2 = C(70, 80, 210),
		sounds = { charge = "bass", rise = "whoosh", zig = "ping", beam = "ghost", strike = "flash", impact = "boom" },
		pitch = 1.15,
		impactAt = 2.95,
		steps = {
			-- 1. Aufladen
			{ t = 0.00, fx = "sky",        tint = C(205, 255, 240), brightness = -0.18, saturation = -0.15, dur = 4.5, fade = 0.7 },
			{ t = 0.00, fx = "starfield",  count = 40, dur = 4.4, ownerOnly = true, extra = true },
			{ t = 0.00, fx = "sound",      slot = "charge" },
			{ t = 0.05, fx = "saucer",     height = 8, crouch = 0.3, rise = 0.55, spins = 2, grow = 1.3, travel = 0.9, zigs = 3, zig = 3,
				hover = 8, fireAt = 2.7, jolt = 0.2, hold = 0.35, back = 0.7, land = 0.3 },
			{ t = 0.10, fx = "shake",      power = 0.2, dur = 0.3 },
			{ t = 0.35, fx = "sound",      slot = "rise" },
			{ t = 0.95, fx = "sound",      slot = "zig" },
			-- 2. Strahl
			{ t = 1.60, fx = "cinematic",  dur = 2.3, style = "beamUp" },
			{ t = 1.75, fx = "tractor",    at = "target", width = 1.8, base = 6.5, open = 0.2, zapAt = 1.0, zap = 0.2, dur = 1.5, rings = 5 },
			{ t = 1.75, fx = "sound",      slot = "beam" },
			{ t = 1.85, fx = "cropcircle", at = "target", radius = 5.5, draw = 0.6, dur = 2.4, pulseAt = 1.1, spin = 0.25 },
			{ t = 1.95, fx = "abduct",     height = 4, lift = 0.6, dropAt = 0.8, drop = 0.2, spin = 2.2 },
			{ t = 2.55, fx = "silence",    level = 0.2, dur = 0.2 },
			-- 3. Schlag
			{ t = 2.75, fx = "sound",      slot = "strike" },
			-- 4. Einschlag (Todesstrahl 1,75 + 1,0 + 0,2 = 2,95; Gegner 1,95 + 0,8 + 0,2 = 2,95)
			{ t = 2.95, fx = "flash",      dur = 0.25 },
			{ t = 2.95, fx = "hitstop",    dur = 0.3 },
			{ t = 2.95, fx = "sound",      slot = "impact" },
			{ t = 2.95, fx = "shake",      power = 1.2, dur = 0.6 },
			{ t = 2.97, fx = "ring",       at = "target", ground = true, toArena = true, radius = "fence", dur = 0.9 },
			{ t = 3.05, fx = "ring",       at = "target", ground = true, toArena = true, radius = "fence", dur = 1.0, second = true },
			{ t = 2.97, fx = "wave",       at = "target", radius = 9, dur = 0.5 },
			{ t = 2.97, fx = "shards",     at = "target", arc = true, count = 14, size = 0.7, dur = 1.0, stone = true },
		},
		-- Echo (0,65 s): kleine Neon-Untertasse ueber dem Gegner, kurzer Strahl,
		-- Todesstrahl, Bodenring (Treffer 0,26 = TIERS[4].echo * 0,4).
		echo = {
			{ t = 0.00, fx = "tractor", at = "target", width = 1.2, base = 4.5, open = 0.08, zapAt = 0.16, zap = 0.1, dur = 0.5, rings = 3, lift = 7 },
			{ t = 0.00, fx = "sound",   slot = "beam" },
			{ t = 0.26, fx = "ring",    at = "target", ground = true, radius = 8, dur = 0.35 },
			{ t = 0.26, fx = "sound",   slot = "impact" },
		},
	},

	ChronosTimeStop = {
		-- 25.10. Zeitstillstand (Chronos-Baerchi): feierlich, dann eiskalt
		-- still, dann ein harter Stampfer. Hauptmotiv: riesiges goldenes
		-- Zifferblatt, dessen Zeiger auf XII ruecken.
		-- Aufladen (0 .. 1,35): Welt warm-sepia (Besitzer); der Baerchi duckt
		--   sich und steigt mit Drehung 5 Studs hoch (0,05 .. 1,15), die Uhr
		--   auf seiner Stirn rast, Zeitsand rieselt; hinter der Arena zeichnet
		--   sich das Zifferblatt (ab 0,3), die Zeiger rasen; goldener Staub
		--   treibt (ab 0,6); Kamera in Untersicht (0,4 .. 2,45).
		-- Zeitstillstand (1,35): Blitz, Welt grau (Besitzer), die Zeitblase
		--   waechst aus dem Baerchi ueber die Arena, Staub und Sand bleiben in
		--   der Luft haengen, Stirn-Uhr auf XII, Zifferblatt auf 11:57, Ring
		--   am Boden; der Gegner erstarrt in Uhrwerk-Ringen (1,6).
		-- Spannung: der Minutenzeiger tickt (1,8 / 2,1); Stille 2,25 .. 2,5.
		-- Schlag: Sprung durch die Zeit (2,3: Nachbilder-Spur, haengt ueber
		--   dem Gegner); XII (2,5) = Stampfer mit zwei Drehungen (.. 2,75).
		-- Einschlag (2,75 = impactAt): Landung, Blitz, Zeitlupe, Risse im
		--   Zifferblatt, die Blase platzt, Staub und Sand fallen, der Gegner
		--   ist wieder da (Server: Rueckstoss), die Ringe zerspringen,
		--   Schockwellen bis zum Zaun; 2,9 zerspringt das Zifferblatt.
		-- Nachklang: Farbe kehrt zurueck (ab 3,1), der Baerchi spult
		--   rueckwaerts nach Hause (3,1 .. 3,9, blaue Nachbilder).
		-- Kein Bonus: Stun meldet nie `bonus`.
		tier = 4, duration = 4.8, color = C(255, 205, 90), color2 = C(55, 75, 170),
		sounds = { charge = "rumble", rise = "whoosh", stop = "bass", tick = "snap", blink = "flash",
			strike = "lunge", impact = "thunder", shatter = "glass" },
		pitch = 0.85,
		impactAt = 2.75,
		steps = {
			-- 1. Aufladen
			{ t = 0.00, fx = "sky",        tint = C(255, 232, 195), brightness = -0.12, saturation = -0.3, dur = 4.6, fade = 0.6 },
			{ t = 0.00, fx = "sound",      slot = "charge" },
			{ t = 0.05, fx = "timewalk",   height = 5, crouch = 0.3, rise = 0.8, spins = 1, grow = 1.25, stopAt = 1.3, blinkAt = 2.25,
				appear = 0.2, lift = 5, slam = 0.25, hold = 0.35, back = 0.8, ghosts = 4 },
			{ t = 0.10, fx = "shake",      power = 0.2, dur = 0.3 },
			{ t = 0.30, fx = "clockface",  at = "arena", radius = 8, lift = 10.5, back = 8, draw = 0.7, stopAt = 1.05,
				ticks = { 1.5, 1.8, 2.2 }, crackAt = 2.45, shatterAt = 2.6, dur = 3.6 },
			{ t = 0.35, fx = "sound",      slot = "rise" },
			{ t = 0.40, fx = "cinematic",  dur = 2.05, style = "lowHero" },
			{ t = 0.60, fx = "timebubble", at = "self", radius = 16, stopAt = 0.75, grow = 0.4, popAt = 2.15, dust = 36 },
			-- 2. Zeitstillstand (1,35)
			{ t = 1.35, fx = "sky",        tint = C(210, 220, 255), brightness = -0.08, saturation = -0.9, dur = 2.25, fade = 0.15 },
			{ t = 1.35, fx = "flash",      dur = 0.2 },
			{ t = 1.35, fx = "sound",      slot = "stop" },
			{ t = 1.35, fx = "shake",      power = 0.5, dur = 0.3 },
			{ t = 1.35, fx = "ring",       at = "self", ground = true, radius = 14, dur = 0.5 },
			{ t = 1.60, fx = "timefreeze", hold = 1.15, linger = 0.7, rings = 2, segs = 22, step = 0.3 },
			{ t = 1.80, fx = "sound",      slot = "tick" },
			{ t = 2.10, fx = "sound",      slot = "tick" },
			{ t = 2.25, fx = "silence",    level = 0.15, dur = 0.25 },
			{ t = 2.30, fx = "sound",      slot = "blink" },
			-- 3. Schlag (XII)
			{ t = 2.50, fx = "sound",      slot = "tick" },
			{ t = 2.50, fx = "sound",      slot = "strike" },
			-- 4. Einschlag (Klon 0,05 + 2,25 + 0,2 + 0,25 = 2,75; Blase 0,6 + 2,15;
			--    Risse 0,3 + 2,45; Gegner 1,6 + 1,15)
			{ t = 2.75, fx = "flash",      dur = 0.3 },
			{ t = 2.75, fx = "hitstop",    dur = 0.3 },
			{ t = 2.75, fx = "sound",      slot = "impact" },
			{ t = 2.75, fx = "shake",      power = 1.3, dur = 0.7 },
			{ t = 2.77, fx = "ring",       at = "target", ground = true, toArena = true, radius = "fence", dur = 0.9 },
			{ t = 2.85, fx = "ring",       at = "target", ground = true, toArena = true, radius = "fence", dur = 1.0, second = true },
			{ t = 2.77, fx = "wave",       at = "target", radius = 9, dur = 0.5 },
			{ t = 2.80, fx = "shards",     at = "target", arc = true, count = 12, size = 0.7, dur = 1.0, stone = true },
			{ t = 2.90, fx = "sound",      slot = "shatter" },
		},
		-- Echo (0,65 s): kleines Zifferblatt ueber dem Gegner, zwei Ticks auf
		-- XII, Risse 0,26 (= TIERS[4].echo * 0,4) und Scherben, Bodenring.
		echo = {
			{ t = 0.00, fx = "clockface", at = "target", radius = 2.2, lift = 2.4, draw = 0.12, stopAt = 0, ticks = { 0.1, 0.2 },
				crackAt = 0.26, shatterAt = 0.32, dur = 0.6 },
			{ t = 0.10, fx = "sound",     slot = "tick" },
			{ t = 0.26, fx = "ring",      at = "target", ground = true, radius = 8, dur = 0.35 },
			{ t = 0.26, fx = "sound",     slot = "impact" },
		},
	},

	RiddleBeam = {
		tier = 4, duration = 4.3, color = C(200, 255, 120), color2 = C(255, 120, 255),
		sounds = { charge = "ping", strike = "rocket", impact = "glass" }, pitch = 1.1,
		steps = {
			{ t = 0.00, fx = "sky",       tint = C(220, 255, 200), brightness = -0.15, saturation = 0.3, dur = 4.0 },
			{ t = 0.00, fx = "sound",     slot = "charge" },
			{ t = 0.00, fx = "ring",      at = "self", radius = 6, dur = 1.6, glyphs = true },
			{ t = 0.30, fx = "ring",      at = "self", radius = 9, dur = 1.4, glyphs = true },
			{ t = 0.60, fx = "cinematic", dur = 2.0, style = "orbit" },
			{ t = 1.80, fx = "beam",      width = 2.5, dur = 1.2, rainbow = true },
			{ t = 1.80, fx = "sound",     slot = "strike" },
			{ t = 2.40, fx = "shards",    at = "target", count = 20, size = 0.8, dur = 1.0, glyphs = true },
			{ t = 2.40, fx = "sound",     slot = "impact" },
			{ t = 2.40, fx = "shake",     power = 0.8, dur = 0.4 },
		},
	},

	-- 21.10. Welt 2: Anime-Pets, aus vorhandenen Effekt-Bausteinen (ohne neue Texturen)
	RubberSmash = {
		tier = 3, duration = 3.8, color = C(230, 70, 60), color2 = C(255, 220, 120),
		sounds = { charge = "whoosh", strike = "boom", impact = "thunder" }, pitch = 0.9,
		steps = {
			{ t = 0.00, fx = "sound",     slot = "charge" },
			{ t = 0.00, fx = "ring",      at = "self", radius = 5, dur = 1.0 },
			{ t = 0.30, fx = "cinematic", dur = 1.6, style = "orbit" },
			{ t = 1.40, fx = "beam",      width = 1.6, dur = 0.5 },
			{ t = 1.40, fx = "sound",     slot = "strike" },
			{ t = 1.90, fx = "flash",     dur = 0.2 },
			{ t = 1.90, fx = "wave",      at = "target", radius = 18, dur = 0.7 },
			{ t = 1.90, fx = "sound",     slot = "impact" },
			{ t = 1.90, fx = "shake",     power = 1.0, dur = 0.6 },
		},
	},

	SpiralDash = {
		tier = 2, duration = 3.0, color = C(255, 150, 50), color2 = C(60, 100, 220),
		sounds = { charge = "whoosh", strike = "whoosh", impact = "ping" }, pitch = 1.3,
		steps = {
			{ t = 0.00, fx = "sound",     slot = "charge" },
			{ t = 0.00, fx = "ring",      at = "self", radius = 4, dur = 0.8 },
			{ t = 0.20, fx = "ring",      at = "self", radius = 7, dur = 0.8 },
			{ t = 0.80, fx = "cinematic", dur = 1.4, style = "orbit" },
			{ t = 1.50, fx = "sound",     slot = "strike" },
			{ t = 1.60, fx = "shards",    at = "target", count = 14, size = 0.7, dur = 0.8 },
			{ t = 1.60, fx = "sound",     slot = "impact" },
			{ t = 1.60, fx = "shake",     power = 0.5, dur = 0.3 },
		},
	},

	StarBlast = {
		tier = 4, duration = 4.0, color = C(255, 200, 80), color2 = C(255, 255, 255),
		sounds = { charge = "rumble", strike = "rocket", impact = "boom" }, pitch = 1.0,
		steps = {
			{ t = 0.00, fx = "sky",       tint = C(255, 235, 190), brightness = 0.1, saturation = 0.2, dur = 3.6 },
			{ t = 0.00, fx = "sound",     slot = "charge" },
			{ t = 0.00, fx = "shake",     power = 0.3, dur = 1.4 },
			{ t = 0.00, fx = "ring",      at = "self", radius = 6, dur = 1.4 },
			{ t = 0.50, fx = "cinematic", dur = 1.8, style = "up" },
			{ t = 1.60, fx = "beam",      width = 3.0, dur = 1.1 },
			{ t = 1.60, fx = "sound",     slot = "strike" },
			{ t = 2.30, fx = "flash",     dur = 0.2 },
			{ t = 2.30, fx = "wave",      at = "target", radius = 22, dur = 0.8 },
			{ t = 2.30, fx = "sound",     slot = "impact" },
			{ t = 2.30, fx = "shake",     power = 1.1, dur = 0.6 },
		},
	},

	PlaidSlash = {
		tier = 3, duration = 3.4, color = C(60, 170, 110), color2 = C(220, 230, 240),
		sounds = { charge = "ping", strike = "whoosh", impact = "glass" }, pitch = 1.1,
		steps = {
			{ t = 0.00, fx = "sound",     slot = "charge" },
			{ t = 0.00, fx = "ring",      at = "self", radius = 5, dur = 1.0 },
			{ t = 0.40, fx = "cinematic", dur = 1.6, style = "orbit" },
			{ t = 1.50, fx = "sound",     slot = "strike" },
			{ t = 1.60, fx = "beam",      width = 0.6, dur = 0.4 },
			{ t = 2.00, fx = "shards",    at = "target", count = 18, size = 0.8, dur = 0.9 },
			{ t = 2.00, fx = "sound",     slot = "impact" },
			{ t = 2.00, fx = "shake",     power = 0.7, dur = 0.4 },
		},
	},

	AscendingLight = {   -- 20.10. P5d
		tier = 4, duration = 4.4, color = C(150, 230, 255), color2 = C(255, 235, 170),
		sounds = { charge = "whoosh", strike = "ping", impact = "boom" }, pitch = 1.0,
		steps = {
			{ t = 0.00, fx = "sky",       tint = C(225, 245, 255), brightness = 0.15, saturation = 0.3, dur = 4.0 },
			{ t = 0.00, fx = "sound",     slot = "charge" },
			{ t = 0.00, fx = "rise",      at = "self", count = 36, dur = 2.0 },
			{ t = 0.50, fx = "cinematic", dur = 2.0, style = "up" },
			{ t = 1.80, fx = "beam",      width = 1.8, dur = 0.9 },
			{ t = 1.80, fx = "sound",     slot = "strike" },
			{ t = 2.40, fx = "wave",      at = "target", radius = 20, dur = 0.8 },
			{ t = 2.40, fx = "sound",     slot = "impact" },
			{ t = 2.40, fx = "shake",     power = 0.7, dur = 0.5 },
		},
	},

	TitanFist = {
		tier = 4, duration = 4.8, color = C(220, 160, 90), color2 = C(255, 240, 200),
		sounds = { charge = "rumble", strike = "boom", impact = "thunder" }, pitch = 0.55,
		steps = {
			{ t = 0.00, fx = "sky",       tint = C(255, 210, 160), brightness = -0.2, saturation = 0.1, dur = 4.4 },
			{ t = 0.00, fx = "sound",     slot = "charge" },
			{ t = 0.00, fx = "shake",     power = 0.35, dur = 1.6 },
			{ t = 0.00, fx = "cinematic", dur = 2.4, style = "up" },
			{ t = 0.40, fx = "meteor",    at = "target", size = 9, height = 90, dur = 1.8, fist = true },
			{ t = 2.20, fx = "flash",     dur = 0.25 },
			{ t = 2.20, fx = "hitstop",   dur = 0.4 },
			{ t = 2.60, fx = "wave",      at = "target", radius = 34, dur = 0.9 },
			{ t = 2.60, fx = "ring",      at = "target", radius = 24, dur = 1.0, crack = true },
			{ t = 2.60, fx = "sound",     slot = "impact" },
			{ t = 2.60, fx = "shake",     power = 1.5, dur = 0.9 },
			{ t = 2.65, fx = "shards",    at = "target", count = 36, size = 1.4, dur = 1.4, stone = true },
		},
	},

	GenesisWave = {
		tier = 4, duration = 5.0, color = C(120, 255, 140), color2 = C(255, 250, 220),
		sounds = { charge = "whoosh", strike = "rumble", impact = "boom" }, pitch = 0.9,
		steps = {
			{ t = 0.00, fx = "sky",       tint = C(200, 255, 210), brightness = 0.15, saturation = 0.4, dur = 4.6 },
			{ t = 0.00, fx = "starfield", count = 50, dur = 4.6 },
			{ t = 0.00, fx = "sound",     slot = "charge" },
			{ t = 0.00, fx = "rise",      at = "arena", count = 40, dur = 2.0 },
			{ t = 0.40, fx = "cinematic", dur = 2.4, style = "orbit" },
			{ t = 1.80, fx = "wave",      at = "self", radius = 12, dur = 0.6 },
			{ t = 2.30, fx = "wave",      at = "self", radius = 22, dur = 0.7 },
			{ t = 2.30, fx = "sound",     slot = "strike" },
			{ t = 2.90, fx = "wave",      at = "self", radius = 34, dur = 0.8 },
			{ t = 2.90, fx = "sound",     slot = "impact" },
			{ t = 2.90, fx = "shake",     power = 1.1, dur = 0.6 },
		},
	},

	ChronosRift = {
		tier = 4, duration = 5.2, color = C(255, 200, 80), color2 = C(80, 60, 160),
		sounds = { charge = "rumble", strike = "glass", impact = "boom" }, pitch = 0.65,
		steps = {
			{ t = 0.00, fx = "sky",       tint = C(255, 230, 170), brightness = -0.1, saturation = -0.6, dur = 4.8 },
			{ t = 0.00, fx = "sound",     slot = "charge" },
			{ t = 0.00, fx = "ring",      at = "arena", radius = 16, dur = 2.0, clock = true },
			{ t = 0.40, fx = "cinematic", dur = 2.4, style = "side" },
			{ t = 1.20, fx = "hitstop",   dur = 0.8 },
			{ t = 2.00, fx = "beam",      width = 0.6, dur = 0.8, rift = true },
			{ t = 2.00, fx = "sound",     slot = "strike" },
			{ t = 2.80, fx = "spiral",    at = "target", radius = 10, count = 30, dur = 0.8 },
			{ t = 3.40, fx = "flash",     dur = 0.3 },
			{ t = 3.40, fx = "wave",      at = "target", radius = 20, dur = 0.7 },
			{ t = 3.40, fx = "sound",     slot = "impact" },
			{ t = 3.40, fx = "shake",     power = 1.2, dur = 0.6 },
		},
	},

	InfinityBarrage = {
		tier = 4, duration = 5.0, color = C(255, 120, 40), color2 = C(255, 255, 160),
		sounds = { charge = "ping", strike = "rocket", impact = "hit" }, pitch = 1.4,
		steps = {
			{ t = 0.00, fx = "sky",       tint = C(255, 200, 150), brightness = -0.15, saturation = 0.3, dur = 4.6 },
			{ t = 0.00, fx = "sound",     slot = "charge" },
			{ t = 0.00, fx = "ring",      at = "self", radius = 7, dur = 1.0, infinity = true },
			{ t = 0.40, fx = "cinematic", dur = 2.2, style = "side" },
			{ t = 1.20, fx = "projectile", size = 1.4, dur = 0.35, count = 1 },
			{ t = 1.45, fx = "projectile", size = 1.4, dur = 0.35, count = 1 },
			{ t = 1.70, fx = "projectile", size = 1.4, dur = 0.35, count = 1 },
			{ t = 1.95, fx = "projectile", size = 1.4, dur = 0.35, count = 1 },
			{ t = 2.20, fx = "projectile", size = 2.4, dur = 0.45, count = 1 },
			{ t = 1.20, fx = "sound",     slot = "strike" },
			{ t = 2.65, fx = "sparks",    at = "target", count = 60, dur = 1.4 },
			{ t = 2.65, fx = "sound",     slot = "impact" },
			{ t = 2.65, fx = "shake",     power = 1.0, dur = 0.7 },
		},
	},

	InfinityStarfall = {
		-- 25.10. Ewiger Sternenfall (Unendlichkeits-Baerchi): schwerelos und
		-- verspielt, dann ein harter Einschlag. Hauptmotiv: riesiges leuchtendes
		-- Unendlichkeitszeichen am Himmel, Kristall-Geysir (Referenzbild).
		-- Aufladen (0 .. 0,95): Welt tiefblau (Besitzer), Sterne; der Baerchi
		--   duckt sich und steigt mit Drehung 6 Studs hoch (0,05 .. 0,95), sein
		--   Kopf-Reif dreht sich, die Sterne rasen auf der Acht; unter dem
		--   Gegner zeichnet sich ein Energienetz (ab 0,3).
		-- Zeichen (0,95 .. 2,25): Anflug in den Kreuzungspunkt (.. 1,21), dann
		--   fliegt er die Acht (16 Studs breit, Mitte 11 Studs hoch) und laesst
		--   ein Lichtband stehen; Kamera tief vor dem Zeichen (0,85 .. 3,3).
		--   Aus seiner Bahn fallen 4 Sternschnuppen (Start 1,35 / 1,53 / 1,71 /
		--   1,89, Einschlag je +0,3) und kesseln den Gegner ein, Kristall-Buesche.
		-- Spannung: haengt bebend im Kreuzungspunkt (2,25 .. 2,6), Stille 2,35 .. 2,6.
		-- Schlag (2,6): das Band faellt in ihn zusammen, Sturz als Komet mit zwei
		--   Vorwaerts-Saltos (.. 2,85).
		-- Einschlag (2,85 = impactAt): Landung, Blitz, Zeitlupe, Kristall-Geysir
		--   mit Fontaene, Netz gleisst, Erdbrocken, Schockwellen bis zum Zaun.
		-- Nachklang: Rueckwaerts-Salto heim (3,2 .. 3,9), alle Kristalle
		--   zerspringen bei 3,85, Netz verblasst bis 4,5.
		-- Kein Bonus: MultiHit meldet nie `bonus`.
		tier = 4, duration = 5.0, color = C(110, 225, 255), color2 = C(60, 60, 170),
		sounds = { charge = "rumble", rise = "whoosh", loop = "ping", star = "snap",
			strike = "lunge", impact = "boom", shatter = "glass" },
		pitch = 1.05,
		impactAt = 2.85,
		steps = {
			-- 1. Aufladen
			{ t = 0.00, fx = "sky",        tint = C(170, 200, 255), brightness = -0.2, saturation = -0.1, dur = 4.6, fade = 0.7 },
			{ t = 0.00, fx = "starfield",  count = 50, dur = 4.4, ownerOnly = true, extra = true },
			{ t = 0.00, fx = "sound",      slot = "charge" },
			{ t = 0.05, fx = "starfall",   height = 6, crouch = 0.3, rise = 0.6, spins = 1, grow = 1.25, loopAt = 0.9, loop = 1.3,
				span = 8, tall = 1.3, lift = 11, diveAt = 2.53, dive = 0.25, flips = 2, hold = 0.35, back = 0.7, segs = 56 },
			{ t = 0.10, fx = "shake",      power = 0.2, dur = 0.3 },
			{ t = 0.30, fx = "gridweb",    at = "target", radius = 7, draw = 0.9, dur = 4.2, spokes = 10, rings = 3, spin = 0.08, pulseAt = 2.55 },
			{ t = 0.35, fx = "sound",      slot = "rise" },
			-- 2. Unendlichkeitszeichen
			{ t = 0.85, fx = "cinematic",  dur = 2.45, style = "infinity" },
			{ t = 0.95, fx = "sound",      slot = "loop" },
			{ t = 1.35, fx = "shootingstars", at = "target", count = 4, every = 0.18, fall = 0.3, radius = 4.6, size = 0.7,
				crystals = 3, breakAt = 2.5 },
			{ t = 1.65, fx = "sound",      slot = "star" },
			{ t = 1.83, fx = "sound",      slot = "star" },
			{ t = 2.01, fx = "sound",      slot = "star" },
			{ t = 2.19, fx = "sound",      slot = "star" },
			-- 3. Spannung
			{ t = 2.35, fx = "silence",    level = 0.2, dur = 0.25 },
			-- 4. Schlag
			{ t = 2.60, fx = "sound",      slot = "strike" },
			-- 5. Einschlag (Klon 0,05 + 2,53 + 0,25 = 2,83, gemessen ~2,85; Netz 0,3 + 2,55)
			{ t = 2.85, fx = "flash",      dur = 0.3 },
			{ t = 2.85, fx = "hitstop",    dur = 0.3 },
			{ t = 2.85, fx = "sound",      slot = "impact" },
			{ t = 2.85, fx = "shake",      power = 1.3, dur = 0.7 },
			{ t = 2.85, fx = "crystalgeyser", at = "target", open = true, count = 22, rings = 2, radius = 3.2, minHeight = 3,
				maxHeight = 8.5, rise = 0.14, stagger = 0.03, shatterAt = 1.0, spray = 70, needles = 14 },
			{ t = 2.87, fx = "ring",       at = "target", ground = true, toArena = true, radius = "fence", dur = 0.9 },
			{ t = 2.95, fx = "ring",       at = "target", ground = true, toArena = true, radius = "fence", dur = 1.0, second = true },
			{ t = 2.87, fx = "wave",       at = "target", radius = 9, dur = 0.5 },
			{ t = 2.88, fx = "shards",     at = "target", arc = true, count = 14, size = 0.8, dur = 1.1, stone = true },
			{ t = 3.85, fx = "sound",      slot = "shatter" },
		},
		-- Echo (0,65 s): eine Sternschnuppe trifft den Gegner (0,26 =
		-- TIERS[4].echo * 0,4), kleiner Kristall-Kranz, Bodenring.
		echo = {
			{ t = 0.00, fx = "shootingstars", at = "target", count = 1, radius = 0, fall = 0.26, size = 0.9, crystals = 0 },
			{ t = 0.00, fx = "sound",      slot = "star" },
			{ t = 0.26, fx = "crystalgeyser", at = "target", count = 7, rings = 1, radius = 2.0, minHeight = 1.6, maxHeight = 3.2,
				rise = 0.08, stagger = 0.01, linger = 0.12, sink = 0.15, spray = 24, needles = 0 },
			{ t = 0.26, fx = "ring",       at = "target", ground = true, radius = 8, dur = 0.35 },
			{ t = 0.26, fx = "sound",      slot = "impact" },
		},
	},

	OmegaStrike = {
		-- v16 (Show-Paket, Prompt 5): die groesste Show. Erhaben, endgueltig,
		-- still vor dem Sturm — die Stille ist so wichtig wie der Schlag.
		-- Aufladen: alle Geraeusche werden leise, die Welt fast schwarz-weiss
		--   (Besitzer); der Baerchi leuchtet (Highlight) — ganz aus dem
		--   Filter nehmen kann Roblox ihn nicht. AmbienceController bietet
		--   kein Anhalten von Wolken/Pollen/Schaum -> nur Farbfilter.
		-- Sammeln: riesiges Omega am Himmel, Lichtpunkte in den vier
		--   Pfadfarben fliegen aus allen Himmelsrichtungen hinein; Kamera
		--   im langsamen Halbkreis um den Baerchi (2,4 s).
		-- Schlag (3,3 s): das Omega zieht sich mit einem Ruck auf die Pfote.
		-- Einschlag (3,55 s): Spektrum laeuft durchs Bild, die Farbe kommt
		--   zurueck; Schockwelle in den vier Pfadfarben bis zum Zaun; schmale
		--   Lichtsaeule fuer ALLE Spieler (`global`, 1,3 s, nur volle Show =
		--   hoechstens einmal pro Lauf); Omega brennt sich unter dem Gegner
		--   ein und verblasst.
		tier = 4, duration = 5.8, color = C(255, 255, 255), color2 = C(70, 60, 95),
		sounds = { charge = "bass", strike = "whoosh", impact = "boom" }, pitch = 0.45,
		impactAt = 3.55,
		steps = {
			-- 1. Aufladen (Stille vor dem Sturm)
			{ t = 0.00, fx = "silence",   level = 0.15, dur = 3.3 },
			{ t = 0.00, fx = "sky",       tint = C(255, 255, 255), brightness = -0.08, saturation = -0.92, dur = 5.5, fade = 1.2 },
			{ t = 0.00, fx = "spotlight", at = "self", dur = 3.6, strength = 0.35 },
			{ t = 0.15, fx = "sound",     slot = "charge" },
			-- 2. Sammeln
			{ t = 1.00, fx = "omega",     mode = "sky", at = "arena", radius = 7, lift = 34, segments = 20, draw = 0.9, pullAt = 2.3, jerk = 0.22, tex = "omega" },
			{ t = 1.00, fx = "cinematic", dur = 2.4, style = "orbitSelf" },
			{ t = 1.30, fx = "converge",  colors = { C(255, 200, 60), C(110, 200, 255), C(150, 80, 255), C(235, 235, 255) },
				perSide = 4, from = 45, lift = 34, flight = 0.9, stagger = 0.25, tex = "orb" },
			-- 3. Schlag: Ruck auf die Pfote (3,30 .. 3,52)
			{ t = 3.30, fx = "sound",     slot = "strike" },
			-- 4. Einschlag
			{ t = 3.55, fx = "flash",     dur = 0.4 },
			{ t = 3.55, fx = "sound",     slot = "impact" },
			{ t = 3.55, fx = "shake",     power = 0.9, dur = 0.5 },
			{ t = 3.55, fx = "wipe",      dur = 0.9, tex = "spectrum" },
			{ t = 3.58, fx = "ring",      at = "target", ground = true, toArena = true, radius = "fence", dur = 0.9, color = C(255, 200, 60), tex = "shockring" },
			{ t = 3.66, fx = "ring",      at = "target", ground = true, toArena = true, radius = "fence", dur = 0.9, color = C(110, 200, 255), tex = "shockring" },
			{ t = 3.74, fx = "ring",      at = "target", ground = true, toArena = true, radius = "fence", dur = 0.9, color = C(150, 80, 255), tex = "shockring" },
			{ t = 3.82, fx = "ring",      at = "target", ground = true, toArena = true, radius = "fence", dur = 0.9, color = C(235, 235, 255), tex = "shockring" },
			{ t = 3.60, fx = "pillar",    at = "arena", feet = true, soft = true, height = 160, width = 1.6, dur = 1.3, tex = "column", global = true },
			{ t = 3.70, fx = "omega",     mode = "brand", at = "target", radius = 2.2, segments = 14, draw = 0.2, burnFor = 0.5, fade = 1.5, tex = "brand" },
		},
		-- Echo (0,65 s): Ruck des Rings auf die Pfote und die Schockwelle —
		-- ohne Entfaerbung, Kamera und Lichtsaeule.
		echo = {
			{ t = 0.00, fx = "omega", mode = "sky", at = "self", radius = 2.5, lift = 6, segments = 12, draw = 0.12, pullAt = 0.16, jerk = 0.16, tex = "omega" },
			{ t = 0.16, fx = "sound", slot = "strike" },
			{ t = 0.32, fx = "ring",  at = "target", ground = true, radius = 10, dur = 0.4, color = C(255, 200, 60) },
			{ t = 0.35, fx = "ring",  at = "target", ground = true, radius = 10, dur = 0.4, color = C(110, 200, 255) },
			{ t = 0.38, fx = "ring",  at = "target", ground = true, radius = 10, dur = 0.4, color = C(150, 80, 255) },
			{ t = 0.41, fx = "ring",  at = "target", ground = true, radius = 10, dur = 0.4, color = C(235, 235, 255) },
			{ t = 0.32, fx = "sound", slot = "impact" },
		},
	},
	OmegaWorldsEnd = {
		-- 25.10.2026 Weltenende (Omega-Baerchi, ersetzt OmegaStrike als
		-- defaultSkill): die groesste Show. Hauptmotiv: der Baerchi steht wie
		-- der kleine Prinz auf seinem eigenen Planeten - und reitet ihn auf den
		-- Gegner. "Der letzte Baerchi. Danach kommt nichts mehr."
		-- Aufladen (0 .. 0,97): Welt violett-dunkel (Besitzer), Sterne; er duckt
		--   sich, Fluegel schlagen, steigt mit Drehung ueber die Arena.
		-- Weltgeburt (0,97 .. 1,55): unter ihm waechst der Planet (Mitte 11 Studs
		--   ueber der Arena); sein Orbit-Ring wird zum Planetenring, die drei
		--   Sterne fliegen als Monde (rosa, cyan, gelb) auf den Ring; er landet
		--   bei 1,55 auf dem Planeten. Kamera tief, Blick hoch (1,2 .. 3,7; beim
		--   Einschlag faehrt sie zurueck auf die ganze Weltkugel).
		-- Monde (2,0 / 2,15 / 2,3): krachen nacheinander hinein, Risse gluehen,
		--   der Planet bebt; der Schatten waechst unter dem Gegner (1,7 .. 2,94).
		-- Spannung: er duckt sich (2,35), Stille 2,38 .. 2,65, Sprung mit
		--   Vorwaerts-Salto (2,45 .. 2,67).
		-- Schlag (2,67): Stampfer, er reitet den Planeten schraeg auf den Gegner.
		-- Einschlag (2,95 = impactAt; Klon 0,05 + 2,62 + 0,27 = 2,94): Planet
		--   zerbirst, Kern blitzt; daraus waechst in 0,6 s eine Weltkugel aus Licht
		--   (Laengen-/Breitengrade, Kontinente des Planeten) auf die Groesse des
		--   ganzen Pits und dreht sich dabei, zerfaellt bis 4,55 in Sternenstaub
		--   (Wunsch des Nutzers 25.10.). Der Ring rast als Bodenwelle davon, drei
		--   Ringe in Mondfarben bis zum Zaun, Krater, Truemmer, Sternstaub.
		-- Nachklang: Rueckwaerts-Salto heim (2,94 .. 3,74), die Sterne kehren
		--   zurueck (bis 4,19); die Farbe kommt bis 5,0 zurueck.
		-- Finisher-Bonus (`bonus`): Supernova, Lichtsaeule fuer ALLE Spieler
		--   (`global`), mehr Wackeln.
		tier = 4, duration = 5.2, color = C(190, 140, 255), color2 = C(58, 40, 120),
		sounds = { charge = "bass", rise = "whoosh", birth = "ping", crash = "hit", strike = "lunge",
			impact = "boom", shatter = "glass", after = "thunder", home = "ping" },
		pitch = 0.75,
		impactAt = 2.95,
		steps = {
			-- 1. Aufladen
			{ t = 0.00, fx = "sky",        tint = C(205, 180, 255), brightness = -0.2, saturation = -0.15, dur = 5.0, fade = 0.7 },
			{ t = 0.00, fx = "starfield",  count = 55, dur = 4.8, ownerOnly = true, extra = true },
			{ t = 0.00, fx = "sound",      slot = "charge" },
			{ t = 0.05, fx = "worldsend",  crouch = 0.3, rise = 0.62, spins = 1, grow = 1.3, lift = 11, radius = 3.4,
				birthAt = 0.92, birth = 0.55, settleAt = 1.5, crashAt = { 1.95, 2.1, 2.25 }, windAt = 2.3, hopAt = 2.4,
				stompAt = 2.62, fall = 0.27, bounce = 0.8, settle = 0.45, shock = 16, chunks = 24, cracks = 3, steps = 7 },
			{ t = 0.10, fx = "shake",      power = 0.2, dur = 0.3 },
			{ t = 0.35, fx = "sound",      slot = "rise" },
			-- 2. Weltgeburt
			{ t = 1.20, fx = "cinematic",  dur = 2.5, style = "worldsEnd" },
			{ t = 0.97, fx = "sound",      slot = "birth" },
			{ t = 1.55, fx = "shake",      power = 0.25, dur = 0.25 },
			{ t = 1.70, fx = "shadow",     at = "target", from = 0.8, radius = 4.2, dur = 1.24, fadeOut = 0.2 },
			-- 3. Die Monde krachen hinein
			{ t = 2.00, fx = "sound",      slot = "crash" },
			{ t = 2.15, fx = "sound",      slot = "crash" },
			{ t = 2.30, fx = "sound",      slot = "crash" },
			{ t = 2.00, fx = "shake",      power = 0.35, dur = 0.45 },
			-- 4. Spannung
			{ t = 2.38, fx = "silence",    level = 0.1, dur = 0.27 },
			-- 5. Schlag (Stampfer)
			{ t = 2.67, fx = "sound",      slot = "strike" },
			{ t = 2.67, fx = "shake",      power = 0.5, dur = 0.27 },
			-- 6. Einschlag
			{ t = 2.95, fx = "flash",      dur = 0.35 },
			{ t = 2.95, fx = "hitstop",    dur = 0.3 },
			{ t = 2.95, fx = "sound",      slot = "impact" },
			{ t = 2.97, fx = "sound",      slot = "shatter" },
			{ t = 2.95, fx = "shake",      power = 1.5, dur = 0.8 },
			{ t = 2.96, fx = "ring",       at = "target", ground = true, toArena = true, radius = "fence", dur = 0.9, color = C(255, 130, 220) },
			{ t = 3.03, fx = "ring",       at = "target", ground = true, toArena = true, radius = "fence", dur = 0.9, color = C(100, 220, 255) },
			{ t = 3.10, fx = "ring",       at = "target", ground = true, toArena = true, radius = "fence", dur = 0.9, color = C(255, 220, 90) },
			{ t = 2.95, fx = "worldglobe", at = "target", radius = "fence", grow = 0.6, dur = 1.6, lift = 0.3, tilt = 23.4,
				spin = 3, meridians = 12, parallels = 5 },
			{ t = 2.97, fx = "crater",     at = "target", radius = 5.5, count = 12, dur = 1.9 },
			{ t = 2.98, fx = "shards",     at = "target", arc = true, count = 14, size = 0.9, dur = 1.1, stone = true },
			{ t = 3.05, fx = "sound",      slot = "after" },
			{ t = 3.10, fx = "dust",       at = "target", count = 40, speed = 16, dur = 1.4, extra = true },
			-- Finisher-Bonus (Server: `bonus`)
			{ t = 2.95, fx = "supernova",  at = "target", radius = 15, dur = 1.0, rays = 14, bonus = true },
			{ t = 2.97, fx = "pillar",     at = "target", feet = true, soft = true, height = 160, width = 2.4, dur = 1.4,
				tex = "column", global = true, bonus = true },
			{ t = 3.00, fx = "shake",      power = 0.8, dur = 0.5, bonus = true },
			-- 7. Nachklang: die Sterne kehren zurueck
			{ t = 3.78, fx = "sound",      slot = "home" },
		},
		-- Echo (0,65 s): ein kleiner Planet mit Ring faellt auf den Gegner und
		-- zerbirst (0,26 = TIERS[4].echo * 0,4), Bodenringe.
		echo = {
			{ t = 0.00, fx = "miniworld",  at = "target", radius = 1.15, height = 7, drop = 0.26, shock = 7, chunks = 8, power = 16 },
			{ t = 0.00, fx = "sound",      slot = "strike" },
			{ t = 0.26, fx = "sound",      slot = "impact" },
			{ t = 0.27, fx = "ring",       at = "target", ground = true, radius = 8, dur = 0.35, color = C(100, 220, 255) },
			{ t = 0.30, fx = "ring",       at = "target", ground = true, radius = 10, dur = 0.35, color = C(255, 130, 220), bonus = true },
		},
	},
	RiddleAvalanche = {
		-- 25.10.2026 Fragenlawine (Raetsel-Baerchi, ersetzt RiddleBeam als
		-- defaultSkill): verspielt wie ein Zaubertrick, dann ein harter
		-- "Aha!"-Moment. Hauptmotiv: goldenes Fragezeichen, das sich immer
		-- weiter teilt ("Beantwortet jede Frage mit einer neuen"). Farben aus
		-- dem Modell: Gold des Monokels, Violett des Hutbands.
		-- Aufladen (0 .. 1,3): Welt leicht violett (Besitzer), Sterne; er
		--   lueftet den Hut, ein kleines "?" springt heraus (0,18) und fliegt
		--   wachsend ueber den Gegner (.. 0,9); er duckt sich (0,5) und steigt
		--   mit Drehung ueber den Landepunkt vor dem Gegner (0,72 .. 1,3).
		-- Lawine (0,95 .. 1,92): das "?" teilt sich 1 -> 2 -> 4 -> 8 (0,95 /
		--   1,25 / 1,55) und wirbelt immer schneller um den Gegner, der sich
		--   verwirrt umschaut; er schwebt und gruebelt, Monokel blitzt (1,62).
		--   Kamera tief auf der Seite der Luecke (1,0 .. 3,4).
		-- Spannung: der Wirbel steht schlagartig still und bebt, Stille
		--   1,92 .. 2,15.
		-- Aha (2,15): Monokel blitzt, er zuckt hoch, alle "?" biegen sich zu
		--   "!" und rammen sich nacheinander als Kaefig in den Boden
		--   (2,27 .. 2,71), der Gegner zuckt zusammen.
		-- Schlag (2,42): Vorwaerts-Salto, Sturz; sein Weg wird zum Strich eines
		--   riesigen "!", er selbst ist der Punkt.
		-- Einschlag (2,85 = impactAt; Landung 2,42 + 0,4 = 2,82, gemessen ~2,85
		--   - mit 2,44 landete er bei 2,87, F32): Blitz,
		--   Zeitlupe, Kaefig und "!" leuchten, Bodenwellen bis zum Zaun.
		-- Nachklang: jede Antwort wird wieder eine Frage - alle "!" biegen sich
		--   zurueck zu "?" (3,0 .. 3,46), heben ab und zerplatzen in kleine
		--   Fragezeichen (3,45 .. 3,8); das riesige "?" steht ueber ihm (er ist
		--   der Punkt), Rueckwaerts-Salto heim (3,39 .. 4,09), es schrumpft in
		--   seinen Hut, als er ihn zieht (4,09 .. 4,48). Alles weg bis 4,64.
		-- Kein Bonus: Ramp meldet nie `bonus`.
		tier = 4, duration = 5.0, color = C(255, 196, 60), color2 = C(150, 85, 225),
		sounds = { charge = "ping", rise = "whoosh", split = "glass", aha = "snap", slam = "hit",
			strike = "lunge", impact = "boom", pop = "ping" },
		pitch = 1.15,
		impactAt = 2.85,
		steps = {
			-- 1. Aufladen
			{ t = 0.00, fx = "sky",        tint = C(228, 210, 255), brightness = -0.18, saturation = 0.05, dur = 4.6, fade = 0.6 },
			{ t = 0.00, fx = "starfield",  count = 40, dur = 4.4, ownerOnly = true, extra = true },
			{ t = 0.00, fx = "riddler",    tipAt = 0, crouchAt = 0.5, crouch = 0.22, rise = 0.58, spins = 1, grow = 1.2, height = 7,
				glintAt = { 0.32, 1.62, 2.15 }, ahaAt = 2.15, diveAt = 2.42, dive = 0.4, flips = 1, gap = 0.9, curlAt = 3.0,
				curl = 0.3, hold = 0.55, back = 0.7, bow = 0.55 },
			{ t = 0.00, fx = "questionmarks", at = "target", count = 8, appear = 0.18, fly = 0.72, big = 5, high = 7.2,
				splitAt = { 0.95, 1.25, 1.55 }, split = 0.24, radius = 6, lift = 4.6, small = 3, whirl = 5, stopAt = 1.92,
				ahaAt = 2.15, aha = 0.16, dropAt = 2.27, every = 0.045, fall = 0.12, inward = 0.82, flashAt = 2.85,
				curlAt = 3.0, curl = 0.32, popAt = 3.45, popEvery = 0.05 },
			{ t = 0.10, fx = "shake",      power = 0.15, dur = 0.25 },
			{ t = 0.15, fx = "sound",      slot = "charge" },
			{ t = 0.72, fx = "sound",      slot = "rise" },
			-- 2. Lawine
			{ t = 0.90, fx = "puzzled",    ahaAt = 1.25, hold = 1.95, look = 0.7 },
			{ t = 0.95, fx = "sound",      slot = "split" },
			{ t = 1.00, fx = "cinematic",  dur = 2.4, style = "riddle" },
			{ t = 1.25, fx = "sound",      slot = "split" },
			{ t = 1.55, fx = "sound",      slot = "split" },
			-- 3. Spannung
			{ t = 1.92, fx = "silence",    level = 0.15, dur = 0.23 },
			-- 4. Aha und Schlag
			{ t = 2.15, fx = "sound",      slot = "aha" },
			{ t = 2.15, fx = "shake",      power = 0.3, dur = 0.2 },
			{ t = 2.28, fx = "sound",      slot = "slam" },
			{ t = 2.28, fx = "shake",      power = 0.4, dur = 0.4 },
			{ t = 2.42, fx = "sound",      slot = "strike" },
			{ t = 2.50, fx = "sound",      slot = "slam" },
			-- 5. Einschlag
			{ t = 2.85, fx = "flash",      dur = 0.3 },
			{ t = 2.85, fx = "hitstop",    dur = 0.3 },
			{ t = 2.85, fx = "sound",      slot = "impact" },
			{ t = 2.85, fx = "shake",      power = 1.2, dur = 0.6 },
			{ t = 2.86, fx = "ring",       at = "target", ground = true, toArena = true, radius = "fence", dur = 0.9 },
			{ t = 2.94, fx = "ring",       at = "target", ground = true, toArena = true, radius = "fence", dur = 0.9, second = true },
			{ t = 2.86, fx = "wave",       at = "target", radius = 7, dur = 0.4 },
			{ t = 2.90, fx = "dust",       at = "target", count = 30, speed = 12, dur = 1.2, extra = true },
			-- 6. Nachklang: Antwort wird Frage
			{ t = 3.00, fx = "sound",      slot = "rise" },
			{ t = 3.45, fx = "sound",      slot = "pop" },
			{ t = 3.65, fx = "sound",      slot = "pop" },
			{ t = 4.30, fx = "sound",      slot = "split" },
		},
		-- Echo (0,65 s): ein "?" ueber dem Gegner wird "!" und faellt ihm auf den
		-- Kopf (0,25; Treffer 0,26 = TIERS[4].echo * 0,4), wird wieder "?" und
		-- zerplatzt (0,38 .. 0,64), Bodenring.
		echo = {
			{ t = 0.00, fx = "riddlebonk", at = "target", size = 2.3, ahaAt = 0.08, aha = 0.07, dropAt = 0.16, fall = 0.09,
				curlAt = 0.3, popAt = 0.38, life = 0.26 },
			{ t = 0.00, fx = "sound",      slot = "aha" },
			{ t = 0.25, fx = "sound",      slot = "impact" },
			{ t = 0.26, fx = "ring",       at = "target", ground = true, radius = 8, dur = 0.35 },
		},
	},

	HellSigil = {
		-- 25.10. Hoellensiegel (Teufel): bessere Fassung des Blender-Prototyps vom
		-- 22.10. (Video-Vorbild des Nutzers), mit zweitem Siegel unter dem Gegner
		-- (Wunsch des Nutzers). Stufe 4 ausdruecklich erlaubt (6 s, 22.10.), aber
		-- KEINE Kamerafahrt - der Spieler behaelt seine Kamera.
		-- Aufladen (0 .. 1,15): Welt dunkelrot (Besitzer), Siegel unter dem Teufel
		--   zeichnet sich (Flammenkranz, Pentagramm, violetter Wulst, Orbit-Linien,
		--   6 Lichtklingen, Feuerringe, Wirbelscheibe am Himmel); der Teufel
		--   steigt mit Fluegelschlaegen und Drehung 6,5 Studs hoch, reckt ab 1,0
		--   den Dreizack.
		-- Sternbruch (1,15): Siegel implodiert, Spitzen, Funken, Indigo-Ring.
		-- Mal (1,2 .. 1,6): rotes Funkeln springt von der Dreizackspitze zum
		--   Gegner; dort zeichnet sich das zweite Siegel, Runenfesseln steigen an
		--   ihm hoch, er zittert und schaut ab 2,35 hoch.
		-- Schwarze Sonne (2,2): Impact-Frame (dunkel/hell/dunkel, Speedlines),
		--   die Sonne ploppt ueber dem Dreizack auf und waechst; ab 2,85 holt der
		--   Teufel Schwung, 3,05 Dreizack-Stoss = Wurf, Flug 0,38 s im Bogen.
		-- Einschlag (3,43, Treffer 3,45): pink/weisser Blitz, Zeitlupe, Kreis
		--   gleisst, Feuersaeule, Windhiebe, Funkelsterne, Kronen-Schockwelle,
		--   Bodenwellen bis zum Zaun; 4,6 pinker Flammenfaecher, Rauch;
		--   4,4 .. 5,05 Rueckwaerts-Salto nach Hause.
		tier = 4, duration = 5.6, color = C(235, 40, 45), color2 = C(32, 6, 12),
		sounds = { charge = "rumble", rise = "whoosh", burst = "snap", mark = "ping", sun = "bass", throw = "lunge", impact = "boom", fire = "thunder" },
		pitch = 0.8,
		impactAt = 3.45,
		steps = {
			-- 1. Aufladen
			{ t = 0.00, fx = "sky",         tint = C(255, 150, 140), brightness = -0.18, saturation = -0.1, dur = 5.4, fade = 0.6 },
			{ t = 0.00, fx = "sound",       slot = "charge" },
			{ t = 0.00, fx = "hellsigil",   at = "self", radius = 7, draw = 0.6, dur = 2.1, spin = 0.6, runes = 16, points = 5, blades = 6, bladeLen = 15, discs = true, burstAt = 1.15 },
			{ t = 0.00, fx = "hellwings",   height = 6.5, crouch = 0.3, rise = 0.7, spins = 1, grow = 1.25, raiseAt = 1.0, windAt = 2.85, throwAt = 3.05, homeAt = 4.4, back = 0.65 },
			{ t = 0.05, fx = "shake",       power = 0.25, dur = 0.4 },
			{ t = 0.30, fx = "sound",       slot = "rise" },
			-- 2. Sternbruch, Mal, zweites Siegel
			{ t = 1.15, fx = "sound",       slot = "burst" },
			{ t = 1.15, fx = "shake",       power = 0.5, dur = 0.25 },
			{ t = 1.20, fx = "hellsigil",   at = "target", radius = 6, markFrom = "avatar", mark = 0.4, draw = 0.9, dur = 3.6, spin = -0.8, runes = 12, points = 5, glowAt = 1.9, pulseAt = 2.25 },
			{ t = 1.20, fx = "sound",       slot = "mark" },
			{ t = 1.60, fx = "cursed",      hold = 1.85, look = 0.75 },
			-- 3. Schwarze Sonne (Impact-Frame) und Wurf
			{ t = 2.21, fx = "impactframe", pattern = "dld", hold = 0.05 },  -- nach blacksun (Silhouette der Sonne)
			{ t = 2.20, fx = "blacksun",    size = 5, lift = 0.4, windAt = 0.65, throwAt = 0.85, fly = 0.38, sink = 0.14, arc = 3 },
			{ t = 2.20, fx = "sound",       slot = "sun" },
			{ t = 2.20, fx = "shake",       power = 0.6, dur = 0.3 },
			{ t = 3.05, fx = "sound",       slot = "throw" },
			-- 4. Einschlag (Sonne trifft 2,20 + 0,85 + 0,38 = 3,43)
			{ t = 3.40, fx = "flash",       tint = C(255, 110, 150), dur = 0.12 },
			{ t = 3.43, fx = "hellfire",    height = 32, radius = 2.2, dur = 2.0, widenAt = 1.0, crownAt = 0.15, crownR = 9.5, fanAt = 1.15 },
			{ t = 3.44, fx = "flash",       dur = 0.32 },
			{ t = 3.45, fx = "hitstop",     dur = 0.25 },
			{ t = 3.45, fx = "sound",       slot = "impact" },
			{ t = 3.45, fx = "shake",       power = 1.3, dur = 0.6 },
			{ t = 3.47, fx = "ring",        at = "target", ground = true, toArena = true, radius = "fence", dur = 0.9 },
			{ t = 3.55, fx = "ring",        at = "target", ground = true, toArena = true, radius = "fence", dur = 1.0, second = true },
			{ t = 3.60, fx = "sound",       slot = "fire" },
		},
		-- Echo (0,65 s): Mini-Siegel unter dem Gegner, kleine Sonne faellt
		-- hinein (Treffer 0,25), kurze Feuersaeule.
		echo = {
			{ t = 0.00, fx = "hellsigil", at = "target", radius = 3.2, draw = 0.12, dur = 0.62, spin = -2, runes = 8, points = 5, pulseAt = 0.26 },
			{ t = 0.00, fx = "sound",     slot = "mark" },
			{ t = 0.02, fx = "blacksun",  echo = true, size = 2.4, height = 7, windAt = 0.05, throwAt = 0.1, fly = 0.13, sink = 0.08, arc = 0.5 },
			{ t = 0.25, fx = "hellfire",  small = true },
			{ t = 0.26, fx = "sound",     slot = "impact" },
		},
	},

	PulsarNova = {
		-- 25.10.2026 Pulsar-Nova (Pulsar-Baerchi, ersetzt PulsarPulse als
		-- defaultSkill): neue, bessere Fassung des Blender-Prototyps "Pulsstoss"
		-- (22.10., Vorbild-Video: Ring -> Sternbruch -> Kugel -> Impact-Frames
		-- -> Feuerkuppel -> Weissblende). Hauptmotiv: der Baerchi wird zum
		-- Pulsar - ein Leuchtturm aus Licht - und schlaegt als Neutronenstern
		-- ein ("Tickt wie eine Uhr. Jeder Schlag lauter."). Farben: Cyan aus
		-- Visier und Duesenflammen, Feuer-Orange, pinker Saum wie im Vorbild.
		-- Aufladen (0 .. 1,1): Welt kuehl-dunkel (Besitzer), Sterne; Bodenblitz,
		--   ein Lichtpunkt zeichnet den Ring um ihn (0 .. 0,35); er duckt sich
		--   (0,38), das Jetpack zuendet, er steigt mit Drehung auf (0,62 ..
		--   1,1), der Ring hebt mit ab und wird sein Orbit-Ring.
		-- Leuchtturm (1,05 .. 2,05): Lichtkegel aus Visier und Jetpack, er
		--   kreist immer schneller; der Visier-Kegel fegt bei 1,2 / 1,48 / 1,7 /
		--   1,86 / 2,01 durch die Kamera jedes Clients - Blitz + Ticken, jedes
		--   lauter (Besitzer: Bildschirm-Schleier). Kamera tief von unten
		--   (1,05 .. 3,55).
		-- Kollaps (2,05): Kegel und Ring stuerzen in ihn, er wird zum weiss-
		--   gluehenden Neutronenstern, Anime-Sternbruch, Funken; Pulse 2,15 /
		--   2,3; Stille 2,25 .. 2,45.
		-- Schlag (2,45): er schiesst als Komet in den Gegner (Schweif cyan ->
		--   orange, Nachbilder).
		-- Einschlag (2,9 = impactAt; Flug 2,45 + 0,43 = 2,88): kleine Kuppel,
		--   Impact-Frames (nur Besitzer: invertiert mit Silhouetten + Speed-
		--   lines, dann Weiss), Feuerkuppel (Radius 8) mit laufenden Flammen-
		--   baendern, Loechern, pinkem Saum, Flammenkranz, Truemmern;
		--   Bodenwellen bis zum Zaun; Pulse 3,45 / 3,95.
		-- Weissblende (4,35): die Kuppel flammt auf und vergeht (Besitzer:
		--   Weiss -> Rosa bis 5,46).
		-- Nachklang: er rollt sich aus dem Krater auf (4,42), Rueckwaerts-Salto
		--   heim (4,58 .. 5,3), der Ring blitzt um seine Fuesse; Flammen
		--   zuengeln am Gegner (Brand = DoT). Alles weg bis 5,65.
		-- Kein Bonus: DoT meldet nie `bonus`.
		tier = 4, duration = 5.7, color = C(70, 228, 255), color2 = C(255, 138, 40),
		sounds = { charge = "bass", ignite = "rocket", tick = "ping", collapse = "glass", pulse = "rumble",
			strike = "lunge", impact = "boom", after = "thunder", flare = "flash", home = "whoosh", land = "ping" },
		pitch = 1.0,
		impactAt = 2.9,
		steps = {
			-- 1. Aufladen
			{ t = 0.00, fx = "sky",        tint = C(200, 236, 255), brightness = -0.2, saturation = 0.05, dur = 5.3, fade = 0.6 },
			{ t = 0.00, fx = "starfield",  count = 40, dur = 5.0, ownerOnly = true, extra = true },
			{ t = 0.00, fx = "pulsar",     ring = 3.6, draw = 0.35, crouchAt = 0.38, crouch = 0.24, rise = 0.48, height = 5.5,
				spins = 1, grow = 1.15, beamAt = 1.05, beamLen = 34, ticks = { 1.2, 1.48, 1.7, 1.86, 2.01 },
				collapseAt = 2.05, pulseAt = { 2.15, 2.3 }, windAt = 2.33, launchAt = 2.45, fly = 0.43,
				emergeAt = 4.42, emerge = 0.16, back = 0.72, settle = 0.35 },
			{ t = 0.00, fx = "sound",      slot = "charge" },
			{ t = 0.05, fx = "shake",      power = 0.15, dur = 0.2 },
			{ t = 0.60, fx = "sound",      slot = "ignite" },
			{ t = 0.62, fx = "shake",      power = 0.22, dur = 0.3 },
			-- 2. Leuchtturm: jeder Durchgang durch die Kamera blitzt und tickt
			-- (der Blitz selbst kommt aus `pulsar`), jeder lauter
			{ t = 1.05, fx = "cinematic",  dur = 2.5, style = "pulsar" },
			{ t = 1.20, fx = "sound",      slot = "tick" },
			{ t = 1.20, fx = "shake",      power = 0.1, dur = 0.12 },
			{ t = 1.48, fx = "sound",      slot = "tick" },
			{ t = 1.48, fx = "shake",      power = 0.15, dur = 0.12 },
			{ t = 1.70, fx = "sound",      slot = "tick" },
			{ t = 1.70, fx = "shake",      power = 0.2, dur = 0.12 },
			{ t = 1.86, fx = "sound",      slot = "tick" },
			{ t = 1.86, fx = "shake",      power = 0.26, dur = 0.12 },
			{ t = 2.01, fx = "sound",      slot = "tick" },
			{ t = 2.01, fx = "shake",      power = 0.32, dur = 0.12 },
			-- 3. Kollaps zum Neutronenstern, Spannung
			{ t = 2.05, fx = "sound",      slot = "collapse" },
			{ t = 2.05, fx = "shake",      power = 0.45, dur = 0.25 },
			{ t = 2.12, fx = "sound",      slot = "pulse" },
			{ t = 2.25, fx = "silence",    level = 0.12, dur = 0.2 },
			-- 4. Schlag
			{ t = 2.45, fx = "sound",      slot = "strike" },
			{ t = 2.45, fx = "shake",      power = 0.4, dur = 0.3 },
			-- 5. Einschlag: Impact-Frames, Feuerkuppel
			{ t = 2.90, fx = "firedome",   at = "target", radius = 8, mini = 3.2, miniFor = 0.07, grow = 0.12,
				pulseAt = { 0.55, 1.05 }, flareAt = 1.45, fade = 0.3, burn = 0.75, holes = 6, skirt = 18, chunks = 10 },
			{ t = 2.93, fx = "novaframe",  invert = 0.045, white = 0.08, fade = 0.16, lines = 46 },
			{ t = 2.90, fx = "sound",      slot = "impact" },
			{ t = 2.90, fx = "shake",      power = 1.4, dur = 0.8 },
			{ t = 2.92, fx = "ring",       at = "target", ground = true, toArena = true, radius = "fence", dur = 0.9, tex = "shockring" },
			{ t = 3.00, fx = "ring",       at = "target", ground = true, toArena = true, radius = "fence", dur = 0.9, second = true, tex = "shockring" },
			{ t = 3.00, fx = "sound",      slot = "after" },
			{ t = 3.05, fx = "dust",       at = "target", count = 36, speed = 15, dur = 1.3, tex = "stardust", extra = true },
			-- 6. Die Kuppel pulst wie der Pulsar (rosa Schleier kommt aus `firedome`)
			{ t = 3.45, fx = "sound",      slot = "pulse" },
			{ t = 3.45, fx = "shake",      power = 0.3, dur = 0.25 },
			{ t = 3.95, fx = "sound",      slot = "pulse" },
			{ t = 3.95, fx = "shake",      power = 0.38, dur = 0.25 },
			-- 7. Weissblende (aus `firedome`) und Nachklang
			{ t = 4.35, fx = "sound",      slot = "flare" },
			{ t = 4.35, fx = "shake",      power = 0.6, dur = 0.4 },
			{ t = 4.58, fx = "sound",      slot = "home" },
			{ t = 5.30, fx = "sound",      slot = "land" },
		},
		-- Echo (0,65 s): ein kleiner Neutronenstern schiesst in den Gegner
		-- (Treffer 0,26 = TIERS[4].echo * 0,4), eine kleine Kuppel ploppt auf,
		-- Bodenring.
		echo = {
			{ t = 0.00, fx = "novabolt",   at = "target", fly = 0.25, radius = 2.6, life = 0.34, size = 0.95 },
			{ t = 0.00, fx = "sound",      slot = "strike" },
			{ t = 0.25, fx = "sound",      slot = "impact" },
			{ t = 0.27, fx = "ring",       at = "target", ground = true, radius = 8, dur = 0.35, second = true, tex = "shockring" },
		},
	},
	-- ------------------------------------------------------------------
	-- 25.10.2026 Bauchrutscher (PolarSlide, Eisbaer, Uncommon, Stufe 2, ohne
	-- Kamerafahrt). Werte wie Eisschlag (balance-neutral), neue Show.
	-- Takte: 0,0 Eisbahn gefriert (0,55 s), Ducken | 0,55 Sprung auf den Bauch |
	-- 0,75-1,45 Rutschen mit Schneefahne und Pirouette | 1,5 Rums: Gegner im
	-- Eisblock (= Treffer, Stun) | 1,5-2,1 Purzeln heim, 2,25 Schuetteln |
	-- 2,35 Eisblock zerspringt | 2,8 Ende. Echo: kleiner Eisblock, zerspringt.
	-- ------------------------------------------------------------------
	PolarSlide = {
		tier = 2, duration = 2.8, impactAt = 1.5,
		color = Color3.fromRGB(160, 215, 255), color2 = Color3.fromRGB(70, 130, 210),
		pitch = 1.1,
		sounds = { charge = "whoosh", slide = "rumble", impact = "boom", shatter = "glass" },
		steps = {
			{ t = 0,    fx = "sound", slot = "charge" },
			{ t = 0,    fx = "icepath", draw = 0.55, width = 2.4, plates = 6, spikes = 8, slideAt = 0.75, slideEnd = 1.5, meltAt = 2.25, dur = 2.75 },
			{ t = 0,    fx = "moves", hold = 0.04, outline = Color3.fromRGB(70, 130, 210), keys = {
				{ t = 0.30, pitch = 0.04, scale = 0.93, ease = "out" },
				{ t = 0.55, dy = 0.9, dz = 1.3, pitch = -0.2, scale = 1, ease = "out", burst = 8 },
				{ t = 0.75, dz = 2.4, dy = -0.35, pitch = -0.22, ease = "in", smoke = 10 },
				{ t = 1.45, at = "land", dz = 0.3, dy = -0.35, pitch = -0.22, yaw = 1, ease = "in", trail = true },
				{ t = 1.50, at = "land", dz = -0.3, dy = -0.1, pitch = -0.16, yaw = 1, ease = "out", burst = 24, smoke = 14 },
				{ t = 2.10, at = "home", pitch = 0, yaw = 1, roll = 1, arc = 2.6, ease = "inout" },
				{ t = 2.25, at = "home", scale = 0.94, ease = "out", smoke = 8 },
				{ t = 2.45, at = "home", yaw = 1.08, scale = 1.02 },
				{ t = 2.62, at = "home", yaw = 0.96 },
				{ t = 2.72, at = "home", yaw = 1, scale = 1 },
			} },
			{ t = 0.75, fx = "sound", slot = "slide" },
			{ t = 1.5,  fx = "sound", slot = "impact" },
			{ t = 1.5,  fx = "iceblock", at = "target", appear = 0.12, breakAt = 0.85, dur = 1.25 },
			{ t = 1.5,  fx = "shake", power = 0.25, dur = 0.2 },
			{ t = 2.35, fx = "sound", slot = "shatter" },
		},
		echo = {
			{ t = 0,    fx = "sound", slot = "impact" },
			{ t = 0.06, fx = "iceblock", at = "target", appear = 0.06, breakAt = 0.26, dur = 0.38, small = true },
			{ t = 0.32, fx = "sound", slot = "shatter" },
		},
	},

	-- ------------------------------------------------------------------
	-- 25.10.2026 Tigersprung (TigerPounce, Tigerbaer, Uncommon, Stufe 2, ohne
	-- Kamerafahrt). Werte wie Feuerbiss (DoT), neue Show.
	-- Takte: 0,0-0,5 Anschleichen (Ducken, Wippen) | 0,5-0,95 Sprung im Bogen vor
	-- den Gegner | 1,0 / 1,14 / 1,28 drei Krallenhiebe (1,0 = Treffer), die
	-- Kratzer schwelen (= Brand) | 1,65 Pose | 1,65-2,3 Rueckwaerts-Salto heim |
	-- 2,6 Ende. Echo: ein Krallenhieb.
	-- ------------------------------------------------------------------
	TigerPounce = {
		tier = 2, duration = 2.6, impactAt = 1.0,
		color = Color3.fromRGB(255, 140, 40), color2 = Color3.fromRGB(255, 215, 90),
		pitch = 1.1,
		sounds = { charge = "lunge", strike = "slash", impact = "snap" },
		steps = {
			{ t = 0,    fx = "moves", outline = Color3.fromRGB(255, 120, 30), hold = 0.04, keys = {
				{ t = 0.30, dz = -0.3, scale = 0.9, ease = "out" },
				{ t = 0.42, dz = -0.25, dy = 0.08, scale = 0.92 },
				{ t = 0.50, dz = -0.3, dy = 0, scale = 0.9, ease = "in" },
				{ t = 0.95, at = "land", dz = -0.3, dxc = -1.0, dy = 0.5, pitch = -0.12, scale = 1.08, arc = 3.2, ease = "in", trail = true },
				{ t = 1.02, at = "land", dz = -0.05, dxc = -1.0, dy = 0, pitch = -0.04, scale = 1, ease = "out", burst = 18, smoke = 8 },
				{ t = 1.14, at = "land", dz = -0.05, dxc = -1.0, roll = -0.03, yaw = 0.03 },
				{ t = 1.28, at = "land", dz = -0.05, dxc = -1.0, roll = 0.03, yaw = -0.03 },
				{ t = 1.42, at = "land", dz = -0.05, dxc = -1.0, roll = 0, yaw = 0 },
				{ t = 1.65, at = "land", dz = -0.1, dxc = -1.0, pitch = 0.06, scale = 1.04, ease = "out" },
				{ t = 2.30, at = "home", pitch = 1.06, scale = 1, arc = 3.0, ease = "inout" },
				{ t = 2.45, at = "home", pitch = 1.0, scale = 0.96, ease = "out", smoke = 6 },
				{ t = 2.56, at = "home", scale = 1 },
			} },
			{ t = 0.5,  fx = "sound", slot = "charge" },
			{ t = 1.0,  fx = "clawmarks", at = "target", count = 3, every = 0.14, claws = 3, len = 2.6, draw = 0.07, fade = 0.3, dur = 1.55 },
			{ t = 1.0,  fx = "sound", slot = "strike" },
			{ t = 1.14, fx = "sound", slot = "strike" },
			{ t = 1.28, fx = "sound", slot = "strike" },
			{ t = 1.28, fx = "sound", slot = "impact" },
			{ t = 1.0,  fx = "shake", power = 0.2, dur = 0.3 },
		},
		echo = {
			{ t = 0.10, fx = "clawmarks", at = "target", count = 1, claws = 3, len = 2.2, draw = 0.06, fade = 0.12, dur = 0.34 },
			{ t = 0.10, fx = "sound", slot = "strike" },
		},
	},

	-- ------------------------------------------------------------------
	-- 25.10.2026 Brennglas (MagnifierBurn, Detektiv, Rare, Stufe 2, ohne
	-- Kamerafahrt). Werte wie Splitterhagel (2.2x + 14), neue Show.
	-- Takte: 0,0-0,65 Pfotenspuren erscheinen, 0,25-1,0 der Detektiv huepft ihnen
	-- in drei Spruengen nach | 1,1 die Lupe waechst aus seiner Pfote | 1,35
	-- Lichtstrahl, Brennpunkt sucht (Rauch, Gluehen) | 2,1 Flammenstoss (=
	-- Treffer), Spuren blitzen, "Aha"-Hopser | 2,45 Hut ziehen | 2,65-2,88
	-- Hopser heim | 3,0 Ende. Echo: kleine Lupe, kurzer Strahl, Flammenstoss.
	-- ------------------------------------------------------------------
	MagnifierBurn = {
		tier = 2, duration = 3.0, impactAt = 2.1,
		color = Color3.fromRGB(255, 214, 110), color2 = Color3.fromRGB(255, 120, 50),
		pitch = 1.0,
		sounds = { charge = "ping", strike = "flash", impact = "boom", aha = "ping" },
		steps = {
			{ t = 0,    fx = "sound", slot = "charge" },
			{ t = 0,    fx = "pawprints", count = 7, every = 0.09, sway = 0.38, gap = 2.4, pulseAt = 2.1, dur = 2.9 },
			{ t = 0,    fx = "moves", hat = "acc_dome,acc_peak,acc_hatband,acc_knob", hold = 0.05, gap = 2.4, keys = {
				{ t = 0.25, pitch = -0.03, scale = 0.95, ease = "out" },
				{ t = 0.50, u = 0.34, h = 0, dx = 0.3, arc = 0.9, ease = "out", scale = 1 },
				{ t = 0.75, u = 0.67, h = 0, dx = -0.3, arc = 0.9 },
				{ t = 1.00, u = 1.0, h = 0, dx = 0, arc = 0.9, smoke = 5 },
				{ t = 1.15, at = "land", pitch = 0.02, scale = 0.97, ease = "out" },
				{ t = 1.40, at = "land", pitch = 0.06, dy = 0.05, scale = 1 },
				{ t = 2.05, at = "land", pitch = 0.06, roll = 0.01 },
				{ t = 2.12, at = "land", pitch = 0.1, dy = 0.35, ease = "out", burst = 10 },
				{ t = 2.28, at = "land", pitch = 0.04, dy = 0, ease = "in" },
				{ t = 2.45, at = "land", pitch = 0.06, tip = 1, ease = "out" },
				{ t = 2.65, at = "land", pitch = 0, tip = 0 },
				{ t = 2.88, at = "home", arc = 1.8, ease = "inout" },
				{ t = 2.95, at = "home", scale = 0.98 },
			} },
			{ t = 1.1,  fx = "lensbeam", lens = 1.1, appear = 0.25, beamAt = 0.25, burnAt = 1.0, away = 0.25, dur = 1.5 },
			{ t = 1.35, fx = "sound", slot = "strike" },
			{ t = 2.05, fx = "sound", slot = "aha" },
			{ t = 2.1,  fx = "sound", slot = "impact" },
			{ t = 2.1,  fx = "shake", power = 0.2, dur = 0.2 },
		},
		echo = {
			{ t = 0,    fx = "lensbeam", lens = 0.7, appear = 0.05, beamAt = 0.05, burnAt = 0.18, away = 0.14, dur = 0.42, small = true },
			{ t = 0.18, fx = "sound", slot = "impact" },
		},
	},

	-- ------------------------------------------------------------------
	-- 25.10.2026 Bass-Drop (BassDrop, Zucker-DJ, Rare, Stufe 2, ohne
	-- Kamerafahrt). Werte wie Zuckersturm (AoE), neue Show.
	-- Takte: 0,0 Schallplatte ploppt unter dem DJ auf, Equalizer-Balken rund um
	-- die Arena | 0,5 / 1,0 / 1,5 drei Beats (Hopser, Bodenring, Balken zucken,
	-- Kopfhoerer leuchten) | 1,55-2,0 Build-up (Ducken, Balken steigen, Platte
	-- rast, Stille) | 2,0 DROP (= Treffer): Bass, Schockwelle bis zum Zaun,
	-- Sprung mit Drehung, Streusel am Gegner | 2,6 Landung, 2,8 Pose | 3,0 Ende.
	-- Echo: Bodenring + Welle + Bass.
	-- ------------------------------------------------------------------
	BassDrop = {
		tier = 2, duration = 3.0, impactAt = 2.0,
		color = Color3.fromRGB(255, 160, 211), color2 = Color3.fromRGB(218, 196, 255),
		pitch = 1.0,
		sounds = { beat = "snap", rise = "whoosh", drop = "bass", impact = "boom" },
		steps = {
			{ t = 0,    fx = "djset", beats = { 0.5, 1.0, 1.5 }, buildAt = 1.55, dropAt = 2.0, dur = 2.95, bars = 14, radius = 7.5, disc = 4.6 },
			{ t = 0,    fx = "moves", keys = {
				{ t = 0.20, dy = 0.15, ease = "out" },
				{ t = 0.50, dy = 0.45, ease = "out" },
				{ t = 0.70, dy = 0.15, ease = "in" },
				{ t = 1.00, dy = 0.45, roll = 0.02, ease = "out" },
				{ t = 1.20, dy = 0.15, ease = "in" },
				{ t = 1.50, dy = 0.45, roll = -0.02, ease = "out" },
				{ t = 1.70, dy = 0.15, ease = "in" },
				{ t = 1.95, dy = 0.1, scale = 0.9, pitch = 0.05, roll = 0 },
				{ t = 2.00, dy = 0.3, scale = 0.95, ease = "out" },
				{ t = 2.32, dy = 1.7, scale = 1.1, roll = 0.5, pitch = 0, ease = "out", burst = 30 },
				{ t = 2.60, dy = 0.15, roll = 1, scale = 0.94, ease = "in", smoke = 12 },
				{ t = 2.80, dy = 0.15, scale = 1, pitch = -0.04, yaw = 0.06, ease = "out" },
				{ t = 2.90, dy = 0.15, yaw = 0.06 },
			} },
			{ t = 0.5,  fx = "sound", slot = "beat" },
			{ t = 1.0,  fx = "sound", slot = "beat" },
			{ t = 1.5,  fx = "sound", slot = "beat" },
			{ t = 1.55, fx = "sound", slot = "rise" },
			{ t = 1.85, fx = "silence", dur = 0.15, level = 0.15 },
			{ t = 2.0,  fx = "sound", slot = "drop" },
			{ t = 2.0,  fx = "sound", slot = "impact" },
			{ t = 2.0,  fx = "shake", power = 0.5, dur = 0.35 },
			{ t = 2.0,  fx = "flash", dur = 0.12, tint = Color3.fromRGB(255, 200, 235) },
		},
		echo = {
			{ t = 0.02, fx = "ring", at = "self", ground = true, radius = 6, dur = 0.3 },
			{ t = 0.12, fx = "wave", at = "self", radius = 8, dur = 0.3 },
			{ t = 0.15, fx = "sound", slot = "drop" },
			{ t = 0.18, fx = "sparks", at = "target", count = 10, dur = 0.26 },
		},
	},
	-- ------------------------------------------------------------------
	-- 25.10.2026 Muenzregen (CoinShower, Goldener Grizzly, Epic, Stufe 3, ohne
	-- Kamerafahrt). Werte wie Gold Rush (Drain 25%), neue Show.
	-- Takte: 0,0-0,62 Aufbaeumen | 0,75 Stampfer: Bodenring, Gold-Riss laeuft zum
	-- Gegner (0,8-1,4) | 1,6 Muenzen spritzen aus dem Gegner (= Treffer, Drain)
	-- und fliegen bis 3,0 im Bogen zum Grizzly, der Haufen waechst, er wird
	-- groesser, Medaille blitzt | 3,0-3,45 Haufen sinkt, Pose | 3,6 Ende.
	-- Echo: 6 Muenzen, kleiner Haufen.
	-- ------------------------------------------------------------------
	CoinShower = {
		tier = 3, duration = 3.6, impactAt = 1.6,
		color = Color3.fromRGB(255, 200, 50), color2 = Color3.fromRGB(190, 150, 60),
		pitch = 0.95,
		sounds = { charge = "rumble", stomp = "boom", strike = "ping", impact = "glass" },
		steps = {
			{ t = 0,    fx = "sound", slot = "charge" },
			{ t = 0,    fx = "moves", hold = 0.05, outline = Color3.fromRGB(255, 170, 40), keys = {
				{ t = 0.45, pitch = 0.12, dy = 0.3, scale = 1.06, ease = "out" },
				{ t = 0.62, pitch = 0.15, dy = 0.4, scale = 1.08 },
				{ t = 0.75, pitch = -0.02, dy = 0, scale = 1.0, ease = "in", burst = 20, smoke = 16 },
				{ t = 0.95, pitch = 0, scale = 0.98, ease = "out" },
				{ t = 1.60, pitch = 0.02, scale = 1.0 },
				{ t = 2.30, pitch = 0.04, scale = 1.08, ease = "out" },
				{ t = 2.75, pitch = 0.06, scale = 1.14, ease = "out", burst = 12 },
				{ t = 3.10, pitch = 0, yaw = 0.05, scale = 1.14 },
				{ t = 3.35, yaw = -0.02, scale = 1.06 },
				{ t = 3.55, yaw = 0, scale = 1 },
			} },
			{ t = 0.75, fx = "sound", slot = "stomp" },
			{ t = 0.75, fx = "shake", power = 0.35, dur = 0.3 },
			{ t = 0.75, fx = "ring", at = "self", ground = true, radius = 5, dur = 0.5 },
			{ t = 0.8,  fx = "crack", dur = 0.6, linger = 2.2, segments = 7, amp = 0.8, width = 0.3 },
			{ t = 1.6,  fx = "sound", slot = "impact" },
			{ t = 1.6,  fx = "coinshower", count = 18, burstAt = 0, rise = 0.28, fly = 0.5, every = 0.035, dur = 2.0 },
			{ t = 1.7,  fx = "sound", slot = "strike" },
			{ t = 2.1,  fx = "sound", slot = "strike" },
			{ t = 1.6,  fx = "rise", at = "target", count = 10, dur = 0.8, toSelf = true, extra = true },
		},
		echo = {
			{ t = 0,    fx = "sound", slot = "impact" },
			{ t = 0.02, fx = "coinshower", count = 6, burstAt = 0, rise = 0.12, fly = 0.25, every = 0.03, dur = 0.52, small = true },
		},
	},

	-- ------------------------------------------------------------------
	-- 25.10.2026 Shuriken-Sturm (ShurikenStorm, Ninja, Epic, Stufe 3, ohne
	-- Kamerafahrt). Werte wie Schwarzes Loch (AoE 2.4x + 25), neue Show.
	-- Takte: 0,45 Rauch-Puff, der Ninja ist weg | 0,5 / 0,7 / 0,9 drei Schatten-
	-- klone erscheinen um den Gegner | 1,2 / 1,4 / 1,6 Shuriken-Wuerfe, bohren
	-- sich um den Gegner in den Boden | 2,0 alle Klone stuermen durch ihn (Puffs)
	-- | 2,27 der echte Ninja erscheint hinter dem Gegner, 2,3 Katana-Schnitt
	-- (= Treffer), Shuriken blitzen | 3,1 Puff, 3,5 Puff zu Hause | 3,8 Ende.
	-- Echo: ein Shuriken von self in den Boden vor dem Gegner.
	-- ------------------------------------------------------------------
	ShurikenStorm = {
		tier = 3, duration = 3.8, impactAt = 2.3,
		color = Color3.fromRGB(231, 63, 75), color2 = Color3.fromRGB(40, 32, 70),
		pitch = 1.05,
		sounds = { charge = "whoosh", throw = "snap", dash = "lunge", strike = "slash", impact = "hit" },
		steps = {
			{ t = 0,    fx = "moves", hold = 0.05, hat = "acc_blade,acc_grip,acc_guard", outline = Color3.fromRGB(231, 63, 75), keys = {
				{ t = 0.30, scale = 0.95, pitch = 0.02, ease = "out" },
				{ t = 0.45, scale = 0.9, dy = 0.1, smoke = 22, hidden = true },
				{ t = 2.24, at = "target", dz = 1.7, yaw = 0.5, scale = 1, dy = 0, hidden = true },
				{ t = 2.27, at = "target", dz = 1.7, yaw = 0.5, hidden = false, smoke = 18, burst = 10 },
				{ t = 2.34, at = "target", dz = 1.7, yaw = 0.5, roll = -0.05, pitch = -0.04, tip = 1, ease = "out" },
				{ t = 2.70, at = "target", dz = 1.7, yaw = 0.5, roll = 0, pitch = 0, tip = 1 },
				{ t = 2.95, at = "target", dz = 1.7, yaw = 0.5, tip = 0 },
				{ t = 3.10, at = "target", dz = 1.7, yaw = 0.5, hidden = true, smoke = 16 },
				{ t = 3.50, at = "home", yaw = 0, hidden = false, smoke = 14 },
				{ t = 3.60, at = "home", scale = 0.96, ease = "out" },
				{ t = 3.72, at = "home", scale = 1 },
			} },
			{ t = 0.45, fx = "sound", slot = "charge" },
			{ t = 0.5,  fx = "ninjaclones", count = 3, radius = 4.5, appearAt = 0, every = 0.2, throwAt = 0.7, flight = 0.35, dashAt = 1.5, dash = 0.2, flashAt = 1.85, dur = 2.6 },
			{ t = 1.2,  fx = "sound", slot = "throw" },
			{ t = 1.4,  fx = "sound", slot = "throw" },
			{ t = 1.6,  fx = "sound", slot = "throw" },
			{ t = 2.0,  fx = "sound", slot = "dash" },
			{ t = 2.27, fx = "sound", slot = "charge" },
			{ t = 2.3,  fx = "katana", at = "target", radius = 1.9, draw = 0.08, fade = 0.3 },
			{ t = 2.3,  fx = "sound", slot = "strike" },
			{ t = 2.32, fx = "sound", slot = "impact" },
			{ t = 2.3,  fx = "hitstop", dur = 0.12 },
			{ t = 2.3,  fx = "shake", power = 0.4, dur = 0.25 },
			{ t = 3.1,  fx = "sound", slot = "charge" },
		},
		echo = {
			{ t = 0,    fx = "ninjaclones", single = true, throwAt = 0, flight = 0.2, flashAt = 0.3, dur = 0.52 },
			{ t = 0.2,  fx = "sound", slot = "impact" },
			{ t = 0.2,  fx = "sparks", at = "target", count = 10, dur = 0.3 },
		},
	},

	-- ------------------------------------------------------------------
	-- 25.10.2026 Wurzelwall (RootBulwark, Uralter Baerchi, Legendary, Stufe 3,
	-- ohne Kamerafahrt). Werte wie Titan-Modus (Schild 90% / 3 Aktionen), neue Show.
	-- Takte: 0,0-0,3 Aufbaeumen | 0,45 Stampfer: Moosring | 0,5-1,4 Wurzeln
	-- brechen aus dem Boden und flechten sich ueber ihm zum Kaefig | 1,4 Spitzen
	-- treffen sich (= Schild): Puls, Blaetter spriessen, Gluehwuermchen, Blatt-
	-- krone leuchtet, leichter Gruenfilter | 3,0 Wurzeln sinken, Blaetter stieben
	-- | 3,6 Ende. Echo: vier kleine Wurzeln.
	-- ------------------------------------------------------------------
	RootBulwark = {
		tier = 3, duration = 3.6, impactAt = 1.4,
		color = Color3.fromRGB(124, 196, 108), color2 = Color3.fromRGB(96, 64, 40),
		pitch = 0.85,
		sounds = { charge = "rumble", stomp = "boom", impact = "snap", leaves = "whoosh" },
		steps = {
			{ t = 0,    fx = "sound", slot = "charge" },
			{ t = 0,    fx = "moves", hold = 0.05, outline = Color3.fromRGB(124, 196, 108), keys = {
				{ t = 0.30, pitch = 0.1, dy = 0.35, scale = 1.03, ease = "out" },
				{ t = 0.45, pitch = -0.02, dy = 0, scale = 1, ease = "in", burst = 14, smoke = 18 },
				{ t = 0.65, pitch = 0, scale = 0.98, ease = "out" },
				{ t = 1.40, pitch = 0.03, scale = 1.03 },
				{ t = 1.55, pitch = 0.02, dy = 0.15, scale = 1.05, ease = "out" },
				{ t = 1.75, dy = 0, scale = 1.03, ease = "in" },
				{ t = 2.90, pitch = 0.02, scale = 1.03 },
				{ t = 3.30, pitch = 0, scale = 1 },
				{ t = 3.50, scale = 1 },
			} },
			{ t = 0.45, fx = "sound", slot = "stomp" },
			{ t = 0.45, fx = "shake", power = 0.3, dur = 0.3 },
			{ t = 0.45, fx = "ring", at = "self", ground = true, radius = 5, dur = 0.6 },
			{ t = 0.5,  fx = "roots", count = 10, segs = 7, radius = 2.3, height = 1.45, grow = 0.55, stagger = 0.05, closeAt = 0.9, sinkAt = 2.5, dur = 3.05 },
			{ t = 1.4,  fx = "sound", slot = "impact" },
			{ t = 1.4,  fx = "sky", saturation = 0.2, brightness = 0.02, tint = Color3.fromRGB(235, 255, 230), dur = 1.4 },
			{ t = 3.0,  fx = "sound", slot = "leaves" },
		},
		echo = {
			{ t = 0,    fx = "roots", count = 4, segs = 4, radius = 1.6, height = 0.8, grow = 0.2, stagger = 0.03, closeAt = 0.22, sinkAt = 0.38, dur = 0.52 },
			{ t = 0.22, fx = "sound", slot = "impact" },
		},
	},

	-- ------------------------------------------------------------------
	-- 25.10.2026 Regenbogenbruecke (RainbowBridge, Regenbogen-Baerchi, Legendary,
	-- Stufe 3, ohne Kamerafahrt). Werte wie Chroma-Blast (3x + 30), neue Show.
	-- Takte: 0,1-0,7 der Regenbogen zeichnet sich von ihm zum Landeplatz | 0,55-
	-- 1,5 Anlauf und Lauf den Bogen hoch (gleiche Kurve wie die Baender) | 1,5-
	-- 1,85 Salto am Scheitel | 2,05-2,38 Bauchrutscher den Bogen hinab, 2,4
	-- Landung vor dem Gegner (= Treffer): Farbkleckse, Regenbogen-Splitter,
	-- Welle, Blitz, Farbsaettigung | 2,6-3,5 der Regenbogen loest sich zu Glitzer
	-- auf, Jubel-Hopser | 3,55 Hopser heim mit Doppelrolle | 3,9 Ende.
	-- Echo: kleiner Bogen bis zum Gegner, Kleckse.
	-- ------------------------------------------------------------------
	RainbowBridge = {
		tier = 3, duration = 3.9, impactAt = 2.4,
		color = Color3.fromRGB(255, 60, 120), color2 = Color3.fromRGB(60, 200, 255),
		pitch = 1.15,
		sounds = { charge = "ping", run = "whoosh", flip = "whoosh", impact = "splat", boom = "boom" },
		steps = {
			{ t = 0,    fx = "sound", slot = "charge" },
			{ t = 0.1,  fx = "rainbow", bands = 6, width = 0.38, curve = 8.5, tilt = 0.35, lift = 0.3, draw = 0.6, dissolveAt = 2.5, dur = 3.6 },
			{ t = 0,    fx = "moves", hold = 0.05, outline = Color3.fromRGB(255, 60, 120), keys = {
				{ t = 0.35, pitch = 0.03, scale = 0.94, ease = "out" },
				{ t = 0.55, scale = 0.9, dy = 0.05 },
				{ t = 0.90, u = 0.16, curve = 8.5, dy = 1.75, pitch = 0.22, scale = 1, ease = "out", trail = true, burst = 6 },
				{ t = 1.25, u = 0.36, curve = 8.5, dy = 1.75, pitch = 0.12, ease = "linear", trail = true },
				{ t = 1.50, u = 0.5, curve = 8.5, dy = 1.75, pitch = 0, ease = "linear" },
				{ t = 1.85, u = 0.5, curve = 8.5, dy = 2.75, roll = 1, ease = "inout", burst = 16 },
				{ t = 2.05, u = 0.64, curve = 8.5, dy = 1.6, pitch = -0.2, ease = "in", trail = true },
				{ t = 2.28, u = 0.9, curve = 8.5, dy = 1.55, pitch = -0.22, ease = "in", trail = true },
				{ t = 2.38, u = 1.0, curve = 8.5, dy = 0, pitch = -0.06, ease = "in", burst = 30, smoke = 14 },
				{ t = 2.55, at = "land", pitch = 0.03, scale = 0.95, ease = "out" },
				{ t = 2.80, at = "land", pitch = 0.05, scale = 1, dy = 0.25, ease = "out" },
				{ t = 2.98, at = "land", dy = 0, ease = "in" },
				{ t = 3.55, at = "home", arc = 3.0, roll = 2, ease = "inout" },
				{ t = 3.70, at = "home", roll = 2, scale = 0.96, ease = "out" },
				{ t = 3.82, at = "home", scale = 1 },
			} },
			{ t = 0.85, fx = "sound", slot = "run" },
			{ t = 1.55, fx = "sound", slot = "flip" },
			{ t = 2.4,  fx = "sound", slot = "impact" },
			{ t = 2.4,  fx = "sound", slot = "boom" },
			{ t = 2.4,  fx = "paintsplash", at = "target", count = 9, radius = 2.4, dur = 1.4 },
			{ t = 2.4,  fx = "shards", at = "target", rainbow = true, count = 16, size = 0.45, dur = 0.7 },
			{ t = 2.4,  fx = "wave", at = "target", radius = 7, dur = 0.45 },
			{ t = 2.4,  fx = "shake", power = 0.45, dur = 0.3 },
			{ t = 2.4,  fx = "flash", dur = 0.1 },
			{ t = 2.35, fx = "sky", saturation = 0.35, brightness = 0.04, dur = 1.0 },
		},
		echo = {
			{ t = 0,    fx = "rainbow", echo = true, bands = 6, width = 0.3, curve = 3, tilt = 0.4, lift = 0.3, draw = 0.18, dissolveAt = 0.28, dur = 0.52 },
			{ t = 0.22, fx = "paintsplash", at = "target", count = 4, radius = 1.6, dur = 0.3 },
			{ t = 0.22, fx = "sound", slot = "impact" },
			{ t = 0.22, fx = "sparks", at = "target", count = 10, dur = 0.28, rainbow = true },
		},
	},
	-- ------------------------------------------------------------------
	-- 26.10.2026 Himmelsgericht (SeraphJudgment, Seraph-Baerchi, Divine, Stufe 4,
	-- eine Kamerafahrt 1,05-3,55). Ersetzt Seraphen-Segen (Heal) als defaultSkill;
	-- neue Werte: Opener 3,4x + 60 (erster Einsatz je Gegner), sonst 1,8x + 60.
	-- Dopamin-Plan: Rhythmus beim Aufladen (drei Fluegel-Schnapper), Senkrechte
	-- (Himmelstor), Heldenmoment (Flug, Speer), Urteil (Ticks, Stille, Sturz),
	-- Wucht (Impact-Frames, Hitstop, Beben, Knall nach Blitz), Nachklang (Saeule,
	-- Kuppel, fallende Ringe, Federregen) und eine Pointe (schiefer Heiligenschein
	-- auf dem Gegner, ploppt).
	-- Takte: 0-1,0 Aufladen: Welt warm-golden, Marke unter dem Seraph, er duckt
	--   sich, die sechs Fluegel schnappen Paar fuer Paar auf (0,22/0,44/0,66,
	--   Funken, Lichtfedern), 0,8 Heiligenschein zuendet | 1,0-1,7 Absprung mit
	--   zwei Drehungen und Nachbildern auf 12 Studs, 1,1 das Himmelstor oeffnet
	--   sich 24 Studs ueber der Arena (klein, dann gross), 1,45 Lichtschaefte,
	--   Federn rieseln | 1,9-2,35 der Speer aus Licht sinkt vom Tor in die Pfoten,
	--   2,3 Zielmarke unter dem Gegner, er schaut hoch und zittert, Lichtfaden vom
	--   Tor, Ticks 2,35/2,55/2,70 (Marke schrumpft, Tor pulst) | 2,95 Ausholen,
	--   Stille | 3,02 Sturz spearvoraus mit Nachbildern | 3,27 Landung, 3,28 Treffer
	--   (impactAt) | 3,28-3,46 Schlag (Tabelle unten) | 3,40-3,8 Saeule bis zum
	--   Tor, Druckwelle bis zum Zaun, Federtruemmer, Brandfleck mit Siegel |
	--   3,8-4,35 die Torringe fallen die Saeule herab und werden zu Kondensringen,
	--   Welt dunkler und golden, 3,88 die Kuppel waechst | 4,0 Federregen |
	--   4,35 der Seraph zieht den Speer, er zerfaellt zu Federn | 4,75-5,4
	--   Rueckwaerts-Salto heim | 5,05 die Krone des Tors landet schief auf dem
	--   Gegner (Pointe), 5,65 ploppt sie | 5,9 Ende.
	-- Schlag-Tabelle (T = 3,28; Welt = alle, Schirm = Besitzer):
	--   T-0,33  Stille (silence 0,1), Marke eng, Tor pulst       | Kamera haelt   | -
	--   T-0,26  Sturz (k^2), Nachbilder                          | Peitsche       | lunge
	--   T-0,02  Blitz (flash gold 0,08)                          | Schnitt tief   | -
	--   T       4 Impact-Frames hell/indigo (0,20), hitstop 0,18 | steht, FOV -12 | hit
	--           kleiner Kern (<= 3,2 Koerperradius), Speer steckt|                |
	--   T+0,10  Knall NACH dem Blitz                             |                | boom, bass
	--   T+0,12  Saeule schiesst hoch, Brandfleck, Risse          | quake 1,0      | -
	--   T+0,15  Lichtwand bis zum Zaun, Federn, Staub, Bodenring |                | rumble
	--   T+0,27  Kamerafahrt endet (Custom)                       | Schnitt        |
	--   T+0,42  Wand erreicht die Kamera: Blitz, zweites Beben   | quake 0,5      | -
	--   T+0,5.. Ringe fallen, Kuppel, Federregen, Welt -0,18     | eigene Kamera  | thunder, ping x3
	-- Echo (0,65 s, Treffer 0,26): Lichtspeer faellt von oben in die Zielmarke,
	--   1 Impact-Frame, Hitstop 0,06, Beben 0,4, Bodenring, Federn; Opener-Bonus:
	--   Lichtsaeule (global) + Zaunring.
	-- ------------------------------------------------------------------
	SeraphJudgment = {
		tier = 4, duration = 5.9, impactAt = 3.28,
		color = C(255, 214, 110), color2 = C(255, 246, 225),
		pitch = 1.1,
		sounds = {
			charge = "whoosh", snap = "snap", halo = "ping", launch = "rocket", gate = "thunder",
			forge = "glass", tick = "ping", dive = "lunge", impact = "hit", boom = "boom", bass = "bass",
			rumble = "rumble", feathers = "whoosh", ring = "ping", pull = "snap", pop = "snap",
		},
		steps = {
			-- 1. Aufladen (0 .. 1,0)
			{ t = 0.00, fx = "sky",         tint = C(255, 236, 200), brightness = 0.05, saturation = 0.12, dur = 5.6, fade = 0.5 },
			{ t = 0.00, fx = "sound",       slot = "charge" },
			{ t = 0.00, fx = "moves", hold = 0.1, outline = C(214, 150, 30), keys = {
				{ t = 0.30, pitch = 0.03, scale = 0.93, dy = -0.05, ease = "out" },
				{ t = 0.70, pitch = 0.04, scale = 0.90 },
				{ t = 0.92, scale = 0.88, dy = -0.1, ease = "in" },
				{ t = 1.00, dy = 1.2, scale = 1.0, pitch = -0.02, ease = "out", trail = true, burst = 24, smoke = 16 },
				{ t = 1.45, dy = 12.8, yaw = 2, scale = 1.18, ease = "out", trail = true },
				{ t = 1.70, dy = 12.0, scale = 1.2, pitch = 0, ease = "inout" },
				{ t = 2.05, dy = 12.3, pitch = -0.03, ease = "inout" },
				{ t = 2.40, dy = 12.0, pitch = 0.07, ease = "inout" },
				{ t = 2.75, dy = 12.15, pitch = 0.09, ease = "inout" },
				{ t = 2.95, dy = 12.7, pitch = -0.05, scale = 1.22, ease = "out" },
				{ t = 3.02, dy = 12.7, pitch = -0.05 },
				{ t = 3.27, at = "land", dy = 0, pitch = -0.14, scale = 1.1, ease = "in", trail = true, burst = 40, smoke = 22 },
				{ t = 3.50, at = "land", pitch = 0.05, scale = 1.02, ease = "out" },
				{ t = 3.95, at = "land", pitch = 0.02, scale = 1.0, ease = "inout" },
				{ t = 4.30, at = "land", dy = 0.45, pitch = -0.04, ease = "out" },
				{ t = 4.45, at = "land", dy = 0, pitch = 0.02, ease = "in", burst = 10 },
				{ t = 4.75, at = "land", pitch = 0 },
				{ t = 5.15, at = "home", arc = 4.5, pitch = 1.0, ease = "inout", trail = true },
				{ t = 5.28, at = "home", pitch = 1.0, scale = 0.95, ease = "out", burst = 8, smoke = 8 },
				{ t = 5.40, at = "home", scale = 1.0 },
			} },
			{ t = 0.02, fx = "seraphwings", snapAt = { 0.2, 0.42, 0.64 }, haloAt = 0.78, launchAt = 0.98, diveAt = 3.0, landAt = 3.25, foldAt = 4.2, dur = 5.4 },
			{ t = 0.10, fx = "ring",        at = "self", ground = true, radius = 3.2, dur = 1.0, tex = "halo" },
			{ t = 0.22, fx = "sound",       slot = "snap" },
			{ t = 0.44, fx = "sound",       slot = "snap" },
			{ t = 0.66, fx = "sound",       slot = "snap" },
			{ t = 0.66, fx = "quake",       power = 0.22 },
			{ t = 0.80, fx = "sound",       slot = "halo" },
			{ t = 0.95, fx = "sound",       slot = "launch" },
			{ t = 1.00, fx = "dust",        at = "self", count = 22, speed = 10, dur = 0.8, tex = "stardust" },
			-- 2. Aufstieg und Himmelstor (1,0 .. 1,9)
			{ t = 1.05, fx = "cinematic",   style = "seraph", dur = 2.5 },
			{ t = 1.10, fx = "halogate",    at = "arena", lift = 24, radius = 16, open = 0.55, raysAt = 0.35, ticks = { 1.25, 1.45, 1.60 }, offAt = 2.18, fallAt = 2.70, fallFor = 0.55, popAt = 4.55, dur = 4.6, global = true },
			{ t = 1.15, fx = "sound",       slot = "gate" },
			{ t = 1.30, fx = "snowfall",    at = "arena", noShell = true, lift = 20, size = 0.5, count = 16, dur = 2.4, tex = "feather", extra = true },
			-- 3. Speer und Zielmarke (1,9 .. 2,95)
			{ t = 1.90, fx = "seraphspear", formAt = 0, form = 0.35, grabAt = 0.45, plantAt = 1.38, pullAt = 2.45, length = 8, dur = 2.7 },
			{ t = 1.95, fx = "sound",       slot = "forge" },
			{ t = 2.30, fx = "seraphmark",  at = "target", radius = 5.5, shrinkTo = 1.6, ticks = { 0.05, 0.25, 0.40 }, releaseAt = 0.96, dur = 1.0 },
			{ t = 2.35, fx = "sound",       slot = "tick" },
			{ t = 2.36, fx = "quake",       power = 0.15 },
			{ t = 2.55, fx = "sound",       slot = "tick" },
			{ t = 2.56, fx = "quake",       power = 0.2 },
			{ t = 2.70, fx = "sound",       slot = "tick" },
			{ t = 2.71, fx = "quake",       power = 0.25 },
			-- 4. Stille und Sturz (2,95 .. 3,28)
			{ t = 2.95, fx = "silence",     dur = 0.33, level = 0.1 },
			{ t = 3.02, fx = "sound",       slot = "dive" },
			-- 5. Einschlag T = 3,28 (Landung 3,27, Speer steckt 3,28 = 1,90 + 1,38)
			{ t = 3.26, fx = "flash",       tint = C(255, 240, 200), dur = 0.08 },
			{ t = 3.28, fx = "impactframe", pattern = "ldld", hold = 0.05, dark = C(70, 50, 160), fill = C(40, 24, 110), light = C(255, 250, 235) },
			{ t = 3.28, fx = "hitstop",     dur = 0.18 },
			{ t = 3.28, fx = "sound",       slot = "impact" },
			{ t = 3.28, fx = "lightnuke",   at = "target", core = 0.2, columnAt = 0.12, height = 160, waveAt = 0.15, domeAt = 0.6, dome = 11, domeFor = 0.7, scorch = 3.6, dur = 2.5, global = true },
			{ t = 3.38, fx = "sound",       slot = "boom" },
			{ t = 3.40, fx = "sound",       slot = "bass" },
			{ t = 3.42, fx = "quake",       power = 1.0 },
			{ t = 3.43, fx = "ring",        at = "target", ground = true, toArena = true, radius = "fence", dur = 0.55 },
			{ t = 3.45, fx = "shards",      at = "target", arc = true, count = 14, size = 0.7, dur = 1.2, tex = "feather" },
			{ t = 3.45, fx = "dust",        at = "target", count = 40, speed = 16, dur = 1.0, tex = "stardust" },
			{ t = 3.55, fx = "sound",       slot = "rumble" },
			{ t = 3.70, fx = "quake",       power = 0.5 },
			{ t = 3.70, fx = "flash",       tint = C(255, 228, 170), dur = 0.12 },
			-- 6. Nachklang: Ringe fallen, Kuppel, Federregen, Pointe
			{ t = 3.80, fx = "sound",       slot = "gate" },
			{ t = 3.85, fx = "sky",         tint = C(255, 214, 150), brightness = -0.18, saturation = 0.1, dur = 1.6, fade = 0.25 },
			{ t = 4.00, fx = "snowfall",    at = "arena", noShell = true, lift = 16, size = 0.55, count = 30, dur = 1.5, tex = "feather" },
			{ t = 4.00, fx = "sound",       slot = "feathers" },
			{ t = 4.30, fx = "sound",       slot = "ring" },
			{ t = 4.35, fx = "sound",       slot = "pull" },
			{ t = 4.55, fx = "sound",       slot = "ring" },
			{ t = 4.80, fx = "sound",       slot = "ring" },
			{ t = 5.05, fx = "sound",       slot = "halo" },
			{ t = 5.65, fx = "sound",       slot = "pop" },
			{ t = 5.65, fx = "sparks",      at = "target", count = 10, dur = 0.25, stars = true },
		},
		echo = {
			{ t = 0.00, fx = "sound",       slot = "forge" },
			{ t = 0.00, fx = "pillar",      at = "target", fromSky = true, feet = true, height = 22, width = 2.4, dur = 0.5, tex = "column" },
			{ t = 0.00, fx = "ring",        at = "target", ground = true, radius = 2.2, dur = 0.3, tex = "halo" },
			{ t = 0.24, fx = "flash",       tint = C(255, 240, 200), dur = 0.06 },
			{ t = 0.26, fx = "impactframe", pattern = "l", hold = 0.05, dark = C(70, 50, 160), fill = C(40, 24, 110), light = C(255, 250, 235) },
			{ t = 0.26, fx = "hitstop",     dur = 0.06 },
			{ t = 0.26, fx = "sound",       slot = "impact" },
			{ t = 0.27, fx = "quake",       power = 0.4 },
			{ t = 0.27, fx = "pillar",      at = "target", feet = true, height = 60, width = 5, dur = 0.38, tex = "column", bonus = true, global = true },
			{ t = 0.28, fx = "ring",        at = "target", ground = true, toArena = true, radius = 9, dur = 0.3 },
			{ t = 0.28, fx = "ring",        at = "target", ground = true, toArena = true, radius = "fence", dur = 0.36, second = true, bonus = true },
			{ t = 0.28, fx = "shards",      at = "target", count = 8, size = 0.5, dur = 0.32, tex = "feather" },
			{ t = 0.30, fx = "sparks",      at = "target", count = 12, dur = 0.3, stars = true },
			{ t = 0.33, fx = "sound",       slot = "boom" },
		},
	},
}

-- Unbekannte Faehigkeit: neutrale Kurz-Show statt gar nichts.
local FALLBACK: SkillFX = FX.BasicPunch

local function get(skillId: string?): SkillFX
	return (skillId and FX[skillId]) or FALLBACK
end

-- Wie lange der Server die Stage fuer die Show anhaelt.
local function getDuration(skillId: string?, full: boolean): number
	local fx = get(skillId)
	if not full then
		return TIERS[fx.tier].echo
	end
	return math.min(fx.duration, TIERS[fx.tier].maxDuration)
end

-- v15.1: WANN die Show den Gegner trifft (Sekunden ab Start). In genau
-- diesem Moment setzt PitArenaService die HP- und Ladeleisten und laesst den
-- Gegner zurueckfliegen — der Schaden soll sichtbar MIT dem Treffer kommen,
-- nicht erst nach der Show.
--
-- Regel: die Shows sind auf ihre Klaenge geschnitten — der "impact"-Ton
-- sitzt auf dem Einschlag (Omega: Strahl + Saeule), wo es keinen gibt, der
-- "strike"-Ton (Schwarzes Loch: die Welle). Hat eine Show keinen von beiden,
-- zaehlt der erste Effekt am Gegner. Eine Show kann das mit `impactAt` selbst
-- setzen.
local HIT_BLOCKS: { [string]: boolean } = {
	beam = true, pillar = true, ring = true, sparks = true, shards = true,
	frost = true, wave = true, spiral = true, rise = true,
}

local function firstSound(fx: SkillFX, slot: string): number?
	for _, step in fx.steps do
		if step.fx == "sound" and step.slot == slot then
			return step.t or 0
		end
	end
	return nil
end

local function getImpactTime(skillId: string?, full: boolean): number
	local fx = get(skillId)
	if not full then
		return TIERS[fx.tier].echo * 0.4
	end
	local limit = getDuration(skillId, true)
	local explicit = (fx :: any).impactAt
	if typeof(explicit) == "number" then
		return math.clamp(explicit, 0, limit)
	end
	local best = firstSound(fx, "impact") or firstSound(fx, "strike")
	if not best then
		for _, step in fx.steps do
			local t = step.t or 0
			if HIT_BLOCKS[step.fx] and (step.at == "target" or step.fx == "beam") then
				if not best or t < best then best = t end
			end
		end
	end
	return math.clamp(best or limit * 0.5, 0, limit)
end

return {
	CINEMATIC_CAMERA = CINEMATIC_CAMERA,
	TIERS            = TIERS,
	PARTICLE_BUDGET  = PARTICLE_BUDGET,
	TEXTURES         = TEXTURES,
	SOUND_LIBRARY    = SOUND_LIBRARY,
	SOUND            = SOUND,
	data             = FX,
	get              = get,
	getDuration      = getDuration,
	getImpactTime    = getImpactTime,
}
