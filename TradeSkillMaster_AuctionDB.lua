-- register this file with Ace Libraries
local TSM = select(2, ...)
TSM = LibStub("AceAddon-3.0"):NewAddon(TSM, "TradeSkillMaster_AuctionDB", "AceEvent-3.0", "AceConsole-3.0")

TSM.version = GetAddOnMetadata("TradeSkillMaster_AuctionDB", "Version") -- current version of the addon

local BASE_DELAY = 0.05

local savedDBDefaults = {
	factionrealm = {
		scanData = "",
		time = 0,
	},
	profile = {
		scanSelections = {},
	},
}

-- Called once the player has loaded WOW.
function TSM:OnInitialize()
	local sTime = GetTime()
	-- load the savedDB into TSM.db
	TSM.db = LibStub:GetLibrary("AceDB-3.0"):New("TradeSkillMaster_AuctionDBDB", savedDBDefaults, true)
	TSM:Deserialize(TSM.db.factionrealm.scanData)
	TSM:RegisterEvent("PLAYER_LOGOUT", TSM.OnDisable)
	TSM.Scan = TSM.modules.Scan

	TSMAPI:RegisterModule("TradeSkillMaster_AuctionDB", TSM.version, GetAddOnMetadata("TradeSkillMaster_Crafting", "Author"), GetAddOnMetadata("TradeSkillMaster_AuctionDB", "Notes"))
	TSMAPI:RegisterSlashCommand("adbreset", TSM.Reset, "resets the data", true)
	TSMAPI:RegisterData("market", TSM.GetData)
	TSM.db.factionrealm.time = 10 -- because AceDB won't save if we don't do this...
	
	TSM:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
end

function TSM:OnDisable()
	local sTime = GetTime()
	TSM:Serialize(TSM.data)
	TSM.db.factionrealm.time = GetTime() - sTime
end

function TSM:Reset()
	for i in pairs(TSM.data) do
		TSM.data[i] = nil
	end
	print("Reset Data")
end

function TSM:GetData(itemID)
	if not TSM.data[itemID] then return end
	local stdDev = math.sqrt(TSM.data[itemID].M2/(TSM.data[itemID].n - 1))
	return TSM.data[itemID].correctedMean, TSM.data[itemID].quantity, TSM.data[itemID].lastSeen, stdDev
end

function TSM:SetQuantity(itemID, quantity)
	TSM.data[itemID].quantity = quantity
end

function TSM:OneIteration(x, itemID) -- x is the market price in the current iteration
	TSM.data[itemID] = TSM.data[itemID] or {n=0, uncorrectedMean=0, correctedMean=0, M2=0, dTimeResidual=0, dTimeResidualI=0, lastSeen=time(), filtered=false}
	local item = TSM.data[itemID]
	item.n = item.n + 1  -- partially from wikipedia;  cc-by-sa license
	local dTime = time() - item.lastSeen
	item.lastSeen = time()
	if item.dTimeResidualI > 0 and dTime < item.dTimeResidual then
		dTime = item.dTimeResidual * math.exp(-item.dTimeResidualI)
		item.dTimeResidualI = item.dTimeResidualI + 1
	end
	local delta = x - item.uncorrectedMean
	item.uncorrectedMean = item.uncorrectedMean + delta/item.n
	item.M2 = item.M2 + delta*(x - item.uncorrectedMean)
	local stdDev = nil
	if item.n ~= 1 then
		stdDev = math.sqrt(item.M2/(item.n - 1))
	end
	if (dTime >= 3600*24 and item.dTimeResidualI == 0) or (dTime > item.dTimeResidual and item.dTimeResidualI > 0) then
		item.dTimeResidual = dTime
		item.dTimeResidualI = 1
	end
	if stdDev==nil or stdDev==0 or item.correctedMean == 0 or item.n <= 2 then
		item.correctedMean = item.uncorrectedMean
		if item.n == 2 then item.filtered = true end
	elseif (stdDev ~= 0 and item.correctedMean ~= 0 and (stdDev + item.correctedMean) > x and (item.correctedMean - stdDev) < x and item.n > 2) or (item.filtered) then
		local w = TSM:GetWeight(dTime, item.n)
		item.correctedMean = w*item.correctedMean + (1-w)*x
		if stdDev > 1.5*math.abs(item.correctedMean - x) then item.filtered = false end
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
	return tonumber(fLink)
end

function TSM:Serialize()
	local results = {}
	for id, v in pairs(TSM.data) do
		tinsert(results, "d" .. id .. "," .. v.n .. "," .. v.uncorrectedMean .. "," .. v.correctedMean .. "," .. v.M2 .. "," .. v.dTimeResidual .. "," .. v.dTimeResidualI .. "," .. v.lastSeen .. "," .. ((not v.filtered and "f") or (v.filtered and "t")))
	end
	TSM.db.factionrealm.scanData = {}
	TSM.db.factionrealm.scanData = table.concat(results)
end

function TSM:Deserialize(data)
	TSM.data = TSM.data or {}
	for k,a,b,correctedMean,d,e,filtered,g,h in string.gmatch(data, "d([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^d]+)") do
		TSM.data[k] = {n=a,uncorrectedMean=b,correctedMean=correctedMean,M2=d,dTimeResidual=e,dTimeResidualI=filtered,lastSeen=g, filtered=(h == "t")}
	end
end