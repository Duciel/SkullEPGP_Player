-- Loot.lua : pending loot with pre-bids (panel under the bidding window) and the loot history of this session
local P = SkullEPGPP
local L = {}
P.Loot = L

local PRE = { { "ROLL", "Roll" }, { "MIN", "Min" }, { "NEED", "Need" }, { "MAX", "Max" } }
local COLOR = { MIN = "|cff33cc33", NEED = "|cffff8000", MAX = "|cffff3333", ROLL = "|cffcccccc" }
local BACKDROP = {
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true, tileSize = 32, edgeSize = 32,
	insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

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

-------------------------------------------------------------------------------
-- Pending loot : child of the bidding window, hanging under it
-------------------------------------------------------------------------------
local PROWS = 8
local PW = 360
local pf = CreateFrame("Frame", "SkullEPGPPlayerPending", P.UI.frame)
pf:SetWidth(PW)
pf:SetHeight(100)
pf:SetPoint("TOPLEFT", P.UI.frame, "BOTTOMLEFT", 0, 6)
pf:EnableMouse(true)
pf:SetBackdrop(BACKDROP)
pf:Hide()

local ptitle = Text(pf, "Pending loot - pre-bid", "GameFontNormal", PW - 40, "LEFT")
ptitle:SetPoint("TOPLEFT", pf, "TOPLEFT", 18, -16)
local phelp = Text(pf, "Your pick is sent automatically when the item is announced (click it again to cancel).", "GameFontDisableSmall", PW - 36)
phelp:SetPoint("TOPLEFT", pf, "TOPLEFT", 18, -30)

local prow = {}
for i = 1, PROWS do
	local row = CreateFrame("Frame", nil, pf)
	row:SetWidth(PW - 36)
	row:SetHeight(24)
	row:SetPoint("TOPLEFT", pf, "TOPLEFT", 18, -52 - (i - 1) * 26)
	row:EnableMouse(true)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetWidth(22)
	row.icon:SetHeight(22)
	row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.text = Text(row, "", "GameFontHighlightSmall", PW - 36 - 26 - 4 * 41)
	row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
	row.btn = {}
	for k = 1, 4 do
		local b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		b:SetWidth(40)
		b:SetHeight(20)
		b:SetPoint("RIGHT", row, "RIGHT", -(4 - k) * 41, 0)
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
local pmore = Text(pf, "", "GameFontDisableSmall", PW - 36, "RIGHT")

function L:RefreshPending()
	local list = P:PendingList()
	local n = table.getn(list)
	if n == 0 then pf:Hide(); return end
	local shown = math.min(n, PROWS)
	for i = 1, PROWS do
		local it = list[i]
		local row = prow[i]
		if it then
			row.item = it
			row.icon:SetTexture(P.iconCache[it.id] or "Interface\\Icons\\INV_Misc_QuestionMark")
			row.text:SetText(it.link .. ((it.count or 1) > 1 and (" |cffffd700x" .. it.count .. "|r") or ""))
			local sent = P:SentChoice(it.id)
			local sel = sent or P.prebid[it.id]
			if sent then row.text:SetText(row.text:GetText() .. " |cff888888sent|r") end
			for k = 1, 4 do
				if sel == PRE[k][1] then row.btn[k]:LockHighlight() else row.btn[k]:UnlockHighlight() end
				row.btn[k]:SetText((sel == PRE[k][1] and COLOR[PRE[k][1]] or "") .. PRE[k][2])
				if sent then row.btn[k]:Disable() else row.btn[k]:Enable() end
			end
			row:Show()
		else
			row.item = nil
			row:Hide()
		end
	end
	pf:SetHeight(52 + shown * 26 + ((n > PROWS) and 14 or 0) + 16)
	pmore:ClearAllPoints()
	pmore:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", -20, 16)
	pmore:SetText(n > PROWS and ("+" .. (n - PROWS) .. " more (hidden)") or "")
	pf:Show()
end

-- icons: GetItemInfo can be costly for an item this client never saw, so at most one lookup per second and
-- 3 tries per item, only while the panel is visible
P.iconCache = {}
local tries = {}
local acc = 0
pf:SetScript("OnUpdate", function()
	acc = acc + (arg1 or 0)
	if acc < 1 then return end
	acc = 0
	for _, it in ipairs(P:VisibleLoot()) do
		if not P.iconCache[it.id] and (tries[it.id] or 0) < 3 then
			tries[it.id] = (tries[it.id] or 0) + 1
			local _, _, _, _, _, _, _, _, tex = GetItemInfo("item:" .. it.id .. ":0:0:0")
			if tex then P.iconCache[it.id] = tex; L:RefreshPending() end
			return
		end
	end
end)
pf:SetScript("OnShow", function() L:RefreshPending() end)

-------------------------------------------------------------------------------
-- History window
-------------------------------------------------------------------------------
local HW, HH, HROWS = 380, 400, 15
local hf = CreateFrame("Frame", "SkullEPGPPlayerHistory", UIParent)
hf:SetWidth(HW)
hf:SetHeight(HH)
hf:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
hf:SetFrameStrata("DIALOG")
hf:SetMovable(true)
hf:EnableMouse(true)
hf:SetClampedToScreen(true)
hf:RegisterForDrag("LeftButton")
hf:SetScript("OnDragStart", function() this:StartMoving() end)
hf:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
hf:SetBackdrop(BACKDROP)
hf:Hide()

local htitle = Text(hf, "Skull EPGP - Loot history", "GameFontNormal", 240, "CENTER")
htitle:SetPoint("TOP", hf, "TOP", 0, -14)
local hclose = CreateFrame("Button", "SkullEPGPPlayerHistoryClose", hf, "UIPanelCloseButton")
hclose:SetPoint("TOPRIGHT", hf, "TOPRIGHT", -6, -6)
local hhelp = Text(hf, "Items won during this session (cleared when you reload or disconnect).", "GameFontDisableSmall", HW - 40)
hhelp:SetPoint("TOPLEFT", hf, "TOPLEFT", 22, -38)

local HTOP = 58
local hhdr = CreateFrame("Frame", nil, hf)
hhdr:SetWidth(HW - 70)
hhdr:SetHeight(14)
hhdr:SetPoint("TOPLEFT", hf, "TOPLEFT", 22, -HTOP)
do
	local a = Text(hhdr, "Item", "GameFontNormalSmall"); a:SetPoint("LEFT", hhdr, "LEFT", 0, 0)
	local b = Text(hhdr, "Winner", "GameFontNormalSmall"); b:SetPoint("LEFT", hhdr, "LEFT", 194, 0)
	local c = Text(hhdr, "Bid / roll", "GameFontNormalSmall"); c:SetPoint("LEFT", hhdr, "LEFT", 270, 0)
end
local hrow = {}
for i = 1, HROWS do
	local row = CreateFrame("Frame", nil, hf)
	row:SetWidth(HW - 70)
	row:SetHeight(18)
	row:SetPoint("TOPLEFT", hf, "TOPLEFT", 22, -HTOP - 16 - (i - 1) * 19)
	row:EnableMouse(true)
	row.text = Text(row, "", "GameFontHighlightSmall", 190)
	row.text:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.who = Text(row, "", "GameFontHighlightSmall", 72)
	row.who:SetPoint("LEFT", row, "LEFT", 194, 0)
	row.bid = Text(row, "", "GameFontHighlightSmall", 70)
	row.bid:SetPoint("LEFT", row, "LEFT", 270, 0)
	ItemTip(row, function() return row.entry and row.entry.link end)
	row:Hide()
	hrow[i] = row
end
local hempty = Text(hf, "Nothing won yet.", "GameFontDisableSmall", HW - 50, "CENTER")
hempty:SetPoint("TOPLEFT", hf, "TOPLEFT", 25, -HTOP - 24)
local hmore = Text(hf, "", "GameFontDisableSmall", 200, "RIGHT")
hmore:SetPoint("BOTTOMRIGHT", hf, "BOTTOMRIGHT", -24, 22)
local hclear = CreateFrame("Button", "SkullEPGPPlayerHistoryClear", hf, "UIPanelButtonTemplate")
hclear:SetWidth(120)
hclear:SetHeight(20)
hclear:SetPoint("BOTTOMLEFT", hf, "BOTTOMLEFT", 22, 18)
hclear:SetText("Clear history")
hclear:SetScript("OnClick", function() P.history = {}; L.offset = 0; L:RefreshHistory() end)
hf:EnableMouseWheel(true)
hf:SetScript("OnMouseWheel", function()
	if arg1 > 0 then L.offset = math.max(0, (L.offset or 0) - 1) else L.offset = (L.offset or 0) + 1 end
	L:RefreshHistory()
end)

function L:RefreshHistory()
	if not hf:IsShown() then return end
	local list = P.history
	local n = table.getn(list)
	local off = self.offset or 0
	if off > math.max(0, n - HROWS) then off = math.max(0, n - HROWS) end
	self.offset = off
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
	if n == 0 then hempty:Show() else hempty:Hide() end
	hmore:SetText(n > HROWS and (n .. " entries, scroll for more") or "")
end

function L:ToggleHistory()
	if hf:IsShown() then hf:Hide() else self.offset = 0; hf:Show(); self:RefreshHistory() end
end
hf:SetScript("OnShow", function() L:RefreshHistory() end)

-------------------------------------------------------------------------------
function L:Refresh()
	self:RefreshPending()
	self:RefreshHistory()
end

-- /epgpp loot : the pending list hangs under the bidding window, so open that one
function L:Show(view)
	if view == "history" then
		self.offset = 0
		hf:Show()
		self:RefreshHistory()
	else
		P.UI:ShowWindow()
		self:RefreshPending()
	end
end

-- the lock follows the announcement: refresh the panel whenever the bidding window refreshes
local oldRefresh = P.UI.Refresh
P.UI.Refresh = function(self)
	oldRefresh(self)
	L:RefreshPending()
end
