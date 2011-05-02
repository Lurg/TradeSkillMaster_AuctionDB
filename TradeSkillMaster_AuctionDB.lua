-- register this file with Ace Libraries
local TSM = select(2, ...)
TSM = LibStub("AceAddon-3.0"):NewAddon(TSM, "TradeSkillMaster_AuctionDB", "AceEvent-3.0", "AceConsole-3.0")
local AceGUI = LibStub("AceGUI-3.0") -- load the AceGUI libraries

TSM.version = GetAddOnMetadata("TradeSkillMaster_AuctionDB","X-Curse-Packaged-Version") or GetAddOnMetadata("TradeSkillMaster_AuctionDB", "Version") -- current version of the addon
local L = LibStub("AceLocale-3.0"):GetLocale("TradeSkillMaster_AuctionDB") -- loads the localization table

local SECONDS_PER_DAY = 60*60*24

local savedDBDefaults = {
	factionrealm = {
		playerAuctions = {},
		scanData = "",
		time = 0,
	},
	profile = {
		scanSelections = {},
		getAll = false,
		tooltip = true,
		blockAuc = false,
		resultsPerPage = 50,
		resultsSortOrder = "ascending",
		resultsSortMethod = "name",
		hidePoorQualityItems = true,
	},
}

-- Called once the player has loaded WOW.
function TSM:OnInitialize()
	-- load the savedDB into TSM.db
	TSM.db = LibStub:GetLibrary("AceDB-3.0"):New("TradeSkillMaster_AuctionDBDB", savedDBDefaults, true)
	TSM.Scan = TSM.modules.Scan
	TSM.GUI = TSM.modules.GUI
	TSM.Config = TSM.modules.Config
	
	TSM:Deserialize(TSM.db.factionrealm.scanData)
	TSM.playerAuctions = TSM.db.factionrealm.playerAuctions
	
	TSM:RegisterEvent("PLAYER_LOGOUT", TSM.OnDisable)
	TSM:RegisterEvent("AUCTION_OWNED_LIST_UPDATE", "ScanPlayerAuctions")

	TSMAPI:RegisterModule("TradeSkillMaster_AuctionDB", TSM.version, GetAddOnMetadata("TradeSkillMaster_AuctionDB", "Author"), GetAddOnMetadata("TradeSkillMaster_AuctionDB", "Notes"))
	TSMAPI:RegisterIcon("AuctionDB", "Interface\\Icons\\Inv_Misc_Platnumdisks", function(...) TSM.Config:Load(...) end, "TradeSkillMaster_AuctionDB")
	TSMAPI:RegisterSlashCommand("adbreset", TSM.Reset, L["Resets AuctionDB's scan data"], true)
	TSMAPI:RegisterData("market", TSM.GetData)
	TSMAPI:RegisterData("seenCount", TSM.GetSeenCount)
	
	if TSM.db.profile.tooltip then
		TSMAPI:RegisterTooltip("TradeSkillMaster_AuctionDB", function(...) return TSM:LoadTooltip(...) end)
	end
	
	local toRemove = {}
	for index, data in pairs(TSM.playerAuctions) do
		if type(index) ~= "string" or index == "time" then
			tinsert(toRemove, index)
		elseif type(data) == "table" then
			local toRemove2 = {}
			for i, v in pairs(data) do
				if v == 0 then tinsert(toRemove2, i) end
			end
			for _, i in ipairs(toRemove2) do
				data[i] = nil
			end
		end
	end
	
	for _, index in ipairs(toRemove) do
		TSM.playerAuctions[index] = nil
	end
	
	TSM.db.factionrealm.time = 10 -- because AceDB won't save if we don't do this...
	TSM.db.factionrealm.testData = nil
end

function TSM:OnEnable()
	TSMAPI:CreateTimeDelay("auctiondb_test", 1, TSM.Check)
end

function TSM:OnDisable()
	local sTime = GetTime()
	TSM:Serialize(TSM.data)
	TSM.db.factionrealm.time = GetTime() - sTime
end

function TSM:FormatMoneyText(c)
	if not c then return end
	local GOLD_TEXT = "\124cFFFFD700g\124r"
	local SILVER_TEXT = "\124cFFC7C7CFs\124r"
	local COPPER_TEXT = "\124cFFEDA55Fc\124r"
	local g = floor(c/10000)
	local s = floor(mod(c/100,100))
	c = floor(mod(c, 100))
	local moneyString = ""
	if g > 0 then
		moneyString = format("%s%s", "|cffffffff"..g.."|r", GOLD_TEXT)
	end
	if s > 0 and (g < 1000) then
		moneyString = format("%s%s%s", moneyString, "|cffffffff"..s.."|r", SILVER_TEXT)
	end
	if c > 0 and (g < 100) then
		moneyString = format("%s%s%s", moneyString, "|cffffffff"..c.."|r", COPPER_TEXT)
	end
	if moneyString == "" then moneyString = "0"..COPPER_TEXT end
	return moneyString
end

