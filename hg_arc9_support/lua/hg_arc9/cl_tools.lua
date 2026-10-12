--[[
    Клиентская часть Homigrad x ARC9 Support.

    1) Страховка: оригинальное ARC9-оружие не рисует вьюмодель (в хомиграде её нет).
    2) Инструменты подбора положения Homigrad-версии ARC9-пушки:

       hg_arc9_tune 1        - включить режим подгонки (на активном оружии)
       hg_arc9_tune_load     - загрузить текущие значения оружия в параметры
       hg_arc9_t_sx/sy/sz    - камера при прицеливании: SightOfs (v2.2: x вперёд, y влево, z вверх от линии ствола);
                               у пушек со старой схемой (SightPos в Overrides / AutoSight=false) - SightPos
       hg_arc9_t_f/r/u       - смещение модели в руке вперёд / вправо / вверх
       hg_arc9_t_af/ar/au    - поворот модели в руке (вокруг Forward / Right / Up)
       hg_arc9_t_rf          - hgRoll: доп. крен оружия в руке (градусы, 0 = ровно)
       hg_arc9_t_pp/py/pr    - addAng: поправка направления выстрела (pitch / yaw / roll)
       hg_arc9_t_ox/oy/oz    - addPos: сдвиг точки дула (вперёд / вправо / вверх)
       hg_arc9_debug 1       - на экране: поворот оружия относительно взгляда и разброс за 1 сек
       hg_arc9_recalib       - пересчитать позу руки активного оружия
       hg_arc9_flip [ось]    - развернуть ось ствола (без аргумента: -ось; или x, -x, y, -y, z, -z)
       hg_arc9_dump          - вывести готовый блок для sh_config.lua (HGARC9.Overrides)
       hg_arc9_state         - диагностика клиента: дуло, ось, камера относительно глаз (пришли вывод при багах)
       hg_arc9_sv_state      - то же для сервера (команда выполняется на сервере, вывод в твоей консоли)

    Чтобы значения применились и на сервере (положение модели у других игроков,
    оружие в рэгдолле), вставь выведенный блок в lua/hg_arc9/sh_config.lua.
]]

-- ---------- 1. страховка ----------

hook.Add("PreDrawViewModel", "HGARC9_HideOriginalVM", function(vm, ply, wep)
	if IsValid(wep) and HGARC9.Proxies[wep:GetClass()] then return true end
end)

-- ---------- 2. подгонка ----------

local cv_tune = CreateClientConVar("hg_arc9_tune", "0", false, false, "Режим подгонки ARC9-оружия в хомиграде", 0, 1)

local keys = {"sx", "sy", "sz", "f", "r", "u", "af", "ar", "au", "pp", "py", "pr", "ox", "oy", "oz", "rf"}
local cv = {}

for _, k in ipairs(keys) do
	cv[k] = CreateClientConVar("hg_arc9_t_" .. k, "0", false, false)
end

local function ActiveProxy()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	local wep = ply:GetActiveWeapon()
	if IsValid(wep) and HGARC9.Sources[wep:GetClass()] then return wep end
end

-- v2.2: какой вектор сейчас редактируют sx/sy/sz
local function SightVec(wep)
	if wep.hgSightLegacy then return wep.SightPos or Vector(0, 0, 0), "SightPos" end

	return wep.SightOfs or Vector(0, 0, 0), "SightOfs"
end

local function Load(wep)
	local s = SightVec(wep)

	cv.sx:SetFloat(s.x)
	cv.sy:SetFloat(s.y)
	cv.sz:SetFloat(s.z)

	cv.f:SetFloat(wep.dwmForward or 0)
	cv.r:SetFloat(wep.dwmRight or 0)
	cv.u:SetFloat(wep.dwmUp or 0)
	cv.af:SetFloat(wep.dwmAForward or 0)
	cv.ar:SetFloat(wep.dwmARight or 0)
	cv.au:SetFloat(wep.dwmAUp or 0)

	local a = wep.addAng or angle_zero
	local o = wep.addPos or vector_origin

	cv.pp:SetFloat(a.p)
	cv.py:SetFloat(a.y)
	cv.pr:SetFloat(a.r)
	cv.ox:SetFloat(o.x)
	cv.oy:SetFloat(o.y)
	cv.oz:SetFloat(o.z)
	cv.rf:SetFloat(wep.hgRoll or 0)
