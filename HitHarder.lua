------------------------
-- HitHarder
-- by afterFriday
-- Show real combat log and summary; Share your Damage with others.
------------------------
require "string"
require "table"
require "math"
require "lib/lib_math"
require "lib/lib_InterfaceOptions"
require "lib/lib_Slash"
require "lib/lib_TextFormat"
require "lib/lib_MovablePanel"
require "lib/lib_Tooltip"
require "./lib/oldSlider"
require "lib/lib_ChatLib"
require "./lib/oldCheckBox"
require "lib/lib_Callback2"
--Constant
local c_ver = 0.71
local c_request = "hH^q"
local c_result = "hH^r"
local c_update = "hH^u"
local c_Endcap = ChatLib.GetEndcapString()
local c_PairBreak			= "|"
local c_DataBreak			= "&"
local c_NumberBreak			= "$"
local c_NumberLength		= 8	--for separately compress entityId 

local c_wl_width = 100
local c_summary_width = 450
local c_PixelsPerScroll = 18
local c_ScrollSpeed = 0.01
local c_DividerSolidPct = 0.3
--Global Tables
local g_combine = {}			--OnHit Integration Table, combine datas who who have same time, target and value together.
local g2_target = {}				--Saved Target information, including damage/heal in/out of self and sync records.
local g2_sum = {}				--Saved Target Summary table, 
local g_unknown = {}			--target who can't get info by Game.GetTargetInfo(entityId), will ask again when OnEntityVitalsChanged mention them.
local g_update_notified = nil

--Global Variable
local g_ScrollAmount = 0
local g_tab = 0
local g_ScrollBarVisible = nil
local g_trim_time = 0			--Trim Time, in order to use System.GetClientTime() to replace System.GetDate()
local g_detial_pos = 1
local g_detial_height = 18
local g_sync_height = 18
local g_detial_num = 0
local g_update_notify_callback = nil
local g_sum={
	visible = nil,
}
local g_wl={
	width = c_wl_width,
	visible = nil,
	height = 18
}
local g_WhiteList = {			--preserved
		{name = "Kanaloa", checked = true},
		{name = "Baneclaw", checked = true},
		{name = "Necronus", checked = true},
		{name = "Melding Shard", checked = true},
		{name = "Melding Tornado Core", checked = true},
}
local g_sync = nil -- Current sync target
local g_feed={
	upcoming = {},
	feeding = nil,	
	period = 3, 	--feeding period, seconds
}

--default setting
local settings = {
	enabled = true,
	debug = false,
	auto_sync = true,
	auto_show = true,
	summary_font = "Demi_8",
	max_saved_summary = 100,
	damage_texture = "Aluminium",
	sync_texture = "Aluminium",
	send_my_result = true,
	show_result = true,
	sample_rate = 1,
	show_short_id = false,
}

--Frames
local SUMMARY_FRAME = Component.GetFrame("Summary_frame")
local SUMMARY_TITLE = Component.GetWidget("Summary_frame_title")
local SUMMARY_TITLE_TEXT = Component.GetWidget("Summary_frame_title_TitleText")
local SUMMARY_TITLE_BORDER = SUMMARY_TITLE:GetChild("border")
local SUMMARY_DATA_LOCAL_GROUP = Component.GetWidget("Summary_frame_local_group")
local SUMMARY_DATA_LOCAL = Component.GetWidget("Summary_Local_List")
local SUMMARY_DATA_SYNC_GROUP = Component.GetWidget("Summary_frame_sync_group")
local SUMMARY_DATA_SYNC = Component.GetWidget("Summary_Sync_List")

local SUMMARY_DATA_WL_GROUP = Component.GetWidget("Summary_frame_wl_group")
local SUMMARY_DATA_WL = Component.GetWidget("Summary_Wl_List")
local WL_INPUT = Component.GetWidget("Summary_frame_wl_group.SearchInput")
local WL_ADD_INPUT = WL_INPUT:GetChild("bg.TextInput")
local SUMMARY_BODY = Component.GetWidget("Summary_frame_body")
local SUMMARY_BODY_BORDER = SUMMARY_BODY:GetChild("border")
local SUMMARY_LOCAL_SLIDER = Slider.Create(SUMMARY_BODY, "vertical")
local SUMMARY_SYNC_SLIDER = Slider.Create(SUMMARY_BODY, "vertical")
local SUMMARY_WHITELIST_SLIDER = Slider.Create(Component.GetWidget("Summary_frame_wl_group.OptionsGroup"), "vertical")

local TOOLTIP_FRAME = Component.GetFrame("Tooltip_Frame")
local TOOLTIP_DATA = {}


local WL_BUTTON = Component.GetWidget("wl_btn")
local DMG_BUTTON = Component.GetWidget("dmg_btn")
local CLOSE_BUTTON = Component.GetWidget("close_btn")
local CLR_BUTTON = Component.GetWidget("clr_btn")

local WL_ADD_BTN = WL_INPUT:GetChild("ClearSearchButton")

local SUMMARY_DATA = {}
local SUMMARY_SYNC_DATA = {}
local WL_CHECKBOX = {}
local df = {}


local CB2_UpdateHit = Callback2.Create()
-----------------------------
--Common Functions
-----------------------------
local function msgg(msg)
	Component.GenerateEvent("MY_SYSTEM_MESSAGE", {text="HH : " .. tostring(msg)})
end

local function debugg(msg)
	if not settings.debug then return end
	Component.GenerateEvent("MY_SYSTEM_MESSAGE", {text="HH-debugg : " .. msg})
end

local function SaveConfig()
	Component.SaveSetting("g_WhiteList", g_WhiteList)
end

function Create_Target_info(entityId,raw_target)
	raw_target = raw_target or Game.GetTargetInfo(entityId)
	if not raw_target then
		raw_target = {entityId = entityId}
		g_unknown[tostring(entityId)] = tonumber(System.GetClientTime())
	end
	local vitals = Game.GetTargetVitals(entityId)
	target = {
		entityId = entityId,
		name = raw_target.name,
		level = raw_target.level,
		isplayer = (raw_target.type and raw_target.type =="character" and not raw_target.isNpc),
		MaxHealth = vitals and vitals.MaxHealth,
	}
	return target
end

function Get_PureName()
	if not g_name then
		local name, faction, race, sex, id = Player.GetInfo()
		get,_,rn = string.find(name,"[[].*[]] (.*)")
		g_name = get and rn or name
	end
	return g_name
end

