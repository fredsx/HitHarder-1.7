
-- ------------------------------------------
-- lib_CheckBox
--   by: Brian Blose
-- ------------------------------------------

--[[ Usage:
	CHECKBOX = CheckBox.Create(PARENT)		-- creates a Check Box
	CHECKBOX:Destroy()						-- Removes the button
	
	CHECKBOX:SetCheckType(type)				-- choose a 'check' or an 'x'
	CHECKBOX:TintCheck(tint)				-- changes the tint of the check; SetCheckType will auto apply the default color for that type
	CHECKBOX:SetCheck(checked)				-- manually sets the box to check or unchecked
	checked = CHECKBOX:IsChecked()			-- returns true if the box is checked; CHECKBOX:GetCheck() also works
	
	CHECKBOX:Enable([enabled])				-- Enables or Disables the CheckBox
	CHECKBOX:Disable([enabled])				-- Disables or Enables the CheckBox
	enabled = CHECKBOX:IsEnabled()			-- returns true if the button is enabled

	
	CHECKBOX is also an EventDispatcher (see lib_EventDispatcher) which dispatches the following events:
		"OnStateChanged",
		"OnScroll",
		"OnRightMouse",
		
		--These can be listened to via EventDispatcher or called as methods like CHECKBOX:OnMouseEnter() though note that this will also fire the EventDispatcher
		----This can be useful for if you want to have a focusbox that covers the checkbox and a label so that the box and label can work/animate together
		"OnMouseEnter",
		"OnMouseLeave",
		"OnMouseDown",
		"OnMouseUp",
		"OnSubmit",
		"OnGotFocus",
		"OnLostFocus",
--]]

if CheckBox then
	-- only include once
	return nil
end
CheckBox = {}

require "lib/lib_Callback2"
require "lib/lib_EventDispatcher"

-- ------------------------------------------
-- CONSTANTS
-- ------------------------------------------
local PRIVATE = {}
local API = {}
local METATABLE = {
	__index = function(t,key) return API[key] end,
	__newindex = function(t,k,v) error("cannot write to value '"..k.."' in WIDGET") end,
}


CheckBox.DEFAULT_BACKDROP_COLOR = "#000000"
CheckBox.DEFAULT_CLICKED_COLOR = "#333333"
CheckBox.DEFAULT_BORDER_COLOR = "#FFFFFF"
CheckBox.DEFAULT_CHECK_COLOR = "#8BCC00"
CheckBox.DEFAULT_X_COLOR = "#FF4444"

local c_MarkTypes = {
	check = CheckBox.DEFAULT_CHECK_COLOR,
	x = CheckBox.DEFAULT_X_COLOR,
}

local bp_CheckBox =
	[[<FocusBox dimensions="dock:fill" class="ui_button">
		<StillArt name="backdrop" dimensions="dock:fill" style="texture:CheckBox_White; region:backdrop; tint:]]..CheckBox.DEFAULT_BACKDROP_COLOR..[[; alpha:1;"/>
		<StillArt name="border" dimensions="dock:fill" style="texture:CheckBox_White; region:border; tint:]]..CheckBox.DEFAULT_BORDER_COLOR..[[; alpha:1;"/>
		<StillArt name="check" dimensions="dock:fill" style="texture:CheckBox_White; region:check; tint:]]..CheckBox.DEFAULT_CHECK_COLOR..[[; alpha:0;"/>
	</FocusBox>]]