end

concommand.Add("hg_arc9_tune_load", function()
	local wep = ActiveProxy()

	if not wep then
		print("[HG-ARC9] возьми в руки Homigrad-версию ARC9-пушки (hg_arc9_...)")

		return
	end

	Load(wep)
	print("[HG-ARC9] значения загружены из " .. wep:GetClass())
end)

local lastWep

hook.Add("Think", "HGARC9_Tune", function()
	if not cv_tune:GetBool() then
		lastWep = nil

		return
	end

	local wep = ActiveProxy()
	if not wep then return end

	-- при смене оружия подтягиваем его текущие значения, чтобы не затирать их чужими
	if lastWep ~= wep then
		lastWep = wep
		Load(wep)

		return
	end

	local sv = Vector(cv.sx:GetFloat(), cv.sy:GetFloat(), cv.sz:GetFloat())

	if wep.hgSightLegacy then wep.SightPos = sv else wep.SightOfs = sv end

	wep.dwmForward = cv.f:GetFloat()
	wep.dwmRight = cv.r:GetFloat()
	wep.dwmUp = cv.u:GetFloat()
	wep.dwmAForward = cv.af:GetFloat()
	wep.dwmARight = cv.ar:GetFloat()
	wep.dwmAUp = cv.au:GetFloat()

	wep.addAng = Angle(cv.pp:GetFloat(), cv.py:GetFloat(), cv.pr:GetFloat())
	wep.addPos = Vector(cv.ox:GetFloat(), cv.oy:GetFloat(), cv.oz:GetFloat())
	wep.hgRoll = cv.rf:GetFloat() -- поза руки пересчитается сама (меняется подпись калибровки)
end)

concommand.Add("hg_arc9_dump", function()
	local wep = ActiveProxy()

	if not wep then
		print("[HG-ARC9] возьми в руки Homigrad-версию ARC9-пушки (hg_arc9_...)")

		return
	end

	local src = HGARC9.Sources[wep:GetClass()]
	local s, sname = SightVec(wep)

	local function r(v) return math.Round(v or 0, 3) end

	print("-- вставь в lua/hg_arc9/sh_config.lua:")
	print(string.format("HGARC9.Overrides[\"%s\"] = {", src))
	print(string.format("\t%s = Vector(%s, %s, %s),", sname, r(s.x), r(s.y), r(s.z)))
	print(string.format("\tdwmForward = %s, dwmRight = %s, dwmUp = %s,", r(wep.dwmForward), r(wep.dwmRight), r(wep.dwmUp)))
	print(string.format("\tdwmAForward = %s, dwmARight = %s, dwmAUp = %s,", r(wep.dwmAForward), r(wep.dwmARight), r(wep.dwmAUp)))

	local a = wep.addAng or angle_zero
	local o = wep.addPos or vector_origin

	print(string.format("\taddAng = Angle(%s, %s, %s),", r(a.p), r(a.y), r(a.r)))
	print(string.format("\taddPos = Vector(%s, %s, %s),", r(o.x), r(o.y), r(o.z)))

	local ax = wep.hgAxis or Vector(1, 0, 0)

	if ax.x ~= 1 or ax.y ~= 0 or ax.z ~= 0 then print(string.format("\thgAxis = Vector(%d, %d, %d),", ax.x, ax.y, ax.z)) end

	if (wep.hgRoll or 0) ~= 0 then print(string.format("\thgRoll = %s,", r(wep.hgRoll))) end

	print("}")
end)

-- ---------- 3. диагностика позы ----------

