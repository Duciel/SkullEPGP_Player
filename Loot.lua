-- Loot.lua : window with the pending loot (pre-bids) and the loot history of this session
local P = SkullEPGPP
local L = {}
P.Loot = L

local W, H = 400, 440
local PROWS, HROWS = 10, 15
local PRE = { { "ROLL", "Roll" }, { "MIN", "Min" }, { "NEED", "Need" }, { "MAX", "Max" } }
local COLOR = { MIN = "|cff33cc33", NEED = "|cffff8000", MAX = "|cffff3333", ROLL = "|cffcccccc" }

local f = CreateFrame("Frame", "SkullEPGPPlayerLoot", UIParent)
f:SetWidth(W)
f:SetHeight(H)
f:SetPoint("CENTER", UIParent, "CENTER", 120, 0)
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

local function ItemTip(frame, getLink)
	frame:SetScript("OnEnter", function()
		local link = getLink()
		local _, _, str = string.find(link or "", "(item:%d+:%d+:%d+:%d+)")
		if str then GameTooltip:SetOwner(frame, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(str); GameTooltip:Show() end
	end)
	frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local title = Text(f, "Skull EPGP - Loot", "GameFontNormal", 200, "CENTER")
title:SetPoint("TOP", f, "TOP", 0, -14)
local close = CreateFrame("Button", "SkullEPGPPlayerLootClose", f, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)

-- the two views
local tabP = CreateFrame("Button", "SkullEPGPPlayerTabPending", f, "UIPanelButtonTemplate")
tabP:SetWidth(100)
tabP:SetHeight(22)
tabP:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -36)
tabP:SetText("Pending")
tabP:SetScript("OnClick", function() L.view = "pending"; L.offset = 0; L:Refresh() end)
local tabH = CreateFrame("Button", "SkullEPGPPlayerTabHistory", f, "UIPanelButtonTemplate")
tabH:SetWidth(100)
tabH:SetHeight(22)
tabH:SetPoint("LEFT", tabP, "RIGHT", 4, 0)
tabH:SetText("History")
tabH:SetScript("OnClick", function() L.view = "history"; L.offset = 0; L:Refresh() end)

local help = Text(f, "", "GameFontHighlightSmall", W - 40)
help:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -64)

-------------------------------------------------------------------------------
-- Pending view
-------------------------------------------------------------------------------
local TOP = 98
local prow = {}
for i = 1, PROWS do
	local row = CreateFrame("Frame", nil, f)
	row:SetWidth(W - 70)
	row:SetHeight(24)
	row:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -TOP - (i - 1) * 26)
	row:EnableMouse(true)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetWidth(22)
	row.icon:SetHeight(22)
	row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.text = Text(row, "", "GameFontHighlightSmall", 150)
	row.text:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
	row.btn = {}
	for k = 1, 4 do
		local b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		b:SetWidth(40)
		b:SetHeight(20)
		b:SetPoint("RIGHT", row, "RIGHT", -(4 - k) * 42, 0)
		b:SetText(PRE[k][2])
		b:SetID(k)
		b:SetScript("OnClick", function()
			if row.item then P:TogglePrebid(row.item.id, PRE[this:GetID()][1]) end
		end)
		row.btn[k] = b
	end
	ItemTip(row, function() return row.item and row.item.link end)
	row:Hide()
	prow[i] = row
end

-------------------------------------------------------------------------------
-- History view
-------------------------------------------------------------------------------
local hrow = {}
for i = 1, HROWS do
	local row = CreateFrame("Frame", nil, f)
	row:SetWidth(W - 70)
	row:SetHeight(18)
	row:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -TOP - 16 - (i - 1) * 19)
	row:EnableMouse(true)
	row.text = Text(row, "", "GameFontHighlightSmall", 190)
	row.text:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.who = Text(row, "", "GameFontHighlightSmall", 80)
	row.who:SetPoint("LEFT", row, "LEFT", 194, 0)
	row.bid = Text(row, "", "GameFontHighlightSmall", 70)
	row.bid:SetPoint("LEFT", row, "LEFT", 278, 0)
	ItemTip(row, function() return row.entry and row.entry.link end)
	row:Hide()
	hrow[i] = row
end
local hhdr = CreateFrame("Frame", nil, f)
hhdr:SetWidth(W - 70)
hhdr:SetHeight(14)
hhdr:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -TOP)
do
	local a = Text(hhdr, "Item", "GameFontNormalSmall"); a:SetPoint("LEFT", hhdr, "LEFT", 0, 0)
	local b = Text(hhdr, "Winner", "GameFontNormalSmall"); b:SetPoint("LEFT", hhdr, "LEFT", 194, 0)
	local c = Text(hhdr, "Bid / roll", "GameFontNormalSmall"); c:SetPoint("LEFT", hhdr, "LEFT", 278, 0)
end

local empty = Text(f, "", "GameFontDisableSmall", W - 50, "CENTER")
empty:SetPoint("TOPLEFT", f, "TOPLEFT", 25, -TOP - 20)

