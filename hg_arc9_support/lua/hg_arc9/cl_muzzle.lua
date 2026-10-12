--[[
    v2.6.2 (исправлено в v2.6.4): ОРИГИНАЛЬНЫЕ ВСПЫШКИ ВЫСТРЕЛА ARC9 (клиент).

    Хомиград не рисует вспышку у прокси-оружия, а ARC9 привязывает её к вьюмодели (которой тут нет).
    Модуль берёт эффект из ARC9-оригинала и играет его в точке дула прокси-оружия, когда оно стреляет
    (у тебя и у других игроков). Ядро аддона не затрагивается.

    Откуда берётся эффект (по цепочке Base до arc9_base):
      MuzzleParticle - имя частицы (pcf), проигрывается ParticleEffect в дуле;
      MuzzleEffect   - имя эффекта (util.Effect), если частицы нет.
    Переопределить для одной пушки в sh_config.lua (Overrides):
      hgMuzzleParticle = "имя_частицы"   (false - не играть вообще)
      hgMuzzleEffect   = "имя_эффекта"

    Команды:
      hg_arc9_muzzle_info   - что нашлось у текущего оружия (все поля с "muzzle"/"flash" в имени)
      hg_arc9_muzzle_test   - сыграть вспышку один раз (без выстрела)
    Отключить: Config.MuzzleFlash = false.
]]

local Cfg = HGARC9.Config
local cache = {}

local function Str(v)
	if v == false then return false end

	return (isstring(v) and v ~= "") and v or nil
end

local function Info(src)
	local c = cache[src]
	if c then return c end

	local ov = HGARC9.Overrides and HGARC9.Overrides[src] or {}

	c = {
		particle = Str(ov.hgMuzzleParticle) or (ov.hgMuzzleParticle == nil and Str(HGARC9.GetStat(src, "MuzzleParticle")) or nil),
		effect = Str(ov.hgMuzzleEffect) or (ov.hgMuzzleEffect == nil and Str(HGARC9.GetStat(src, "MuzzleEffect")) or nil),
	}

	if c.particle == false then c.particle = nil end
	if c.effect == false then c.effect = nil end

	cache[src] = c

	return c
end

-- v2.6.4: позиция вспышки = дуло модели ТАК, КАК ОНА НАРИСОВАНА В РУКЕ (HGARC9_ModelMuzzle).
-- Раньше брался GetTrace(true): у игрока на ногах он подменял точку на "запасную от глаз" (если дуло дальше
-- EyeAimMaxDist), а направление брал из EyeAngles - вспышка могла оказаться не на стволе.
local MAX_OWNER_DIST = 150 -- дальше от головы владельца - считаем, что кости битые, и вспышку не играем

function HGARC9.MuzzleFlash(wep)
	local src = HGARC9.Sources and HGARC9.Sources[wep:GetClass()]
	if not src then return false end

	local i = Info(src)
	if not i.particle and not i.effect then return false end

	local owner = wep:GetOwner()

	-- кости владельца должны быть актуальны именно сейчас (иначе дуло берётся с позы прошлого кадра)
	if IsValid(owner) then owner:SetupBones() end

	local ok, pos, ang = pcall(wep.HGARC9_ModelMuzzle, wep)
	if not ok or not pos or not ang then return false end

	-- защита от мусорных координат (рэгдолл не прогрузился, кости не готовы): лучше без вспышки, чем в другом месте
	-- (в фейке/рэгдолле оружие может лежать далеко от самого игрока - там проверку не делаем)
	local fake = IsValid(owner) and (IsValid(owner.FakeRagdoll) or IsValid(owner:GetNWEntity("Ragdoll")) or IsValid(owner:GetNWEntity("ragdollWeapon")))

	if IsValid(owner) and not fake and pos:DistToSqr(owner:GetPos() + owner:OBBCenter()) > MAX_OWNER_DIST * MAX_OWNER_DIST then return false end

	if i.particle then
		if not i.precached then
			PrecacheParticleSystem(i.particle)
			i.precached = true
		end

		ParticleEffect(i.particle, pos, ang)

		return true
	end

	local model = IsValid(wep.worldModel) and wep.worldModel or wep
	local ed = EffectData()

	ed:SetOrigin(pos)
	ed:SetStart(pos)
	ed:SetAngles(ang)
	ed:SetNormal(ang:Forward())
	ed:SetEntity(model)
	ed:SetScale(1)

	-- Аттачмент НЕ передаём: worldModel стоит в кисти (render origin = рука), а не в итоговой точке, и эффект
	-- привязывался бы к его muzzle в неправильном месте. Точка уже посчитана в pos.
	util.Effect(i.effect, ed)

	return true