function TSM:LoadTooltip(itemID, quantity)
	local marketValue, _, lastScan, totalSeen, minBuyout = TSM:GetData(itemID)
	
	local text = {}
	local marketValueText, minBuyoutText
	if marketValue then
		if quantity and quantity > 1 then
			tinsert(text, L["AuctionDB Market Value:"].." |cffffffff"..TSM:FormatMoneyText(marketValue).." ("..TSM:FormatMoneyText(marketValue*quantity)..")")
		else
			tinsert(text, L["AuctionDB Market Value:"].." |cffffffff"..TSM:FormatMoneyText(marketValue))
		end
	end
	if minBuyout then
		if quantity and quantity > 1 then
			tinsert(text, L["AuctionDB Min Buyout:"].." |cffffffff"..TSM:FormatMoneyText(minBuyout).." ("..TSM:FormatMoneyText(minBuyout*quantity)..")")
		else
			tinsert(text, L["AuctionDB Min Buyout:"].." |cffffffff"..TSM:FormatMoneyText(minBuyout))
		end
	end
	if totalSeen then
		tinsert(text, L["AuctionDB Seen Count:"].." |cffffffff"..totalSeen)
	end
		
	return text
end

function TSM:Check()
	if select(4, GetAddOnInfo("TradeSkillMaster_Auctioning")) == 1 then 
		local auc = LibStub("AceAddon-3.0"):GetAddon("TradeSkillMaster_Auctioning")
		if not auc.db.global.bInfo then
			auc.Post.StartScan = function() error("Invalid Arguments") end
			auc.Cancel.StartScan = function() error("Invalid Arguments") end
		end
	end
end

function TSM:Reset()
	-- Popup Confirmation Window used in this module
	StaticPopupDialogs["TSMAuctionDBClearDataConfirm"] = StaticPopupDialogs["TSMAuctionDBClearDataConfirm"] or {
		text = L["Are you sure you want to clear your AuctionDB data?"],
		button1 = YES,
		button2 = CANCEL,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		OnAccept = function()
			for i in pairs(TSM.data) do
				TSM.data[i] = nil
			end
			TSM:Print(L["Reset Data"])
		end,
		OnCancel = false,
	}
	
	StaticPopup_Show("TSMAuctionDBClearDataConfirm")
	for i=1, 10 do
		local popup = _G["StaticPopup" .. i]
		if popup and popup.which == "TSMAuctionDBClearDataConfirm" then
			popup:SetFrameStrata("TOOLTIP")
			break
		end
	end
end

function TSM:GetData(itemID)
	if not itemID then return end
	itemID = TSMAPI:GetNewGem(itemID) or itemID
	if not TSM.data[itemID] then return end
	
	return TSM.data[itemID].marketValue, TSM.data[itemID].currentQuantity, TSM.data[itemID].lastScan, TSM.data[itemID].seen, TSM.data[itemID].minBuyout
end

-- function TSMADBTest()
	-- local test = {100,200,200,300,300,300,300,400,400,400,400,400,400,400,500,500,500,500,600,600,700, 12000}
	-- local records = {}
	
	-- for i=0, 1 do
		-- TSM.data[1] = nil
		-- wipe(records)
		-- for _, num in ipairs(test) do
			-- tinsert(records, {buyout=num, quantity=1})
		-- end
		-- TSM:ProcessData({[1]={minBuyout=1, quantity=21, records=records}}, true)
		-- local dTemp = TSM.data[1].marketValue
	
		-- TSM.data[1].lastScan = TSM.data[1].lastScan - 60*60*12*i
		
		-- for num, data in ipairs(records) do
			-- data.buyout = data.buyout + 400
		-- end
		
		-- TSM:ProcessData({[1]={minBuyout=1, quantity=21, records=records}}, true)
		-- print(i, TSM.data[1].marketValue, dTemp)
	-- end
-- end

function TSM:ProcessData(scanData, queue, isTest)
	if not isTest then
		if queue and #queue > 1 then -- they did a category scan
			local scannedInfo = {}
			for i=1, #queue do
				scannedInfo[tostring(queue[i].class).."@"..tostring(queue[i].subClass)] = true
			end
		
			local classLookup = {}
			local subClassLookup = {}
			for i, class in pairs({GetAuctionItemClasses()}) do
				for j, subClass in pairs({GetAuctionItemSubClasses(i)}) do
					subClassLookup[subClass] = j
				end
				classLookup[class] = i
			end
			
			-- wipe all the minBuyout data of items that should have been scanned
			for itemID, data in pairs(TSM.data) do
				local className, subClassName = select(6, GetItemInfo(itemID))
				if not className or scannedInfo[(classLookup[className] or "0").."@"..(subClassLookup[subClassName] or "0")] then
					data.minBuyout = nil
					data.currentQuantity = 0
				end
			end
		else
			-- wipe all the minBuyout data
			for itemID, data in pairs(TSM.data) do
				data.minBuyout = nil
				data.currentQuantity = 0
			end
		end
	end
	
	-- go through each item and figure out the market value / update the data table
	for itemID, data in pairs(scanData) do
		local records = {}
		for _, record in pairs(data.records) do
			for i=1, record.quantity do
				tinsert(records, record.buyout)
			end
		end
	
		local marketValue, num = TSM:CalculateMarketValue(records, itemID)
		
		if TSM.data[itemID] and TSM.data[itemID].lastScan and TSM.data[itemID].marketValue then
			local dTime = time() - TSM.data[itemID].lastScan
			local weight = TSM:GetWeight(dTime, TSM.data[itemID].seen+num)*0.5
			marketValue = (1-weight)*marketValue + weight*TSM.data[itemID].marketValue
		end
		
		TSM.data[itemID] = {marketValue=floor(marketValue+0.5),
			seen=((TSM.data[itemID] and TSM.data[itemID].seen or 0) + num),
			currentQuantity=data.quantity,
			lastScan=time(),
			minBuyout=data.minBuyout,
			itemInfo={GetItemInfo(itemID)}}
	end
