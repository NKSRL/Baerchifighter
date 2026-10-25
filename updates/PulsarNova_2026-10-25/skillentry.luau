    -- 25.10.2026 Pulsar-Nova (Pulsar-Baerchi, ersetzt PulsarPulse als
    -- defaultSkill; PulsarPulse bleibt fuer alte Baerchis und Fusionen): neue
    -- Fassung des Blender-Prototyps "Pulsstoss" vom 22.10. DoT wie Nebelbrand und
    -- Hoellensiegel - die Feuerkuppel brennt nach. Cosmic liegt ueber Divine:
    -- sofort 1.8x + 60, Brand 3 Aktionen je 20 + 0.35x ATK (gesamt ~2.85x + 120,
    -- Hoellensiegel ~2.7x + 105, Nebelbrand ~2.8x + 80), Ladung 5.
    PulsarNova = {
        id = "PulsarNova", displayName = "Pulsar-Nova",
        effectType = "DoT", category = "damage", cooldown = 5, charge = 5,
        params = { multiplier = 1.8, baseDamage = 60, dotDamage = 20, dotMultiplier = 0.35, dotDuration = 3 },
        description = "Wird zum Neutronenstern und schlaegt als Komet ein: 1.8x ATK + 60, danach brennt der Gegner 3 Aktionen.",
        drawback = "Der Grossteil des Schadens kommt erst als Brand, ein neuer Brand ersetzt den alten.",
    },