concommand.Add("hg_arc9_recalib", function()
	local wep = ActiveProxy()

	if not wep then
		print("[HG-ARC9] возьми в руки Homigrad-версию ARC9-пушки (hg_arc9_...)")

		return
	end

	wep.hgLocalSig = nil
	local L = wep:HGARC9_GetHandAngle(LocalPlayer())

	if L then
		local B = wep.hgBAng or angle_zero

		print(string.format("[HG-ARC9] %s: B = (%.1f %.1f %.1f), localAngle = (%.1f %.1f %.1f)", wep:GetClass(), B.p, B.y, B.r, L.p, L.y, L.r))
	else
		print("[HG-ARC9] калибровка недоступна (AutoCalibrate = false, фейк или нет кости R_Hand)")
	end
end)

concommand.Add("hg_arc9_flip", function(_, _, args)
	local wep = ActiveProxy()

	if not wep then
		print("[HG-ARC9] возьми в руки Homigrad-версию ARC9-пушки (hg_arc9_...)")

		return
	end

	local names = {
		["x"] = Vector(1, 0, 0), ["-x"] = Vector(-1, 0, 0),
		["y"] = Vector(0, 1, 0), ["-y"] = Vector(0, -1, 0),
		["z"] = Vector(0, 0, 1), ["-z"] = Vector(0, 0, -1),
	}

	local ax = args[1] and names[string.lower(args[1])]

	if not ax then ax = -(wep.hgAxis or Vector(1, 0, 0)) end

	wep.hgAxis = ax
	wep.hgAxisDone = true
	wep.hgMuzzleLocal = nil -- кончик дула снова по габариту модели
	wep.hgLocalSig = nil

	print(string.format("[HG-ARC9] ось ствола %s: (%d %d %d). Если стало правильно, впиши в sh_config.lua:\n  HGARC9.Overrides[\"%s\"] = { hgAxis = Vector(%d, %d, %d) }", wep:GetClass(), ax.x, ax.y, ax.z, HGARC9.Sources[wep:GetClass()] or "?", ax.x, ax.y, ax.z))
end)

local cv_dbg = CreateClientConVar("hg_arc9_debug", "0", false, false, "Показать поворот ARC9-оружия в руке относительно взгляда", 0, 1)
local hist = {}