local up = CreateFrame("Button", "SkullEPGPPlayerLootUp", f, "UIPanelScrollUpButtonTemplate")
up:SetPoint("TOPRIGHT", f, "TOPRIGHT", -20, -TOP)
up:SetScript("OnClick", function() L.offset = math.max(0, (L.offset or 0) - 3); L:Refresh() end)
local down = CreateFrame("Button", "SkullEPGPPlayerLootDown", f, "UIPanelScrollDownButtonTemplate")
down:SetPoint("TOPRIGHT", f, "TOPRIGHT", -20, -TOP - 26 * 9 + 6)
down:SetScript("OnClick", function() L.offset = (L.offset or 0) + 3; L:Refresh() end)
f:EnableMouseWheel(true)
f:SetScript("OnMouseWheel", function()
	if arg1 > 0 then L.offset = math.max(0, (L.offset or 0) - 1) else L.offset = (L.offset or 0) + 1 end
	L:Refresh()
end)

local clear = CreateFrame("Button", "SkullEPGPPlayerLootClear", f, "UIPanelButtonTemplate")
clear:SetWidth(120)
clear:SetHeight(20)
clear:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 22, 18)
clear:SetText("Clear history")
clear:SetScript("OnClick", function() P.history = {}; L.offset = 0; L:Refresh() end)

local more = Text(f, "", "GameFontDisableSmall", 200, "RIGHT")
more:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 22)

-------------------------------------------------------------------------------
function L:Refresh()
	if not f:IsShown() then return end
	self.view = self.view or "pending"
	local pending = (self.view == "pending")
	if pending then tabP:LockHighlight(); tabH:UnlockHighlight() else tabH:LockHighlight(); tabP:UnlockHighlight() end
	local off = self.offset or 0
	if pending then
		help:SetText("Pick Roll / Min / Need / Max for an item: your choice is sent automatically when the officer announces it. Click again to cancel.")
		local list = P:VisibleLoot()
		local n = table.getn(list)
		if off > math.max(0, n - PROWS) then off = math.max(0, n - PROWS) end
		self.offset = off
		for i = 1, PROWS do
			local it = list[off + i]
			local row = prow[i]
			if it then
				row.item = it
				local tex = P.iconCache[it.id]
				row.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
				row.text:SetText(it.link .. ((it.count or 1) > 1 and (" |cffffd700x" .. it.count .. "|r") or ""))
				local sel = P.prebid[it.id]
				for k = 1, 4 do
					if sel == PRE[k][1] then row.btn[k]:LockHighlight() else row.btn[k]:UnlockHighlight() end
					row.btn[k]:SetText((sel == PRE[k][1] and COLOR[PRE[k][1]] or "") .. PRE[k][2])
				end
				row:Show()
			else
				row.item = nil
				row:Hide()
			end
		end
		for i = 1, HROWS do hrow[i]:Hide() end
		hhdr:Hide()
		clear:Hide()
		if n == 0 then
			empty:SetText("No pending item. The officer shares the list of the items dropped by the bosses; items hidden by your item filter are not shown.")
			empty:Show()
		else
			empty:Hide()
		end
		more:SetText(n > PROWS and (n .. " items, scroll for more") or "")
	else
		help:SetText("Items won during this session (cleared when you reload or disconnect).")
		local list = P.history
		local n = table.getn(list)
		if off > math.max(0, n - HROWS) then off = math.max(0, n - HROWS) end
		self.offset = off
		for i = 1, PROWS do prow[i].item = nil; prow[i]:Hide() end
		hhdr:Show()
		for i = 1, HROWS do
			local e = list[off + i]
			local row = hrow[i]
			if e then
				row.entry = e
				row.text:SetText(e.link)
				row.who:SetText(e.char)
				local tier = string.find(e.bid, "^Roll") and "ROLL" or e.bid
				row.bid:SetText((COLOR[tier] or "") .. e.bid .. "|r")
				row:Show()
			else
				row.entry = nil
				row:Hide()
			end
		end
		clear:Show()
		if n == 0 then empty:SetText("Nothing won yet."); empty:Show() else empty:Hide() end
		more:SetText(n > HROWS and (n .. " entries, scroll for more") or "")
	end
end

function L:Show(view)
	self.view = view or self.view or "pending"
	self.offset = 0
	f:Show()
	self:Refresh()
end

function L:Toggle(view)
	if f:IsShown() and (not view or view == self.view) then f:Hide() else self:Show(view) end
end

f:SetScript("OnShow", function() L:Refresh() end)

-- icons: GetItemInfo can be costly for an item this client never saw, so at most one lookup per second,
-- 3 tries per item, only while the pending view is open
P.iconCache = {}
local tries = {}
local acc = 0
f:SetScript("OnUpdate", function()
	acc = acc + (arg1 or 0)
	if acc < 1 then return end
	acc = 0
	if L.view ~= "pending" then return end
	for _, it in ipairs(P:VisibleLoot()) do
		if not P.iconCache[it.id] and (tries[it.id] or 0) < 3 then
			tries[it.id] = (tries[it.id] or 0) + 1
			local _, _, _, _, _, _, _, _, tex = GetItemInfo("item:" .. it.id .. ":0:0:0")
			if tex then P.iconCache[it.id] = tex; L:Refresh() end
			return
		end
	end
end)
