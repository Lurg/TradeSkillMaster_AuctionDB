-- register this file with Ace Libraries
local TSM = select(2, ...)
TSM = LibStub("AceAddon-3.0"):NewAddon(TSM, "TradeSkillMaster_AuctionDB", "AceEvent-3.0", "AceConsole-3.0", "AceSerializer-3.0")

TSM.version = GetAddOnMetadata("TradeSkillMaster_AuctionDB", "Version") -- current version of the addon

local BASE_DELAY = 0.05

local savedDBDefaults = {
	factionrealm = {
		scanData = {},
		recentAuctions = {},
	},
}

-- Called once the player has loaded WOW.
function TSM:OnInitialize()
	local sTime = GetTime()
	-- load the savedDB into TSM.db
	TSM.db = LibStub:GetLibrary("AceDB-3.0"):New("TradeSkillMaster_AuctionDBDB", savedDBDefaults, true)
	TSM:Deserialize(TSM.db.factionrealm.scanData)
	TSM:RegisterEvent("PLAYER_LOGOUT", TSM.OnDisable)
	print(TSM.db.factionrealm.time, GetTime() - sTime)

	TSMAPI:RegisterModule("TradeSkillMaster_AuctionDB", TSM.version, "Sapu", GetAddOnMetadata("TradeSkillMaster_AuctionDB", "Notes"))
	TSMAPI:RegisterSlashCommand("adbstart", TSM.Start, "starts collecting data on auctions seen", true)
	TSMAPI:RegisterSlashCommand("adbstop", TSM.Stop, "stops collecting data on auctions seen", true)
	TSMAPI:RegisterSlashCommand("adbreset", TSM.Reset, "resets the data", true)
	TSMAPI:RegisterSlashCommand("adblookup", TSM.Lookup, "looks up the market value for an item", true)
	TSMAPI:RegisterData("market", TSM.GetData)
end

function TSM:OnDisable()
	local sTime = GetTime()
	TSM:Serialize(TSM.data)
	TSM.db.factionrealm.time = GetTime() - sTime
end

function TSM:Start()
	print("Started")
	TSM:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
end

local delay = CreateFrame("Frame")
delay.time = 0
delay.retries = 3
delay.retryItems = {}
delay:SetScript("OnShow", function(self) self.time = BASE_DELAY end)
delay:SetScript("OnUpdate", function(self, elapsed)
		self.time = self.time - elapsed
		if self.time <= 0 then
			TSM:ScanAuctions()
			self:Hide()
		end
	end)
delay:Hide()

function TSM:AUCTION_ITEM_LIST_UPDATE()
	TSM:UnregisterEvent("AUCTION_ITEM_LIST_UPDATE")
	TSM:ScanAuctions()
	TSM:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
end

-- scans the currently shown page of auctions and collects all the data
function TSM:ScanAuctions()
	if #(delay.retryItems) > 0 then
		local retry = false
		for _, i in pairs(delay.retryItems) do
			local name, _, quantity, _, _, _, bid, _, buyout, _, _, owner = GetAuctionItemInfo("list", i)
			if name and buyout then
				-- this is good data so save it!
				i = nil
			else
				retry = true
			end
		end
		if retry and delay.retries > 0 then
			delay.retries = delay.retries - 1
			delay:Show()
		else
			delay.retries = 3
		end
		return
	end
	local sTime = GetTime()

	for i=1, GetNumAuctionItems("list") do
		-- checks whether or not the name and owner of the auctions are valid
		-- if either are invalid, the data is bad
		local name, _, quantity, _, _, _, bid, _, buyout, _, _, owner = GetAuctionItemInfo("list", i)
		if name and buyout then
			-- this data is valid
			TSM:OneIteration(buyout/quantity, TSM:GetSafeLink(GetAuctionItemLink("list", i)))
		else
			tinsert(delay.retryItems, i)
		end
	end
	
	if #(delay.retryItems) > 0 then
		delay:Show()
		delay.retries = 3
	end
end

function TSM:Stop()
	TSM:UnregisterEvent("AUCTION_ITEM_LIST_UPDATE")
	for i, v in pairs(TSM.data) do
		print("index = " .. i)
		foreach(v, function(a, b) if a == "u" or a == "c" then print(a, TSM:FormatTextMoney(b)) else print(a, b) end end)
	end
end

function TSM:Reset()
	for i in pairs(TSM.data) do
		TSM.data[i] = nil
	end
	print("Reset Data")
end

