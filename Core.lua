-- Skull EPGP Player (WoW 1.12 / Lua 5.0)
-- Receives the loot announcements of the officer addon (SkullEPGP_Officer) and lets you answer with one click.
-- Protocol (addon prefix SKULLEPGP, sent by the master looter / raid leader):
--   AUC;<id>;<seconds left>;<copies>;<link>      bidding open
--   BID;<id>;<char>;<MIN|NEED|MAX|ROLL>;<roll>;<pr>   somebody bid / rolled
--   END;<id>    bidding closed        CAN;<id>   cancelled
--   WIN;<id>;<char>;<tier>;<cost>               item awarded
--   P;<Main/Alt>,<ep>,<gp>;...                   priorities       CFG;<MIN>;<NEED>;<MAX>;<baseGP>   prices
-- Player -> officer: "REQ" (asks for my priority, prices and the current announcement); the officer answers "NP" when I am not in the list
SkullEPGPP = {}
local P = SkullEPGPP
P.PREFIX = "SKULLEPGP"
P.TIERS = { ROLL = 1, MIN = 2, NEED = 3, MAX = 4 }
P.auction = nil
P.pending = nil            -- { choice, t } : a choice was sent, waiting for the officer's confirmation
P.lastReq = -100

local DEFAULTS = {
	autoShow = true,
	autoClose = true,
	cfg = { MIN = 5, NEED = 15, MAX = 45, baseGP = 0 },
	me = nil,              -- { ep, gp } last known values of this character's main
}

function P:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff49C0C0[EPGP]|r " .. tostring(msg))
end

local function split(s, sep)
	local out, pos = {}, 1
	while true do
		local a = string.find(s, sep, pos, true)
		if not a then
			table.insert(out, string.sub(s, pos))
			break
		end
		table.insert(out, string.sub(s, pos, a - 1))
		pos = a + string.len(sep)
	end
	return out
end

local function copyDefaults(dst, src)
	for k, v in pairs(src) do
		if dst[k] == nil then
			if type(v) == "table" then
				dst[k] = {}
				copyDefaults(dst[k], v)
			else
				dst[k] = v
			end
		elseif type(v) == "table" and type(dst[k]) == "table" then
			copyDefaults(dst[k], v)
		end
	end
end

function P:InitDB()
	SkullEPGP_PlayerDB = SkullEPGP_PlayerDB or {}
	self.db = SkullEPGP_PlayerDB
	copyDefaults(self.db, DEFAULTS)
end

-------------------------------------------------------------------------------
-- Who may send us announcements: the raid / party leader and the master looter
-------------------------------------------------------------------------------
function P:IsOfficerName(name)
	if not name then return false end
	name = string.lower(name)
	local nraid = GetNumRaidMembers() or 0
	if nraid > 0 then
		for i = 1, nraid do
			local n, rank = GetRaidRosterInfo(i)
			if n and string.lower(n) == name and rank and rank >= 1 then return true end   -- leader or assistant
		end
	else
		for i = 1, (GetNumPartyMembers() or 0) do
			local u = "party" .. i
			local n = UnitName(u)
			if n and string.lower(n) == name and UnitIsPartyLeader and UnitIsPartyLeader(u) then return true end
		end
		if string.lower(UnitName("player")) == name and IsPartyLeader and IsPartyLeader() then return true end
	end
	local method, partyID, raidID = GetLootMethod()
	if method == "master" then
		local u
		if raidID and raidID > 0 then u = "raid" .. raidID elseif partyID == 0 then u = "player" elseif partyID and partyID > 0 then u = "party" .. partyID end
		local n = u and UnitName(u)
		if n and string.lower(n) == name then return true end
	end
	return false
end

-------------------------------------------------------------------------------
-- Priority
-------------------------------------------------------------------------------
function P:PR(ep, gp)
	local den = (gp or 0) + (self.db.cfg.baseGP or 0)
	if den < 1 then den = 1 end
	return (ep or 0) / den
end

function P:MyPR()
	local me = self.db and self.db.me
	if not me then return nil end
	return self:PR(me.ep, me.gp), me.ep, me.gp
end

