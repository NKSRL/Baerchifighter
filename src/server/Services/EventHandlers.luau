--!nonstrict
-- EventHandlers.luau
-- ServerScriptService/Services/EventHandlers.luau
--
-- Die Spiel-Logik der fuenf Events (Stand 2026-10-02):
--   Ufo, HotEgg, MutationsSturm, Koenigshuegel, Schatzgraeber
--
-- Jeder Handler hat die Signatur   handler(api, def) -> session
-- und die Session hat   session.stop() -> results
-- wobei results = { [Player] = { egg = EventBonus?, mutationRoll = boolean? } }
-- die Belohnungen sind, die EventParticipationService am Event-ENDE auszahlt.
-- (Das UFO zahlt seine Belohnung schon beim Absetzen aus, dort ist results leer.)
--
-- `api` stellt EventParticipationService bereit (siehe dort, buildApi): die
-- Handler fassen weder Spielerdaten noch ActivityLock direkt an, sie laufen
-- nur mit Figuren ueber api.walkTo und lesen api.participants().
--
-- ALLE Zahlen stehen in EventConfig.

local RunService          = game:GetService("RunService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local EventConfig     = require(ReplicatedStorage.Config.EventConfig)
local FigureFX        = require(ServerScriptService.Util.FigureFX)
local FigurePlacement = require(ServerScriptService.Util.FigurePlacement)

local EventHandlers = {}

--------------------------------------------------------------------------------
-- Hilfen
--------------------------------------------------------------------------------

local function flatDist(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function make(className, props, parent)
	local inst = Instance.new(className)
	for key, value in props do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

local function fxPart(props, parent)
	props.Anchored   = true
	props.CanCollide = false
	props.CanQuery   = false
	props.CanTouch   = false
	props.CastShadow = false
	return make("Part", props, parent)
end

local function rootOf(figure)
	return figure.PrimaryPart or figure:FindFirstChildWhichIsA("BasePart", true)
end

-- Kleine Textmarke ueber der Figur (Fortschritt, "Ei!", ...). nil entfernt sie.
local function setLabel(part, text)
	local figure = part.figure
	if not figure or not figure.Parent then
		return
	end

	local gui = figure:FindFirstChild("EventLabel")
	if not text then
		if gui then
			gui:Destroy()
		end
		return
	end

	if not gui then
		local root = rootOf(figure)
		if not root then
			return
		end
		gui = make("BillboardGui", {
			Name         = "EventLabel",
			Size         = UDim2.fromOffset(120, 26),
			StudsOffset  = Vector3.new(0, 6, 0),
			AlwaysOnTop  = true,
			Adornee      = root,
			MaxDistance  = 220,
		}, figure)
		make("TextLabel", {
			Name                   = "Text",
			Size                   = UDim2.fromScale(1, 1),
			BackgroundTransparency = 0.35,
			BackgroundColor3       = Color3.fromRGB(20, 20, 30),
			TextColor3             = Color3.new(1, 1, 1),
			TextScaled             = true,
			Font                   = Enum.Font.GothamBold,
		}, gui)
	end

	gui.Text.Text = text
end

local function newFolder(name)
	local folder = Instance.new("Folder")
	folder.Name   = name
	folder.Parent = workspace
	return folder
end

-- Kurzer Kampf zweier Teilnehmer: serverseitiger Vergleich (ATK/HP-basiert,
-- siehe api.power) mit etwas Zufall. Dauert fix `seconds`. Gibt Gewinner und
-- Verlierer zurueck.
local function duel(api, a, b, seconds)
	local ra = api.power(a) * (0.8 + math.random() * 0.4)
	local rb = api.power(b) * (0.8 + math.random() * 0.4)

	local winner, loser = a, b
	if rb > ra then
		winner, loser = b, a
	end

	local startedAt = os.clock()
	task.spawn(function()
		while os.clock() - startedAt < seconds - 0.4 and api.running() do
			if a.figure and b.figure and a.figure.Parent and b.figure.Parent then
				pcall(FigureFX.attackLunge, a.figure, b.figure:GetPivot().Position, 2, 0.3)
				task.wait(0.35)
				pcall(FigureFX.attackLunge, b.figure, a.figure:GetPivot().Position, 2, 0.3)
				task.wait(0.35)
			else
				break
			end
		end
	end)

	task.wait(seconds)

	if loser.figure and loser.figure.Parent then
		pcall(FigureFX.hitFlash, loser.figure, Color3.fromRGB(255, 80, 80), 0.6)
	end

	return winner, loser
end

local function moveFoot(figure, from, to, seconds, spin)
	local startedAt = os.clock()
	while true do
		local t = math.clamp((os.clock() - startedAt) / seconds, 0, 1)
		FigurePlacement.place(
			figure,
			from:Lerp(to, t),
			CFrame.Angles(0, (spin or 0) * t, 0)
		)
		if t >= 1 then
			break
		end
		RunService.Heartbeat:Wait()
	end
end

--------------------------------------------------------------------------------
-- UFO
--------------------------------------------------------------------------------

function EventHandlers.Ufo(api, def)
	local cfg    = EventConfig.UFO
	local center = api.center
	local ringR  = api.radius * cfg.BEAM_RADIUS_FACTOR
	local hoverY = center.Y + 40

	local running    = true
	local beamOpen   = true
	local idleTimer  = 0
	local fightPause = 0
	local states     = {}      -- [Presence] = Zustand
	local taken      = {}      -- [Player] = true: in DIESEM Event schon entfuehrt
	local pairCool   = {}      -- ["uidA|uidB"] = os.clock() bis zu dem nicht erneut gekaempft wird

	local folder = newFolder("EventUfo")

	-- UFO-Optik: Scheibe, Kuppel, Beam, Ring am Boden
	local discPos = Vector3.new(center.X, hoverY, center.Z)
	fxPart({
		Name = "Disc", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Metal,
		Color = Color3.fromRGB(170, 180, 195), Size = Vector3.new(3, 26, 26),
		CFrame = CFrame.new(discPos) * CFrame.Angles(0, 0, math.rad(90)),
	}, folder)
	fxPart({
		Name = "Dome", Shape = Enum.PartType.Ball, Material = Enum.Material.Glass,
		Color = Color3.fromRGB(120, 255, 190), Transparency = 0.3, Size = Vector3.new(12, 10, 12),
		CFrame = CFrame.new(discPos + Vector3.new(0, 3, 0)),
	}, folder)
	local beamHeight = hoverY - center.Y
	local beam = fxPart({
		Name = "Beam", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon,
		Color = Color3.fromRGB(120, 255, 190), Transparency = 0.65,
		Size = Vector3.new(beamHeight, ringR * 2, ringR * 2),
		CFrame = CFrame.new(Vector3.new(center.X, center.Y + beamHeight / 2, center.Z)) * CFrame.Angles(0, 0, math.rad(90)),
	}, folder)
	local ring = fxPart({
		Name = "Ring", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon,
		Color = Color3.fromRGB(120, 255, 190), Transparency = 0.3,
		Size = Vector3.new(0.3, ringR * 2, ringR * 2),
		CFrame = CFrame.new(Vector3.new(center.X, center.Y + 0.25, center.Z)) * CFrame.Angles(0, 0, math.rad(90)),
	}, folder)

	local function setBeam(open)
		beamOpen = open
		beam.Transparency = if open then 0.65 else 1
		ring.Transparency = if open then 0.3 else 0.85
		ring.Color        = if open then Color3.fromRGB(120, 255, 190) else Color3.fromRGB(255, 90, 90)
	end

	local function stateOf(part)
		local st = states[part]
		if not st then
			st = { progress = 0, moving = false, fightUntil = 0, coolUntil = 0, abducting = false, inBeam = false }
			states[part] = st
		end
		return st
	end

	local function abduct(part, st)
		st.abducting     = true
		part.abducting   = true
		taken[part.player] = true
		setLabel(part, "ENTFUEHRT!")

		task.spawn(function()
			local ok, err = pcall(function()
				local figure = part.figure
				local player = part.player
				api.toast(player, "UFO: Dein Baerchi wird entfuehrt!")

				local startFoot = api.footOf(figure)
				local ufoFoot   = Vector3.new(center.X, hoverY - 6, center.Z)
				pcall(FigureFX.burstAt, startFoot, Color3.fromRGB(120, 255, 190), folder, 24)

				-- 1) hochgezogen
				FigureFX.stopIdle(figure)
				moveFoot(figure, startFoot, ufoFoot, 2.0, math.pi * 4)

				-- 2) Transport zum Plot des Spielers
				local plotPos = api.plotPosition(player)
				local overPlot = (plotPos or ufoFoot) + Vector3.new(0, 40, 0)
				setLabel(part, "Transport...")
				moveFoot(figure, ufoFoot, overPlot, 3.0, math.pi * 2)

				-- 3) Wartezeit ueber dem Plot
				local waitStart = os.clock()
				while os.clock() - waitStart < cfg.ABDUCT_WAIT_SECONDS do
					local left = math.ceil(cfg.ABDUCT_WAIT_SECONDS - (os.clock() - waitStart))
					setLabel(part, string.format("Landung in %ds", left))
					FigurePlacement.place(
						figure,
						overPlot + Vector3.new(0, math.sin((os.clock() - waitStart) * 2) * 1.2, 0),
						CFrame.Angles(0, (os.clock() - waitStart) * 1.5, 0)
					)
					task.wait(0.1)
				end

				-- 4) Absetzen auf dem Plot
				setLabel(part, nil)
				local homeFoot = part.homeFoot
				moveFoot(figure, overPlot, homeFoot + Vector3.new(0, 4, 0), 1.5, 0)
				api.finishHome(part)
				api.ufoReward(part)
			end)

			if not ok then
				warn("[EventHandlers.Ufo] Entfuehrung fehlgeschlagen:", err)
				pcall(setLabel, part, nil)
				pcall(api.finishHome, part)
			end
		end)
	end

	local function startFight(a, b, sa, sb, now)
		sa.fightUntil = now + cfg.FIGHT_SECONDS
		sb.fightUntil = now + cfg.FIGHT_SECONDS
		fightPause    = now + cfg.FIGHT_SECONDS
		a.cancelWalk, b.cancelWalk = true, true
		setLabel(a, "KAMPF!")
		setLabel(b, "KAMPF!")

		task.spawn(function()
			local ok, err = pcall(function()
				local winner, loser = duel(api, a, b, cfg.FIGHT_SECONDS)
				local sw, sl = stateOf(winner), stateOf(loser)

				-- Verlierer: aus dem Ring gedraengt, beginnt von vorne.
				sl.progress  = 0
				sl.coolUntil = os.clock() + 4
				api.toast(loser.player, "Kampf verloren - Beam-Fortschritt zurueckgesetzt")
				api.toast(winner.player, "Kampf gewonnen!")
				setLabel(winner, nil)
				setLabel(loser, nil)

				sl.moving = true
				task.spawn(function()
					api.walkTo(loser, loser.standFoot)
					sl.moving = false
				end)
				sw.fightUntil = 0
			end)
			if not ok then
				warn("[EventHandlers.Ufo] Kampf fehlgeschlagen:", err)
			end
		end)
	end

	local function closeBeam()
		for part, st in states do
			st.progress = 0
			setLabel(part, nil)
		end
		for _, part in api.participants() do
			api.toast(part.player, "UFO: Der Beam wurde zurueckgesetzt - alle Countdowns beginnen von vorne")
		end
		setBeam(false)
		task.delay(4, function()
			if running then
				idleTimer = 0
				setBeam(true)
			end
		end)
	end

	for _, part in api.participants() do
		api.toast(part.player, string.format(
			"UFO: Geh in den Strahl! %ds Beam-Fortschritt bis zur Entfuehrung", cfg.BEAM_REQUIRED_SECONDS
		))
	end

	local dt = 0.25
	task.spawn(function()
		while running do
			task.wait(dt)
			local ok, err = pcall(function()
				local parts = api.participants()
				local now   = os.clock()
				local anyInBeam = false
				local inBeamList = {}

				for _, part in parts do
					local st = stateOf(part)
					if st.abducting or taken[part.player] then
						continue
					end
					local foot = api.footOf(part.figure)
					st.inBeam = beamOpen and flatDist(foot, center) <= ringR
					if st.inBeam and now >= st.fightUntil then
						anyInBeam = true
						table.insert(inBeamList, part)
					end
				end

				-- Wer nicht im Beam steht, laeuft zum Beam: bevorzugt zu einem
				-- Baerchi, das schon drin steht (Regel 2), sonst zur eigenen Seite.
				for _, part in parts do
					local st = stateOf(part)
					if st.abducting or taken[part.player] then continue end
					if beamOpen and not st.inBeam and not st.moving and not part.busy
						and now >= st.fightUntil and now >= st.coolUntil then

						st.moving = true
						local target
						local anchor = inBeamList[1]
						if anchor and anchor ~= part then
							local af   = api.footOf(anchor.figure)
							local from = api.footOf(part.figure)
							local dir  = Vector3.new(from.X - af.X, 0, from.Z - af.Z)
							if dir.Magnitude < 0.1 then dir = Vector3.new(1, 0, 0) end
							target = af + dir.Unit * (cfg.TOUCH_DISTANCE * 0.7)
						else
							local dir = Vector3.new(part.standFoot.X - center.X, 0, part.standFoot.Z - center.Z)
							if dir.Magnitude < 0.1 then dir = Vector3.new(1, 0, 0) end
							target = center + dir.Unit * (ringR * 0.5)
						end

						task.spawn(function()
							api.walkTo(part, target)
							st.moving = false
							if running and api.stillHere(part) and not st.abducting then
								pcall(FigureFX.idleBob, part.figure, { height = 0.8, rate = 1.1 })
							end
						end)
					end
				end

				-- Beruehrung -> Kampf (mindestens einer im Beam)
				for i = 1, #parts do
					for j = i + 1, #parts do
						local a, b = parts[i], parts[j]
						local sa, sb = stateOf(a), stateOf(b)
						if sa.abducting or sb.abducting or taken[a.player] or taken[b.player] then continue end
						if now < sa.fightUntil or now < sb.fightUntil then continue end
						if not (sa.inBeam or sb.inBeam) then continue end
						local key = a.baerchiUid .. "|" .. b.baerchiUid
						if pairCool[key] and now < pairCool[key] then continue end
						if flatDist(api.footOf(a.figure), api.footOf(b.figure)) <= cfg.TOUCH_DISTANCE then
							pairCool[key] = now + cfg.FIGHT_SECONDS + 6
							startFight(a, b, sa, sb, now)
						end
					end
				end

				-- Beam-Fortschritt (pausiert waehrend eines Kampfes)
				if beamOpen and now >= fightPause then
					for _, part in inBeamList do
						local st = stateOf(part)
						st.progress += dt
						setLabel(part, string.format("%d / %ds", math.floor(st.progress), cfg.BEAM_REQUIRED_SECONDS))
						if st.progress >= cfg.BEAM_REQUIRED_SECONDS then
							abduct(part, st)
						end
					end
				end

				-- Beam-Timeout
				if beamOpen then
					if anyInBeam or now < fightPause then
						idleTimer = 0
					else
						idleTimer += dt
						if idleTimer >= cfg.BEAM_IDLE_TIMEOUT_SECONDS then
							closeBeam()
						end
					end
				end
			end)
			if not ok then
				warn("[EventHandlers.Ufo] Tick fehlgeschlagen:", err)
			end
		end
	end)

	return {
		stop = function()
			running = false
			for part in states do
				if not part.abducting then
					part.cancelWalk = true
				end
				pcall(setLabel, part, nil)
			end
			if folder then
				folder:Destroy()
			end
			return {}
		end,
	}