-- ------------------------------------------
-- FRONTEND FUNCTIONS
-- ------------------------------------------
CheckBox.Create = function(PARENT, mark)
	local FOCUS = Component.CreateWidget(bp_CheckBox, PARENT)
	
	local WIDGET = {
		GROUP = FOCUS,
		BACKDROP = FOCUS:GetChild("backdrop"),
		BORDER = FOCUS:GetChild("border"),
		CHECK = FOCUS:GetChild("check"),
		checked = false,
		mouse_over = false,
		mouse_down = false,
		disabled = false,
		has_focus = false,
	}
	WIDGET.DISPATCHER = EventDispatcher.Create(WIDGET)
	WIDGET.DISPATCHER:Delegate(WIDGET)
	
	local used_events = {"OnMouseEnter", "OnMouseLeave", "OnMouseDown", "OnMouseUp", "OnSubmit", "OnGotFocus", "OnLostFocus"}
	for _, event in ipairs(used_events) do
		WIDGET.GROUP:BindEvent(event, function(args)
			API[event](WIDGET, args)
		end)
	end
	
	local other_events = {"OnScroll", "OnRightMouse"}
	for _, event in ipairs(other_events) do
		WIDGET.GROUP:BindEvent(event, function(args)
			WIDGET:DispatchEvent(event, args)
		end)
	end
	
	setmetatable(WIDGET, METATABLE)
	if mark then
		WIDGET:SetCheckType(mark)
	end
	PRIVATE.RefreshState(WIDGET, 0)
	return WIDGET
end

-- ------------------------------------------
-- WIDGET API
-- ------------------------------------------
local COMMON_METHODS = { -- forward the following methods to the GROUP widget
	"GetDims", "SetDims", "MoveTo", "QueueMove", "FinishMove",
	"GetParam", "SetParam", "ParamTo", "CycleParam", "QueueParam", "FinishParam",
	"SetFocusable", "SetFocus", "ReleaseFocus", "HasFocus",
	"Show", "Hide", "IsVisible", "GetBounds", "SetTag", "GetTag"
}
for _, method_name in pairs(COMMON_METHODS) do
	API[method_name] = function(WIDGET, ...)
		return WIDGET.GROUP[method_name](WIDGET.GROUP, ...)
	end
end

API.Destroy = function(WIDGET)
	WIDGET.DISPATCHER:Destroy()
	Component.RemoveWidget(WIDGET.GROUP)
	for k,v in pairs(WIDGET) do
		WIDGET[k] = nil
	end
end

API.TintCheck = function(WIDGET, tint)
	WIDGET.CHECK:SetParam("tint", tint)
end

API.TintBorder = function(WIDGET, tint)
	WIDGET.BORDER:SetParam("tint", tint)
end

API.SetCheckType = function(WIDGET, mark)
	local tint = c_MarkTypes[mark]
	if tint then
		WIDGET.CHECK:SetRegion(mark)
		WIDGET:TintCheck(tint)
	else
		warn("Invalid CheckBox CheckType: "..mark)
	end
end

API.SetCheck = function(WIDGET, checked, from_user)
	-- can't take nil, or will messy up the metatable
	local new_state
	if checked then
		new_state = true
	else
		new_state = false
	end
	if WIDGET.checked ~= new_state then
		WIDGET.checked = new_state
		PRIVATE.RefreshState(WIDGET)
		PRIVATE.OnStateChanged(WIDGET, from_user)
	end
end

API.IsChecked = function(WIDGET)
	return WIDGET.checked
end
API.GetCheck = API.IsChecked --Compatiblity with CheckBox Widget

API.Enable = function(WIDGET, ...)
    local arg = {n=select('#',...),...}
	--allow NULL to work as true to mimic Show() and nil to work as false to mimic Show(nil)
	WIDGET.disabled = not (arg[1] or arg.n == 0)
	PRIVATE.RefreshState(WIDGET)
end

API.Disable = function(WIDGET, ...) --inverted Enable
    local arg = {n=select('#',...),...}
	WIDGET:Enable(not (arg[1] or arg.n == 0))
end

API.IsEnabled = function(WIDGET)
	return not WIDGET.disabled
end

-- ------------------------------------------
-- WIDGET EVENTS/API
-- ------------------------------------------
-- All the event functions double as API incase you need to fake an event 
---- ie fake an OnMouseEnter and click when you mouse over and click a label you have for the checkbox
API.OnMouseEnter = function(WIDGET, args)
	if WIDGET.disabled then return nil end
	WIDGET.mouse_over = true
	PRIVATE.RefreshState(WIDGET)
	WIDGET:DispatchEvent("OnMouseEnter", args)