function TSM:Lookup(link)
	local name, nLink = GetItemInfo(link)
	if not name then
		TSM:Print("Invalid item \"" .. link .. "\". Check your spelling or try using an item link instead of the name.")
		return
	end
	
	local itemID = TSM:GetSafeLink(nLink)
	if itemID and TSM.data[itemID] then
		TSM:Print("The market value of " .. name .. " is " .. TSM:FormatTextMoney(TSM.data[itemID].c) ..
			" and the item has been seen " .. TSM.data[itemID].n .. " times.")
	else
		TSM:Print("No data for " .. name)
	end
end

function TSM:GetData(itemID, extra)
	if not TSM.data[itemID] then return end
	return TSM.data[itemID].c, TSM.data[itemID].n
end

function TSM:OneIteration(x, itemID) -- x is the market price in the current iteration
	TSM.data[itemID] = TSM.data[itemID] or {n=0, u=0, c=0, m=0, r=0, l=0, t=time(), f=false}
	local item = TSM.data[itemID]
	item.n = item.n + 1  -- partially from wikipedia;  cc-by-sa license
	local dTime = time() - item.t
	item.t = time()
	if item.l > 0 and dTime < item.r then
		dTime = item.r * math.exp(-item.l)
		item.l = item.l + 1
	end
	local delta = x - item.u
	item.u = item.u + delta/item.n
	item.m = item.m + delta*(x - item.u)
	local stdDev = nil
	if item.n ~= 1 then
		stdDev = math.sqrt(item.m/(item.n - 1))
	end
	if (dTime >= 3600*24 and item.l == 0) or (dTime > item.r and item.l > 0) then
		item.r = dTime
		item.l = 1
	end
	if stdDev==nil or stdDev==0 or item.c == 0 or item.n <= 2 then
		item.c = item.u
		if item.n == 2 then item.f = true end
	elseif (stdDev ~= 0 and item.c ~= 0 and (stdDev + item.c) > x and (item.c - stdDev) < x and item.n > 2) or (item.f) then
		local w = TSM:GetWeight(dTime, item.n)
		item.c = w*item.c + (1-w)*x
		if stdDev > 1.5*math.abs(item.c - x) then item.f = false end
	end
end

function TSM:GetWeight(dTime, i)
	-- k here is valued for w value of 0.5 after 2 weeks
	-- k = -1209600 / log_0.5(i/2)
	-- a "good" idea would be to precalculate k for values of i either at addon load or with a script
	--   to cut down on processing time.  Also note that as i -> 2, k -> negative infinity
	--   so we'd like to avoid i <= 2
	if dTime < 3600 then return (i-1)/i end
	local s = 14*24*60*60 -- 2 weeks
	local k = -s/(math.log(i/2)/math.log(0.5))
	return (i-i^(dTime/(dTime + k)))/i
end

function TSM:GetSafeLink(link)
	if not link then return end
	local s, e = string.find(link, "|H(.-):([-0-9]+)")
	local fLink = string.sub(link, s+7, e)
	return tonumber(fLink) or fLink
end

-- Stolen from Tekkub!
local GOLD_TEXT = "|cffffd700g|r"
local SILVER_TEXT = "|cffc7c7cfs|r"
local COPPER_TEXT = "|cffeda55fc|r"

-- Truncates to save space: after 10g stop showing copper, after 100g stop showing silver
function TSM:FormatTextMoney(money)
	local gold = math.floor(money / COPPER_PER_GOLD)
	local silver = math.floor((money - (gold * COPPER_PER_GOLD)) / COPPER_PER_SILVER)
	local copper = math.floor(math.fmod(money, COPPER_PER_SILVER))
	local text = ""
	
	-- Add gold
	if gold>0 then
		text = string.format("%d%s ", gold, GOLD_TEXT)
	end
	
	-- Add silver
	if silver>0 and gold<100 then
		text = string.format("%s%d%s ", text, silver, SILVER_TEXT)
	end
	
	-- Add copper if we have no silver/gold found, or if we actually have copper
	if text == "" or (copper>0 and gold<=10) then
		text = string.format("%s%d%s ", text, copper, COPPER_TEXT)
	end
	
	return string.trim(text)
end

function TSM:Serialize(data)
	local results = {}
	for id, v in pairs(data) do
		tinsert(results, "d" .. id .. "," .. v.n .. "," .. v.u .. "," .. v.c .. "," .. v.m .. "," .. v.r .. "," .. v.l .. "," .. v.t .. "," .. ((not v.f and "f") or (v.f and "t")))
	end
	
	TSM.db.factionrealm.scanData = table.concat(results)
end

function TSM:Deserialize(data)
	local results = {}
	for k,a,b,c,d,e,f,g,h in string.gmatch(data, "d([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^d]+)") do
		results[k] = {n=a,u=b,c=c,m=d,r=e,l=f,t=g, f=(h == "t")}
	end
	
	TSM.data = results
end