function Pack_Data(ttl_dmg_out, entityId, name, level, MaxHealth)
	local str = Get_PureName() .. c_DataBreak .. Compress_Number(ttl_dmg_out) .. c_DataBreak .. Compress_Number(entityId) .. c_DataBreak .. name .. c_DataBreak .. level .. c_DataBreak .. Compress_Number(MaxHealth)
	return str
	--return tostring(data)
end

function UnPack_Data(str)
	_,_,a,b,c,d,e,f = string.find(str,"(.*)"..c_DataBreak.."(.*)"..c_DataBreak.."(.*)"..c_DataBreak.."(.*)"..c_DataBreak.."(.*)"..c_DataBreak.."(.*)")
	b = tonumber(Decompress_Number(b))
	c = Decompress_Number(c)
	f = tonumber(Decompress_Number(f))
	local data = {
		sender = a,
		d_out = b,
		target = {
			entityId = c,
			name = d,
			level = e,
			MaxHealth = f,
		}
	}
	return data
	--return jsontotable(str)
end

function Compress_Number(num)
	local n = num
	local a = {}
	repeat
		local p1 = string.sub(n,-c_NumberLength,-1)
		local p2 = string.sub(n,1, -(c_NumberLength+1))
		table.insert(a,p1)
		n = p2
	until not n or n == ""
	local st = ""
	for i=#a,1,-1 do
		if st=="" then
			st = _math.Base10ToBaseN(a[i], 64)
		else
			st = st .. c_NumberBreak .. _math.Base10ToBaseN(a[i], 64)
		end
	end
	return st
	--return _math.Base10ToBaseN(num, 64)
	--return num
end
function Fill_Zero(str,length)
	if length > string.len(str) then
		repeat
			str = "0"..str
		until length == string.len(str)

	end
	return str
end
function Decompress_Number(num)
	local res = {};
	for m in string.gmatch(num, "([^"..c_NumberBreak.."]+)") do
		table.insert(res, m)
	end	
	local res2 = ""
	for i,v in ipairs(res) do
		if i==1 then
			res2 = _math.BaseNToBase10(v, 64)
		else
			res2 = res2 .. Fill_Zero(_math.BaseNToBase10(v, 64),c_NumberLength)
		end
	end
	return res2
	--return _math.BaseNToBase10(num, 64)
	--return num
end

-----------------------------
--White List Functions
-----------------------------
function CreateCheckBox(name, action, do_check, catId) --referenced from Inventory.lua
	local CAT_CHOICE = {GROUP=Component.CreateWidget("OptionsChoicePrint", SUMMARY_DATA_WL)}
	CAT_CHOICE.GROUP:SetDims("left:0; right:100%; top:0; height:"..g_wl.height)
	CAT_CHOICE.CHECKBOX = CheckBox.Create(CAT_CHOICE.GROUP:GetChild("ChoiceGroup"))
	CAT_CHOICE.CHECKBOX:AddHandler("OnStateChanged", action)
	CAT_CHOICE.CHECKBOX:SetDims("left:0; width:23; height:23; top:0")
	CAT_CHOICE.CHECKBOX.BACKDROP:SetDims("height:14; width:14; center-y:50%; center-x:50%")
	CAT_CHOICE.CHECKBOX.BORDER:SetTexture("DialogWidgets", "checkbox")
	CAT_CHOICE.CHECKBOX.CHECK:SetTexture("DialogWidgets", "check")
	CAT_CHOICE.CHECKBOX.CHECK:SetDims("height:13; width:13; center-x:50%; center-y:50%")
	CAT_CHOICE.CHECKBOX:SetCheck(do_check)
	CAT_CHOICE.CHECKBOX:AddHandler("OnStateChanged", function()
		local chk = CAT_CHOICE.CHECKBOX:GetCheck()
		local id = tonumber(CAT_CHOICE.CHECKBOX.GROUP:GetTag())
		g_WhiteList[id].checked = chk
		ReBuild_Local_Data()
		SaveConfig()
	end)	

	CAT_CHOICE.FOCUS = CAT_CHOICE.GROUP:GetChild("Text"):GetChild("Focus")
	CAT_CHOICE.FOCUS:BindEvent("OnMouseEnter", function() CAT_CHOICE.CHECKBOX:OnMouseEnter() end)
	CAT_CHOICE.FOCUS:BindEvent("OnMouseLeave", function() CAT_CHOICE.CHECKBOX:OnMouseLeave() end)
	CAT_CHOICE.FOCUS:BindEvent("OnMouseDown", function() CAT_CHOICE.CHECKBOX:OnMouseDown() end)
	CAT_CHOICE.FOCUS:BindEvent("OnMouseUp", function() CAT_CHOICE.CHECKBOX:OnMouseUp() end)

	-- del Button
	CAT_CHOICE.DELETE = CAT_CHOICE.GROUP:GetChild("delete")
	CAT_CHOICE.DELETE:BindEvent("OnMouseDown", function(args)
		OnRemove_WL(tonumber(CAT_CHOICE.CHECKBOX.GROUP:GetTag()))
	end);
	local X = CAT_CHOICE.DELETE:GetChild("X")
	CAT_CHOICE.DELETE:BindEvent("OnMouseEnter", function()
		X:ParamTo("tint", Component.LookupColor("red"), 0.15);
		X:ParamTo("glow", "#30991111", 0.15)
	end);
	CAT_CHOICE.DELETE:BindEvent("OnMouseLeave", function()
		X:ParamTo("tint", Component.LookupColor("white"), 0.15)
		X:ParamTo("glow", "#00000000", 0.15)
	end);
	if catId then
		CAT_CHOICE.CHECKBOX.GROUP:SetTag(tonumber(catId))
	end

	CAT_CHOICE.TEXT = CAT_CHOICE.GROUP:GetChild("Text")
	CAT_CHOICE.TEXT:SetText(name)

	local text_dims = CAT_CHOICE.TEXT:GetTextDims().width+75
	if text_dims > g_wl.width then
		g_wl.width = text_dims
	end
	g_wl.visible = not g_wl.visible
	return CAT_CHOICE
end

