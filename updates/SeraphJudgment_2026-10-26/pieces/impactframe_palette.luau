	-- 26.10. (Himmelsgericht): Palette waehlbar - `dark` (Tint der dunklen Bilder),
	-- `light` (Tint der hellen), `fill` (Silhouetten im dunklen Bild); Standard = Hoellensiegel-Rot.
	local darkTint: Color3 = if typeof(s.dark) == "Color3" then s.dark else Color3.fromRGB(255, 55, 55)
	local lightTint: Color3 = if typeof(s.light) == "Color3" then s.light else Color3.new(1, 1, 1)
	local darkFill: Color3 = if typeof(s.fill) == "Color3" then s.fill else Color3.fromRGB(170, 0, 12)
