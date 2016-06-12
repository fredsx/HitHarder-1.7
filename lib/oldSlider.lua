
-- ------------------------------------------
-- lib_Slider
--	by: John Su
-- ------------------------------------------
--	creates complex sliders (functionally/aesthetically)

--[[ Usage:
	SLIDER = Slider.Create(PARENT, [style])		-- creates a slider in a style; valid styles are:
													"vertical",		-- (default) for viewing vertical content
													"horizontal",	-- for viewing horizontal content
													"adjuster",		-- for scaling values
	SLIDER:Destroy();							-- destroys the slider
	WIDGET = SLIDER:GetWidget();				-- returns the container widget
	
	SLIDER can also be interfaced like a Slider-Widget using Slider-Widget methods, parameters, and events
--]]

if Slider then
	-- only include once
	return nil
end
Slider = {};
local lf = {};
local BaseApi;
local SliderApi = {};

local c_IceVertStyle = "vertical";
local c_IceHorzStyle = "horizontal";
local c_PeaHorzStyle = "adjuster";
local c_DefaultStyle = c_IceVertStyle;

local c_SliderMetatable = {
	__index = function(t,key) return SliderApi[key] or BaseApi(t,key); end,
	__newindex = function(t,k,v) error("cannot write to value '"..k.."' in SLIDER"); end
};

local c_SliderStyleMethods = {
	[c_IceVertStyle] = {},
	[c_IceHorzStyle] = {},
	[c_PeaHorzStyle] = {},
};

local c_SliderParams = {"percent", "thumbsize", "fixedthumbsize"};
local c_SliderMethods = {"SetPercent", "GetPercent", "SetMinPercent", "GetMinPercent", "SetMaxPercent", "GetMaxPercent",
						 "SetSteps", "GetSteps", "SetScrollSteps", "GetScrollSteps", "SetJumpSteps", "GetJumpSteps", "EatMice"};

-- faster lookups
for _,paramName in pairs(c_SliderParams) do
	c_SliderParams[paramName] = true;
end
for _,methodName in pairs(c_SliderMethods) do
	c_SliderMethods[methodName] = true;
end

-- ------------------------------------------
-- BLUEPRINTS
-- ------------------------------------------
local bp_PeaSlider = [[<FocusBox dimensions="center-x:50%; width:100%; height:16">
	<StillArt name="ticks" dimensions="center-y:50%; height:10; center-x:50%; width:100%-6" style="texture:SliderPea; region:back; xwrap:25"/>
	<Group name="track" dimensions="center-y:50%; height:10; center-x:50%; width:100%-16">
		<StillArt name="length" dimensions="width:100%+16; height:100%" style="texture:SliderPea; region:traversable"/>
	</Group>
	<Group name="fill" dimensions="center-y:50%; left:8; right:100%-8; height:16">
		<StillArt name="start" dimensions="right:0; height:100%; width:50t" style="texture:SliderPea; region:fill_left;"/>
		<StillArt name="length" dimensions="left:0; height:100%; right:100%" style="texture:SliderPea; region:fill_mid;"/>
		<StillArt name="secondary" dimensions="left:0; height:100%; right:100%" style="texture:SliderPea; region:fill_mid; tint:FF0000"/>
	</Group>
	<Group name="border" dimensions="width:100%; center-y:50%; height:16">
		<StillArt dimensions="left:0; height:100%; width:50t" style="texture:SliderPea; region:border_left;"/>
		<StillArt dimensions="left:50t; height:100%; width:100%-100t" style="texture:SliderPea; region:border_mid;"/>
		<StillArt dimensions="right:100%; height:100%; width:50t" style="texture:SliderPea; region:border_right;"/>
	</Group>
	<Slider name="slider" dimensions="width:100%; center-y:50%; height:16" style="texture:SliderPea; horizontal:true; inverted:true; fixedthumbsize:16;
		region-thumb-min:thumb_left;
		region-thumb-mid:thumb_mid;
		region-thumb-max:thumb_right;
		region-slider-min:blank;
		region-slider-mid:blank;
		region-slider-max:blank;"/>
</FocusBox>]];