end

API.OnMouseLeave = function(WIDGET, args)
	if WIDGET.disabled then return nil end
	WIDGET.mouse_over = false
	WIDGET.mouse_down = false
	PRIVATE.RefreshState(WIDGET)
	WIDGET:DispatchEvent("OnMouseLeave", args)
end

API.OnMouseDown = function(WIDGET, args)
	if WIDGET.disabled then return nil end
	WIDGET.mouse_down = true
	PRIVATE.RefreshState(WIDGET)
	WIDGET:DispatchEvent("OnMouseDown", args)
end

API.OnMouseUp = function(WIDGET, args)
	if WIDGET.disabled then return nil end
	if WIDGET.mouse_down then
		WIDGET.mouse_down = false
		WIDGET.checked = not WIDGET.checked
		PRIVATE.RefreshState(WIDGET)
		PRIVATE.OnStateChanged(WIDGET, true)
	end
	WIDGET:DispatchEvent("OnMouseUp", args)
end

API.OnSubmit = function(WIDGET, args)
	if WIDGET.disabled then return nil end
	WIDGET.checked = not WIDGET.checked
	PRIVATE.RefreshState(WIDGET)
	WIDGET:DispatchEvent("OnSubmit", args)
	PRIVATE.OnStateChanged(WIDGET, true)
end

API.OnGotFocus = function(WIDGET, args)
	if WIDGET.disabled then return nil end
	WIDGET.has_focus = true
	PRIVATE.RefreshState(WIDGET)
	WIDGET:DispatchEvent("OnGotFocus", args)
end

API.OnLostFocus = function(WIDGET, args)
	if WIDGET.disabled then return nil end
	WIDGET.has_focus = false
	PRIVATE.RefreshState(WIDGET)
	WIDGET:DispatchEvent("OnLostFocus", args)
end

-- ------------------------------------------
-- PRIVATE FUNCTIONS
-- ------------------------------------------
PRIVATE.OnStateChanged = function(WIDGET, from_user)
	local args = {
		checked = WIDGET.checked,
		widget = WIDGET.GROUP,		--Compatiblity with CheckBox Widget
		user = from_user,			--Compatiblity with CheckBox Widget
	}
	if from_user then
		System.PlaySound("Play_Click021")
	end
	WIDGET:DispatchEvent("OnStateChanged", args)
end

PRIVATE.RefreshState = function(WIDGET, dur)
	dur = dur or .1
	
	if WIDGET.disabled then
		WIDGET.mouse_over = false
		WIDGET.mouse_down = false
		if WIDGET.has_focus then
			WIDGET.has_focus = false
			WIDGET.GROUP:ReleaseFocus()
		end
		WIDGET.GROUP:EatMice(false)
		WIDGET.GROUP:ParamTo("alpha", 0.2, dur)
	else
		WIDGET.GROUP:EatMice(true)
		WIDGET.GROUP:ParamTo("alpha", 1, dur)
	end
	
	if WIDGET.mouse_down then
		WIDGET.BACKDROP:ParamTo("tint", CheckBox.DEFAULT_CLICKED_COLOR, dur)
	else
		WIDGET.BACKDROP:ParamTo("tint", CheckBox.DEFAULT_BACKDROP_COLOR, dur)
	end
	
	if WIDGET.mouse_over or WIDGET.has_focus then
		WIDGET.BORDER:ParamTo("alpha", 1, dur)
		WIDGET.CHECK:ParamTo("exposure", 1, dur)
	else
		WIDGET.BORDER:ParamTo("alpha", 0.6, dur)
		WIDGET.CHECK:ParamTo("exposure", 0, dur)
	end
	
	WIDGET.CHECK:ParamTo("alpha", tonumber(WIDGET.checked), dur)
end