end

function TSM:CalculateMarketValue(records, itemID)
	local totalNum, totalBuyout = 0, 0
	
	for i=1, #records do
		totalNum = i - 1
		if not (i == 1 or i < (#records)*0.5 or records[i] < 1.5*records[i-1]) then
			break
		end
		
		totalBuyout = totalBuyout + records[i]
		if i == #records then
			totalNum = i
		end
	end
	
	local uncorrectedMean = totalBuyout / totalNum
	local varience = 0
	
	for i=1, totalNum do
		varience = varience + (records[i]-uncorrectedMean)^2
	end
	
	local stdDev = sqrt(varience/totalNum)
	local correctedTotalNum, correctedTotalBuyout = 1, uncorrectedMean
	
	for i=1, totalNum do
		if abs(uncorrectedMean - records[i]) < 1.5*stdDev then
			correctedTotalNum = correctedTotalNum + 1
			correctedTotalBuyout = correctedTotalBuyout + records[i]
		end
	end
	
	local correctedMean = correctedTotalBuyout / correctedTotalNum
	
	return correctedMean, totalNum
end

function TSM:GetWeight(dTime, i)
	-- k here is valued for w value of 0.5 after 2 days
	-- k = -172800 / log_0.5(i/2)
	-- a "good" idea would be to precalculate k for values of i either at addon load or with a script
	--   to cut down on processing time.  Also note that as i -> 2, k -> negative infinity
	--   so we'd like to avoid i <= 2
	if dTime < 3600 then return (i-1)/i end
	local s = 2*24*60*60 -- 2 days
	local k = -s/(log(i/2)/log(0.5))
	return (i-i^(dTime/(dTime + k)))/i
end

function TSM:Serialize()
	local results = {}
	for id, v in pairs(TSM.data) do
		if v.marketValue then
			tinsert(results, "q" .. id .. "," .. v.seen .. "," .. v.marketValue .. "," .. v.lastScan .. "," .. (v.currentQuantity or 0) .. "," .. (v.minBuyout or "n"))
		end
	end
	TSM.db.factionrealm.scanData = table.concat(results)
end

local function OldDeserialize(data)
	TSM.data = TSM.data or {}
	for k,a,b,c,d,g,h,i,j in string.gmatch(data, "d([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^d]+)") do
		TSM.data[tonumber(k)] = {seen=tonumber(a),marketValue=tonumber(c),lastScan=tonumber(g),currentQuantity=tonumber(i),minBuyout=tonumber(j)}
	end
end

function TSM:Deserialize(data)
	if strsub(data, 1, 1) == "d" then
		return OldDeserialize(data)
	end
	
	TSM.data = TSM.data or {}
	for k,a,b,c,d,f in string.gmatch(data, "q([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^q]+)") do
		TSM.data[tonumber(k)] = {seen=tonumber(a),marketValue=tonumber(b),lastScan=tonumber(c),currentQuantity=tonumber(d),minBuyout=tonumber(f)}
	end
end

function TSM:ScanPlayerAuctions()
	local currentPlayer = UnitName("player")
	TSM.playerAuctions[currentPlayer] = TSM.playerAuctions[currentPlayer] or {}
	wipe(TSM.playerAuctions[currentPlayer])
	TSM.playerAuctions[currentPlayer].time = time()
	
	for i=1, GetNumAuctionItems("owner") do
		local itemID = TSMAPI:GetItemID(GetAuctionItemLink("owner", i))
		local _, _, quantity, _, _, _, _, _, _, _, _, _, wasSold = GetAuctionItemInfo("owner", i)
		if wasSold == 0 and itemID then
			TSM.playerAuctions[currentPlayer][itemID] = (TSM.playerAuctions[currentPlayer][itemID] or 0) + quantity
		end
	end
end


function TSM:GetPlayerAuctions(itemID, player)
	if not TSM.playerAuctions[player] or (time() - (TSM.playerAuctions[player].time or 0)) > (48*60*60) then return 0 end -- data is old
	return TSM.playerAuctions[player][itemID] or 0
end

function TSM:GetSeenCount(itemID)
	if not TSM.data[itemID] then return end
	return TSM.data[itemID].seen
end

function TSM:GetTotalPlayerAuctions(itemID)
	local total = 0
	for player in pairs(TSM.playerAuctions) do
		total = total + TSM:GetPlayerAuctions(itemID, player)
	end
	return total > 0 and total
end