-------------------------------------------------------------------------------
-- Messages from the officer
-------------------------------------------------------------------------------
function P:HandleMessage(text, sender)
	if not self.db or not text then return end
	local f = split(text, ";")
	local tag = f[1]
	if tag == "P" then
		local me = string.lower(UnitName("player"))
		for i = 2, table.getn(f) do
			local e = split(f[i], ",")
			local ep, gp = tonumber(e[2]), tonumber(e[3])
			if e[1] and ep and gp then
				for name in string.gfind(e[1], "[^/]+") do
					if string.lower(name) == me then
						self.db.me = { ep = ep, gp = gp }
						self.db.noEntry = nil
						if self.UI then self.UI:Refresh() end
					end
				end
			end
		end
	elseif tag == "NP" then
		if not f[2] or string.lower(f[2]) ~= string.lower(UnitName("player")) then return end
		self.db.noEntry = true            -- the officer has no priority for me: stop asking
		if self.UI then self.UI:Refresh() end
	elseif tag == "CFG" then
		local mn, nd, mx, base = tonumber(f[2]), tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
		if mn and nd and mx then
			self.db.cfg.MIN, self.db.cfg.NEED, self.db.cfg.MAX = mn, nd, mx
			self.db.cfg.baseGP = base or 0
			if self.UI then self.UI:Refresh() end
		end
	elseif tag == "AUC" then
		local id, secs, count = tonumber(f[2]), tonumber(f[3]), tonumber(f[4])
		if not id or not secs then return end
		local link = table.concat(f, ";", 5)
		local a = self.auction
		if a and a.id == id then
			a.endTime = GetTime() + secs           -- answer to REQ for the same announcement: just resync the timer
			if a.state == "closed" then a.state = "open" end
		else
			self.auction = { id = id, link = link, count = count or 1, endTime = GetTime() + secs, state = "open",
				bids = {}, winners = {}, myChoice = nil, started = GetTime(), test = (sender == "test") }
			self.pending = nil
			if self.UI and self.db.autoShow then self.UI:ShowWindow() end
			PlaySound("igQuestLogOpen")
			if not self.db.me and not self.db.noEntry then self:Request() end
		end
		if self.UI then self.UI:Refresh() end
	elseif tag == "BID" then
		local a = self.auction
		local id = tonumber(f[2])
		if not a or a.id ~= id or not f[3] then return end
		local bid, roll, pr = f[4], tonumber(f[5]) or 0, tonumber(f[6]) or 0
		if not self.TIERS[bid] then return end
		a.bids[string.lower(f[3])] = { char = f[3], bid = bid, roll = (roll > 0) and roll or nil, pr = pr, t = GetTime() }
		if string.lower(f[3]) == string.lower(UnitName("player")) then
			a.myChoice = bid
			self.pending = nil
		end
		if self.UI then self.UI:Refresh() end
	elseif tag == "END" or tag == "CAN" then
		local a = self.auction
		if a and a.id == tonumber(f[2]) then
			a.state = (tag == "END") and "closed" or "cancelled"
			a.closedAt = GetTime()
			self.pending = nil
			if self.UI then self.UI:Refresh() end
		end
	elseif tag == "WIN" then
		local a = self.auction
		if not a or a.id ~= tonumber(f[2]) or not f[3] then return end
		table.insert(a.winners, { char = f[3], bid = f[4], cost = tonumber(f[5]) or 0 })
		a.bids[string.lower(f[3])] = nil
		if table.getn(a.winners) >= (a.count or 1) then
			a.state = "awarded"
			a.closedAt = GetTime()
		end
		if string.lower(f[3]) == string.lower(UnitName("player")) then
			self:Print("|cff33cc33You won " .. a.link .. "!|r")
		end
		if self.UI then self.UI:Refresh() end
	end
end

function P:OnAddonMessage(prefix, text, channel, sender)
	if prefix ~= self.PREFIX or not self.db then return end
	if text == "REQ" then return end                       -- player -> officer message
	if string.len(text) > 2 and string.sub(text, 3, 3) == ";" and string.sub(text, 1, 1) == "S" then return end   -- officer <-> officer sync
	if not self:IsOfficerName(sender) then return end
	self:HandleMessage(text, sender)
end

-------------------------------------------------------------------------------
-- Choices
-------------------------------------------------------------------------------
-- may the button for this choice (ROLL / MIN / NEED / MAX) be used now ?
function P:CanChoose(choice)
	local a = self.auction
	if not a or a.state ~= "open" or self.pending then return false end
	if a.myChoice == nil then return true end
	return a.myChoice == "NEED" and choice == "MAX"       -- one choice per announcement; NEED can be upgraded to MAX
end

function P:Channel()
	if GetNumRaidMembers() > 0 then return "RAID" end
	if GetNumPartyMembers() > 0 then return "PARTY" end
	return nil
end

function P:Choose(choice)
	if not self:CanChoose(choice) then return false end
	if self.auction.test then
		self:Print("(test) would send: " .. choice)
		self.auction.myChoice = choice
		if self.UI then self.UI:Refresh() end
		return true
	end
	if choice == "ROLL" then
		local ok = pcall(RandomRoll, 1, 100)
		if not ok then self:Print("Could not roll: type /roll in the chat.") return false end
	else
		local ch = self:Channel()
		if not ch then self:Print("You are not in a group.") return false end
		SendChatMessage(choice, ch)
	end
	self.pending = { choice = choice, t = 0 }
	if self.UI then self.UI:Refresh() end
	return true
end

