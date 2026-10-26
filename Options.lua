-- Options.lua : minimap button + settings window (item blacklist / whitelist)
local P = SkullEPGPP
local O = {}
P.Options = O

-------------------------------------------------------------------------------
-- Minimap button
-------------------------------------------------------------------------------
local M = {}
P.Minimap = M
local btn = CreateFrame("Button", "SkullEPGPPlayerMinimapButton", Minimap)
btn:SetWidth(32)
btn:SetHeight(32)
btn:SetFrameStrata("MEDIUM")
btn:SetFrameLevel(8)
btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btn:RegisterForDrag("LeftButton")
local icon = btn:CreateTexture(nil, "BACKGROUND")
icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
icon:SetWidth(20)
icon:SetHeight(20)
icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 6, -6)
local border = btn:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetWidth(52)
border:SetHeight(52)
border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)

function M:SetPosition(angle)
	angle = tonumber(angle) or 200
	local rad = math.rad(angle)
	btn:ClearAllPoints()
	btn:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 52 - (80 * math.cos(rad)), (80 * math.sin(rad)) - 52)
end

function M:Apply()
	if not P.db then return end
	-- positioned only once (pfUI and co. re-parent minimap buttons into their own bar)
	if not self.positioned then
		self.positioned = true
		self:SetPosition(P.db.minimapAngle)
	end
	if P.db.minimapHidden then btn:Hide() else btn:Show() end
end

