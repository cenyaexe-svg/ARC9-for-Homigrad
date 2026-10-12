--[[
    Homigrad x ARC9 Support - ядро.

    ПОЧЕМУ ТАК.
    В хомиграде камера стоит в голове плеймодели (CalcView в cl_view.lua + render.RenderView),
    вьюмодели нет вообще, оружие рисуется как отдельная clientside-модель в правой руке
    (salat_base: GetTransform / WorldModelTransform), руки доворачиваются через ManipulateBoneAngles
    (ApplyAnim), прицеливание - через SWEP:Camera(), а в режиме фейка (рэгдолла) оружие вообще
    не активно у игрока и стреляется из хука "Player Think". Всё это завязано на isHGWeapon(wep)
    (wep.ishgweapon) и методы salat_base.

    ARC9 рассчитывает на вьюмодель, свои CalcView/HUD/TPIK и активное оружие, поэтому "как есть"
    в хомиграде он ломается. Вместо костылей поверх ARC9 мы для КАЖДОГО ARC9-оружия создаём
    нативное оружие хомиграда (Base = "salat_base"), перенося из ARC9: модель, звук выстрела,
    урон, темп стрельбы, магазин, тип патронов, разброс, отдачу, холдтайп.
    Получается оружие, которое полностью работает в системе хомиграда: фейк-рэгдолл,
    ADS-камера в голове, руки, спина (vbw), лут, инвентарь, слоты, боль/урон.
]]

HGARC9 = HGARC9 or {}
HGARC9.Proxies = HGARC9.Proxies or {} -- ARC9 класс -> класс прокси
HGARC9.Sources = HGARC9.Sources or {} -- класс прокси -> ARC9 класс

if SERVER and not HGARC9.ShotLog then
	HGARC9.ShotLog = CreateConVar("hg_arc9_shotlog", "0", FCVAR_NONE, "Писать в консоль сервера, куда уходят пули ARC9-оружия относительно взгляда", 0, 1)
end

local Cfg = HGARC9.Config

-- v2.3: клиент сообщает серверу, где у него дуло относительно глаз (в системе взгляда). Серверные кости рук
-- (лерпы ApplyAnim по FrameTime, ManipulateBone) не совпадают с клиентскими на единицы юнитов - отсюда
-- «слегка в сторону» даже при верном направлении. Сервер ограничивает значение и использует его как точку выстрела.
if SERVER then
	util.AddNetworkString("hg_arc9_muzzle")

	net.Receive("hg_arc9_muzzle", function(_, ply)
		if not Cfg.ClientMuzzle or not IsValid(ply) then return end

		local v = net.ReadVector()

		if v.x ~= v.x or v.y ~= v.y or v.z ~= v.z then return end
		if v:LengthSqr() > 60 * 60 then return end

		ply.hgArc9MuzOfs = v
		ply.hgArc9MuzTime = CurTime()
	end)
else
	local nextSend, lastSend, last = 0, 0, nil

	hook.Add("Think", "HGARC9_SendMuzzle", function()
		if not Cfg.ClientMuzzle or CurTime() < nextSend then return end

		local ply = LocalPlayer()
		if not IsValid(ply) then return end

		local wep = ply:GetActiveWeapon()
		if not IsValid(wep) or not wep.HGARC9_EyeAimActive or not wep:HGARC9_EyeAimActive(ply) then return end

		nextSend = CurTime() + 0.05

		local mpos, mang = wep:GetTrace(true)
		if not mpos then return end

		local ofs = WorldToLocal(mpos, angle_zero, ply:EyePos(), mang)

		if last and last:DistToSqr(ofs) < 0.09 and CurTime() - lastSend < 1 then return end

		last, lastSend = ofs, CurTime()

		net.Start("hg_arc9_muzzle", true)
		net.WriteVector(ofs)
		net.SendToServer()
	end)
end

local function Log(msg)
	MsgC(Color(120, 200, 255), "[HG-ARC9] ", color_white, tostring(msg) .. "\n")
end

HGARC9.Log = Log

-- ============================ ЧТЕНИЕ ХАРАКТЕРИСТИК ARC9 ============================

-- Ищем поле в самом оружии, затем вверх по цепочке Base (включая arc9_base).
local function GetStat(class, key)
	local c = class
	local depth = 0

	while c and depth < 16 do
		local t = weapons.GetStored(c)
		if not t then return nil end

		local v = t[key]
		if v ~= nil then return v end
		if c == "arc9_base" then return nil end

		c = t.Base
		depth = depth + 1
	end

	return nil
end

HGARC9.GetStat = GetStat

local function FirstString(v)
	if isstring(v) then return v end

	if istable(v) then
		for _, s in ipairs(v) do
			if isstring(s) then return s end
		end

		for _, s in pairs(v) do
			if isstring(s) then return s end
		end
	end

	return nil
end

local function Num(v, default)
	if isnumber(v) then return v end

	return default
end

-- ============================ ФИЛЬТР ============================

local SKIP_HOLD = {
	melee = true,
	melee2 = true,
	knife = true,
	fist = true,
	grenade = true,
	slam = true,
}

function HGARC9.IsARC9Class(class)
	if class == "arc9_base" then return false end
	if not weapons.GetStored("arc9_base") then return false end

	return weapons.IsBasedOn(class, "arc9_base")
end

