--[[
    v2.6: подгонка высоты камеры при ПКМ (клиент).

    Почему прицел "кривой" у каждой пушки по-разному:
      1) высота прицельных планок над стволом у моделей разная (у ARC9-моделей до нескольких единиц);
      2) у моделей без аттачмента muzzle "линия ствола" берётся по центру габарита модели, а не по настоящему стволу,
         поэтому ошибка зависит от формы модели (магазин, приклад, оптика).
    Одно число на тип оружия (SightOfs.z по умолчанию) этого не покрывает.

    Команды:
      hg_arc9_autofit        - посчитать SightOfs.z по мешу модели (линия через мушку и целик), применить и вывести
      hg_arc9_sight dz [dy]  - сдвинуть камеру на dz вверх / dy влево (отрицательное - вниз / вправо), без hg_arc9_tune
                               пример: hg_arc9_sight -0.2   (оружие на экране выше -> камеру опустить)
      hg_arc9_dump           - (из cl_tools) вывести блок для sh_config.lua

    Совет: забинди nudge на клавиши:
      bind kp_plus  "hg_arc9_sight 0.1"
      bind kp_minus "hg_arc9_sight -0.1"
]]

local function ActiveProxy()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	local wep = ply:GetActiveWeapon()
	if IsValid(wep) and HGARC9.Sources and HGARC9.Sources[wep:GetClass()] then return wep end
end

local LAT = 1.3 -- ширина полосы вдоль оси ствола, в которой ищем мушку/целик

-- Возвращает z (высота камеры над линией ствола), либо nil, причина
function HGARC9.FitSight(wep, camBack)
	if not wep.WorldModel or wep.WorldModel == "" then return nil, "нет WorldModel" end

	local meshes = util.GetModelMeshes(wep.WorldModel, 0)
	if not meshes then return nil, "util.GetModelMeshes не вернул меш" end

	local ax = wep.hgAxis or Vector(1, 0, 0)
	local ang = ax:Angle()
	local f, u, r = ax, ang:Up(), ang:Right()

	local c = wep.hgCenter or vector_origin
	local h = wep.hgHalf or Vector(14, 0, 0)
	local tip = wep.hgMuzzleLocal or Vector(c.x + f.x * h.x, c.y + f.y * h.y, c.z + f.z * h.z)
	local len = 2 * (math.abs(f.x) * h.x + math.abs(f.y) * h.y + math.abs(f.z) * h.z)

	if len < 8 then return nil, "модель слишком короткая" end

	local sTip, hTip, lTip = tip:Dot(f), tip:Dot(u), tip:Dot(r)

	-- мушка: самая высокая точка у дула; целик: самая высокая точка в средней/задней части
	local fS, fH = nil, -math.huge
	local rS, rH = nil, -math.huge

	for _, m in ipairs(meshes) do
		for _, v in ipairs(m.triangles or {}) do
			local p = v.pos

			if math.abs(p:Dot(r) - lTip) <= LAT then
				local s, hh = p:Dot(f), p:Dot(u)
				local back = sTip - s -- расстояние от дула назад

				if hh > hTip - 1 then
					if back >= -0.5 and back <= len * 0.2 then
						if hh > fH then fH, fS = hh, s end
					elseif back >= len * 0.3 and back <= len * 0.8 then
						if hh > rH then rH, rS = hh, s end
					end
				end
			end
		end
	end

	if not fS or not rS then return nil, "не нашёл мушку/целик в полосе вдоль ствола" end
	if fS - rS < len * 0.15 then return nil, "мушка и целик слишком близко" end

	local slope = (fH - rH) / (fS - rS)

	-- где камера вдоль ствола (в координатах модели)
	local sCam

	if wep.hgSightLegacy then
		sCam = sTip + (wep.SightPos and wep.SightPos.x or -25)
	else
		sCam = sTip - camBack + (wep.SightOfs and wep.SightOfs.x or 0)
	end

	local hCam = rH + slope * (sCam - rS)
	local z = hCam - hTip

	return math.Clamp(z, -2, 8), string.format("мушка h=%.2f (%.1f от дула), целик h=%.2f (%.1f от дула), линия на камере h=%.2f, дуло h=%.2f", fH, sTip - fS, rH, sTip - rS, hCam, hTip)
end

local function SetZ(wep, z, y)
	if wep.hgSightLegacy then
		local o = wep.SightPos or Vector(0, 0, 0)
		wep.SightPos = Vector(o.x, y or o.y, z)
	else
		local o = wep.SightOfs or Vector(0, 0, 0)
		wep.SightOfs = Vector(o.x, y or o.y, z)
	end
end

concommand.Add("hg_arc9_autofit", function()
	local wep = ActiveProxy()
	local ply = LocalPlayer()

	if not wep then
		print("[HG-ARC9] возьми в руки Homigrad-версию ARC9-пушки (hg_arc9_...)")

		return
	end

	local pos, ang = wep:GetTrace(true)
	local camBack = (pos - ply:EyePos()):Dot(ang:Forward())
	local z, info = HGARC9.FitSight(wep, camBack)

	if not z then
		print("[HG-ARC9] автоподбор не удался: " .. tostring(info) .. ". Подгони вручную: hg_arc9_sight -0.2")

		return
	end

	SetZ(wep, z)

	print("[HG-ARC9] " .. wep:GetClass() .. ": " .. info)
	print(string.format("[HG-ARC9] %s = %.2f применено. Проверь ПКМ, добей hg_arc9_sight, затем hg_arc9_dump.", wep.hgSightLegacy and "SightPos.z" or "SightOfs.z", z))
end)

concommand.Add("hg_arc9_sight", function(_, _, args)
	local wep = ActiveProxy()

	if not wep then
		print("[HG-ARC9] возьми в руки Homigrad-версию ARC9-пушки (hg_arc9_...)")

		return
	end

	local dz, dy = tonumber(args[1]) or 0, tonumber(args[2]) or 0
	local o = wep.hgSightLegacy and (wep.SightPos or Vector(0, 0, 0)) or (wep.SightOfs or Vector(0, 0, 0))

	SetZ(wep, o.z + dz, o.y + dy)

	print(string.format("[HG-ARC9] %s: z %.2f, y %.2f (вверх = камера выше = оружие на экране ниже)", wep:GetClass(), o.z + dz, o.y + dy))
end)