btn:SetScript("OnDragStart", function()
	this:LockHighlight()
	this:SetScript("OnUpdate", function()
		local mx, my = GetCursorPosition()
		local scale = UIParent:GetScale()
		local x = Minimap:GetLeft() - mx / scale + 70
		local y = my / scale - Minimap:GetBottom() - 70
		local angle = math.deg(math.atan2(y, x))
		if angle < 0 then angle = angle + 360 end
		P.db.minimapAngle = angle
		M:SetPosition(angle)
	end)
end)
btn:SetScript("OnDragStop", function()
	this:SetScript("OnUpdate", nil)
	this:UnlockHighlight()
end)
btn:SetScript("OnClick", function()
	if arg1 == "RightButton" then P.UI:Toggle() else O:Toggle() end
end)
btn:SetScript("OnEnter", function()
	GameTooltip:SetOwner(this, "ANCHOR_LEFT")
	GameTooltip:SetText("Skull EPGP - Player")
	local mode = P.db and P.db.filterMode or "off"
	GameTooltip:AddLine("Item filter: " .. (mode == "black" and "blacklist" or mode == "white" and "whitelist" or "off"), 0.8, 0.8, 0.8)
	GameTooltip:AddLine("Click: item filter / settings", 1, 1, 1)
	GameTooltip:AddLine("Right-click: show / hide the bidding window", 1, 1, 1)
	GameTooltip:AddLine("Drag: move this button", 0.7, 0.7, 0.7)
	GameTooltip:Show()
end)
btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-------------------------------------------------------------------------------
-- Settings window
-------------------------------------------------------------------------------
local ROWS = 9
local W, H = 330, 470
local f = CreateFrame("Frame", "SkullEPGPPlayerOptions", UIParent)
f:SetWidth(W)
f:SetHeight(H)
f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
f:SetFrameStrata("DIALOG")
f:SetMovable(true)
f:EnableMouse(true)
f:SetClampedToScreen(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", function() this:StartMoving() end)
f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
f:SetBackdrop({
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true, tileSize = 32, edgeSize = 32,
	insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
f:Hide()

local function Text(parent, text, font, w, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	if text then fs:SetText(text) end
	if w then fs:SetWidth(w) end
	fs:SetJustifyH(justify or "LEFT")
	return fs
end

local title = Text(f, "Skull EPGP - Item filter", "GameFontNormal", 240, "CENTER")
title:SetPoint("TOP", f, "TOP", 0, -14)
local close = CreateFrame("Button", "SkullEPGPPlayerOptionsClose", f, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)

local intro = Text(f, "Choose for which items the bidding window opens by itself when the officer announces loot. You can always open it by hand (/epgpp or right-click on the minimap button).", "GameFontHighlightSmall", W - 40)
intro:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -36)

-- mode: three check buttons used as radio buttons
local MODES = {
	{ "off", "Off - open the window for every item" },
	{ "black", "Blacklist - NOT for the items of the blacklist" },
	{ "white", "Whitelist - ONLY for the items of the whitelist" },
}
local checks = {}
for i = 1, 3 do
	local c = CreateFrame("CheckButton", "SkullEPGPPlayerMode" .. i, f, "UICheckButtonTemplate")
	c:SetWidth(24)
	c:SetHeight(24)
	c:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -78 - (i - 1) * 24)
	local label = Text(f, MODES[i][2], "GameFontNormalSmall", W - 80)
	label:SetPoint("LEFT", c, "RIGHT", 4, 0)
	c:SetID(i)          -- the index is read from the button itself: closures over a loop variable are unreliable in Lua 5.0
	c:SetScript("OnClick", function()
		local mode = MODES[this:GetID()][1]
		P.db.filterMode = mode
		if mode ~= "off" then O.view = mode end
		O:Refresh()
	end)
	checks[i] = c
end

-- which list is displayed / edited
local viewLabel = Text(f, "", "GameFontNormal", 190)
viewLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -160)
local switch = CreateFrame("Button", "SkullEPGPPlayerSwitch", f, "UIPanelButtonTemplate")
switch:SetWidth(110)
switch:SetHeight(20)
switch:SetPoint("TOPRIGHT", f, "TOPRIGHT", -20, -157)
switch:SetScript("OnClick", function()
	O.view = (O.view == "black") and "white" or "black"
	O:Refresh()
end)

-- rows
local rows = {}
for i = 1, ROWS do
	local row = CreateFrame("Frame", nil, f)
	row:SetWidth(W - 70)
	row:SetHeight(20)
	row:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -184 - (i - 1) * 21)
	row:EnableMouse(true)
	row.text = Text(row, "", "GameFontHighlightSmall", W - 100)
	row.text:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.del = CreateFrame("Button", nil, row, "UIPanelCloseButton")
	row.del:SetWidth(22)
	row.del:SetHeight(22)
	row.del:SetPoint("RIGHT", row, "RIGHT", 4, 0)
	row.del:SetScript("OnClick", function()
		if row.key then P:RemoveFromList(O.view, row.key); O:Refresh() end
	end)
	row:SetScript("OnEnter", function()
		if row.link then
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			local _, _, str = string.find(row.link, "(item:%d+:%d+:%d+:%d+)")
			if str then GameTooltip:SetHyperlink(str) end
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row:Hide()
	rows[i] = row
end
local empty = Text(f, "(empty)", "GameFontDisableSmall", 200)
empty:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -188)
local up = CreateFrame("Button", "SkullEPGPPlayerOptUp", f, "UIPanelScrollUpButtonTemplate")
up:SetPoint("TOPRIGHT", f, "TOPRIGHT", -20, -184)
up:SetScript("OnClick", function() O.offset = math.max(0, (O.offset or 0) - 3); O:Refresh() end)
local down = CreateFrame("Button", "SkullEPGPPlayerOptDown", f, "UIPanelScrollDownButtonTemplate")
down:SetPoint("TOPRIGHT", f, "TOPRIGHT", -20, -184 - (ROWS - 1) * 21 + 4)
down:SetScript("OnClick", function() O.offset = (O.offset or 0) + 3; O:Refresh() end)
f:EnableMouseWheel(true)
f:SetScript("OnMouseWheel", function()
	if arg1 > 0 then O.offset = math.max(0, (O.offset or 0) - 1) else O.offset = (O.offset or 0) + 1 end
	O:Refresh()
end)

-- add an item
local addHelp = Text(f, "Add an item: shift-click it (bag or chat link) into the box, or type its name or id.", "GameFontHighlightSmall", W - 40)
addHelp:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -184 - ROWS * 21 - 6)
local box = CreateFrame("EditBox", "SkullEPGPPlayerAddBox", f, "InputBoxTemplate")
box:SetWidth(210)
box:SetHeight(20)
box:SetAutoFocus(false)
box:SetPoint("TOPLEFT", f, "TOPLEFT", 28, -184 - ROWS * 21 - 34)
box:SetScript("OnEscapePressed", function() this:ClearFocus() end)
local function DoAdd()
	local text = box:GetText()
	if text and text ~= "" then
		local ok, e = P:AddToList(O.view, text)
		if ok then box:SetText("") ; box:ClearFocus(); O:Refresh() else P:Print("Could not add this item.") end
	end
end
box:SetScript("OnEnterPressed", DoAdd)
local add = CreateFrame("Button", "SkullEPGPPlayerAddBtn", f, "UIPanelButtonTemplate")
add:SetWidth(70)
add:SetHeight(22)
add:SetPoint("LEFT", box, "RIGHT", 6, 0)
add:SetText("Add")
add:SetScript("OnClick", DoAdd)