-- bids sorted like the officer's ranking: tier, priority, roll, arrival
function P:SortedBids()
	local a = self.auction
	local list = {}
	if not a then return list end
	for _, b in pairs(a.bids) do table.insert(list, b) end
	table.sort(list, function(x, y)
		local tx, ty = self.TIERS[x.bid], self.TIERS[y.bid]
		if tx ~= ty then return tx > ty end
		if tx > 1 and x.pr ~= y.pr then return x.pr > y.pr end
		local rx, ry = x.roll or 0, y.roll or 0
		if rx ~= ry then return rx > ry end
		if x.t ~= y.t then return x.t < y.t end
		return x.char < y.char
	end)
	return list
end

-------------------------------------------------------------------------------
-- Requests, timers, events
-------------------------------------------------------------------------------
function P:Request()
	local now = GetTime()
	if now - self.lastReq < 5 then return end
	local ch = self:Channel()
	if not ch then return end
	self.lastReq = now
	SendAddonMessage(self.PREFIX, "REQ", ch)
end

P.tick = 0
function P:OnUpdate(elapsed)
	if not self.db then return end
	self.tick = self.tick + (elapsed or 0)
	if self.pending then
		self.pending.t = self.pending.t + (elapsed or 0)
		if self.pending.t > 3 then
			self.pending = nil
			self:Print("No confirmation from the officer yet for your choice (not in the EPGP list, or the choice was refused).")
			if self.UI then self.UI:Refresh() end
		end
	end
	-- no priority yet (the officer imported before we were connected): ask again every 30 s, silently
	self.reqTick = (self.reqTick or 0) + (elapsed or 0)
	if self.reqTick >= 30 then
		self.reqTick = 0
		if self.inGroup and not self.db.me and not self.db.noEntry then self:Request() end
	end
	if self.tick < 0.25 then return end
	self.tick = 0
	local a = self.auction
	if a and a.closedAt and self.db.autoClose and GetTime() - a.closedAt > 20 and self.UI then
		self.UI:HideWindow()
	end
	if self.UI then self.UI:UpdateTimer() end
end

function P:OnEvent(event, a1, a2, a3, a4)
	if event == "VARIABLES_LOADED" then
		self:InitDB()
		if self.UI then self.UI:ApplySaved() end
	elseif not self.db then
		return
	elseif event == "PLAYER_ENTERING_WORLD" or event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
		local n = (GetNumRaidMembers() or 0) + (GetNumPartyMembers() or 0)
		if n > 0 and not self.inGroup then self.db.noEntry = nil; self:Request() end      -- just joined a group: ask for my priority and the current item
		self.inGroup = n > 0
		if n == 0 then self.auction = nil; if self.UI then self.UI:HideWindow() end end
	elseif event == "CHAT_MSG_ADDON" then
		self:OnAddonMessage(a1, a2, a3, a4)
	end
end

local frame = CreateFrame("Frame", "SkullEPGPPlayerEvents")
local evs = { "VARIABLES_LOADED", "PLAYER_ENTERING_WORLD", "RAID_ROSTER_UPDATE", "PARTY_MEMBERS_CHANGED", "CHAT_MSG_ADDON" }
for i = 1, table.getn(evs) do frame:RegisterEvent(evs[i]) end
frame:SetScript("OnEvent", function() P:OnEvent(event, arg1, arg2, arg3, arg4) end)
frame:SetScript("OnUpdate", function() P:OnUpdate(arg1) end)

-------------------------------------------------------------------------------
-- Slash command
-------------------------------------------------------------------------------
SLASH_SKULLEPGPP1 = "/epgpp"
SLASH_SKULLEPGPP2 = "/skullepgpp"
SlashCmdList["SKULLEPGPP"] = function(msg)
	if not P.db then return end
	msg = string.lower(msg or "")
	if msg == "" then
		P.UI:Toggle()
	elseif msg == "test" then
		P:HandleMessage("CFG;5;15;45;10", "test")
		P:HandleMessage("P;" .. UnitName("player") .. ",5726.24,6.52", "test")
		P:HandleMessage("AUC;999;45;1;|cffa335ee|Hitem:19019:0:0:0|h[Thunderfury, Blade of the Windseeker]|h|r", "test")
		P:HandleMessage("BID;999;Alice;MAX;0;346.67", "test")
		P:HandleMessage("BID;999;Bob;NEED;0;200.12", "test")
		P:HandleMessage("BID;999;Carol;MIN;0;150.5", "test")
		P:HandleMessage("BID;999;Dave;ROLL;87;0", "test")
		P:Print("Test announcement shown (your buttons will not send anything useful).")
	elseif msg == "auto on" or msg == "auto off" then
		P.db.autoShow = (msg == "auto on")
		P:Print("Open the window automatically on an announcement: " .. (P.db.autoShow and "yes" or "no"))
	elseif msg == "reset" then
		P.UI:ResetPosition()
	elseif msg == "req" then
		P.lastReq = -100
		P:Request()
	else
		P:Print("/epgpp - show / hide the window   |   /epgpp auto on|off   |   /epgpp reset   |   /epgpp req (ask the officer for your priority)   |   /epgpp test")
	end
end