local bp_VertSlider = [[<Slider name="slider" dimensions="center-x:50%; center-y:50%; height:100%; width:14" class="#Slider"/>]]
local bp_HorzSlider = [[<Slider name="slider" dimensions="center-x:50%; center-y:50%; width:100%; height:14" class="SliderHorizontal"/>]]

-- ------------------------------------------
-- LIB API
-- ------------------------------------------
function Slider.Create(PARENT, style)
	local SLIDER = {
		style = style or c_DefaultStyle,
		virtualMax = false,
		event_binds = { -- event_bind[event_name] = func; bound through SliderApi.BindEvent()
			OnStateChanged = false,
		},
		-- WIDGET
		-- SLIDER_WIDGET
	};
	
	if (SLIDER.style == c_IceVertStyle) then
		SLIDER.WIDGET = Component.CreateWidget(bp_VertSlider, PARENT);
		SLIDER.SLIDER_WIDGET = SLIDER.WIDGET;
	elseif (SLIDER.style == c_IceHorzStyle) then
		SLIDER.WIDGET = Component.CreateWidget(bp_HorzSlider, PARENT);
		SLIDER.SLIDER_WIDGET = SLIDER.WIDGET;
	elseif (SLIDER.style == c_PeaHorzStyle) then
		SLIDER.WIDGET = Component.CreateWidget(bp_PeaSlider, PARENT);
		SLIDER.TRACK = SLIDER.WIDGET:GetChild("track.length");
		SLIDER.FILL_START = SLIDER.WIDGET:GetChild("fill.start");
		SLIDER.FILL = SLIDER.WIDGET:GetChild("fill.length");
		SLIDER.SECONDARY = SLIDER.WIDGET:GetChild("fill.secondary")
		SLIDER.BORDER = SLIDER.WIDGET:GetChild("border");
		SLIDER.SLIDER_WIDGET = SLIDER.WIDGET:GetChild("slider");
	else
		error("invalid slider style: "..tostring(style));
	end
	
	SLIDER.SLIDER_WIDGET:BindEvent("OnStateChanged", function(arg)
		c_SliderStyleMethods[style].OnStateChanged(SLIDER);
		lf.FireEvent(SLIDER, "OnStateChanged", arg);
	end);
	
	setmetatable(SLIDER, c_SliderMetatable);
	
	c_SliderStyleMethods[style].OnStateChanged(SLIDER);
	
	return SLIDER;
end

-- ------------------------------------------
-- SLIDER API
-- ------------------------------------------
function SliderApi.Destroy(SLIDER)
	Component.RemoveWidget(SLIDER.WIDGET);
	
	for k,v in pairs(SLIDER) do
		SLIDER[k] = nil;
	end
	setmetatable(SLIDER, nil);
end

function SliderApi.GetWidget(SLIDER)
	return SLIDER.WIDGET;
end

-- uiWidget overrides
local c_ParamMethods = {"GetParam", "SetParam", "ParamTo", "QueueParam", "CycleParam", "FinishParam"};
for _,method in pairs(c_ParamMethods) do
	SliderApi[method] = function(SLIDER, param, ...)
		if (c_SliderParams[param]) then
			return SLIDER.SLIDER_WIDGET[method](SLIDER.SLIDER_WIDGET, param, ...);
		else
			return SLIDER.WIDGET[method](SLIDER.WIDGET, param, ...);
		end
	end
end

-- uiSliderWidget overrides
function SliderApi.SetMinPercent(SLIDER, percent)
	local ret = SLIDER.SLIDER_WIDGET:SetMinPercent(percent);
	lf.StyleMethod(SLIDER, "SetMinPercent", percent);
	return ret;
end

function SliderApi.SetMaxPercent(SLIDER, percent)
	local ret = SLIDER.SLIDER_WIDGET:SetMaxPercent(percent);
	lf.StyleMethod(SLIDER, "SetMaxPercent", percent);
	return ret;
end

function SliderApi.SetPercent(SLIDER, ...)
	local ret = SLIDER.SLIDER_WIDGET:SetPercent(...);
	c_SliderStyleMethods[SLIDER.style].OnStateChanged(SLIDER);
	return ret;
end

