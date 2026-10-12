--[[
    v2.8: РУЧНАЯ ПОДГОНКА ПРИЦЕЛА КОЛЁСИКОМ + ПРЕСЕТЫ ПО ОРУЖИЮ (клиент).

    Забинди в консоли (один раз):
      bind mwheelup   "hg_arc9_wheel 1"
      bind mwheeldown "hg_arc9_wheel -1"
      bind <клавиша>  "hg_arc9_mode"      -- переключение режима: вертикаль -> горизонталь -> наклон оружия
      bind <клавиша>  "hg_arc9_step"      -- шаг: 0.02 / 0.05 / 0.1 / 0.25 / 0.5 / 1
      bind <клавиша>  "hg_arc9_save"      -- сохранить пресет текущего оружия
    Вернуть колёсико на смену оружия:
      bind mwheelup invprev
      bind mwheeldown invnext

    Работа: возьми пушку, зажми ПКМ, крути колесо. Режимы:
      1 ВЕРТИКАЛЬ   - колесо вверх = камера выше (оружие на экране ниже), вниз = камера ниже
      2 ГОРИЗОНТАЛЬ - колесо вверх = камера правее (оружие на экране левее), вниз = левее
      3 НАКЛОН      - колесо вверх = ствол вверх (мушка на экране выше). Нужен, когда мушка и целик стоят
                      друг на друге, но весь прицел выше/ниже перекрестия: это наклон линии прицеливания,
                      сдвигом камеры его не убрать.
    Инвертировать направление колеса: hg_arc9_wheel_invert 1.

    Пресеты пишутся в garrysmod/data/hg_arc9_presets.json (для игры) и hg_arc9_presets.txt (готовый
    текст для sh_presets.lua - его присылай мне). Сохранённые пресеты применяются сами при взятии оружия в руки.

    hg_arc9_presets        - показать все сохранённые
    hg_arc9_preset_clear   - удалить пресет текущего оружия
    hg_arc9_hud 0/1        - плашка с режимом и значениями
]]

local FILE_JSON, FILE_TXT = "hg_arc9_presets.json", "hg_arc9_presets.txt"

local cv_inv = CreateClientConVar("hg_arc9_wheel_invert", "0", true, false)
local cv_hud = CreateClientConVar("hg_arc9_hud", "1", true, false)

local MODES = {"ВЕРТИКАЛЬ камеры", "ГОРИЗОНТАЛЬ камеры", "НАКЛОН оружия (ствол вверх/вниз)"}
local STEPS = {0.02, 0.05, 0.1, 0.25, 0.5, 1}
local mode, stepIdx = 1, 3
local lastUse = 0

local presets = {}

local function LoadPresets()
	local raw = file.Read(FILE_JSON, "DATA")

	presets = raw and util.JSONToTable(raw) or {}
end

LoadPresets()

local function ActiveProxy()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	local wep = ply:GetActiveWeapon()
	if IsValid(wep) and HGARC9.Sources and HGARC9.Sources[wep:GetClass()] then return wep end
end

local function R(v) return math.Round(v or 0, 4) end

local function VecName(wep)
	return wep.hgSightLegacy and "SightPos" or "SightOfs"
end

local function GetVec(wep)
	return wep[VecName(wep)] or Vector(0, 0, 0)
end

-- пока крутим - автоподбор не должен перезаписывать значения
local function Claim(wep)
	wep.hgUserOfs = true
end

-- ---------- применение сохранённых пресетов ----------

local applied = setmetatable({}, {__mode = "k"})

local function ApplyPreset(wep, p)
	Claim(wep)

	local v = p.v
	wep[p.kind == "SightPos" and "SightPos" or "SightOfs"] = Vector(v.x, v.y, v.z)

	wep.hgSightDir = p.dir and Vector(p.dir.x, p.dir.y, p.dir.z) or nil
end

hook.Add("Think", "HGARC9_PresetApply", function()
	local wep = ActiveProxy()
	if not wep or applied[wep] then return end

	applied[wep] = true

	local p = presets[HGARC9.Sources[wep:GetClass()]]
	if p then ApplyPreset(wep, p) end
end)

-- ---------- колесо / режимы ----------

concommand.Add("hg_arc9_wheel", function(_, _, args)
	local wep = ActiveProxy()
	if not wep then return end

	local dir = tonumber(args[1]) or 0
	if dir == 0 then return end

	if cv_inv:GetBool() then dir = -dir end

	local st = STEPS[stepIdx]

	Claim(wep)
	applied[wep] = true -- не перезатирать пресетом то, что крутим сейчас

	if mode == 3 then
		local d = wep.hgSightDir or wep.hgAxis or Vector(1, 0, 0)
		local a = d:Angle()

		a.p = a.p + dir * st
		wep.hgSightDir = a:Forward()
	else
		local name = VecName(wep)
		local v = GetVec(wep)

		if mode == 1 then
			wep[name] = Vector(v.x, v.y, v.z + dir * st)
		else
			wep[name] = Vector(v.x, v.y - dir * st, v.z) -- вверх = камера правее (y - влево)
		end
	end

	lastUse = CurTime()
end)

