		elseif style == "seraph" then
			-- 26.10. (Himmelsgericht): tief vorn-seitlich beim Seraph (auf der Seite
			-- der Spielkamera, aus `oldCf`), folgt dem `moves`-Klon in die Hoehe -
			-- der Blick kippt hoch, das Himmelstor rueckt ins Bild; waehrend des
			-- Zielens langsamer Push-in; im Sturz schwenkt der Blick mit dem Klon
			-- zum Gegner (Peitsche); am Einschlag harter Schnitt in eine tiefe
			-- Untersicht neben dem Speer (Hitstop, Beben), dann zurueck (Custom).
			local sideV = ctx.fwd:Cross(Vector3.yAxis)
			sideV = if sideV.Magnitude < 0.1 then Vector3.xAxis else sideV.Unit
			if seraphSide == 0 then
				seraphSide = if (oldCf.Position - center):Dot(sideV) >= 0 then 1 else -1
			end
			local sv = sideV * seraphSide
			local f = ctx.avatarCf or CFrame.lookAt(ctx.selfFeet, ctx.selfFeet + ctx.fwd)
			local sc = ctx.avatarScale or 1
			local body = f.Position + Vector3.new(0, ctx.selfSize.Y * sc * 0.5, 0)
			local hitP = ctx.seraphHit or ctx.targetFeet
			local look: Vector3
			if k < 0.89 then
				-- Aufstieg (k 0..0,34): Auge steigt mit, Blick kippt hoch; Zielen (0,34..0,79): Push-in
				local q1 = math.clamp(k / 0.34, 0, 1)
				local q2 = math.clamp((k - 0.34) / 0.45, 0, 1)
				local dist = 9 - 2 * q1 - 1.5 * q2
				local high = 1.2 + 2.6 * q1 + 1.4 * q2
				eye = ctx.selfFeet + ctx.fwd * (6 - 1.5 * q1) + sv * dist + Vector3.new(0, high, 0)
				look = body + Vector3.new(0, 0.6, 0)
				-- Sturz (0,79..0,89): der Blick peitscht mit dem Klon zum Gegner
				local q3 = math.clamp((k - 0.79) / 0.1, 0, 1)
				if q3 > 0 then
					look = look:Lerp(hitP + Vector3.new(0, 1.5, 0), q3 * q3)
				end
			else
				-- Einschlag (ab 0,89): harter Schnitt, tiefe Untersicht neben dem Speer
				eye = hitP + sv * 6.5 - ctx.fwd * 4 + Vector3.new(0, 0.9, 0)
				look = hitP + Vector3.new(0, 3.2 + 6 * (k - 0.89), 0)
			end
			cam.CFrame = CFrame.lookAt(eye, look)
