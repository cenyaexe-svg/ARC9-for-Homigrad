--[[
    Готовые пресеты прицела (подгонка колёсиком, hg_arc9_save). Ключ - класс ИСХОДНОГО ARC9-оружия.
    Сюда вставляется содержимое hg_arc9_presets.txt. Поля попадают в HGARC9.Overrides, не перезаписывая то, что уже
    задано вручную в sh_config.lua.
]]

HGARC9 = HGARC9 or {}

HGARC9.Presets = HGARC9.Presets or {
	["arc9_cod2019_ar_ak47"] = {
		SightOfs = Vector(-2, -0.08, 2.26),
		hgSightDir = Vector(1, 0, -0.0063),
	},
	["arc9_cod2019_ar_an94"] = {
		SightOfs = Vector(-2, -0.14, 2.3),
		hgSightDir = Vector(1, 0, 0.0091),
	},
	["arc9_cod2019_ar_asval"] = {
		SightOfs = Vector(-2, -0.1, 1.1),
		hgSightDir = Vector(1, 0, -0.0049),
	},
	["arc9_cod2019_ar_cr56amax"] = {
		SightOfs = Vector(-2, -0.02, 2.34),
		hgSightDir = Vector(1, 0, -0.0035),
	},
	["arc9_cod2019_ar_fal"] = {
		SightOfs = Vector(-2, -0.06, 2.16),
		hgSightDir = Vector(1, 0, -0.0024),
	},
	["arc9_cod2019_ar_famas"] = {
		SightOfs = Vector(-2, -0.06, 5.1),
		hgSightDir = Vector(1, 0, 0.0052),
	},
	["arc9_cod2019_ar_grau556"] = {
		SightOfs = Vector(-2, -0.18, 2.12),
		hgSightDir = Vector(1, 0, 0.0035),
	},
	["arc9_cod2019_ar_kilo141"] = {
		SightOfs = Vector(-2, -0.04, 3.3),
		hgSightDir = Vector(1, 0, 0),
	},
	["arc9_cod2019_ar_m13"] = {
		SightOfs = Vector(-2, 0.02, 2.54),
		hgSightDir = Vector(1, 0, -0.0038),
	},
	["arc9_cod2019_ar_m4"] = {
		SightOfs = Vector(-2, 0.02, 2.68),
		hgSightDir = Vector(1, 0, -0.0007),
	},
	["arc9_cod2019_ar_oden"] = {
		SightOfs = Vector(-2, -0.06, 3.52),
		hgSightDir = Vector(1, 0, 0.0031),
	},
	["arc9_cod2019_ar_ram7"] = {
		SightOfs = Vector(-2, -0.06, 2.4),
	},
	["arc9_cod2019_ar_scar"] = {
		SightOfs = Vector(-2, 0.04, 3.58),
		hgSightDir = Vector(1, 0, -0.0007),
	},
	["arc9_cod2019_la_m32"] = {
		SightOfs = Vector(-2, 0.14, 2.6),
		hgSightDir = Vector(-1, 0, 0),
	},
	["arc9_cod2019_la_pila"] = {
		SightOfs = Vector(-2, 3.15, 3.73),
		hgSightDir = Vector(-1, 0, -0.0079),
	},
	["arc9_cod2019_la_rpg"] = {
		SightOfs = Vector(-2, 0.22, 1.66),
		hgSightDir = Vector(-0.9996, 0, -0.0279),
	},
	["arc9_cod2019_la_strela"] = {
		SightOfs = Vector(-2, 3.85, 1),
		hgSightDir = Vector(-0.9999, 0, -0.0105),
	},
	["arc9_cod2019_lm_bruenmk9"] = {
		SightOfs = Vector(-2, 0.16, 2.78),
		hgSightDir = Vector(-1, 0, 0.0077),
	},
	["arc9_cod2019_lm_finn"] = {
		SightOfs = Vector(-2, 0.1, 2.78),
		hgSightDir = Vector(-1, 0, -0.0031),
	},
	["arc9_cod2019_lm_holger"] = {
		SightOfs = Vector(-2, 0.08, 2.74),
		hgSightDir = Vector(-1, 0, 0.0004),
	},
	["arc9_cod2019_lm_m91"] = {
		SightOfs = Vector(-2, 0.08, 3.8),
		hgSightDir = Vector(-1, 0, 0.0017),
	},
	["arc9_cod2019_lm_mg34"] = {
		SightOfs = Vector(-2, 0.08, 2.18),
		hgSightDir = Vector(-1, 0, -0.0017),
	},
	["arc9_cod2019_lm_minigun"] = {
		SightOfs = Vector(-2, 1.84, 1.4),
	},
	["arc9_cod2019_lm_pkm"] = {
		SightOfs = Vector(-2, 0.08, 3.02),
		hgSightDir = Vector(-1, 0, -0.0003),
	},
	["arc9_cod2019_lm_raal"] = {
		SightOfs = Vector(-2, 0.18, 4.12),
		hgSightDir = Vector(-1, 0, -0.0014),
	},
	["arc9_cod2019_lm_sa86"] = {
		SightOfs = Vector(-2, 0.1, 3.94),
		hgSightDir = Vector(-1, 0, 0.001),
	},
	["arc9_cod2019_mm_crossbow"] = {
		SightOfs = Vector(-2, 0, 3.1),
		hgSightDir = Vector(-1, 0, 0.0017),
	},
	["arc9_cod2019_mm_kar98k"] = {
		SightOfs = Vector(-2, 0.1, 0.55),
		hgSightDir = Vector(-0.9999, 0, -0.0148),
	},
	["arc9_cod2019_mm_m14"] = {
		SightOfs = Vector(-2, 0.1, 0.9),
		hgSightDir = Vector(-1, 0, 0),
	},
	["arc9_cod2019_mm_mk2"] = {
		SightOfs = Vector(-2, -0.15, 0.4),
		hgSightDir = Vector(-1, 0, -0.0026),
	},
	["arc9_cod2019_mm_sks"] = {
		SightOfs = Vector(-2, 0.1, 1.05),
		hgSightDir = Vector(-0.9997, 0, -0.0236),
	},
	["arc9_cod2019_mm_spr208"] = {
		SightOfs = Vector(-2, 0.16, 1),
		hgSightDir = Vector(-0.9998, 0, -0.0209),
	},
	["arc9_cod2019_pi_357"] = {
		SightOfs = Vector(0, 0.07, 1.35),
	},
	["arc9_cod2019_pi_357_akimbo"] = {
		SightOfs = Vector(0, 0.08, 1.34),
		hgSightDir = Vector(1, 0, 0.0003),
	},
	["arc9_cod2019_pi_50gs"] = {
		SightOfs = Vector(0, -0.2, 1.04),
		hgSightDir = Vector(-0.9999, 0, 0.0154),
	},
	["arc9_cod2019_pi_50gs_akimbo"] = {
		SightOfs = Vector(0, -0.2, 1.04),
		hgSightDir = Vector(-0.9999, 0, 0.0157),
	},
	["arc9_cod2019_pi_m19"] = {
		SightOfs = Vector(0, 0.06, 0.86),
		hgSightDir = Vector(1, 0, -0.0042),
	},
	["arc9_cod2019_pi_m1911"] = {
		SightOfs = Vector(0, 0.04, 0.56),
		hgSightDir = Vector(1, 0, -0.0087),
	},
	["arc9_cod2019_pi_m1911_akimbo"] = {
		SightOfs = Vector(0, 0.04, 0.52),
		hgSightDir = Vector(1, 0, -0.0052),
	},
	["arc9_cod2019_pi_m19_akimbo"] = {
		SightOfs = Vector(0, 0.06, 0.82),
		hgSightDir = Vector(1, 0, -0.0052),
	},
	["arc9_cod2019_pi_renetti"] = {
		SightOfs = Vector(0, 0.06, 0.74),
		hgSightDir = Vector(1, 0, -0.0073),
	},
	["arc9_cod2019_pi_renetti_akimbo"] = {
		SightOfs = Vector(0, 0.04, 0.74),
		hgSightDir = Vector(1, 0, -0.0021),
	},
	["arc9_cod2019_pi_sykov"] = {
		SightOfs = Vector(0, 0.08, 0.52),
		hgSightDir = Vector(1, 0, -0.0087),
	},
	["arc9_cod2019_pi_sykov_akimbo"] = {
		SightOfs = Vector(0, 0.08, 0.56),
		hgSightDir = Vector(1, 0, -0.0052),
	},
	["arc9_cod2019_pi_x16"] = {
		SightOfs = Vector(0, 0.08, 0.42),
		hgSightDir = Vector(1, 0, 0.0003),
	},
	["arc9_cod2019_pi_x16_akimbo"] = {
		SightOfs = Vector(0, 0.1, 0.42),
		hgSightDir = Vector(1, 0, -0.001),
	},
	["arc9_cod2019_sh_725"] = {
		SightOfs = Vector(-2, 0.1, 0.75),
		hgSightDir = Vector(-0.9998, 0, 0.0199),
	},
	["arc9_cod2019_sh_jak12"] = {
		SightOfs = Vector(-2, 0.1, 3.35),
		hgSightDir = Vector(-1, 0, -0.0017),
	},
	["arc9_cod2019_sh_model680"] = {
		SightOfs = Vector(-2, 0.07, 0.5),
		hgSightDir = Vector(-1, 0, -0.0045),
	},
	["arc9_cod2019_sh_origin12"] = {
		SightOfs = Vector(-2, 0.07, 2.64),
		hgSightDir = Vector(-1, 0, 0.0002),
	},
	["arc9_cod2019_sh_r90"] = {
		SightOfs = Vector(-2, 0.1, 3.7),
		hgSightDir = Vector(-1, 0, -0.0035),
	},
	["arc9_cod2019_sh_vlk"] = {
		SightOfs = Vector(-2, 0.1, 0.65),
		hgSightDir = Vector(-1, 0, 0.0061),
	},
	["arc9_cod2019_sm_aug"] = {
		SightOfs = Vector(-2, 0.02, 2.48),
		hgSightDir = Vector(0.9999, 0, -0.0157),
	},
	["arc9_cod2019_sm_bizon"] = {
		SightOfs = Vector(-2, -0.08, 1.5),
		hgSightDir = Vector(-0.9999, 0, -0.0105),
	},
	["arc9_cod2019_sm_cx9"] = {
		SightOfs = Vector(-2, -0.14, 1.34),
		hgSightDir = Vector(-0.9994, 0, -0.0342),
	},
	["arc9_cod2019_sm_iso"] = {
		SightOfs = Vector(-2, 0.04, 2.52),
		hgSightDir = Vector(-1, 0, 0.0035),
	},
	["arc9_cod2019_sm_mp5"] = {
		SightOfs = Vector(-2, -0.08, 1.94),
		hgSightDir = Vector(0.9998, 0, -0.0206),
	},
	["arc9_cod2019_sm_mp7"] = {
		SightOfs = Vector(-2, 0.08, 1.36),
		hgSightDir = Vector(-1, 0, -0.0077),
	},
	["arc9_cod2019_sm_p90"] = {
		SightOfs = Vector(-2, -0.16, 3.98),
		hgSightDir = Vector(0.9999, 0, -0.014),
	},
	["arc9_cod2019_sm_striker45"] = {
		SightOfs = Vector(-2, 0.12, 2.44),
		hgSightDir = Vector(-1, 0, -0.0028),
	},
	["arc9_cod2019_sm_uzi"] = {
		SightOfs = Vector(-2, 0.16, 1.32),
		hgSightDir = Vector(-1, 0, -0.0056),
	},
	["arc9_cod2019_sm_vector"] = {
		SightOfs = Vector(-2, 0.12, 1.36),
		hgSightDir = Vector(-1, 0, -0.0024),
	},
	["arc9_cod2019_sn_ax50"] = {
		SightOfs = Vector(-2, 0.12, 2.6),
		hgSightDir = Vector(-1, 0, -0.0021),
	},
	["arc9_cod2019_sn_hdr"] = {
		SightOfs = Vector(-2, 0.12, 1.24),
	},
	["arc9_cod2019_sn_rytec"] = {
		SightOfs = Vector(-2, 0.1, 1.9),
	},
	["arc9_cod2019_sn_svd"] = {
		SightOfs = Vector(-2, 0.08, 0.46),
		hgSightDir = Vector(-0.9998, 0, -0.0188),
	},
}

HGARC9.Overrides = HGARC9.Overrides or {}

for class, preset in pairs(HGARC9.Presets) do
	local ov = HGARC9.Overrides[class] or {}

	for k, v in pairs(preset) do
		if ov[k] == nil then ov[k] = v end
	end

	HGARC9.Overrides[class] = ov
end