function HGARC9.ShouldConvert(class)
	if Cfg.Blacklist and Cfg.Blacklist[class] then return false end
	if not HGARC9.IsARC9Class(class) then return false end

	local hold = GetStat(class, "HoldType")
	if isstring(hold) and SKIP_HOLD[string.lower(hold)] then return false end

	if GetStat(class, "Throwing") or GetStat(class, "Melee") then return false end

	local ammo = GetStat(class, "Ammo")
	if isstring(ammo) and string.lower(ammo) == "none" then return false end

	return true
end

-- ============================ ПОДБОР МОДЕЛИ ============================

local PLACEHOLDER = {
	["models/weapons/w_pistol.mdl"] = true,
	["models/weapons/w_smg1.mdl"] = true,
	["models/weapons/w_irifle.mdl"] = true,
	["models/weapons/w_357.mdl"] = true,
	["models/weapons/w_shotgun.mdl"] = true,
	["models/weapons/w_crowbar.mdl"] = true,
}

local function GoodModel(m)
	return isstring(m) and m ~= "" and not PLACEHOLDER[m]
end

local function PickModel(class)
	local wm = GetStat(class, "WorldModel")
	local wmm = GetStat(class, "WorldModelMirror")
	local vm = GetStat(class, "ViewModel")

	local list = {}

	if GoodModel(wm) and wm ~= vm then list[#list + 1] = wm end
	if GoodModel(wmm) then list[#list + 1] = wmm end
	if GoodModel(wm) then list[#list + 1] = wm end
	if GoodModel(vm) then list[#list + 1] = vm end

	for _, m in ipairs(list) do
		if util.IsValidModel(m) then return m end
	end

	return list[1]
end

-- ============================ КЛАССИФИКАЦИЯ ============================

local PISTOL_HOLD = {
	revolver = true,
	pistol = true,
}

local function Classify(hold, clip, num, rpm)
	if num > 1 then return "shotgun" end
	if PISTOL_HOLD[hold] then return "pistol" end
	if clip >= 75 then return "lmg" end
	if hold == "smg" then return "smg" end
	if rpm <= 100 then return "sniper" end

	return "rifle"
end

local DEFAULT_SIGHT = {
	pistol  = Vector(-22, 0.1, -1.0),
	smg     = Vector(-28, 1.2, -0.2),
	rifle   = Vector(-30, 1.7, -0.27),
	lmg     = Vector(-32, 1.7, -0.27),
	shotgun = Vector(-35, 1.5, -0.1),
	sniper  = Vector(-55, 0, 0),
}

-- Коэффициенты для автоматического расчёта SightPos.x от длины модели (см. InitAdd)
-- v2.3: камера прицеливания над линией ствола (высота прицельной планки) и чуть назад: на уровне ствола
-- ресивер закрывал обзор. x вперёд, y влево, z вверх. Точнее - hg_arc9_tune.
local DEFAULT_OFS = {
	pistol  = Vector(0, 0, 0),
	smg     = Vector(-2, 0, 1.0),
	rifle   = Vector(-2, 0, 0.9),
	lmg     = Vector(-2, 0, 1.4),
	shotgun = Vector(-2, 0, 1.0),
	sniper  = Vector(-3, 0, 1.3),
}

local SIGHT_LEN_MUL = {
	smg = 0.95,
	rifle = 0.95,
	lmg = 0.95,
	shotgun = 1.0,
	sniper = 1.1,
}

local DEFAULT_RELOAD = {
	pistol = 1.9,
	smg = 2.1,
	rifle = 2.4,
	lmg = 5.0,
	shotgun = 3.0,
	sniper = 3.0,
}

local function AmmoValid(name)
	return isstring(name) and game.GetAmmoID(name) ~= -1
end

local function MapAmmo(class, ammo, dmg, kind, strict)
	local result = HGARC9.AmmoByClass and HGARC9.AmmoByClass[class]

	if not result then
		local a = isstring(ammo) and string.lower(ammo) or ""

		if kind == "shotgun" then
			result = "12/70 gauge"
		elseif kind == "sniper" then
			result = (dmg >= 130) and "12.7x99 mm" or "7.62x39 mm"
		elseif HGARC9.AmmoByARC9 and HGARC9.AmmoByARC9[a] then
			result = HGARC9.AmmoByARC9[a]

			if a == "pistol" and kind == "pistol" and dmg >= 40 then result = ".44 Magnum" end
		elseif isstring(ammo) and AmmoValid(ammo) then
			result = ammo
		elseif kind == "pistol" then
			result = "9x19 mm Parabellum"
		else
			result = "5.56x45 mm"
		end
	end

	-- Во втором проходе (InitPostEntity) патроны хомиграда точно зарегистрированы
	if strict and not AmmoValid(result) then
		result = (kind == "pistol") and "pistol" or "ar2"
	end

	return result
end

-- ============================ ГЕНЕРАЦИЯ ПРОКСИ ============================

local function ProxyName(class)
	local name = (Cfg.ProxyPrefix or "hg_") .. class

	if #name > 60 then name = string.sub(name, 1, 50) .. "_" .. util.CRC(class) end

	return name
end

function HGARC9.BuildProxy(class, strict)
	local src = weapons.GetStored(class)
	if not src then return end

	local model = PickModel(class)
	if not model then
		if Cfg.Debug then Log("пропуск " .. class .. ": нет модели") end

		return
	end

	local SWEP = {}

	-- ---------- базовые данные ----------
	local clip = Num(GetStat(class, "ClipSize"), 30)
	if clip < 1 then clip = 30 end

	local num = math.max(math.floor(Num(GetStat(class, "Num"), 1)), 1)
	local hold = string.lower(GetStat(class, "HoldType") or "ar2")
	hold = (HGARC9.HoldTypeMap and HGARC9.HoldTypeMap[hold]) or hold

	local rpm = math.Clamp(Num(GetStat(class, "RPM"), 600), 30, 1500)
	local kind = Classify(hold, clip, num, rpm)
	local twoHands = kind ~= "pistol"

	local dmgMax = Num(GetStat(class, "DamageMax"), 25)
	local dmg
	if num > 1 then
		dmg = dmgMax * Cfg.PelletDamageScale
	else
		dmg = dmgMax * Cfg.DamageScale
	end

	dmg = math.Clamp(math.floor(dmg + 0.5), 5, 250)

	local shootWait = 60 / rpm

	-- автоматический огонь: у ARC9 Mode < 0 (в Firemodes)
	local automatic = false
	local fm = GetStat(class, "Firemodes")

	if istable(fm) then
		for _, f in ipairs(fm) do
			if istable(f) and isnumber(f.Mode) and f.Mode < 0 then
				automatic = true

				break
			end
		end
	end

	if not automatic then shootWait = math.max(shootWait, 0.08) end

	local spreadScale = (num > 1) and 1 or Cfg.SpreadScale
	local spread = math.Clamp(Num(GetStat(class, "Spread"), 0.01) * spreadScale, 0, 0.2)
	local ammo = MapAmmo(class, GetStat(class, "Ammo"), dmg, kind, strict)

	local sound = FirstString(GetStat(class, "ShootSound")) or "weapons/smg1/smg1_fire1.wav"
	local soundFar = FirstString(GetStat(class, "DistantShootSound")) or ""

	-- ---------- SWEP ----------
	SWEP.Base = "salat_base"

	SWEP.PrintName = GetStat(class, "PrintName") or class
	SWEP.Author = "HG-ARC9 / " .. tostring(GetStat(class, "Author") or "ARC9")
	SWEP.Instructions = "ARC9 -> Homigrad (" .. class .. ")"
	SWEP.Category = Cfg.Category

	SWEP.Spawnable = GetStat(class, "Spawnable") == true
	SWEP.AdminOnly = GetStat(class, "AdminOnly") == true

	SWEP.Primary = {
		ClipSize = clip,
		DefaultClip = clip,
		Automatic = automatic,
		Ammo = ammo,
		Cone = spread,
		Damage = dmg,
		Spread = 0,
		Sound = sound,
		SoundFar = soundFar,
		Force = math.Clamp(dmg * 2, 20, 120),
	}

	SWEP.Secondary = {
		ClipSize = -1,
		DefaultClip = -1,
		Automatic = false,
		Ammo = "none",
	}

	SWEP.Weight = 5
	SWEP.AutoSwitchTo = false
	SWEP.AutoSwitchFrom = false

	SWEP.HoldType = hold
	SWEP.TwoHands = twoHands
	SWEP.ShootWait = shootWait
	SWEP.ReloadTime = DEFAULT_RELOAD[kind] or 2.4
	SWEP.ReloadSound = (kind == "pistol") and "" or "weapons/ar2/ar2_reload.wav"

	if num > 1 then SWEP.NumBullet = num end

	SWEP.shotgun = kind == "shotgun"
	SWEP.revolver = kind == "pistol" and clip <= 8

	SWEP.Slot = Num(GetStat(class, "Slot"), 2)
	SWEP.SlotPos = Num(GetStat(class, "SlotPos"), 0)
	SWEP.DrawAmmo = true
	SWEP.DrawCrosshair = false

	-- Вьюмодели в хомиграде нет, но поле должно быть валидным
	SWEP.ViewModel = model
	SWEP.WorldModel = model

	-- SightPos - СТАРАЯ схема камеры (от дула: x назад, y влево, z вверх). Используется, только если
	-- Config.AutoSight = false или SightPos задан в Overrides (старые подогнанные значения продолжают работать).
	SWEP.SightPos = Vector(DEFAULT_SIGHT[kind].x, DEFAULT_SIGHT[kind].y, DEFAULT_SIGHT[kind].z)
	-- v2.2: НОВАЯ схема. Камера стоит на линии ствола в точке, ближайшей к голове (глубина от размеров модели
	-- не зависит), SightOfs - сдвиг от неё в системе взгляда: x вперёд, y ВЛЕВО, z вверх. 0,0,0 = пуля в центр экрана.
	SWEP.SightOfs = Vector((DEFAULT_OFS[kind] or vector_origin).x, (DEFAULT_OFS[kind] or vector_origin).y, (DEFAULT_OFS[kind] or vector_origin).z)
	SWEP.addPos = Vector(0, 0, 0)
	-- v1 компенсировала крен через addAng (петля обратной связи хомиграда удваивала и раскачивала его).
	-- v2: поза руки считается явно (см. HGARC9_GetHandAngle), addAng - только поправка направления выстрела.
	SWEP.addAng = Angle(0, 0, Cfg.AutoCalibrate and 0 or (Cfg.LegacyRollFix or 90))
	SWEP.hgRoll = Cfg.RollFix or 0

	if kind == "sniper" then SWEP.addfov = 50 end

	-- Данные для InitAdd / GetTrace / ApplyEyeSpray
	SWEP.hgKind = kind
	SWEP.hgAxis = Vector(1, 0, 0) -- ось ствола в пространстве модели (в Source оружие смотрит по +X)
	SWEP.hgRecoilUp = math.Clamp(Num(GetStat(class, "RecoilUp"), 0.8) * Num(GetStat(class, "Recoil"), 1) * Cfg.RecoilScale, 0.1, 6)
	SWEP.hgRecoilSide = math.Clamp(Num(GetStat(class, "RecoilSide"), 0.4) * Num(GetStat(class, "Recoil"), 1) * Cfg.RecoilScale, 0.05, 4)
	SWEP.hgSourceClass = class

	-- ---------- оверрайды пользователя ----------
	local ov = HGARC9.Overrides and HGARC9.Overrides[class]

	if istable(ov) then
		SWEP.hgUserSight = ov.SightPos ~= nil
		SWEP.hgUserOfs = ov.SightOfs ~= nil
		SWEP.hgUserAxis = ov.hgAxis ~= nil
		SWEP.hgUserMuzzle = ov.hgMuzzleLocal ~= nil

		for k, v in pairs(ov) do
			if k == "Primary" and istable(v) then
				for pk, pv in pairs(v) do
					SWEP.Primary[pk] = pv
				end
			else
				SWEP[k] = istable(v) and table.Copy(v) or v
			end
		end

		-- если пользователь поменял ClipSize, а DefaultClip не трогал
		if ov.Primary and ov.Primary.ClipSize and not ov.Primary.DefaultClip then SWEP.Primary.DefaultClip = ov.Primary.ClipSize end
	end

	SWEP.hgSightLegacy = (not Cfg.AutoSight) or (SWEP.hgUserSight == true)

	-- ---------- методы ----------

	-- Вызывается из salat_base:Initialize (после AddHomigradWeapon).
	-- Считаем геометрию модели: от неё зависит точка/направление выстрела (GetTrace)
	-- и автоматическая позиция камеры при прицеливании.
	function SWEP:InitAdd()
		local mins, maxs = self:GetModelBounds()
		if not mins or not maxs then return end

		local size = maxs - mins
		if size:Length() < 4 then return end

		self.hgCenter = (mins + maxs) * 0.5
		self.hgHalf = size * 0.5

		local ax = self.hgAxis or Vector(1, 0, 0)
		local len = math.abs(ax.x) * size.x + math.abs(ax.y) * size.y + math.abs(ax.z) * size.z

		if not self.hgUserSight then
			local x

			if self.hgKind == "pistol" then
				x = -(len + 13)
			else
				x = -(len * (SIGHT_LEN_MUL[self.hgKind] or 0.95))
			end

			self.SightPos = Vector(math.Clamp(x, -75, -14), self.SightPos.y, self.SightPos.z)
		end

		self:HGARC9_AutoSight()
	end

	-- v2.4: высота камеры при ПКМ по геометрии модели. Камера на уровне ствола давала «мушку ниже точки попадания»:
	-- прицельные планки выше оси ствола. Берём верх габарита модели над осью ствола (у винтовок это планки/мушка)
	-- и ставим камеру на эту высоту. "Вверх" модели - тот же up, что использует расчёт позы руки (ось ствола -> угол).
	-- Пистолеты не трогаем (у них посадка уже совпадает), оверрайд SightOfs в Overrides тоже.
	function SWEP:HGARC9_AutoSight()
		if not Cfg.AutoSightHeight or self.hgUserOfs or self.hgKind == "pistol" then return end

		local mins, maxs = self:GetModelBounds()
		if not mins or not maxs then return end

		local u = (self.hgAxis or Vector(1, 0, 0)):Angle():Up()
		local top = -math.huge

		for _, x in ipairs({mins.x, maxs.x}) do
			for _, y in ipairs({mins.y, maxs.y}) do
				for _, z in ipairs({mins.z, maxs.z}) do
					top = math.max(top, Vector(x, y, z):Dot(u))
				end
			end
		end

		local ref = (self.hgMuzzleLocal or self.hgCenter or vector_origin):Dot(u)
		local h = math.Clamp(top - ref, 0, 7) * (Cfg.AutoSightHeightMul or 1)
		local o = self.SightOfs or vector_origin

		self.SightOfs = Vector(o.x, o.y, h)
		self.hgAutoSightH = h
	end

	-- ================= v2: СТАБИЛЬНАЯ ПОЗА РУКИ =================
	-- salat_base:ApplyAnim каждый кадр делает self.localAngle = Lerp(localAngle, угол_ствола_в_системе_руки):
	-- покомпонентный lerp эйлеровых углов по костям прошлого кадра. Вероятная причина дёрганья и «плавания»
	-- у ARC9-моделей: угол ствола берётся из геометрии модели с произвольным поворотом, эйлеровы углы
	-- переключаются между эквивалентными представлениями (±180, ±90), и lerp между ними даёт полуобороты
	-- (шум костей при ходьбе -> дёрганье, в покое -> дрейф крена). Проверить: hg_arc9_debug 1.
	--
	-- Решение: считаем localAngle ОДИН РАЗ аналитически и подставляем каждый кадр вместо петли.
	--   H = EyeAngles * L * Roll(-90)        - рука (так её строит ApplyAnim)
	--   W = H * B                            - модель оружия (B - выравнивание кости R_Hand модели + dwm*)
	--   хотим W * Ax = EyeAngles * Roll(hgRoll)   (Ax - ось ствола модели)
	--   => L = Roll(hgRoll) * Ax^-1 * B^-1 * Roll(90)
	-- B берём измерением: B = H^-1 * W при текущей позе (инвариант, не зависит от кадра).

	-- Куда у модели смотрит ствол. Позиция аттачмента "muzzle" у моделей надёжна (в отличие от его
	-- ориентации): направление ствола = от центра габарита к дулу, по доминирующей оси со знаком.
	-- Раньше всегда считалось +X, и у моделей со стволом по -X/±Y оружие целилось за спину.
	local MUZZLE_NAMES = {"muzzle", "muzzle_flash", "muzzleflash", "1", "barrel"}

	-- v2.2: на КЛИЕНТЕ хомиград перед чтением костей зовёт SetupBones(), на СЕРВЕРЕ - нет. Кэш костей сервера
	-- строится один раз за тик в том положении, в котором модель оказалась при первом обращении, а GetTransform
	-- читает R_Hand модели сразу после SetPos/SetAngles. В результате серверное W (и B, и дуло) не совпадало
	-- с клиентским. InvalidateBoneCache() заставляет сервер пересчитать кости (метод есть не во всех сборках).
	local function Invalidate(ent)
		if SERVER and IsValid(ent) and ent.InvalidateBoneCache then ent:InvalidateBoneCache() end
	end

	-- Обычный игрок на ногах (не фейк/рэгдолл, не самоубийство, не NPC): направление выстрела = взгляд.
	local function IsFake(ply)
		return IsValid(ply.FakeRagdoll) or IsValid(ply:GetNWEntity("Ragdoll")) or IsValid(ply:GetNWEntity("ragdollWeapon"))
	end

	function SWEP:HGARC9_EyeAimActive(owner)
		if not Cfg.EyeAim then return false end
		if not IsValid(owner) or not owner:IsPlayer() then return false end
		if owner:GetNWBool("Suiciding") then return false end

		return not IsFake(owner)
	end

	function SWEP:HGARC9_DetectAxis()
		if self.hgAxisDone then return end
		if not Cfg.AutoAxis or self.hgUserAxis then self.hgAxisDone = true return end
		if not self.hgCenter then return end -- InitAdd ещё не отработал

		local model = IsValid(self.worldModel) and self.worldModel or self:CreateWorldModel()
		if not IsValid(model) then return end

		self.worldModel = model

		local op, oa = model:GetPos(), model:GetAngles()

		model:SetPos(vector_origin)
		model:SetAngles(angle_zero)

		if CLIENT then
			model:SetRenderOrigin(vector_origin)
			model:SetRenderAngles(angle_zero)
			model:SetupBones()
		else
			Invalidate(model)
		end

		local att

		for _, n in ipairs(MUZZLE_NAMES) do
			local id = model:LookupAttachment(n)

			if id and id > 0 then
				att = model:GetAttachment(id)

				if att then break end
			end
		end

		model:SetPos(op)
		model:SetAngles(oa)

		if CLIENT then
			model:SetRenderOrigin(op)
			model:SetRenderAngles(oa)
		else
			Invalidate(model)
		end

		self.hgAxisDone = true

		if not att then
			if Cfg.Debug then HGARC9.Log(self:GetClass() .. ": аттачмент muzzle не найден, ось ствола +X (если оружие целится назад - hg_arc9_flip)") end

			return
		end

		local d = att.Pos - self.hgCenter
		local ax, ay, az = math.abs(d.x), math.abs(d.y), math.abs(d.z)
		local big = math.max(ax, ay, az)

		if big < 3 or big < d:Length() * 0.6 then return end -- дуло у центра или по диагонали: не доверяем

		if big == ax then self.hgAxis = Vector(d.x > 0 and 1 or -1, 0, 0)
		elseif big == ay then self.hgAxis = Vector(0, d.y > 0 and 1 or -1, 0)
		else self.hgAxis = Vector(0, 0, d.z > 0 and 1 or -1) end

		if not self.hgUserMuzzle then self.hgMuzzleLocal = Vector(att.Pos.x, att.Pos.y, att.Pos.z) end

		self.hgLocalSig = nil -- ось поменялась - пересчитать позу руки

		self:HGARC9_AutoSight()

		if Cfg.Debug then HGARC9.Log(string.format("%s: ось ствола (%d %d %d) по аттачменту muzzle", self:GetClass(), self.hgAxis.x, self.hgAxis.y, self.hgAxis.z)) end
	end

	local function AngM(a)
		local m = Matrix()
		m:SetAngles(a)

		return m
	end

	local ROLL90 = Angle(0, 0, 90)

	function SWEP:HGARC9_Signature()
		local ax = self.hgAxis or Vector(1, 0, 0)

		local sd = self.hgSightDir or ax

		return string.format("%s|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%.4f|%.4f|%.4f", tostring(self.WorldModel), self.dwmAUp or 0, self.dwmARight or 0, self.dwmAForward or 0, self.hgRoll or 0, ax.x, ax.y, ax.z, sd.x, sd.y, sd.z)
	end

	-- Возвращает постоянный localAngle для руки (или nil - тогда работает штатная петля).
	function SWEP:HGARC9_GetHandAngle(ply)
		if not Cfg.AutoCalibrate then return end
		if not IsValid(ply) or not ply:IsPlayer() then return end

		-- в фейке (рэгдолл) рука не ведётся ApplyAnim'ом, положение даёт физика
		if IsValid(ply.FakeRagdoll) or IsValid(ply:GetNWEntity("ragdollWeapon")) then return self.hgLocalAngle end

		self:HGARC9_DetectAxis()

		local sig = self:HGARC9_Signature()
		if self.hgLocalAngle and self.hgLocalSig == sig then return self.hgLocalAngle end

		local bon = ply:LookupBone("ValveBiped.Bip01_R_Hand")
		if not bon then return self.hgLocalAngle end

		-- GetTransform сам делает SetupBones, поэтому W и H берутся из одного и того же состояния костей
		local _, W = self:GetTransform()
		if not W then return self.hgLocalAngle end

		local hm = ply:GetBoneMatrix(bon)
		if not hm then return self.hgLocalAngle end

		local _, Bang = WorldToLocal(vector_origin, W, vector_origin, hm:GetAngles())

		local ax = self.hgAxis or Vector(1, 0, 0)
		-- hgSightDir (необязательно): по взгляду ставится линия прицеливания вместо оси ствола (режим 3 в hg_arc9_mode)
		local M = AngM(Angle(0, 0, self.hgRoll or 0)) * AngM((self.hgSightDir or ax):Angle()):GetInverse()
		local L = (M * AngM(Bang):GetInverse() * AngM(ROLL90)):GetAngles()

		self.hgLocalAngle = L
		self.hgLocalSig = sig
		self.hgBAng = Bang

		if Cfg.Debug then HGARC9.Log(string.format("%s: калибровка руки B=(%.1f %.1f %.1f) L=(%.1f %.1f %.1f)", self:GetClass(), Bang.p, Bang.y, Bang.r, L.p, L.y, L.r)) end

		return L
	end

	local function BaseSWEP()
		return weapons.GetStored("salat_base")
	end

	-- Штатный ApplyAnim, но с зафиксированным localAngle: петля обратной связи отключена.
	function SWEP:ApplyAnim(ply)
		local L = self:HGARC9_GetHandAngle(ply)

		if L then self.localAngle = L end

		BaseSWEP().ApplyAnim(self, ply)

		-- базовый метод в конце кадра сдвигает localAngle к углу ствола - откатываем
		if L then self.localAngle = L end
	end

	-- Модель оружия не должна проигрывать анимацию: у вьюмоделей ARC9 кость R_Hand
	-- двигается в idle-анимации, а по ней модель выравнивается в руке (GetTransform).
	function SWEP:CreateWorldModel()
		local model = BaseSWEP().CreateWorldModel(self)

		-- v2.2: и на сервере тоже: серверная модель-prop участвует в GetTransform (кость R_Hand)
		if IsValid(model) then
			model:SetSequence(0)
			model:SetCycle(0)
			model:SetPlaybackRate(0)
		end

		return model
	end

	-- v2.2: копия salat_base:GetTransform с одним отличием: на сервере перед чтением костей сбрасывается
	-- кэш костей (см. Invalidate). На клиенте поведение полностью штатное.
	function SWEP:GetTransform(model, force)
		local owner = self:GetOwner()

		model = IsValid(model) and model or nil

		if not IsValid(owner) then return self:GetPos(), self:GetAngles() end

		if not model then
			self.worldModel = IsValid(self.worldModel) and self.worldModel or self:CreateWorldModel()
			model = self.worldModel
		end

		local rw = owner:GetNWEntity("ragdollWeapon")
		if IsValid(rw) and not force then return rw:GetPos(), rw:GetAngles() end

		local body = IsValid(owner.FakeRagdoll) and owner.FakeRagdoll or owner
		if IsValid(rw) then model = rw end
		if not IsValid(model) then return self:GetPos(), self:GetAngles() end

		if CLIENT then model:SetPredictable(true) end

		if CLIENT then
			body:SetupBones()
			model:SetupBones()
		else
			Invalidate(body)
		end

		local bon = body:LookupBone("ValveBiped.Bip01_R_Hand")
		if not bon then return self:GetPos(), self:GetAngles() end

		local rh = body:GetBoneMatrix(bon)

		if body:IsRagdoll() then
			rh = Matrix()

			local phys = body:GetPhysicsObjectNum(body:TranslateBoneToPhysBone(bon))
			if not IsValid(phys) then return end

			rh:SetTranslation(phys:GetPos())
			rh:SetAngles(phys:GetAngles())
		end

		if not rh then return self:GetPos(), self:GetAngles() end

		local pos, ang = rh:GetTranslation(), rh:GetAngles()
		local oldpos, oldang = model:GetPos(), model:GetAngles()

		model:SetPos(pos)
		model:SetAngles(ang)

		if CLIENT then
			model:SetRenderOrigin(pos)
			model:SetRenderAngles(ang)
			model:SetupBones()
		else
			Invalidate(model)
		end

		local bon2 = model:LookupBone("ValveBiped.Bip01_R_Hand")

		if bon2 then
			local rh_wep = model:GetBoneMatrix(bon2)

			if rh_wep then
				local newmat = rh_wep:GetInverse() * rh

				pos, ang = LocalToWorld(newmat:GetTranslation(), newmat:GetAngles(), pos, ang)
			end
		end

		model:SetPos(oldpos)
		model:SetAngles(oldang)

		pos:Add(ang:Forward() * (self.dwmForward or 0))
		pos:Add(ang:Right() * (self.dwmRight or 0))
		pos:Add(ang:Up() * (self.dwmUp or 0))

		ang:RotateAroundAxis(ang:Up(), self.dwmAUp or 0)
		ang:RotateAroundAxis(ang:Right(), self.dwmARight or 0)
		ang:RotateAroundAxis(ang:Forward(), self.dwmAForward or 0)

		return pos, ang
	end

	-- Дуло по геометрии модели в том положении, в котором она рисуется в руке (или лежит в рэгдолле):
	-- точка = muzzle аттачмент (hgMuzzleLocal) либо край габарита, направление = W * Ax.
	-- Здесь же сырые данные для диагностики (hg_arc9_state / hg_arc9_sv_state).
	function SWEP:HGARC9_ModelMuzzle()
		self:HGARC9_DetectAxis()

		local pos, ang = self:GetTransform()

		if not pos or not ang then
			pos, ang = self:GetPos(), self:GetAngles()
		end

		local ax = self.hgAxis or Vector(1, 0, 0)
		local tip = self.hgMuzzleLocal

		if not tip then
			local c = self.hgCenter or vector_origin
			local h = self.hgHalf or Vector(14, 0, 0)

			tip = Vector(c.x + ax.x * h.x, c.y + ax.y * h.y, c.z + ax.z * h.z)
		end

		return LocalToWorld(tip, ax:Angle(), pos, ang)
	end

	-- ТОЧКА И НАПРАВЛЕНИЕ ВЫСТРЕЛА (используют: FireBullet - пули на сервере, Camera - прицел на клиенте,
	-- ApplyAnim, hg_show_hitposmuzzle).
	--
	-- v2.2, обычный игрок на ногах: НАПРАВЛЕНИЕ = взгляд (EyeAngles), независимо от костей и модели.
	--   Рука и так калибруется так, что ствол смотрит по взгляду (v2), а считать направление пули из
	--   костей на сервере ненадёжно: B/L сервера и клиента расходились, и пули уходили вправо.
	--   ТОЧКА = дуло модели (как рисуется в руке); если она неправдоподобно далеко от глаз (битые кости
	--   сервера) - запасная точка от глаз; для пули (не nomodify) точка не заходит за стену.
	-- Фейк/рэгдолл/самоубийство: как в v2 (направление по модели W * Ax * addAng).
	-- Камера при ПКМ: точка на линии ствола, ближайшая к глазам, + SightOfs. Одна функция для камеры (клиент)
	-- и для схождения пули (сервер), чтобы они совпадали.
	function SWEP:HGARC9_CamOrigin(eyePos, mpos, ang)
		local fwd = ang:Forward()
		local base = mpos + fwd * (eyePos - mpos):Dot(fwd)

		return (LocalToWorld(self.SightOfs or vector_origin, angle_zero, base, ang))
	end

	function SWEP:GetTrace(nomodify)
		local owner = self:GetOwner()
		local mpos, mang = self:HGARC9_ModelMuzzle()

		if self:HGARC9_EyeAimActive(owner) then
			local eye = owner:EyeAngles()
			local eyePos = owner:EyePos()

			mang = Angle(eye.p, eye.y, 0)

			-- сервер: точка дула, присланная клиентом (см. hg_arc9_muzzle)
			if SERVER and Cfg.ClientMuzzle and owner.hgArc9MuzOfs and CurTime() - (owner.hgArc9MuzTime or 0) < 3 then
				mpos = LocalToWorld(owner.hgArc9MuzOfs, angle_zero, eyePos, mang)
			end

			local maxd = Cfg.EyeAimMaxDist or 90

			if mpos:DistToSqr(eyePos) > maxd * maxd then
				mpos = eyePos + mang:Forward() * 10 + mang:Right() * (self.TwoHands and 7 or 2.5) - mang:Up() * 4
			end

			if not nomodify then
				local tr = util.TraceLine({start = eyePos, endpos = mpos, mask = MASK_SOLID_BRUSHONLY})

				if tr.Hit then mpos = tr.HitPos + (eyePos - tr.HitPos):GetNormalized() end

				-- v2.3: только для выстрела - пуля идёт из дула в ту точку, куда смотрит прицел/перекрестие
				-- (при ПКМ - из камеры), поэтому не уходит вбок на любой дистанции.
				if self.hgShooting and Cfg.Converge then
					local camPos = (self:IsSighted() and not self.hgSightLegacy) and self:HGARC9_CamOrigin(eyePos, mpos, mang) or eyePos
					local filter = {owner, self}

					if IsValid(self.worldModel) then filter[#filter + 1] = self.worldModel end
					if IsValid(owner.wep) then filter[#filter + 1] = owner.wep end

					local ctr = util.TraceLine({start = camPos, endpos = camPos + mang:Forward() * 12000, filter = filter, mask = MASK_SHOT})

					if ctr.HitPos:DistToSqr(mpos) > 30 * 30 then
						mang = (ctr.HitPos - mpos):Angle()
					end
				end
			end
		end

		if nomodify then return mpos, mang end

		return LocalToWorld(self.addPos or vector_origin, self.addAng or angle_zero, mpos, mang)
	end

	-- Лог выстрелов на сервере: hg_arc9_shotlog 1 (консоль сервера) - куда реально ушла пуля относительно взгляда.
	function SWEP:FireBullet()
		self.hgShooting = true

		local ok, res = pcall(self.HGARC9_FireBullet, self)

		self.hgShooting = false

		if not ok then error(res, 0) end

		return res
	end

	function SWEP:HGARC9_FireBullet()
		if SERVER and HGARC9.ShotLog and HGARC9.ShotLog:GetBool() then
			local ply = self:GetOwner()

			if IsValid(ply) and ply:IsPlayer() then
				local pos, ang = self:GetTrace()
				local eye = ply:EyeAngles()
				local lp = WorldToLocal(pos, ang, ply:EyePos(), eye)
				local _, la = WorldToLocal(vector_origin, ang, vector_origin, eye)

				local text = string.format("[HG-ARC9] выстрел %s (%s): дуло от глаз fwd %.1f left %.1f up %.1f | направление vs взгляд p %.2f y %.2f | eyeAim %s",
					self:GetClass(), ply:Nick(), lp.x, lp.y, lp.z, math.NormalizeAngle(la.p), math.NormalizeAngle(la.y), tostring(self:HGARC9_EyeAimActive(ply)))

				print(text)
				ply:PrintMessage(HUD_PRINTCONSOLE, text .. "\n")
			end
		end

		return BaseSWEP().FireBullet(self)
	end

	-- v2.2: камера при прицеливании (клиент).
	-- Было (salat_base): камера = дуло + SightPos в системе дула, SightPos.x считался от габарита модели.
	-- У моделей ARC9 габарит не равен длине оружия, а привязка к дулу делает глубину камеры зависимой от длины
	-- ствола и положения руки: камера уезжала за спину. Теперь камера стоит на линии ствола (zero parallax:
	-- пуля идёт в центр экрана) в точке, ближайшей к голове, + SightOfs. Глубина от модели не зависит.
	function SWEP:Camera(ply, origin, angles, fov)
		local pos, ang = self:GetTrace(true)
		local _, anglef = self:GetTrace()

		local sighted = self:IsSighted()

		self.hgLerpAim = LerpFT(0.1, self.hgLerpAim or 0, sighted and 1 or 0)

		local neworigin

		if self.hgSightLegacy or not self:HGARC9_EyeAimActive(ply) then
			neworigin = LocalToWorld(self.SightPos, self.SightAng or angle_zero, pos, ang)
		else
			neworigin = self:HGARC9_CamOrigin(origin, pos, ang)
		end

		origin = LerpVector(self.hgLerpAim, origin, neworigin)

		local animpos = math.max(self:LastShootTime() - CurTime() + 0.1, 0) * 20

		origin = origin + anglef:Forward() * animpos
		origin = origin + anglef:Right() * math.Rand(-0.1, 0.1) * (animpos / 200) + anglef:Up() * math.Rand(-0.1, 0.1) * (animpos / 200)

		self.hgAddFov = LerpFT(0.1, self.hgAddFov or 0, sighted and -(self.addfov or 20) or 0)

		return origin, angles, fov + self.hgAddFov
	end

	-- Отдача: salat_base вызывает это (клиент, владелец), если метод определён.
	-- eyeSpray применяется к углам камеры/прицела в SWEP:Step.
	function SWEP:ApplyEyeSpray()
		local clipSize = math.max(self.Primary.ClipSize or 1, 1)
		local f = math.max((self.ShootingSpray or 0) / clipSize, 0.35)

		self.eyeSpray = self.eyeSpray + Angle(
			-math.Rand(self.hgRecoilUp * 0.5, self.hgRecoilUp) * f,
			math.Rand(-self.hgRecoilSide, self.hgRecoilSide) * f,
			0
		)
	end

	if Cfg.Debug then
		Log(string.format("%s -> %s | %s | dmg %d | wait %.3f | clip %d | ammo %s | hold %s | %s", class, ProxyName(class), kind, dmg, shootWait, clip, ammo, hold, model))
	end

	return SWEP, ProxyName(class)
end

-- ============================ РЕГИСТРАЦИЯ ============================

function HGARC9.RegisterAll(strict)
	if not weapons.GetStored("arc9_base") then
		Log("ARC9 Weapon Base не найден - поддержка отключена.")

		return 0
	end

	if not weapons.GetStored("salat_base") then
		Log("salat_base не найден - это не Homigrad? Поддержка отключена.")

		return 0
	end

	local count = 0

	for _, t in ipairs(weapons.GetList()) do
		local class = t.ClassName

		if class and not HGARC9.Sources[class] and HGARC9.ShouldConvert(class) then
			local ok, SWEP, name = pcall(HGARC9.BuildProxy, class, strict)

			if ok and SWEP then
				weapons.Register(SWEP, name)

				HGARC9.Proxies[class] = name
				HGARC9.Sources[name] = class

				count = count + 1
			elseif not ok then
				ErrorNoHalt("[HG-ARC9] ошибка конвертации " .. tostring(class) .. ": " .. tostring(SWEP) .. "\n")
			end
		end
	end

	HGARC9.RegisteredCount = count
	Log("зарегистрировано Homigrad-версий ARC9-оружия: " .. count)

	return count
end

local function FirstPass()
	HGARC9.RegisterAll(false)
end

local function SecondPass()
	-- Homigrad-патроны гарантированно зарегистрированы: проверяем и чиним
	HGARC9.RegisterAll(true)
end

hook.Add("PostGamemodeLoaded", "HGARC9_Register", FirstPass)
hook.Add("InitPostEntity", "HGARC9_RegisterStrict", function() timer.Simple(0, SecondPass) end)

-- Ручная перезагрузка Lua (lua_openscript / refresh) - GAMEMODE уже существует
if GAMEMODE then timer.Simple(0, SecondPass) end

concommand.Add("hg_arc9_reload", function(ply)
	if SERVER and IsValid(ply) and not ply:IsSuperAdmin() then return end

	include("hg_arc9/sh_config.lua")
	Cfg = HGARC9.Config

	HGARC9.RegisterAll(true)
end)

concommand.Add("hg_arc9_list", function(ply)
	if SERVER and IsValid(ply) and not ply:IsAdmin() then return end

	local out = {}

	for src, proxy in pairs(HGARC9.Proxies) do
		out[#out + 1] = proxy .. "   <-   " .. src
	end

	table.sort(out)

	local text = "[HG-ARC9] Homigrad-версий: " .. #out .. "\n" .. table.concat(out, "\n") .. "\n"

	if SERVER and IsValid(ply) then
		ply:PrintMessage(HUD_PRINTCONSOLE, text)
	else
		Msg(text)
	end
end)