function OnAdd_WL(name,checked)
	if not name or name=="" then debugg("no name") end
	table.insert(g_WhiteList,{name=name,checked=checked})
	add_WL(#g_WhiteList)
	Update_Scroll()
	ReBuild_Local_Data()
	SaveConfig()
end

function add_WL(idx)
	idx = tonumber(idx)
	if not idx or not g_WhiteList[idx] then debugg(" no g_WhiteList["..tostring(idx).."]") end
	local checked = g_WhiteList[idx].checked
	local name = g_WhiteList[idx].name
	WL_CHECKBOX[idx] = CreateCheckBox(name, function(CHECK)
		g_WhiteList[idx].checked = CHECK.checked
	end, checked, idx)
end

function OnRemove_WL(idx)

	idx = tonumber(idx)
	local su
	if idx == #g_WhiteList and idx > 12 then su = true end
	if g_WhiteList[idx] then table.remove(g_WhiteList,idx) end

	for i=#WL_CHECKBOX,1,-1 do
		remove_WL(i)
	end
	
	g_wl.width = c_wl_width
	for i,CAT in ipairs(g_WhiteList) do
		add_WL(i)
	end
	
	Update_Scroll()
	ReBuild_Local_Data()
	SaveConfig()
end

function remove_WL(idx)
	idx = tonumber(idx)
	if not idx then debugg("remove_WL: idx is nil") return end
	if WL_CHECKBOX[idx] and WL_CHECKBOX[idx].GROUP then
		WL_CHECKBOX[idx].CHECKBOX:Destroy()
		Component.RemoveWidget(WL_CHECKBOX[idx].GROUP)
		table.remove(WL_CHECKBOX,idx)
	end
end
--PVP
function IsInWhiteList(target)
	if not target or not target.name then return nil end
	for i,v in pairs(g_WhiteList) do
		if (( string.lower(v.name) == string.lower("pvp") and target.isplayer) or
			string.lower(target.name) == string.lower(v.name) or
			string.lower(v.name) == string.lower("all")
			) and v.checked then
			return true
		end
	end
	return nil
end

-----------------------------
-- Damage-out Sync Tab Functions
-----------------------------
function Create_Sync_Data(name,entityId)
	local DATA = {}
	DATA.entityId = entityId
	DATA.name = name
	DATA.GROUP = Component.CreateWidget("Data_Group", SUMMARY_DATA_SYNC)
	DATA.GROUP:SetDims("top:_; width:100%; height:"..tostring(g_sync_height))
	DATA.NAME_TEXT_SHADOW = DATA.GROUP:GetChild("name_text"):GetChild("text_shadow")
	DATA.NAME_TEXT = DATA.GROUP:GetChild("name_text"):GetChild("text")
	DATA.DAMAGE_TEXT_SHADOW = DATA.GROUP:GetChild("damage_text"):GetChild("text_shadow")
	DATA.DAMAGE_TEXT = DATA.GROUP:GetChild("damage_text"):GetChild("text")
	DATA.BAR = DATA.GROUP:GetChild("dmg_bar_grp")
	DATA.BAR:GetChild("dmg_bar"):SetParam("tint", Random_Color())
	DATA.BAR:GetChild("dmg_bar"):SetTexture("BAR_"..settings.sync_texture)
	DATA.FOCUS = DATA.GROUP:GetChild("focus")
	DATA.NAME_TEXT:SetTextColor("#ffffff")
	DATA.NAME_TEXT_SHADOW:SetTextColor("#000000")
	DATA.DAMAGE_TEXT:SetTextColor("#ffffff")
	DATA.DAMAGE_TEXT_SHADOW:SetTextColor("#000000")
	DATA.FOCUS:BindEvent("OnScroll", Update_Scroll)
	DATA.FOCUS:BindEvent("OnRightMouse", function(args) end)
	DATA.FOCUS:BindEvent("OnMouseEnter", function(args) end)
	DATA.FOCUS:BindEvent("OnMouseLeave", function(args) end)
	DATA.GROUP:Show(true)
	table.insert(SUMMARY_SYNC_DATA,DATA)
	Update_Sync_Data(DATA)
end

function Destroy_Sync_Data()
	for idx=#SUMMARY_SYNC_DATA,1,-1 do
		SUMMARY_SYNC_DATA[idx].data = nil
		Component.RemoveWidget(SUMMARY_SYNC_DATA[idx].GROUP)
		table.remove(SUMMARY_SYNC_DATA, idx)
	end
end

function OnUpdate_Sync_Data(name)
	local target = g2_target[g_sync]
	if not target or not target.sync or not target.sync[name] then return end
	-- Update Current Sync data
	for i,DATA in ipairs(SUMMARY_SYNC_DATA) do
		if DATA.name == name then
			Update_Sync_Data(DATA)
			return
		end
	end
	-- Create New Sync data
	Create_Sync_Data(name,g_sync)
	Update_Scroll()
end
function Update_Sync_Data(DATA)
	local name = DATA.name
	local target = g2_target[DATA.entityId]
	Shadow_Text(DATA.NAME_TEXT, DATA.NAME_TEXT_SHADOW, name)
	local dmg_out = target.sync[name]
	if target.MaxHealth then
		local pct = tostring( math.min(math.floor(dmg_out*1000/tonumber(target.MaxHealth))/10))
		DATA.BAR:MoveTo("left:0; width:"..pct.."%",0.1)
		Shadow_Text(DATA.DAMAGE_TEXT, DATA.DAMAGE_TEXT_SHADOW, _math.MakeReadable(dmg_out) .. " / " .. tostring(pct) .. "%" )
	else
		Shadow_Text(DATA.DAMAGE_TEXT, DATA.DAMAGE_TEXT_SHADOW, _math.MakeReadable(dmg_out))
	end
end
function ReBuild_Sync_Data(entityId)
	Destroy_Sync_Data()
	g_sync = entityId
	local target = g2_target[entityId]
	if target.sync then
		for name,d_out in pairs(target.sync) do
			Create_Sync_Data(name,entityId)
		end
	end
	Update_Scroll()
	if target.MaxHealth then
		SUMMARY_TITLE_TEXT:SetText((target.packed and "~" or "")..(target.name or "Unknown") .. " / "..tostring(target.MaxHealth) .. ShortId(entityId))
	else
		SUMMARY_TITLE_TEXT:SetText((target.packed and "~" or "")..(target.name or "Unknown").. ShortId(entityId))
	end
end


-----------------------------
-- Damage-out Tab Functions
-----------------------------
function Pack_Local_Data()
	debugg("Pack_Local_Data")
	local pt = tostring(System.GetClientTime())
	for i,entityId in ipairs(g2_sum) do
		if g2_target[entityId] and not g2_target[entityId].packed then
			local p_entityId =entityId.."#"..pt
			g2_sum[i] = p_entityId
			g2_target[p_entityId] = g2_target[entityId]
			g2_target[entityId] = nil
			g2_target[p_entityId].packed = pt
			g2_target[p_entityId].entityId = p_entityId
		end
	end
end
function Create_Local_Data(target)
	local DATA = {}
	DATA.entityId = target.entityId
	DATA.GROUP = Component.CreateWidget("Data_Group", SUMMARY_DATA_LOCAL)
	DATA.GROUP:SetDims("top:_; left:5; width:100%; height:"..tostring(g_detial_height))
	DATA.NAME_TEXT = DATA.GROUP:GetChild("name_text"):GetChild("text")
	DATA.NAME_TEXT_SHADOW = DATA.GROUP:GetChild("name_text"):GetChild("text_shadow")
	DATA.DAMAGE_TEXT = DATA.GROUP:GetChild("damage_text"):GetChild("text")
	DATA.DAMAGE_TEXT_SHADOW = DATA.GROUP:GetChild("damage_text"):GetChild("text_shadow")
	DATA.BAR = DATA.GROUP:GetChild("dmg_bar_grp")
	DATA.BAR:GetChild("dmg_bar"):SetParam("tint", target.bar_color)
	DATA.BAR:GetChild("dmg_bar"):SetTexture("BAR_"..settings.damage_texture)	
	DATA.NAME_TEXT:SetTextColor("#ffffff")
	DATA.NAME_TEXT_SHADOW:SetTextColor("#000000")
	DATA.DAMAGE_TEXT:SetTextColor("#ffffff")
	DATA.DAMAGE_TEXT_SHADOW:SetTextColor("#000000")
	DATA.FOCUS = DATA.GROUP:GetChild("focus")
	DATA.FOCUS:BindEvent("OnScroll", Update_Scroll)
	DATA.FOCUS:BindEvent("OnMouseDown", function(args) Send_Data(Compress_Number(DATA.entityId),c_request) ReBuild_Sync_Data(DATA.entityId) ShowTab(1) end)
	DATA.FOCUS:BindEvent("OnRightMouse", function(args) Send_Data(Compress_Number(DATA.entityId),c_request) ReBuild_Sync_Data(DATA.entityId) ShowTab(1) end)
	DATA.FOCUS:BindEvent("OnMouseEnter", function(args)
		local t = g2_target[DATA.entityId]
		if t.ttl_dmg_out and t.ttl_dmg_out > 0 and t.dmg_out then
			TOOLTIP_DATA.WIDGET = Component.CreateWidget("Tooltip", TOOLTIP_FRAME)
			TOOLTIP_DATA.LIST = TOOLTIP_DATA.WIDGET:GetChild("list_group.list")
			TOOLTIP_DATA.TEXT = {}
			local max_width = TOOLTIP_DATA.WIDGET:GetChild("title.text"):GetTextDims().width+10
			for typ,val in pairs(t.dmg_out) do
				local TEXT = Component.CreateWidget("Tooltip_list", TOOLTIP_DATA.LIST)
				local pct =  math.min(math.floor(val*1000/t.ttl_dmg_out)/10)
				TEXT:SetDims("width:100%;top:_;height:20")
				TEXT:GetChild("Text_left"):SetText(typ)
				TEXT:GetChild("Text_right"):SetText(val .. " / "..pct .. "%")
				table.insert(TOOLTIP_DATA.TEXT,TEXT)
				local w1 = TEXT:GetChild("Text_left"):GetTextDims().width
				local w2 = TEXT:GetChild("Text_right"):GetTextDims().width
				max_width = math.max( w1+w2+30, max_width)
			end
			TOOLTIP_DATA.WIDGET:SetDims("width:"..max_width..";top:0;height:"..(20*(#TOOLTIP_DATA.TEXT)+14))
			Tooltip.Show(TOOLTIP_DATA.WIDGET)
		end
	end)
	DATA.FOCUS:BindEvent("OnMouseLeave", function(args)
		if TOOLTIP_DATA.TEXT then
			for i=#TOOLTIP_DATA.TEXT,1,-1 do
				Component.RemoveWidget(TOOLTIP_DATA.TEXT[i])
			end
		end
		if TOOLTIP_DATA.WIDGET then
			Component.RemoveWidget(TOOLTIP_DATA.WIDGET)
		end
		Tooltip.Show(nil)
	end)
	DATA.GROUP:Show(true)
	Update_Local_Data(DATA,target)
	table.insert(SUMMARY_DATA,DATA)
end

function Shadow_Text(T1,T2,text)
	T1:SetText(text)
	T2:SetText(text)
end
function Update_Summary_Font()
	for _,DATA in ipairs(SUMMARY_DATA) do		--Update Frame
		DATA.NAME_TEXT:SetFont(settings.summary_font)
		DATA.NAME_TEXT_SHADOW:SetFont(settings.summary_font)
		DATA.DAMAGE_TEXT:SetFont(settings.summary_font)
		DATA.DAMAGE_TEXT_SHADOW:SetFont(settings.summary_font)
	end
	for _,DATA in ipairs(SUMMARY_SYNC_DATA) do		--Update Frame
		DATA.NAME_TEXT:SetFont(settings.summary_font)
		DATA.NAME_TEXT_SHADOW:SetFont(settings.summary_font)
		DATA.DAMAGE_TEXT:SetFont(settings.summary_font)
		DATA.DAMAGE_TEXT_SHADOW:SetFont(settings.summary_font)
	end
end
function Find_Local_Data(entityId)
	for i=#SUMMARY_DATA,1,-1 do		--Update Frame
		if SUMMARY_DATA[i].entityId == entityId then
			return SUMMARY_DATA[i]
		end
	end
end
function Update_Local_Data(DATA,target)
	local maxhp = target.MaxHealth
	local ttl_dmg_out = target.ttl_dmg_out or 0
	local level = target.level and "(" .. tostring(target.level) .. ")" or ""
	Shadow_Text(DATA.NAME_TEXT,DATA.NAME_TEXT_SHADOW,(target.packed and "~" or "")..(target.name or "Unknown")..level ..ShortId(target.entityId))
	if maxhp then
		local pct = math.floor((ttl_dmg_out / maxhp)*1000)/10
		Shadow_Text(DATA.DAMAGE_TEXT, DATA.DAMAGE_TEXT_SHADOW, _math.MakeReadable(ttl_dmg_out).." / ".. _math.MakeReadable(maxhp) .." / ".. pct .. "%")
		DATA.BAR:MoveTo("left:0; width:"..math.min(100,pct).."%",0.1)
	else
		Shadow_Text(DATA.DAMAGE_TEXT, DATA.DAMAGE_TEXT_SHADOW, _math.MakeReadable(ttl_dmg_out))				
	end
end
function OnUpdate_Local_Data(target)
	local entityId = target.entityId
	if not IsInWhiteList(target) then return end

	local is_new = true
	for idx=#g2_sum,1,-1 do
		if g2_sum[idx] == entityId then
			is_new = false
		end
	end
	if is_new then
		--Add data
		target.bar_color = Random_Color() --set color on generated.
		table.insert(g2_sum, entityId)	
		g2_target[entityId] = target
		CheckMaxSummarySize()
		--Add Frame data
		Create_Local_Data(target)
		Update_Scroll()
	else
		for k,v in pairs(target) do		--Update data
			if k=="sync" then
				for name,val in pairs(v) do
					g2_target[entityId][name] = val
				end
			elseif k~="dmg_out" and k~="ttl_dmg_out" then
				g2_target[entityId][k] = g2_target[entityId][k] or v
			end
		end
		local DATA = Find_Local_Data(entityId)
		if DATA then Update_Local_Data(DATA,g2_target[entityId]) end
	end
end

function Random_Color()
	local function get_rgb()
		return ttl,r,g,b
	end
	local r,g,b
	repeat
		r,g,b = math.random(110,235),math.random(110,235),math.random(110,235)
	until r+g+b > 400 and r+g+b < 600
	local color = string.format("#%02X%02X%02X", r, g, b)
	return tostring(color)
end

function ReBuild_Local_Data()
	for idx=#SUMMARY_DATA,1,-1 do
		SUMMARY_DATA[idx].data = nil
		Component.RemoveWidget(SUMMARY_DATA[idx].GROUP)
		table.remove(SUMMARY_DATA, idx)
	end
	for i,entityId in ipairs(g2_sum) do
		local target = g2_target[entityId]
		if IsInWhiteList(target) then
			Create_Local_Data(target)
		end
	end
	Update_Scroll()
end


-----------------------------
--Summary Frame Functions
-----------------------------
function ToggleSummary(show)
	g_sum.visible = show
	if ( show ) then
		ShowSummary()
	else
		HideSummary()
	end
end

function HideSummary()
	SUMMARY_TITLE_TEXT:ParamTo("alpha", 0, 0.2);
	SUMMARY_FRAME:ParamTo("alpha", 0, 0.2);
end

function ShowSummary()
	SUMMARY_TITLE_TEXT:ParamTo("alpha", 1, 0.2);
	SUMMARY_FRAME:ParamTo("alpha", 1, 0.2);
	SUMMARY_FRAME:Show(true);
	Update_Scroll()
end

function reset_summary()
	g2_target = {}
	g2_sum = {}
	ReBuild_Local_Data()
	Destroy_Sync_Data()
	ShowTab(0)
end

function ShowTab(tab)
	SUMMARY_BODY_BORDER:SetParam("alpha",1)
	tab = tab or 0
	g_tab = tab
	if g_tab~=2 then
		WL_BUTTON:GetChild("X"):ParamTo("tint", Component.LookupColor("white"), 0.15)
		WL_BUTTON:GetChild("X"):ParamTo("glow", "#00000000", 0.15)
	end
	if g_tab~=0 then
		DMG_BUTTON:GetChild("X"):ParamTo("tint", Component.LookupColor("white"), 0.15)
		DMG_BUTTON:GetChild("X"):ParamTo("glow", "#00000000", 0.15)
	end

	if tab==0 then
		SUMMARY_DATA_LOCAL_GROUP:Show(true)
		SUMMARY_DATA_SYNC_GROUP:Show(false)
		SUMMARY_DATA_WL_GROUP:Show(false)
		SUMMARY_TITLE_TEXT:SetText("Hit Harder")
	elseif tab==1 then
		SUMMARY_DATA_SYNC_GROUP:Show(true)
		SUMMARY_DATA_LOCAL_GROUP:Show(false)
		SUMMARY_DATA_WL_GROUP:Show(false)
	elseif tab==2 then
		SUMMARY_DATA_SYNC_GROUP:Show(false)
		SUMMARY_DATA_LOCAL_GROUP:Show(false)
		SUMMARY_DATA_WL_GROUP:Show(true)
	end
	Update_Scroll()
end

function Update_Scroll(args) -- used on Tabs and White List
	local amount = args and args.amount or 0
	local PARENT,SLIDER,LIST
	SUMMARY_LOCAL_SLIDER:Show(false)
	SUMMARY_SYNC_SLIDER:Show(false)
	SUMMARY_WHITELIST_SLIDER:Show(false)
	if g_tab == 0 then
		PARENT = SUMMARY_DATA_LOCAL_GROUP
		SLIDER = SUMMARY_LOCAL_SLIDER
		LIST = SUMMARY_DATA_LOCAL
	elseif g_tab==1 then
		PARENT = SUMMARY_DATA_SYNC_GROUP
		SLIDER = SUMMARY_SYNC_SLIDER
		LIST = SUMMARY_DATA_SYNC
	elseif g_tab==2 then
		PARENT = Component.GetWidget("Summary_frame_wl_group.OptionsGroup.group")
		SLIDER = SUMMARY_WHITELIST_SLIDER
		LIST = SUMMARY_DATA_WL
	end
	local view_height = PARENT:GetBounds().height	
	local InventoryHeight = LIST:GetLength()+2

	local diff = InventoryHeight - view_height
	if InventoryHeight > view_height then
		local steps = diff / c_PixelsPerScroll + 1
		SLIDER:SetScrollSteps(steps)
		SLIDER:SetJumpSteps(steps)
		SLIDER:SetParam("thumbsize", math.max(0.05, view_height/InventoryHeight))
		g_ScrollBarVisible = true
		SLIDER:Show(true)
		PARENT:MoveTo("top:0;bottom:100%;left:0;right:100%-10", c_ScrollSpeed)
		g_ScrollAmount = SLIDER:GetPercent() * diff
		local pct = (g_ScrollAmount + (amount * c_PixelsPerScroll)) / (diff)
		pct = math.min(1,math.max(0,pct))
		LIST:MoveTo("height:_; top:"..-(pct*diff), c_ScrollSpeed)
		SLIDER:SetPercent(pct)
	else
		g_ScrollBarVisible = false
		SLIDER:Show(false)
		PARENT:MoveTo("top:0;bottom:100%;left:0;right:100%", c_ScrollSpeed)
	end
end

-----------------------------
--Communication Core Functions
-----------------------------
function QueueFeed(target)
	for _,v in ipairs(g_WhiteList) do
		if string.lower(v.name) == string.lower(target.name) and v.checked then
			g_feed.upcoming[target.entityId] = true
			if not g_feed.feeding then g_feed.feeding=true callback(OnFeed,nil,0.1) end
			break
		end
	end
end

function OnFeed()
	for k,v in pairs(g_feed.upcoming) do
		if v then
			Feed(k)
			g_feed.upcoming[k]=nil
			g_feed.feeding=true
			callback(OnFeed,nil,g_feed.period)
			return
		end
	end
	g_feed.feeding=nil
end

function Feed(entityId)
	local target = g2_target[entityId]
	if target and target.ttl_dmg_out and target.name and target.level and target.MaxHealth then
		Send_Data(Pack_Data(target.ttl_dmg_out, entityId, target.name, target.level, target.MaxHealth),c_result)
	end
end

function Send_Data(data,link)
	local msg = c_Endcap..link..c_PairBreak..data..c_Endcap
	if Platoon.IsInPlatoon() then
		Chat.SendChannelText("platoon", msg)
	elseif Squad.IsInSquad() then
		Chat.SendChannelText("squad", msg)
	else
		--Chat.SendChannelText("zone", msg)
	end
end

function CheckMaxSummarySize()
	if #g2_sum > settings.max_saved_summary then
		repeat
			for idx=1,#SUMMARY_DATA do
				if SUMMARY_DATA[idx].entityId == g2_sum[1] then
					Component.RemoveWidget(SUMMARY_DATA[idx].GROUP)
					table.remove(SUMMARY_DATA, idx)
					Update_Scroll()
					break
				end
			end
			g2_target[g2_sum[1]] = nil
			table.remove(g2_sum,1)
		until not (#g2_sum > settings.max_saved_summary)
	end
end

function Handle_Link(args)
	if not settings.enabled then return end
	local link_type = args.link_type
	local data = args.link_data
	local author = args.author
	if link_type == c_request and settings.send_my_result then
		Feed(Decompress_Number(data))
	elseif link_type == c_result and settings.show_result then
		local result = UnPack_Data(data)
		local entityId = result.target.entityId
		if IsInWhiteList(result.target) then
			local target = g2_target[entityId]
			if target then
				target.name = target.name or result.target.name
				target.level = target.level or result.target.level
				target.MaxHealth = target.MaxHealth or result.target.MaxHealth
			else
				target = result.target
			end
			target.sync = target.sync or {}
			target.sync[result.sender] = result.d_out
			OnUpdate_Local_Data(target)
			if g_sync and g_sync == entityId then
				OnUpdate_Sync_Data(result.sender)
			else
				if settings.auto_sync then
					if settings.auto_show then
						ToggleSummary(true)
					end
					ReBuild_Sync_Data(entityId)
					OnUpdate_Sync_Data(result.sender)
					ShowTab(1)
				end			
			end
			
		end
	elseif link_type == c_update then
		local latest = tonumber(data)
		if c_ver < latest then
			if not g_update_notified or g_update_notified < latest then
				g_update_notified = latest
				msgg("Newer version of HitHarder (v"..tostring(latest)..") was found, please update your HitHarder (v"..tostring(c_ver)..").")
			end
		end
	end
end

function ShortId(entityId)
	return (settings.show_short_id and "::" .. string.sub(entityId,-5) or "")
end
-----------------------------
--Event Functions
-----------------------------
function OnHit(args)
	if not settings.enabled then return end
	if not args or args.damage <=0 then return end
	if not args.damageType and not args.type then return end
	local entityId = tostring(args.entityId)
	local type = args.damageType or args.type
	if args.damage >500000 then
		msgg("ignore an over 500000 damage out: ".. tostring(args.damage))
		--msgg("debug targetinfo=".. (g2_target[entityId] and tostring(g2_target[entityId]) or tostring(Game.GetTargetInfo(entityId))) )
		--msgg("debug args=".. (tostring(args)))
		return
	end

	if g_combine[entityId] then
		g_combine[entityId].total_damage = g_combine[entityId].total_damage + args.damage
		g_combine[entityId].damage = g_combine[entityId].damage or {}
		g_combine[entityId].damage[type] = (g_combine[entityId].damage[type] or 0) + args.damage
		debugg("OnHit, Combine ("..tostring(System.GetClientTime()))
	else
		g_combine[entityId] = {
			client_time = tonumber(System.GetClientTime()),
			total_damage = args.damage,
			damage = {
				[type] = args.damage
			}
		}
		debugg("OnHit, New ("..tostring(System.GetClientTime()))
	end
end

function Hit()
	for entityId,info in pairs(g_combine) do
		if info and ( (info.client_time+200) < tonumber(System.GetClientTime()) ) then
			--recorded target info
			local target
			if not g2_target[entityId] then	
				debugg("new target")
				target = Create_Target_info(entityId)
			else
				target = g2_target[entityId]
				local vitals = Game.GetTargetVitals(entityId)
				target.MaxHealth = vitals and vitals.MaxHealth
			end
			target.ttl_dmg_out = (target.ttl_dmg_out or 0) + info.total_damage
			for type,damage in pairs(info.damage) do
				target.dmg_out = target.dmg_out or {}
				target.dmg_out[type] = (target.dmg_out[type] or 0) + info.damage[type]
			end
			if IsInWhiteList(target) then
				OnUpdate_Local_Data(target)
				QueueFeed(g2_target[target.entityId]) --Feeding
			else
			
			end
			--Update_Details_Data(info,target)
			g_combine[entityId] = nil
			return
		end
	end
end

function OnEscape()
	Component.SetInputMode("cursor")
	Component.SetInputMode(nil)
end

function OnHudShow(args)
	if args.show and g_sum.visible and settings.enabled then
		ShowSummary()
	elseif not args.show then
		HideSummary()
	end
end

function OnEntityVitalsChanged(args)
	local entityId = tostring(args.entityId)
	if not entityId then return end
	if g_unknown[entityId] then
		debugg("OnEntityVitalsChanged, found g_unknown ("..tostring(System.GetClientTime()))
		if g_unknown[entityId] + 10000 < tonumber(System.GetClientTime()) then
			g_unknown[entityId] = nil
		else
			local raw_target = Game.GetTargetInfo(entityId)
			if raw_target then
				local target = Create_Target_info(entityId,raw_target)
				for k,v in pairs(target) do
					if g2_target[entityId] then
						g2_target[entityId][k] = v
					end
				end
				if IsInWhiteList(target) then
					g2_target[entityId] = target
					local DATA = Find_Local_Data(entityId)
					if DATA then Update_Local_Data(DATA,g2_target[entityId]) end
					QueueFeed(g2_target[entityId])									--Feeding
				end
				g_unknown[entityId] = nil
			end
		end
	end
end

function OnPlayerReady()
	CB2_UpdateHit = Callback2.CreateCycle(Hit)
	CB2_UpdateHit:Run(0.1)
end

function OnEnterZone()
	Pack_Local_Data()
	ReBuild_Local_Data()
end

function OnSpawn(args)
	Pack_Local_Data()
	ReBuild_Local_Data()
end

function OnComponentLoad()
	local fonts = {
		"UbuntuRegular_8","UbuntuRegular_9","UbuntuRegular_10","UbuntuRegular_11",
		"UbuntuBold_8","UbuntuBold_9","UbuntuBold_10","UbuntuBold_11","UbuntuBold_12","UbuntuBold_13","UbuntuBold_15","UbuntuBold_20",
		"Demi_8","Demi_9","Demi_10","Demi_11","Narrow_8","Narrow_9","Narrow_10","Narrow_11","Narrow_12",
		"Wide_7","Wide_8","Wide_9","Wide_10","Demi_9o","Demi_12o",
		"UbuntuMedium_8o","UbuntuMedium_9o","RB_Narrow_10B","RB_Narrow_11B","RB_Regular_10","RB_Wide_10B","RB_Wide_11B",
	}
	local textures = {"Aluminium","BantoBar","Glaze2","Gloss","Graphite","Grid","Healbot","LiteStep","Minimalist","normTex","Otravi","Perl","Round","Smooth",}
	SUMMARY_LOCAL_SLIDER:SetDims("top:2;bottom:100%-2;right:100%-2; width:7")
	SUMMARY_LOCAL_SLIDER:BindEvent("OnStateChanged", Update_Scroll)
	SUMMARY_LOCAL_SLIDER:Show(false)
	SUMMARY_SYNC_SLIDER:SetDims("top:2;bottom:100%-2;right:100%-2; width:7")
	SUMMARY_SYNC_SLIDER:BindEvent("OnStateChanged", Update_Scroll)
	SUMMARY_SYNC_SLIDER:Show(false)
	SUMMARY_WHITELIST_SLIDER:SetDims("top:2; bottom:100%-2; width:7; right:100%-2")
	SUMMARY_WHITELIST_SLIDER:BindEvent("OnStateChanged", Update_Scroll)
	SUMMARY_WHITELIST_SLIDER:Show(false)
	
	InterfaceOptions.StartGroup({label="Version ".. c_ver})
	InterfaceOptions.AddCheckBox({id="ENABLED" , label="Enable addon", default=settings.enabled})
	InterfaceOptions.AddCheckBox({id="DEBUG" , label="Debug mode", default=settings.debug})
	InterfaceOptions.AddCheckBox({id="SHOW_SHORT_ID" , label="Show target's short id(for debug)", default=settings.show_short_id})
	InterfaceOptions.StopGroup({})
	InterfaceOptions.AddCheckBox({id="SEND_MY_RESULT" , label="Send my damage out data to other player", default=settings.send_my_result})
	InterfaceOptions.AddCheckBox({id="SHOW_RESULT" , label="Show other players' damage out data", default=settings.show_result})
	InterfaceOptions.AddCheckBox({id="AUTO_SYNC" , label="Auto Sync", default=settings.auto_sync})
	InterfaceOptions.AddCheckBox({id="AUTO_SHOW" , label="Open when new sync target comes in.", default=settings.auto_show})
	InterfaceOptions.AddSlider({id="MAX_SAVED_SUMMARY" , label="Max Summary Info Saved", min=10, max=200, inc=10, default=settings.max_saved_summary})
	InterfaceOptions.AddChoiceMenu({id="SUMMARY_FONT" , label="Font of Summary", default=settings.summary_font})
	for i,v in ipairs(fonts) do
		InterfaceOptions.AddChoiceEntry({menuId="SUMMARY_FONT", label=v, val=v})	
	end
	InterfaceOptions.AddChoiceMenu({id="DAMAGE_TEXTURE" , label="Texture of Damage Statusbar", default=settings.damage_texture})
	for i,v in ipairs(textures) do
		InterfaceOptions.AddChoiceEntry({menuId="DAMAGE_TEXTURE", label=v, val=v})
	end
	InterfaceOptions.AddChoiceMenu({id="SYNC_TEXTURE" , label="Texture of Sync Statusbar", default=settings.sync_texture})
	for i,v in ipairs(textures) do
		InterfaceOptions.AddChoiceEntry({menuId="SYNC_TEXTURE", label=v, val=v})
	end

	InterfaceOptions.SetCallbackFunc(function(id, val)
		settings[string.lower(id)] = val
		if id == "ENABLED" then
			if not settings.enabled then ToggleSummary(nil) end
		elseif id == "SHOW_HP" then
		elseif id == "AUTO_SYNC" then
		elseif id == "AUTO_SHOW" then
		elseif id == "DEBUG" then
		elseif id == "MAX_SAVED_SUMMARY" then
			CheckMaxSummarySize()
			ReBuild_Local_Data()
		elseif id == "SUMMARY_FONT" then
			Update_Summary_Font()
		elseif id == "SYNC_TEXTURE" then
			for k,DATA in ipairs(SUMMARY_SYNC_DATA) do
				DATA.BAR:GetChild("dmg_bar"):SetTexture("BAR_"..settings.sync_texture)
			end
		elseif id == "DAMAGE_TEXTURE" then
			for k,DATA in ipairs(SUMMARY_DATA) do
				DATA.BAR:GetChild("dmg_bar"):SetTexture("BAR_"..settings.damage_texture)
			end
		elseif id == "SHOW_SHORT_ID" then
			ReBuild_Local_Data()
		end
	end, "HitHarder")
	LIB_SLASH.BindCallback({slash_list = "/hh", description = "HitHarder", func = function(args)
		if not settings.enabled then return end
		if not args[1] then
			--msgg("HitHarder' Usage:\n\"/hh clr\" -- clear detail records.\n\"/hh show\" -- show summary information.\n\"/hh debug\" -- show debug info.\n\"/hh log\" -- log debug info.")
			ToggleSummary(true)
		elseif args[1] == "show" then
			ToggleSummary(true)
		elseif args[1] == "debug" then
			msgg("g2_target = "..tostring(g2_target))
			msgg("g2_sum = "..tostring(g2_sum))
			msgg("#g2_target = "..tostring(#g2_target))
			msgg("#g2_sum = "..tostring(#g2_sum))
		elseif args[1] == "log" then
			log("g2_target = "..tostring(g2_target))
			log("g2_sum = "..tostring(g2_sum))
			log("#g2_target = "..tostring(#g2_target))
			log("#g2_sum = "..tostring(#g2_sum))
		elseif args[1] == "zone" then
			local zone = Game.GetZoneInfo(Game.GetZoneId())
			msgg("zone = "..tostring(zone))
		elseif args[1] == "compress" then
			local num2 = Decompress_Number(Compress_Number(args[2]))
			if num2 ~= args[2] then
				msgg("not equal, num = "..num.." ~= "..num2 .. " = num")
			end
		elseif args[1] == "hidebg" then
			SUMMARY_BODY_BORDER:SetParam("alpha",0)
			SUMMARY_TITLE_BORDER:SetParam("alpha",0)
		elseif args[1] == "showbg" then
			SUMMARY_BODY_BORDER:SetParam("alpha",1)
			SUMMARY_TITLE_BORDER:SetParam("alpha",1)
		end
	end})

	-- Set Moveable
	MovablePanel.ConfigFrame({
		frame = SUMMARY_FRAME,
		MOVABLE_PARENT = Component.GetWidget("Summary_frame_title_MovableParent"),
		RESIZABLE_PARENT = Component.GetWidget("ResizableParent"),
		min_height = 80,
		min_width = 200,
		step_height = 1,
		step_width = 1,
		OnResize = OnUpdateSummaryWindowSize,		
	})

	-- Load Config
	g_WhiteList = Component.GetSetting("g_WhiteList") or g_WhiteList
	
	-- Close Button
	CLOSE_BUTTON:BindEvent("OnMouseDown", function()
		ToggleSummary(nil)
	end);
	local X = CLOSE_BUTTON:GetChild("X")
	CLOSE_BUTTON:BindEvent("OnMouseEnter", function()
		X:ParamTo("tint", Component.LookupColor("red"), 0.15);
		X:ParamTo("glow", "#30991111", 0.15)
	end);
	CLOSE_BUTTON:BindEvent("OnMouseLeave", function()
		X:ParamTo("tint", Component.LookupColor("white"), 0.15)
		X:ParamTo("glow", "#00000000", 0.15)
	end);


	WL_BUTTON:BindEvent("OnMouseDown", function()
		ShowTab(2)
	end);
	WL_BUTTON:BindEvent("OnMouseEnter", function()
		WL_BUTTON:GetChild("X"):ParamTo("tint", "ccaa00", 0.15);
		WL_BUTTON:GetChild("X"):ParamTo("glow", "#30991111", 0.15)
	end);
	WL_BUTTON:BindEvent("OnMouseLeave", function()
		if g_tab~=2 then
			WL_BUTTON:GetChild("X"):ParamTo("tint", Component.LookupColor("white"), 0.15)
			WL_BUTTON:GetChild("X"):ParamTo("glow", "#00000000", 0.15)
		end
	end);
	
	DMG_BUTTON:BindEvent("OnMouseDown", function()
		ShowTab()
	end);
	DMG_BUTTON:BindEvent("OnMouseEnter", function()
		DMG_BUTTON:GetChild("X"):ParamTo("tint", "FF00FF", 0.15);
		DMG_BUTTON:GetChild("X"):ParamTo("glow", "#30991111", 0.15)
	end);
	DMG_BUTTON:BindEvent("OnMouseLeave", function()
		if g_tab~=0 then
			DMG_BUTTON:GetChild("X"):ParamTo("tint", Component.LookupColor("white"), 0.15)
			DMG_BUTTON:GetChild("X"):ParamTo("glow", "#00000000", 0.15)
		end
	end);	
	
	CLR_BUTTON:BindEvent("OnMouseDown", function()
		reset_summary()
		ShowTab()
	end);
	local X_CLR = CLR_BUTTON:GetChild("X")
	CLR_BUTTON:BindEvent("OnMouseEnter", function()
		X_CLR:ParamTo("tint", "#00FFFF", 0.15);
		X_CLR:ParamTo("glow", "#30991111", 0.15)
	end);
	CLR_BUTTON:BindEvent("OnMouseLeave", function()
		X_CLR:ParamTo("tint", Component.LookupColor("white"), 0.15)
		X_CLR:ParamTo("glow", "#00000000", 0.15)
	end);
	

	--Trim Time, in order to use System.GetClientTime() to replace System.GetDate()
	local _,_,time_h,time_m,time_s = string.find(System.GetDate("%H:%M:%S"), "(.*):(.*):(.*)")
	g_trim_time = tonumber(System.GetClientTime()) - (tonumber(time_h)*60*60+tonumber(time_m)*60+tonumber(time_s))*1000

	

	ChatLib.RegisterCustomLinkType(c_request, Handle_Link);
	ChatLib.RegisterCustomLinkType(c_result, Handle_Link);
	ChatLib.RegisterCustomLinkType(c_update, Handle_Link);

	--White List
	local CATEGORY_TEXT = Component.CreateWidget("Text_Group", SUMMARY_DATA_WL)
	CATEGORY_TEXT:SetDims("left:5; right:100%; top:0; height:"..tostring(g_wl.height))
	CATEGORY_TEXT:GetChild("Text"):SetText("White List:")

	for idx,CAT in ipairs(g_WhiteList) do
		add_WL(idx)
	end

	local function add()
		local name = WL_ADD_INPUT:GetText()
		if not name or name == "" then return end
		for i,v in ipairs(g_WhiteList) do
			if string.lower(name) == string.lower(v.name) then
				msgg(tostring(name) .. " is already in White List.")
				return
			end
		end
		OnAdd_WL(name,true)
		msgg(tostring(name) .. " has been added into White List.")
		WL_ADD_INPUT:SetText("")
		WL_ADD_INPUT:ReleaseFocus()
	end	
	WL_ADD_INPUT:BindEvent("OnSubmit", add)
	WL_ADD_BTN:BindEvent("OnMouseDown", add)


	WL_ADD_BTN:BindEvent("OnMouseEnter", function()
		WL_ADD_BTN:GetChild("X"):ParamTo("tint", Component.LookupColor("green"), 0.15);
		WL_ADD_BTN:GetChild("X"):ParamTo("glow", "#30991111", 0.15)
	end);
	WL_ADD_BTN:BindEvent("OnMouseLeave", function()
			WL_ADD_BTN:GetChild("X"):ParamTo("tint", Component.LookupColor("white"), 0.15)
			WL_ADD_BTN:GetChild("X"):ParamTo("glow", "#00000000", 0.15)
	end);	
	Update_Scroll()
	ShowTab()
end

function OnUpdateSummaryWindowSize(args)
	Update_Scroll()
end

function OnTeamUpdate(args)
	if g_update_notify_callback then
		cancel_callback(g_update_notify_callback)
		g_update_notify_callback = nil
	end
	g_update_notify_callback = callback(function() Send_Data(c_ver,c_update) g_update_notify_callback = nil end,nil,5)
end

