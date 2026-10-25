        elseif style == "pulsar" then
            -- 25.10. (Pulsar-Nova): tief auf der Seite der Spielkamera (`pulsar`
            -- legt sie beim Start fest), Blick hoch auf den kreisenden
            -- Leuchtturm - die Lichtkegel fegen ueber die Kamera; folgt dem
            -- Neutronenstern im Flug; nach dem Einschlag (`firedome`) zurueck
            -- und hoch auf die ganze Feuerkuppel.
            local n = ctx.pulsarCam or Vector3.new(0, 0, 1)
            local sideV = Vector3.yAxis:Cross(n)
            sideV = if sideV.Magnitude < 0.1 then Vector3.xAxis else sideV.Unit
            local hv = ctx.pulsarHover or (ctx.selfFeet + Vector3.new(0, 7, 0))
            eye = hv + n * (12.5 - 2 * k) + sideV * (2.5 + 3 * k) + Vector3.new(0, -3.6 + 1.2 * k, 0)
            local look = hv + Vector3.new(0, 0.8, 0)
            local av = ctx.avatarCf
            if av then
                local w = math.clamp((k - 0.5) / 0.14, 0, 1)
                w = 1 - (1 - w) ^ 3
                look = look:Lerp(av.Position, w)
                eye = eye:Lerp((hv + ctx.targetPos) / 2 + n * 15 + Vector3.new(0, 2.5, 0), w * 0.85)
            end
            local d0 = ctx.novaT0
            if d0 then
                local q = math.clamp((os.clock() - d0) / 0.42, 0, 1)
                q = 1 - (1 - q) ^ 3
                local dc = ctx.novaCenter or ctx.targetPos
                local dr = ctx.novaRadius or 8
                eye = eye:Lerp(dc + n * (dr * 3.1) + sideV * 3 + Vector3.new(0, dr * 0.9, 0), q)
                look = look:Lerp(dc + Vector3.new(0, dr * 0.25, 0), q)
            end
            cam.CFrame = CFrame.lookAt(eye, look)