end

--------------------------------------------------------------------------------
-- Hot Egg
--------------------------------------------------------------------------------

function EventHandlers.HotEgg(api, def)
	local cfg = EventConfig.HOT_EGG

	local running       = true
	local holder        = nil
	local lastHolder    = nil
	local cooldownUntil = 0
	local chasing       = false
	local fire          = nil

	local function setHolder(part)
		if fire then
			fire:Destroy()
			fire = nil
		end
		if holder then
			setLabel(holder, nil)
		end
		holder = part
		if part and part.figure then
			local root = rootOf(part.figure)
			if root then
				fire = make("Fire", { Size = 8, Heat = 6, Color = Color3.fromRGB(255, 120, 40), SecondaryColor = Color3.fromRGB(255, 60, 20) }, root)
			end
			setLabel(part, "HEISSES EI!")
			api.toast(part.player, "Du hast das heisse Ei! Gib es per Beruehrung weiter.")
		end
	end

	task.spawn(function()
		while running do
			task.wait(cfg.CHECK_INTERVAL_SECONDS)
			local ok, err = pcall(function()
				local parts = api.participants()

				if holder and not api.stillHere(holder) then
					setHolder(nil)
				end
				if not holder and #parts > 0 then
					setHolder(parts[math.random(1, #parts)])
				end

				if not holder or chasing or holder.busy or #parts < 2 then
					return
				end
				if os.clock() < cooldownUntil then
					return
				end

				local hf = api.footOf(holder.figure)
				local best, bestDist = nil, math.huge
				for _, other in parts do
					if other ~= holder and other ~= lastHolder then
						local d = flatDist(hf, api.footOf(other.figure))
						if d < bestDist then
							best, bestDist = other, d
						end
					end
				end
				if not best then
					best = if parts[1] ~= holder then parts[1] else parts[2]
				end

				chasing = true
				local chaser = holder
				task.spawn(function()
					local ef = api.footOf(best.figure)
					local dir = Vector3.new(hf.X - ef.X, 0, hf.Z - ef.Z)
					if dir.Magnitude < 0.1 then dir = Vector3.new(1, 0, 0) end
					api.walkTo(chaser, ef + dir.Unit * (cfg.TOUCH_DISTANCE * 0.7))

					if running and holder == chaser and api.stillHere(best) and api.stillHere(chaser)
						and flatDist(api.footOf(chaser.figure), api.footOf(best.figure)) <= cfg.TOUCH_DISTANCE + 1.5 then
						lastHolder    = chaser
						cooldownUntil = os.clock() + cfg.PASS_COOLDOWN_SECONDS
						setHolder(best)
						task.spawn(function()
							api.walkTo(chaser, chaser.standFoot)
							if running and api.stillHere(chaser) then
								pcall(FigureFX.idleBob, chaser.figure, { height = 1.6, rate = 2.2 })
							end
						end)
					end
					chasing = false
				end)
			end)
			if not ok then
				warn("[EventHandlers.HotEgg] Tick fehlgeschlagen:", err)
			end
		end
	end)

	return {
		stop = function()
			running = false
			local results = {}
			for _, part in api.participants() do
				part.cancelWalk = true
			end
			if holder and api.stillHere(holder) then
				results[holder.player] = { egg = def.bonus }
			end
			if holder then
				setLabel(holder, nil)
			end
			if fire then
				fire:Destroy()
			end
			return results
		end,
	}
end

--------------------------------------------------------------------------------
-- Mutations-Sturm
--------------------------------------------------------------------------------

function EventHandlers.MutationsSturm(api, def)
	local cfg     = EventConfig.STORM
	local running = true
	local folder  = newFolder("EventStorm")
	local color   = Color3.fromRGB(255, 90, 235)

	local function strike(part)
		local pos = api.footOf(part.figure)
		local bolt = fxPart({
			Name = "Bolt", Material = Enum.Material.Neon, Color = color, Transparency = 0.1,
			Size = Vector3.new(0.8, 70, 0.8),
			CFrame = CFrame.new(pos + Vector3.new(0, 35, 0)),
		}, folder)
		pcall(FigureFX.burstAt, pos + Vector3.new(0, 2, 0), color, folder, 24)
		pcall(FigureFX.hitFlash, part.figure, color, 0.5)
		task.delay(0.3, function()
			bolt:Destroy()
		end)
	end

	task.spawn(function()
		while running do
			task.wait(cfg.STRIKE_INTERVAL_SECONDS)
			if not running then break end
			local ok, err = pcall(function()
				local parts = api.participants()
				if #parts > 0 then
					strike(parts[math.random(1, #parts)])
				end
			end)
			if not ok then
				warn("[EventHandlers.MutationsSturm] Blitz fehlgeschlagen:", err)
			end
		end
	end)

	return {
		stop = function()
			running = false
			local results = {}
			for _, part in api.participants() do
				results[part.player] = { mutationRoll = true }
				pcall(strike, part)
			end
			task.delay(1, function()
				folder:Destroy()
			end)
			return results
		end,
	}
end

--------------------------------------------------------------------------------
-- Koenigshuegel
--------------------------------------------------------------------------------

function EventHandlers.Koenigshuegel(api, def)
	local cfg     = EventConfig.KING
	local running = true
	local center  = api.center
	local hillR   = api.radius * cfg.HILL_RADIUS_FACTOR
	local folder  = newFolder("EventKing")

	fxPart({
		Name = "Hill", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 215, 70), Transparency = 0.45,
		Size = Vector3.new(0.4, hillR * 2, hillR * 2),
		CFrame = CFrame.new(Vector3.new(center.X, center.Y + 0.3, center.Z)) * CFrame.Angles(0, 0, math.rad(90)),
	}, folder)

	local seconds   = {}   -- [Player] = Sekunden oben
	local coolUntil = {}   -- [Presence] = os.clock()
	local fighting  = false

	local function onHill(part)
		return flatDist(api.footOf(part.figure), center) <= hillR
	end

	task.spawn(function()
		while running do
			task.wait(cfg.TICK_SECONDS)
			local ok, err = pcall(function()
				local parts = api.participants()
				local king, kingTime = nil, -1
				for _, part in parts do
					local up = onHill(part)
					if up then
						seconds[part.player] = (seconds[part.player] or 0) + cfg.TICK_SECONDS
					end
					local t = seconds[part.player] or 0
					if up and t > kingTime then
						king, kingTime = part, t
					end
					setLabel(part, string.format("%ds oben", math.floor(seconds[part.player] or 0)))
				end

				for _, part in parts do
					if part.busy or fighting or os.clock() < (coolUntil[part] or 0) then
						continue
					end

					if not onHill(part) then
						local dir = Vector3.new(part.standFoot.X - center.X, 0, part.standFoot.Z - center.Z)
						if dir.Magnitude < 0.1 then dir = Vector3.new(1, 0, 0) end
						local target = center + dir.Unit * (hillR * 0.5)
						if king and king ~= part then
							local kf = api.footOf(king.figure)
							local from = api.footOf(part.figure)
							local d = Vector3.new(from.X - kf.X, 0, from.Z - kf.Z)
							if d.Magnitude < 0.1 then d = Vector3.new(1, 0, 0) end
							target = kf + d.Unit * 4
						end
						task.spawn(function()
							api.walkTo(part, target)
							if running and api.stillHere(part) then
								pcall(FigureFX.idleBob, part.figure, { height = 1.6, rate = 2.2 })
							end
						end)
					elseif king and king ~= part and not king.busy then
						-- Herausforderer: zum Koenig laufen und kaempfen
						local kf = api.footOf(king.figure)
						local pf = api.footOf(part.figure)
						if flatDist(kf, pf) > 6 then
							local d = Vector3.new(pf.X - kf.X, 0, pf.Z - kf.Z)
							if d.Magnitude < 0.1 then d = Vector3.new(1, 0, 0) end
							task.spawn(function()
								api.walkTo(part, kf + d.Unit * 4)
							end)
						end
					end
				end

				-- Beruehrung zweier Teilnehmer auf dem Huegel -> Kampf
				if not fighting then
					for i = 1, #parts do
						for j = i + 1, #parts do
							local a, b = parts[i], parts[j]
							if onHill(a) and onHill(b)
								and flatDist(api.footOf(a.figure), api.footOf(b.figure)) <= 6
								and os.clock() >= (coolUntil[a] or 0) and os.clock() >= (coolUntil[b] or 0) then

								fighting = true
								a.cancelWalk, b.cancelWalk = true, true
								task.spawn(function()
									local ok2, err2 = pcall(function()
										local winner, loser = duel(api, a, b, 3)
										coolUntil[loser] = os.clock() + 6
										api.toast(loser.player, "Vom Huegel gestossen!")
										api.toast(winner.player, "Du haeltst den Huegel!")
										api.walkTo(loser, loser.standFoot)
									end)
									if not ok2 then
										warn("[EventHandlers.Koenigshuegel] Kampf fehlgeschlagen:", err2)
									end
									fighting = false
								end)
								return
							end
						end
					end
				end
			end)
			if not ok then
				warn("[EventHandlers.Koenigshuegel] Tick fehlgeschlagen:", err)
			end
		end
	end)

	return {
		stop = function()
			running = false
			local results = {}
			local bestPlayer, bestTime = nil, 0
			for _, part in api.participants() do
				part.cancelWalk = true
				setLabel(part, nil)
				local t = seconds[part.player] or 0
				if t > bestTime then
					bestPlayer, bestTime = part.player, t
				end
			end
			if bestPlayer then
				results[bestPlayer] = { egg = def.bonus }
			end
			folder:Destroy()
			return results
		end,
	}
end

--------------------------------------------------------------------------------
-- Schatzgraeber
--------------------------------------------------------------------------------

function EventHandlers.Schatzgraeber(api, def)
	local cfg     = EventConfig.TREASURE
	local running = true
	local center  = api.center
	local folder  = newFolder("EventTreasure")

	local started = {}   -- [Presence] = true
	local finds   = {}   -- [Player] = Anzahl Funde
	local bombed  = {}   -- [Player] = true

	local function randomSite()
		local angle = math.random() * math.pi * 2
		local dist  = api.radius * (0.25 + math.random() * 0.55)
		return Vector3.new(center.X + math.cos(angle) * dist, center.Y, center.Z + math.sin(angle) * dist)
	end

	local function run(part)
		local level   = api.level(part)
		local sites   = math.min(cfg.MAX_SITES, cfg.BASE_SITES + math.floor(level / cfg.LEVEL_PER_EXTRA_SITE))
		local digTime = math.max(cfg.MIN_DIG_SECONDS, cfg.BASE_DIG_SECONDS - level * cfg.DIG_SECONDS_PER_LEVEL)
		local player  = part.player

		finds[player] = finds[player] or 0
		api.toast(player, string.format("Schatzgraeber: %d Fundstellen - Vorsicht, Bomben!", sites))

		for i = 1, sites do
			if not running or not api.stillHere(part) then return end

			local pos = randomSite()
			local mound = fxPart({
				Name = "Mound", Shape = Enum.PartType.Ball, Material = Enum.Material.Ground,
				Color = Color3.fromRGB(120, 85, 50), Size = Vector3.new(4, 1.6, 4),
				CFrame = CFrame.new(pos + Vector3.new(0, 0.6, 0)),
			}, folder)
			local isBomb = math.random() < cfg.BOMB_SHARE

			if not api.walkTo(part, pos) then
				mound:Destroy()
				return
			end

			-- graben
			setLabel(part, string.format("Graebt %d/%d", i, sites))
			pcall(FigureFX.idleBob, part.figure, { height = 0.35, rate = 3 })
			local t0 = os.clock()
			while os.clock() - t0 < digTime do
				if not running or not api.stillHere(part) then
					mound:Destroy()
					setLabel(part, nil)
					return
				end
				task.wait(0.25)
			end
			pcall(FigureFX.stopIdle, part.figure)
			mound:Destroy()

			if isBomb then
				local boom = Instance.new("Explosion")
				boom.Position = pos
				boom.BlastRadius = 6
				boom.BlastPressure = 0
				boom.DestroyJointRadiusPercent = 0
				boom.Parent = folder
				pcall(FigureFX.defeatCollapse, part.figure, 0.8)
				finds[player] = 0
				bombed[player] = true
				setLabel(part, nil)
				api.toast(player, "BOMBE! Dein Baerchi ist besiegt - die Beute ist weg")
				api.recall(player)
				return
			end

			finds[player] += 1
			pcall(FigureFX.burstAt, pos + Vector3.new(0, 1, 0), Color3.fromRGB(255, 220, 90), folder, 20)
			api.toast(player, string.format("Fund! (%d)", finds[player]))
		end

		setLabel(part, nil)
		api.toast(player, string.format("Alle Fundstellen geleert: %d Funde", finds[player]))
		if api.walkTo(part, part.standFoot) and running and api.stillHere(part) then
			pcall(FigureFX.idleBob, part.figure, { height = 0.35, rate = 3 })
		end
	end

	task.spawn(function()
		while running do
			local ok, err = pcall(function()
				for _, part in api.participants() do
					if not started[part] and not bombed[part.player] then
						started[part] = true
						task.spawn(function()
							local ok2, err2 = pcall(run, part)
							if not ok2 then
								warn("[EventHandlers.Schatzgraeber] Lauf fehlgeschlagen:", err2)
							end
						end)
					end
				end
			end)
			if not ok then
				warn("[EventHandlers.Schatzgraeber] Tick fehlgeschlagen:", err)
			end
			task.wait(1)
		end
	end)

	return {
		stop = function()
			running = false
			local results = {}
			for _, part in api.participants() do
				part.cancelWalk = true
				setLabel(part, nil)
				local n = finds[part.player] or 0
				if n > 0 and not bombed[part.player] then
					local reward = nil
					for _, tier in cfg.REWARDS do
						if n >= tier.minFinds then
							reward = tier
						end
					end
					if reward then
						results[part.player] = { egg = {
							kind = "eggs", eggType = reward.eggType, eggPick = reward.eggPick,
							amount = reward.amount, blueprintChance = reward.blueprintChance,
						} }
					end
				end
			end
			folder:Destroy()
			return results
		end,
	}
end

return EventHandlers