end

-- Выстрел = уменьшился магазин (работает и для чужих игроков, и без предсказания на клиенте).
-- v2.6.4: в Think вспышку только ПОМЕЧАЕМ (кости в этот момент ещё с прошлого кадра), а играем её
-- в PostDrawOpaqueRenderables - когда позы игроков и оружия уже посчитаны для текущего кадра.
local pending = {}

hook.Add("Think", "HGARC9_MuzzleFlash", function()
	if not Cfg.MuzzleFlash then return end

	for _, ply in ipairs(player.GetAll()) do
		local wep = ply:GetActiveWeapon()

		if IsValid(wep) and HGARC9.Sources[wep:GetClass()] then
			local clip = wep:Clip1()
			local prev = wep.hgFlashClip

			-- сменили оружие / снова взяли в руки: прошлое значение магазина не считается
			if ply.hgFlashWep ~= wep then
				ply.hgFlashWep = wep
				prev = nil
			end

			wep.hgFlashClip = clip

			if prev and clip < prev and clip >= 0 and not ply:IsDormant() then pending[wep] = CurTime() end
		else
			ply.hgFlashWep = nil
		end
	end
end)

hook.Add("PostDrawOpaqueRenderables", "HGARC9_MuzzleFlashPlay", function(bDrawingDepth, bDrawingSkybox)
	if bDrawingDepth or bDrawingSkybox then return end
	if next(pending) == nil then return end

	for wep, t in pairs(pending) do
		pending[wep] = nil

		-- устаревшая метка (оружие убрали / игрок пропал) - пропускаем
		if IsValid(wep) and CurTime() - t < 0.5 and IsValid(wep:GetOwner()) then HGARC9.MuzzleFlash(wep) end
	end
end)

local function ActiveProxy()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	local wep = ply:GetActiveWeapon()
	if IsValid(wep) and HGARC9.Sources and HGARC9.Sources[wep:GetClass()] then return wep end
end

concommand.Add("hg_arc9_muzzle_info", function()
	local wep = ActiveProxy()

	if not wep then
		print("[HG-ARC9] возьми в руки Homigrad-версию ARC9-пушки (hg_arc9_...)")

		return
	end

	local src = HGARC9.Sources[wep:GetClass()]
	local i = Info(src)

	print(string.format("[HG-ARC9] %s (источник %s): будет играться частица = %s, эффект = %s", wep:GetClass(), src, tostring(i.particle), tostring(i.effect)))
	print("[HG-ARC9] все поля источника с \"muzzle\"/\"flash\" в имени (цепочка Base):")

	local c, depth, found = src, 0, false

	while c and depth < 16 do
		local t = weapons.GetStored(c)
		if not t then break end

		for k, v in pairs(t) do
			if isstring(k) and (string.find(k:lower(), "muzzle", 1, true) or string.find(k:lower(), "flash", 1, true)) then
				found = true
				print(string.format("  [%s] %s = %s", c, k, istable(v) and "<table>" or tostring(v)))
			end
		end

		if c == "arc9_base" then break end

		c = t.Base
		depth = depth + 1
	end

	if not found then print("  (ничего не найдено)") end
end)

concommand.Add("hg_arc9_muzzle_test", function()
	local wep = ActiveProxy()

	if not wep then
		print("[HG-ARC9] возьми в руки Homigrad-версию ARC9-пушки (hg_arc9_...)")

		return
	end

	print("[HG-ARC9] вспышка " .. (HGARC9.MuzzleFlash(wep) and "сыграна" or "не сыграна: у оружия нет MuzzleParticle/MuzzleEffect (см. hg_arc9_muzzle_info)"))
end)