function SliderApi.SetVirtualMax(SLIDER, vMax)
	if vMax then
		SLIDER.virtualMax = vMax
	end
	c_SliderStyleMethods[SLIDER.style].OnStateChanged(SLIDER);
end

function SliderApi.BindEvent(SLIDER, event, func)
	if SLIDER.event_binds[event] ~= nil then
		-- reserved bindings
		SLIDER.event_binds[event] = func;
	else
		return SLIDER.SLIDER_WIDGET:BindEvent(event, func);
	end
end

-- ------------------------------------------
-- Styled Methods
-- ------------------------------------------
function lf.StyleMethod(SLIDER, method, ...)
	return c_SliderStyleMethods[SLIDER.style][method](SLIDER, ...);
end
function lf.NilFunc() end

-- PEA HORIZONTAL SLIDER
c_SliderStyleMethods[c_PeaHorzStyle].SetMinPercent = function(SLIDER, pct)
	if (pct <= 0) then
		SLIDER.TRACK:SetDims("right:_; left:-8");
	else
		SLIDER.TRACK:SetDims("right:_; left:"..(pct*100).."%");
	end
end

c_SliderStyleMethods[c_PeaHorzStyle].SetMaxPercent = function(SLIDER, pct)
	SLIDER.TRACK:Show(pct > 0);
	if (pct >= 1) then
		SLIDER.TRACK:SetDims("left:_; right:100%+8");
	else
		SLIDER.TRACK:SetDims("left:_; right:"..(pct*100).."%");
	end
end

c_SliderStyleMethods[c_PeaHorzStyle].OnStateChanged = function(SLIDER)
	local pct = SLIDER.SLIDER_WIDGET:GetPercent();
	lf.UpdatePeaHorzFill(SLIDER, pct)
end

function lf.UpdatePeaHorzFill(SLIDER, pct)
	local percent = pct or SLIDER.SLIDER_WIDGET:GetPercent()

	--determine visibility and color of the first half-circle bit of the fill
	SLIDER.FILL_START:Show(percent > 0);
	if percent > 0 and SLIDER.virtualMax == 0 then
		SLIDER.FILL_START:SetParam("tint", "#FF0000")
	else
		SLIDER.FILL_START:SetParam("tint", "#FFFFFF")
	end

	--determine visibility and size of the red secondary fill
	if SLIDER.virtualMax and SLIDER.virtualMax < percent then
		SLIDER.FILL:SetDims("left:_; right:"..(SLIDER.virtualMax*100).."%");
		SLIDER.SECONDARY:SetDims("left:"..(SLIDER.virtualMax*100).."%; right"..(percent*100).."%")
		SLIDER.SECONDARY:Show(true)
	else
		SLIDER.FILL:SetDims("left:_; right:"..(percent*100).."%");
		SLIDER.SECONDARY:Show(false)
	end
end

-- ICE SLIDER
c_SliderStyleMethods[c_IceHorzStyle].OnStateChanged = lf.NilFunc;
c_SliderStyleMethods[c_IceHorzStyle].SetMinPercent = lf.NilFunc;
c_SliderStyleMethods[c_IceHorzStyle].SetMaxPercent = lf.NilFunc;
c_SliderStyleMethods[c_IceVertStyle].OnStateChanged = lf.NilFunc;
c_SliderStyleMethods[c_IceVertStyle].SetMinPercent = lf.NilFunc;
c_SliderStyleMethods[c_IceVertStyle].SetMaxPercent = lf.NilFunc;

-- ------------------------------------------
-- Local Misc
-- ------------------------------------------
function BaseApi(SLIDER, key)
	-- forwarding function to slider widget
	local WIDGET;
	if (c_SliderMethods[key]) then
		WIDGET = SLIDER.SLIDER_WIDGET;
	else
		WIDGET = SLIDER.WIDGET;
	end
	return function(_, ...)
		return WIDGET[key](WIDGET, ...);
	end
end

function lf.FireEvent(SLIDER, event, args)
	local bind = SLIDER.event_binds[event]
	if bind then
		local bind_type = type(bind)
		if bind_type == "function" then
			bind(args)
		elseif bind_type == "string" then
			error("can't call function by string '"..bind.."'")
		end
	end
end
