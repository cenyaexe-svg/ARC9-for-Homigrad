--[[
    Серверная часть Homigrad x ARC9 Support.

    Если к игроку каким-то образом попало ОРИГИНАЛЬНОЕ ARC9-оружие
    (спавн-меню, ply:Give("arc9_xxx"), лут, админ-выдача, чужой аддон), оно заменяется
    на свою Homigrad-версию (hg_arc9_xxx) с сохранением патронов в магазине.
    Оригинал при этом ни разу не становится активным оружием, поэтому ARC9-код
    (viewmodel, TPIK, свой CalcView/HUD) не успевает ничего сломать.
]]

local Cfg = HGARC9.Config

-- Работает по классу и числу патронов, а НЕ по энтити: движок может удалить
-- заблокированное оружие сразу, и к моменту таймера энтити уже невалидна.
local function GiveProxy(ply, class, clip)
	local proxy = HGARC9.Proxies[class]
	if not proxy then return end
	if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end

	if ply:HasWeapon(proxy) then
		-- Уже есть такая же пушка: патроны из магазина отдаём запасом
		if clip and clip > 0 then
			local have = ply:GetWeapon(proxy)

			if IsValid(have) then ply:GiveAmmo(clip, have:GetPrimaryAmmoType(), true) end
		end

		return
	end

	local new = ply:Give(proxy)

	if not IsValid(new) then
		HGARC9.Log("не удалось выдать " .. proxy .. " игроку " .. ply:Nick() .. " (оружие не зарегистрировано или подбор запрещён)")

		return
	end

	if clip and clip >= 0 then new:SetClip1(math.min(clip, new:GetMaxClip1())) end

	if Cfg.Debug then HGARC9.Log("конвертировано: " .. class .. " -> " .. proxy .. " (" .. ply:Nick() .. ")") end
end

local function Schedule(ply, wep)
	local class = wep:GetClass()
	local clip = wep:Clip1()

	timer.Simple(0, function()
		GiveProxy(ply, class, clip)

		if IsValid(wep) then wep:Remove() end
	end)
end

-- Лучший вариант: блокируем подбор оригинала ещё до экипировки.
-- (Если хук хомиграда сработает раньше и вернёт true - сработает WeaponEquip ниже.)
hook.Add("PlayerCanPickupWeapon", "HGARC9_Convert", function(ply, wep)
	if not Cfg.AutoConvertPickup then return end
	if not IsValid(wep) or not HGARC9.Proxies[wep:GetClass()] then return end

	-- Лежащее в мире оружие подбирается по правилам хомиграда (E и взгляд) -
	-- заменим его после экипировки в WeaponEquip.
	if wep.Spawned then return end
	if wep.HGARC9_Converting then return false end

	wep.HGARC9_Converting = true

	Schedule(ply, wep)

	return false
end)

-- Запасной вариант: оригинал уже экипирован - тут же меняем на Homigrad-версию.
hook.Add("WeaponEquip", "HGARC9_Convert", function(wep, ply)
	if not Cfg.AutoConvertPickup then return end
	if not IsValid(wep) or not HGARC9.Proxies[wep:GetClass()] then return end
	if wep.HGARC9_Converting then return end

	wep.HGARC9_Converting = true

	Schedule(ply, wep)
end)

-- Тестовая выдача: hg_arc9_give <класс ARC9 или класс прокси>
concommand.Add("hg_arc9_give", function(ply, _, args)
	if IsValid(ply) and not ply:IsAdmin() then return end

	local class = args[1]
	if not class then return end

	local proxy = HGARC9.Proxies[class] or (HGARC9.Sources[class] and class)

	if not proxy then
		local msg = "[HG-ARC9] класс не найден: " .. class .. " (список: hg_arc9_list)"

		if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg .. "\n") else print(msg) end

		return
	end

	local target = IsValid(ply) and ply or nil

	if not target then
		for _, p in ipairs(player.GetAll()) do
			target = p

			break
		end
	end

	if IsValid(target) then
		local wep = target:Give(proxy)

		if IsValid(wep) then wep:SetClip1(wep:GetMaxClip1()) end
	end
end)

-- v2.2: серверная диагностика. Выполни в своей консоли: hg_arc9_sv_state (нужны права админа).
-- Вывод идёт в твою консоль и в консоль сервера. Сравни с клиентским hg_arc9_state: hgAxis, hgMuzzleLocal,
-- «дуло по модели» (у обычного игрока ожидается то же, что у клиента) и B/hgLocalAngle должны совпадать.
concommand.Add("hg_arc9_sv_state", function(ply)
	if not IsValid(ply) then return end
	if not ply:IsAdmin() then return end

	local wep = ply:GetActiveWeapon()

	if not IsValid(wep) or not HGARC9.Sources[wep:GetClass()] then
		ply:PrintMessage(HUD_PRINTCONSOLE, "[HG-ARC9] возьми в руки Homigrad-версию ARC9-пушки (hg_arc9_...)\n")

		return
	end

	local eye, eyePos = ply:EyeAngles(), ply:EyePos()

	local function V(v) return string.format("%.1f %.1f %.1f", v.x, v.y, v.z) end
	local function A(a) return string.format("%.2f %.2f %.2f", math.NormalizeAngle(a.p), math.NormalizeAngle(a.y), math.NormalizeAngle(a.r)) end

	local function rel(p, a)
		local lp, la = WorldToLocal(p, a or angle_zero, eyePos, eye)

		return V(lp), A(la)
	end

	local ax = wep.hgAxis or Vector(1, 0, 0)
	local mpos, mang = wep:HGARC9_ModelMuzzle()
	local fpos, fang = wep:GetTrace()
	local mp, ma = rel(mpos, mang)
	local fp, fa = rel(fpos, fang)

	local lines = {
		"===== [HG-ARC9] hg_arc9_sv_state (СЕРВЕР) =====",
		string.format("%s | EyeAim %s | InvalidateBoneCache %s", wep:GetClass(), tostring(wep:HGARC9_EyeAimActive(ply)), tostring(wep.InvalidateBoneCache ~= nil)),
		string.format("hgAxis (%d %d %d) | hgMuzzleLocal %s | hgCenter %s", ax.x, ax.y, ax.z, wep.hgMuzzleLocal and V(wep.hgMuzzleLocal) or "нет (край габарита)", wep.hgCenter and V(wep.hgCenter) or "?"),
		string.format("взгляд: ang %s | глаза %s", A(eye), V(eyePos)),
		string.format("дуло по модели (W*Ax): pos [%s]  угол vs взгляд [%s]", mp, ma),
		string.format("GetTrace() (пуля):     pos [%s]  угол vs взгляд [%s]", fp, fa),
		string.format("B (%s) | hgLocalAngle %s", A(wep.hgBAng or angle_zero), wep.hgLocalAngle and A(wep.hgLocalAngle) or "нет"),
		"(пуля у обычного игрока: угол vs взгляд должен быть 0 0 0)",
	}

	local text = table.concat(lines, "\n") .. "\n"

	ply:PrintMessage(HUD_PRINTCONSOLE, text)
	Msg(text)
end)