-- last announced item: icon + name + "Add" button (only shown once an item has been announced)
local cur = CreateFrame("Frame", "SkullEPGPPlayerLastItem", f)
cur:SetWidth(W - 56)
cur:SetHeight(26)
cur:SetPoint("TOPLEFT", f, "TOPLEFT", 28, -184 - ROWS * 21 - 62)
cur:EnableMouse(true)
local curIcon = cur:CreateTexture(nil, "ARTWORK")
curIcon:SetWidth(24)
curIcon:SetHeight(24)
curIcon:SetPoint("LEFT", cur, "LEFT", 0, 0)
curIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
local curText = Text(cur, "", "GameFontNormalSmall", W - 56 - 24 - 74)
curText:SetPoint("LEFT", curIcon, "RIGHT", 6, 0)
local curAdd = CreateFrame("Button", "SkullEPGPPlayerAddCurrent", cur, "UIPanelButtonTemplate")
curAdd:SetWidth(64)
curAdd:SetHeight(22)
curAdd:SetPoint("RIGHT", cur, "RIGHT", 0, 0)
curAdd:SetText("Add")
curAdd:SetScript("OnClick", function()
	local a = P.auction
	if not a or not a.link then return end
	local ok = P:AddToList(O.view, a.link)
	if ok then P:Print("Added to the " .. O.view .. "list: " .. a.link) end
	O:Refresh()
end)
cur:SetScript("OnEnter", function()
	local a = P.auction
	if a and a.link then
		local _, _, str = string.find(a.link, "(item:%d+:%d+:%d+:%d+)")
		if str then GameTooltip:SetOwner(cur, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(str); GameTooltip:Show() end
	end
end)
cur:SetScript("OnLeave", function() GameTooltip:Hide() end)
cur:Hide()

-- shift-click on an item while the box has the keyboard focus: put the item in the box
local function BoxHasFocus() return GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() == box end
local oldSetItemRef = SetItemRef
if oldSetItemRef then
	SetItemRef = function(link, text, button)
		if IsShiftKeyDown() and BoxHasFocus() and text and string.find(text, "Hitem:") then
			box:SetText(text)
			return
		end
		return oldSetItemRef(link, text, button)
	end
end
local oldContainerClick = ContainerFrameItemButton_OnClick
if oldContainerClick then
	ContainerFrameItemButton_OnClick = function(button, ignoreModifiers)
		if IsShiftKeyDown() and BoxHasFocus() and button == "LeftButton" then
			local link = GetContainerItemLink(this:GetParent():GetID(), this:GetID())
			if link then box:SetText(link); return end
		end
		return oldContainerClick(button, ignoreModifiers)
	end
end

function O:Refresh()
	if not P.db then return end
	self.view = self.view or ((P.db.filterMode == "white") and "white" or "black")
	for i = 1, 3 do checks[i]:SetChecked(P.db.filterMode == MODES[i][1] and 1 or nil) end
	local isBlack = (self.view == "black")
	viewLabel:SetText((isBlack and "|cffff6060Blacklist|r" or "|cff60ff60Whitelist|r") .. " (edited list)")
	switch:SetText(isBlack and "Edit whitelist" or "Edit blacklist")
	local a = P.auction
	if a and a.link then
		local tex = a.iconTex      -- cached by the bidding window (no GetItemInfo call here)
		curIcon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
		curText:SetText(a.link)
		if P:InList(self.view, a.link) then curAdd:Disable() else curAdd:Enable() end
		cur:Show()
	else
		cur:Hide()
	end
	local list = P:ListEntries(self.view)
	local n = table.getn(list)
	local maxOff = math.max(0, n - ROWS)
	if (self.offset or 0) > maxOff then self.offset = maxOff end
	if (self.offset or 0) < 0 then self.offset = 0 end
	for i = 1, ROWS do
		local it = list[(self.offset or 0) + i]
		if it then
			rows[i].key = it.key
			rows[i].link = it.e.link
			rows[i].text:SetText(it.e.link or ("|cffffffff[" .. (it.e.name or "?") .. "]|r"))
			rows[i]:Show()
		else
			rows[i].key = nil
			rows[i].link = nil
			rows[i]:Hide()
		end
	end
	if n == 0 then empty:Show() else empty:Hide() end
end

function O:IsShown() return f:IsShown() end

function O:Toggle()
	if f:IsShown() then f:Hide() else f:Show(); self:Refresh() end
end
f:SetScript("OnShow", function() O:Refresh() end)
