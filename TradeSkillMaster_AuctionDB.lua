-- register this file with Ace Libraries
local TSM = select(2, ...)
TSM = LibStub("AceAddon-3.0"):NewAddon(TSM, "TradeSkillMaster_AuctionDB", "AceEvent-3.0", "AceConsole-3.0")
local AceGUI = LibStub("AceGUI-3.0") -- load the AceGUI libraries

TSM.version = GetAddOnMetadata("TradeSkillMaster_AuctionDB","X-Curse-Packaged-Version") or GetAddOnMetadata("TradeSkillMaster_AuctionDB", "Version") -- current version of the addon

local BASE_DELAY = 0.05

local savedDBDefaults = {
	factionrealm = {
		playerAuctions = {},
		scanData = "",
		time = 0,
	},
	profile = {
		scanSelections = {},
	},
}

-- Called once the player has loaded WOW.
function TSM:OnInitialize()
	-- load the savedDB into TSM.db
	TSM.db = LibStub:GetLibrary("AceDB-3.0"):New("TradeSkillMaster_AuctionDBDB", savedDBDefaults, true)
	TSM.Scan = TSM.modules.Scan
	
	TSM:Deserialize(TSM.db.factionrealm.scanData)
	TSM.playerAuctions = TSM.db.factionrealm.playerAuctions
	
	TSM:RegisterEvent("PLAYER_LOGOUT", TSM.OnDisable)
	TSM:RegisterEvent("AUCTION_OWNED_LIST_UPDATE", "ScanPlayerAuctions")

	TSMAPI:RegisterModule("TradeSkillMaster_AuctionDB", TSM.version, GetAddOnMetadata("TradeSkillMaster_AuctionDB", "Author"), GetAddOnMetadata("TradeSkillMaster_AuctionDB", "Notes"))
	TSMAPI:RegisterIcon("AuctionDB", "Interface\\Icons\\Inv_Misc_Platnumdisks", function(...) TSM:LoadGUI(...) end, "TradeSkillMaster_AuctionDB")
	TSMAPI:RegisterSlashCommand("adbreset", TSM.Reset, "resets the data", true)
	TSMAPI:RegisterSlashCommand("adblookup", TSM.Lookup, "prints out information about a given item", true)
	TSMAPI:RegisterData("market", TSM.GetData)
	TSMAPI:RegisterData("playerAuctions", TSM.GetPlayerAuctions)
	TSMAPI:RegisterData("seenCount", TSM.GetSeenCount)
	
	TSM.db.factionrealm.time = 10 -- because AceDB won't save if we don't do this...
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
	if not itemID then return end
	itemID = TSMAPI:GetNewGem(itemID) or itemID
	if not TSM.data[itemID] then return end
	local stdDev = math.sqrt(TSM.data[itemID].M2/(TSM.data[itemID].n - 1))
	return TSM.data[itemID].correctedMean, TSM.data[itemID].quantity, TSM.data[itemID].lastSeen, stdDev, TSM.data[itemID].minBuyout
end

function TSM:Lookup(itemID)
	local name, link = GetItemInfo(itemID)
	itemID = TSMAPI:GetItemID(link)
	if not TSM.data[itemID] then return TSM:Print("No data for that item") end
	local stdDev = math.sqrt(TSM.data[itemID].M2/(TSM.data[itemID].n - 1))
	local value = math.floor(TSM.data[itemID].correctedMean/100+0.5)/100
	TSM:Print(name .. " has a market value of " .. value .. "gold and was seen " .. (TSM.data[itemID].quantity or "???") ..
		" times last scan and " .. TSM.data[itemID].n .. " times total. The stdDev is " .. stdDev .. ".")
end

function TSM:SetQuantity(itemID, quantity)
	TSM.data[itemID].quantity = quantity
end

function TSM:OneIteration(x, itemID) -- x is the market price in the current iteration
	TSM.data[itemID] = TSM.data[itemID] or {n=0, uncorrectedMean=0, correctedMean=0, M2=0, --[[dTimeResidual=0, dTimeResidualI=0,]] lastSeen=time(), filtered=false}
	local item = TSM.data[itemID]
	item.n = item.n + 1  -- partially from wikipedia;  cc-by-sa license
	local dTime = time() - item.lastSeen
	--[[if item.dTimeResidualI > 0 and dTime < item.dTimeResidual then
		dTime = item.dTimeResidual * math.exp(-item.dTimeResidualI)
		item.dTimeResidualI = item.dTimeResidualI + 1
	end]]
	local delta = x - item.uncorrectedMean
	item.uncorrectedMean = item.uncorrectedMean + delta/item.n
	item.M2 = item.M2 + delta*(x - item.uncorrectedMean)
	local stdDev = nil
	if item.n ~= 1 then
		stdDev = math.sqrt(item.M2/(item.n - 1))
	end
	--[[if (dTime >= 3600*24 and item.dTimeResidualI == 0) or (dTime > item.dTimeResidual and item.dTimeResidualI > 0) then
		item.dTimeResidual = dTime
		item.dTimeResidualI = 1
	end]]
	local c = 1.5
	if stdDev ~= nil and stdDev ~= 0 then -- some more filtering just to make sure anyone trying to reset a market
		if stdDev > 2*item.correctedMean then c = 1 end -- doesn't get through to us!
		if stdDev > 4*item.correctedMean then c = 0.7 end
	end
	if stdDev==nil or stdDev==0 or item.correctedMean == 0 or item.n <= 2 then
		item.correctedMean = item.uncorrectedMean
		if item.n == 2 then item.filtered = true end
	elseif (stdDev ~= 0 and item.correctedMean ~= 0 and (stdDev*c + item.correctedMean) > x and (item.correctedMean - stdDev*c) < x and item.n > 2) or item.filtered then
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

