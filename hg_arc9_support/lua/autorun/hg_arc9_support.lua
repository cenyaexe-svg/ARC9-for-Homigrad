--[[
    Homigrad x ARC9 Support - загрузчик.
    Все настройки: lua/hg_arc9/sh_config.lua
]]

HGARC9 = HGARC9 or {}

if SERVER then
	AddCSLuaFile("hg_arc9/sh_config.lua")
	AddCSLuaFile("hg_arc9/sh_core.lua")
	AddCSLuaFile("hg_arc9/sh_presets.lua")
	AddCSLuaFile("hg_arc9/cl_presets.lua")
	AddCSLuaFile("hg_arc9/cl_muzzle.lua")
	AddCSLuaFile("hg_arc9/cl_tools.lua")
	AddCSLuaFile("hg_arc9/cl_sightfit.lua")
end

include("hg_arc9/sh_config.lua")
include("hg_arc9/sh_presets.lua")
include("hg_arc9/sh_core.lua")

if SERVER then
	include("hg_arc9/sv_convert.lua")
else
	include("hg_arc9/cl_tools.lua")
	include("hg_arc9/cl_sightfit.lua")
	include("hg_arc9/cl_presets.lua")
	include("hg_arc9/cl_muzzle.lua")
end