hook.Add("HUDPaint", "HGARC9_Debug", function()
	if not cv_dbg:GetBool() then return end

	local wep = ActiveProxy()
	local ply = LocalPlayer()
	if not wep or IsValid(ply.FakeRagdoll) then return end

	local pos, ang = wep:GetTransform()
	if not pos or not ang then return end

	-- поворот оружия в системе взгляда: при хорошей калибровке ≈ (0, 0, hgRoll) и не меняется
	local _, rel = WorldToLocal(vector_origin, ang, vector_origin, ply:EyeAngles())
	local now = CurTime()
	hist[#hist + 1] = {t = now, p = math.NormalizeAngle(rel.p), y = math.NormalizeAngle(rel.y), r = math.NormalizeAngle(rel.r)}

	while hist[1] and hist[1].t < now - 1 do table.remove(hist, 1) end

	local mn = {p = 1e9, y = 1e9, r = 1e9}
	local mx = {p = -1e9, y = -1e9, r = -1e9}

	for _, h in ipairs(hist) do
		for _, k in ipairs({"p", "y", "r"}) do
			mn[k] = math.min(mn[k], h[k])
			mx[k] = math.max(mx[k], h[k])
		end
	end

	local last = hist[#hist]
	local L = wep.localAngle or angle_zero
	local x, y = ScrW() * 0.02, ScrH() * 0.4

	draw.SimpleText(string.format("%s  | калибровка: %s", wep:GetClass(), wep.hgLocalAngle and "вкл" or "выкл"), "DermaDefault", x, y, color_white)
	draw.SimpleText(string.format("оружие vs взгляд: p %.1f  y %.1f  r %.1f", last.p, last.y, last.r), "DermaDefault", x, y + 16, color_white)
	draw.SimpleText(string.format("разброс за 1с:    p %.2f  y %.2f  r %.2f", mx.p - mn.p, mx.y - mn.y, mx.r - mn.r), "DermaDefault", x, y + 32, color_white)
	draw.SimpleText(string.format("localAngle: %.1f %.1f %.1f", L.p, L.y, L.r), "DermaDefault", x, y + 48, color_white)
end)

-- ---------- 4. диагностика v2.2 ----------

local function V(v) return string.format("%.1f %.1f %.1f", v.x, v.y, v.z) end
local function A(a) return string.format("%.2f %.2f %.2f", math.NormalizeAngle(a.p), math.NormalizeAngle(a.y), math.NormalizeAngle(a.r)) end

-- Клиентская диагностика. Все точки даны В СИСТЕМЕ ВЗГЛЯДА: fwd вперёд, left влево, up вверх от глаз.
concommand.Add("hg_arc9_state", function()
	local wep = ActiveProxy()
	local ply = LocalPlayer()

	if not wep then
		print("[HG-ARC9] возьми в руки Homigrad-версию ARC9-пушки (hg_arc9_...)")

		return
	end

	local eye, eyePos = ply:EyeAngles(), ply:EyePos()
	local mins, maxs = wep:GetModelBounds()
	local size = (mins and maxs) and (maxs - mins) or vector_origin
	local ax = wep.hgAxis or Vector(1, 0, 0)

	local function rel(p, a)
		local lp, la = WorldToLocal(p, a or angle_zero, eyePos, eye)

		return V(lp), A(la)
	end

	local mpos, mang = wep:HGARC9_ModelMuzzle()
	local tpos, tang = wep:GetTrace(true)
	local fpos, fang = wep:GetTrace()
	local mp, ma = rel(mpos, mang)
	local tp, ta = rel(tpos, tang)
	local fp, fa = rel(fpos, fang)

	print("===== [HG-ARC9] hg_arc9_state (КЛИЕНТ) =====")
	print(string.format("%s | src %s | модель %s", wep:GetClass(), tostring(HGARC9.Sources[wep:GetClass()]), tostring(wep.WorldModel)))
	print(string.format("вид: %s | kind %s | EyeAim %s | AutoSight %s | камера по старой схеме: %s", wep:IsSighted() and "ПРИЦЕЛ" or "от бедра", tostring(wep.hgKind), tostring(wep:HGARC9_EyeAimActive(ply)), tostring(HGARC9.Config.AutoSight), tostring(wep.hgSightLegacy)))
	print(string.format("hgAxis (%d %d %d) | hgMuzzleLocal %s | hgCenter %s | габарит %s", ax.x, ax.y, ax.z, wep.hgMuzzleLocal and V(wep.hgMuzzleLocal) or "нет (край габарита)", wep.hgCenter and V(wep.hgCenter) or "?", V(size)))
	print(string.format("взгляд: ang %s  | глаза %s", A(eye), V(eyePos)))
	print(string.format("дуло по модели (W*Ax):   pos [%s]  угол vs взгляд [%s]", mp, ma))
	print(string.format("GetTrace(true) (камера): pos [%s]  угол vs взгляд [%s]", tp, ta))
	print(string.format("GetTrace()  (пуля):      pos [%s]  угол vs взгляд [%s]", fp, fa))

	local L = wep.localAngle or angle_zero
	local B = wep.hgBAng or angle_zero

	print(string.format("localAngle (%s) | B (%s) | hgLocalAngle %s", A(L), A(B), wep.hgLocalAngle and A(wep.hgLocalAngle) or "нет"))

	-- сравнение камер: старая (от дула) и новая (на линии ствола)
	local oldcam = LocalToWorld(wep.SightPos or vector_origin, wep.SightAng or angle_zero, tpos, tang)
	local newcam = wep:HGARC9_CamOrigin(eyePos, tpos, tang)

	print(string.format("SightPos (старая) %s -> камера [%s]", V(wep.SightPos or vector_origin), (rel(oldcam))))
	print(string.format("SightOfs (новая)  %s -> камера [%s]", V(wep.SightOfs or vector_origin), (rel(newcam))))
	print("(ожидание: у новой схемы камера в пределах ~10 ед. от глаз; у старой при баге - далеко позади, fwd сильно отрицательный)")
end)