function TSM:Serialize()
	local results = {}
	for id, v in pairs(TSM.data) do
		tinsert(results, "d" .. id .. "," .. v.n .. "," .. v.uncorrectedMean .. "," .. v.correctedMean ..
			"," .. v.M2 .. "," .. v.lastSeen .. "," ..
			((not v.filtered and "0") or (v.filtered and "1")) .. "," .. (v.quantity or 0) .. "," .. (v.minBuyout or "n"))
	end
	TSM.db.factionrealm.scanData = table.concat(results)
end

function TSM:Deserialize(data)
	TSM.data = TSM.data or {}
	for k,a,b,c,d,g,h,i,j in string.gmatch(data, "d([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^d]+)") do
		TSM.data[tonumber(k)] = {n=tonumber(a),uncorrectedMean=tonumber(b),correctedMean=tonumber(c),M2=tonumber(d),lastSeen=tonumber(g),filtered=(h == "1" or h == "t"),quantity=tonumber(i),minBuyout=tonumber(j)}
	end
end

function TSM:LoadGUI(parent)
	--Truncate will leave off silver or copper if gold is greater than 100.
	local function CopperToGold(c)
		local GOLD_TEXT = "\124cFFFFD700g\124r"
		local SILVER_TEXT = "\124cFFC7C7CFs\124r"
		local COPPER_TEXT = "\124cFFEDA55Fc\124r"
		local g = floor(c/10000)
		local s = floor(mod(c/100,100))
		c = floor(mod(c, 100))
		local moneyString = ""
		if g > 0 then
			moneyString = string.format("%d%s", g, GOLD_TEXT)
		end
		if s > 0 and (g < 100) then
			moneyString = string.format("%s%d%s", moneyString, s, SILVER_TEXT)
		end
		if c > 0 and (g < 100) then
			moneyString = string.format("%s%d%s", moneyString, c, COPPER_TEXT)
		end
		if moneyString == "" then moneyString = "0"..COPPER_TEXT end
		return moneyString
	end

	local container = AceGUI:Create("SimpleGroup")
	container:SetLayout("list")
	parent:AddChild(container)
	
	local spacer = AceGUI:Create("Label")
	spacer:SetFullWidth(true)
	spacer:SetText(" ")
	container:AddChild(spacer)
	
	local text = AceGUI:Create("Label")
	text:SetFullWidth(true)
	text:SetFontObject(GameFontNormalLarge)
	container:AddChild(text)
	
	local editBox = AceGUI:Create("EditBox")
	editBox:SetWidth(200)
	editBox:SetLabel("Item Lookup:")
	editBox:SetCallback("OnEnterPressed", function(_, _, value)
			if not value then return TSM:Print("No data for that item") end
			local itemID
			local name, link = GetItemInfo(value)
			if not link then
				for ID in pairs(TSM.data) do
					local name = GetItemInfo(ID)
					if name == value then
						itemID = ID
					end
				end
			else
				itemID = TSMAPI:GetItemID(link)
			end
			if not TSM.data[itemID] then return TSM:Print("No data for that item") end
			local stdDev = math.sqrt(TSM.data[itemID].M2/(TSM.data[itemID].n - 1))
			local value = CopperToGold(TSM.data[itemID].correctedMean)
			text:SetText(name .. " has a market value of " .. value .. " and was seen " .. (TSM.data[itemID].quantity or "???") ..
				" times last scan and " .. TSM.data[itemID].n .. " times total. The stdDev is " .. stdDev .. ".")
		end)
	container:AddChild(editBox, text)
end

function TSM:ScanPlayerAuctions()
	for itemID in pairs(TSM.playerAuctions) do
		if type(itemID) == "number" then
			TSM.playerAuctions[itemID] = 0
		end
	end
	TSM.playerAuctions.time = GetTime()
	
	for i=1, GetNumAuctionItems("owner") do
		local itemID = TSMAPI:GetItemID(GetAuctionItemLink("owner", i))
		local _, _, quantity, _, _, _, _, _, _, _, _, _, wasSold = GetAuctionItemInfo("owner", i)
		if wasSold == 0 then
			TSM.playerAuctions[itemID] = (TSM.playerAuctions[itemID] or 0) + quantity
		end
	end
end

function TSM:GetPlayerAuctions(itemID)
	if not itemID then return "Invalid argument" end
	if (GetTime() - (TSM.playerAuctions.time or 0)) > (60*60) then return 0 end -- data is too old
	return TSM.playerAuctions[itemID] or 0
end

function TSM:GetSeenCount(itemID)
	if not TSM.data[itemID] then return end
	return TSM.data[itemID].n
end