concommand.Add("hg_arc9_mode", function(_, _, args)
	local n = tonumber(args[1])

	mode = (n and MODES[n]) and n or (mode % #MODES + 1)
	lastUse = CurTime()

	print("[HG-ARC9] режим: " .. MODES[mode])
end)

concommand.Add("hg_arc9_step", function(_, _, args)
	local n = tonumber(args[1])

	if n then
		for i, s in ipairs(STEPS) do
			if math.abs(s - n) < 1e-6 then stepIdx = i end
		end
	else
		stepIdx = stepIdx % #STEPS + 1
	end

	lastUse = CurTime()

	print("[HG-ARC9] шаг: " .. STEPS[stepIdx])
end)

-- ---------- сохранение ----------

local function WriteFiles()
	file.Write(FILE_JSON, util.TableToJSON(presets, true))

	local keys = table.GetKeys(presets)
	table.sort(keys)

	local out = {"-- hg_arc9 пресеты прицела (вставь в lua/hg_arc9/sh_presets.lua, внутри HGARC9.Presets)"}

	for _, k in ipairs(keys) do
		local p = presets[k]
		local v = p.v

		out[#out + 1] = string.format("\t[\"%s\"] = {", k)
		out[#out + 1] = string.format("\t\t%s = Vector(%s, %s, %s),", p.kind, R(v.x), R(v.y), R(v.z))

		if p.dir then out[#out + 1] = string.format("\t\thgSightDir = Vector(%s, %s, %s),", R(p.dir.x), R(p.dir.y), R(p.dir.z)) end

		out[#out + 1] = "\t},"
	end

	file.Write(FILE_TXT, table.concat(out, "\n") .. "\n")
end

concommand.Add("hg_arc9_save", function()
	local wep = ActiveProxy()

	if not wep then
		print("[HG-ARC9] возьми в руки Homigrad-версию ARC9-пушки (hg_arc9_...)")

		return
	end

	local src = HGARC9.Sources[wep:GetClass()]
	local v = GetVec(wep)
	local d = wep.hgSightDir

	presets[src] = {
		kind = VecName(wep),
		v = {x = R(v.x), y = R(v.y), z = R(v.z)},
		dir = d and {x = R(d.x), y = R(d.y), z = R(d.z)} or nil,
	}

	WriteFiles()

	print(string.format("[HG-ARC9] сохранён пресет %s: %s = Vector(%s, %s, %s)%s", src, VecName(wep), R(v.x), R(v.y), R(v.z), d and string.format(", hgSightDir = Vector(%s, %s, %s)", R(d.x), R(d.y), R(d.z)) or ""))
	print("[HG-ARC9] файлы: garrysmod/data/" .. FILE_JSON .. " и " .. FILE_TXT)

	lastUse = CurTime()
end)

concommand.Add("hg_arc9_presets", function()
	LoadPresets()

	local n = 0

	for k, p in SortedPairs(presets) do
		n = n + 1
		print(string.format("%s: %s (%s, %s, %s)%s", k, p.kind, R(p.v.x), R(p.v.y), R(p.v.z), p.dir and (" dir (" .. R(p.dir.x) .. ", " .. R(p.dir.y) .. ", " .. R(p.dir.z) .. ")") or ""))
	end

	print("[HG-ARC9] пресетов: " .. n)
end)

concommand.Add("hg_arc9_preset_clear", function()
	local wep = ActiveProxy()
	if not wep then return end

	local src = HGARC9.Sources[wep:GetClass()]

	presets[src] = nil
	WriteFiles()

	print("[HG-ARC9] пресет удалён: " .. src .. " (вступит в силу после перезахода/hg_arc9_reload)")
end)

-- ---------- плашка ----------

hook.Add("HUDPaint", "HGARC9_PresetHUD", function()
	if not cv_hud:GetBool() or CurTime() - lastUse > 10 then return end

	local wep = ActiveProxy()
	if not wep then return end

	local v = GetVec(wep)
	local d = wep.hgSightDir
	local src = HGARC9.Sources[wep:GetClass()]
	local x, y = ScrW() * 0.02, ScrH() * 0.55

	local lines = {
		{src, color_white},
		{"режим: " .. MODES[mode] .. "   шаг: " .. STEPS[stepIdx], Color(120, 255, 120)},
		{string.format("%s: x %.2f  y %.2f  z %.2f", VecName(wep), v.x, v.y, v.z), color_white},
		{d and string.format("наклон: dir %.4f %.4f %.4f", d.x, d.y, d.z) or "наклон: нет", color_white},
		{presets[src] and "пресет сохранён (hg_arc9_save - перезаписать)" or "пресет не сохранён (hg_arc9_save)", presets[src] and Color(120, 200, 255) or Color(255, 200, 100)},
	}

	for i, l in ipairs(lines) do
		draw.SimpleTextOutlined(l[1], "DermaDefault", x, y + (i - 1) * 16, l[2], TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, color_black)
	end
end)
