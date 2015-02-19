-- ------------------------------------------------------------------------------ --
--                           TradeSkillMaster_AuctionDB                           --
--           http://www.curse.com/addons/wow/tradeskillmaster_auctiondb           --
--                                                                                --
--             A TradeSkillMaster Addon (http://tradeskillmaster.com)             --
--    All Rights Reserved* - Detailed license information included with addon.    --
-- ------------------------------------------------------------------------------ --

-- register this file with Ace Libraries
local TSM = select(2, ...)
TSM = LibStub("AceAddon-3.0"):NewAddon(TSM, "TSM_AuctionDB", "AceEvent-3.0", "AceConsole-3.0")
local AceGUI = LibStub("AceGUI-3.0") -- load the AceGUI libraries

local L = LibStub("AceLocale-3.0"):GetLocale("TradeSkillMaster_AuctionDB") -- loads the localization table

TSM.MAX_AVG_DAY = 1
local SECONDS_PER_DAY = 60 * 60 * 24

TSM.GLOBAL_PRICE_INFO = {
	{
		source = "DBGlobalMinBuyoutAvg",
		sourceLabel = L["AuctionDB - Global Minimum Buyout Average (via TSM App)"],
		sourceArg = "globalMinBuyout",
		tooltipText = L["Global Min Buyout Avg:"],
		tooltipText2 = L["Global Min Buyout Avg x%s:"],
		tooltipKey = "globalMinBuyoutAvgTooltip",
	},
	{
		source = "DBGlobalMarketAvg",
		sourceLabel = L["AuctionDB - Global Market Value Average (via TSM App)"],
		sourceArg = "globalMarketValue",
		tooltipText = L["Global Market Value Avg:"],
		tooltipText2 = L["Global Market Value Avg x%s:"],
		tooltipKey = "globalMarketValueAvgTooltip",
	},
	{
		source = "DBGlobalHistorical",
		sourceLabel = L["AuctionDB - Global Historical Price (via TSM App)"],
		sourceArg = "globalHistorical",
		tooltipText = L["Global Historical Price:"],
		tooltipText2 = L["Global Historical Price x%s:"],
		tooltipKey = "globalHistoricalPriceTooltip",
	},
	{
		source = "DBGlobalSaleAvg",
		sourceLabel = L["AuctionDB - Global Sale Average (via TSM App)"],
		sourceArg = "globalSale",
		tooltipText = L["Global Sale Average:"],
		tooltipText2 = L["Global Sale Average x%s:"],
		tooltipKey = "globalSaleAvgTooltip",
	},
}

local savedDBDefaults = {
	realm = {
		lastSaveTime = nil,
		scanData = "",
		lastCompleteScan = 0,
		lastPartialScan = 0,
		hasAppData = nil,
	},
	global = {
		scanData = "",
		lastUpdate = 0,
	},
	profile = {
		tooltip = true,
		resultsPerPage = 50,
		resultsSortOrder = "ascending",
		resultsSortMethod = "name",
		hidePoorQualityItems = true,
		marketValueTooltip = true,
		minBuyoutTooltip = true,
		historicalPriceTooltip = true,
		globalMarketValueAvgTooltip = true,
		globalMinBuyoutAvgTooltip = true,
		globalSaleAvgTooltip = true,
		globalHistoricalPriceTooltip = true,
		showAHTab = true,
	},
}

-- Called once the player has loaded WOW.
function TSM:OnInitialize()
	-- just blow away old factionrealm data for 6.0.1
	if TradeSkillMaster_AuctionDBDB and TradeSkillMaster_AuctionDBDB.factionrealm then
		TradeSkillMaster_AuctionDBDB.factionrealm = nil
	end

	-- load the savedDB into TSM.db
	TSM.db = LibStub:GetLibrary("AceDB-3.0"):New("TradeSkillMaster_AuctionDBDB", savedDBDefaults, true)

	-- make easier references to all the modules
	for moduleName, module in pairs(TSM.modules) do
		TSM[moduleName] = module
	end

	-- register this module with TSM
	TSM:RegisterModule()
	
	-- TSM3 changes
	TSM.db.realm.appDataUpdate = nil
end

-- registers this module with TSM by first setting all fields and then calling TSMAPI:NewModule().
function TSM:RegisterModule()
	TSM.priceSources = {
		{ key = "DBMarket", label = L["AuctionDB - Market Value"], callback = "GetMarketValue" },
		{ key = "DBMinBuyout", label = L["AuctionDB - Minimum Buyout"], callback = "GetMinBuyout" },
		{ key = "DBHistorical", label = L["AuctionDB - Historical Price (via TSM App)"], callback = "GetHistoricalPrice" },
	}
	for _, info in pairs(TSM.GLOBAL_PRICE_INFO) do
		tinsert(TSM.priceSources, { key = info.source, label = info.sourceLabel, callback = "GetGlobalPrice", arg = info.sourceArg })
	end
	TSM.icons = {
		{ side = "module", desc = "AuctionDB", slashCommand = "auctiondb", callback = "Config:Load", icon = "Interface\\Icons\\Inv_Misc_Platnumdisks" },
	}
	if TSM.db.profile.showAHTab then
		TSM.auctionTab = { callbackShow = "GUI:Show", callbackHide = "GUI:Hide" }
	end
	TSM.moduleAPIs = {
		{ key = "lastCompleteScan", callback = TSM.GetLastCompleteScan },
		{ key = "lastCompleteScanTime", callback = TSM.GetLastCompleteScanTime },
	}
	TSM.tooltipOptions = { callback = "Config:LoadTooltipOptions" }
	TSMAPI:NewModule(TSM)
end

function TSMAuctionDB_LoadAppData(index, dataStr)
	if index ~= "Global" and gsub(index, "’", "'") ~= gsub(GetRealmName(), "’", "'") then return end
	local data = assert(loadstring(dataStr))()
	TSM.AppData = TSM.AppData or {}
	if index == "Global" then
		TSM.AppData.global = data
	else
		TSM.AppData.realm = data
	end
end

function TSM:OnEnable()
	-- check if we can load realm data from the app
	local realmAppData = TSM.AppData and TSM.AppData.realm
	if realmAppData and (realmAppData.downloadTime > TSM.db.realm.lastCompleteScan or (realmAppData.downloadTime == TSM.db.realm.lastCompleteScan and realmAppData.downloadTime > TSM.db.realm.lastPartialScan)) then
		TSM.updatedRealmData = (realmAppData.downloadTime > TSM.db.realm.lastCompleteScan)
		TSM.db.realm.lastCompleteScan = realmAppData.downloadTime
		TSM.db.realm.hasAppData = true
		TSM.realmData = {}
		local fields = realmAppData.fields
		for _, data in ipairs(realmAppData.data) do
			local itemString
			for i, key in ipairs(fields) do
				if i == 1 then
					-- item string must be the first field
					itemString = TSMAPI:GetBaseItemString2(data[i])
					TSM.realmData[itemString] = {}
				else
					TSM.realmData[itemString][key] = data[i]
				end
			end
			TSM.realmData[itemString].lastScan = realmAppData.downloadTime
		end
	else
		TSM.Compress:LoadRealmData()
	end
	
	local globalAppData = TSM.AppData and TSM.AppData.global
	if globalAppData and globalAppData.downloadTime >= TSM.db.global.lastUpdate then
		TSM.updatedGlobalData = (globalAppData.downloadTime > TSM.db.global.lastUpdate)
		TSM.db.global.lastUpdate = globalAppData.downloadTime
		TSM.globalData = {}
		local fields = globalAppData.fields
		for _, data in ipairs(globalAppData.data) do
			local itemString
			for i, key in ipairs(fields) do
				if i == 1 then
					-- item string must be the first field
					itemString = TSMAPI:GetBaseItemString2(data[i])
					TSM.globalData[itemString] = {}
				else
					TSM.globalData[itemString][key] = data[i]
				end
			end
		end
	else
		TSM.Compress:LoadGlobalData()
	end
	
	TSM.AppData = nil
	TSMAuctionDB_LoadAppData = nil
	for itemString in pairs(TSM.realmData) do
		TSMAPI:QueryItemInfo(TSMAPI:GetItemString(itemString))
	end
end

function TSM:OnTSMDBShutdown()
	TSM.Compress:SaveRealmData()
	TSM.Compress:SaveGlobalData()
end

local function TooltipInsertValueText(text, quantity, str, strAlt, value)
	if not value then return end
	if TSMAPI:GetMoneyCoinsTooltip() then
		if IsShiftKeyDown() then
			tinsert(text, { left = "  " .. format(strAlt, quantity), right = TSMAPI:FormatTextMoneyIcon(value * quantity, "|cffffffff", true) })
		else
			tinsert(text, { left = "  " .. str, right = TSMAPI:FormatTextMoneyIcon(value, "|cffffffff", true) })
		end
	else
		if IsShiftKeyDown() then
			tinsert(text, { left = "  " .. format(strAlt, quantity), right = TSMAPI:FormatTextMoney(value * quantity, "|cffffffff", true) })
		else
			tinsert(text, { left = "  " .. str, right = TSMAPI:FormatTextMoney(value, "|cffffffff", true) })
		end
	end
end

function TSM:GetTooltip(itemString, quantity)
	if not TSM.db.profile.tooltip then return end
	itemString = TSMAPI:GetBaseItemString2(itemString)
	if not itemString then return end
	
	local text = {}
	quantity = quantity or 1

	-- add min buyout info
	if TSM.db.profile.minBuyoutTooltip then
		TooltipInsertValueText(text, quantity, L["Min Buyout:"], L["Min Buyout x%s:"], TSM:GetMinBuyout(itemString))
	end

	-- add market value info
	if TSM.db.profile.marketValueTooltip then
		TooltipInsertValueText(text, quantity, L["Market Value:"], L["Market Value x%s:"], TSM:GetMarketValue(itemString))
	end

	-- add historical price info
	if TSM.db.profile.historicalPriceTooltip then
		TooltipInsertValueText(text, quantity, L["Historical Price:"], L["Historical Price x%s:"], TSM:GetHistoricalPrice(itemString))
	end

	-- add global price info
	for _, info in ipairs(TSM.GLOBAL_PRICE_INFO) do
		if TSM.db.profile[info.tooltipKey] then
			TooltipInsertValueText(text, quantity, info.tooltipText, info.tooltipText2, TSM:GetGlobalPrice(itemString, info.sourceArg))
		end
	end

	-- add heading and last scan time info
	if #text > 0 then
		local lastScan = TSM:GetLastScanTime(itemString)
		if lastScan then
			local timeDiff = SecondsToTime(time() - lastScan)
			tinsert(text, 1, { left = "|cffffff00" .. "TSM AuctionDB:", right = "|cffffffff" .. format(L["%s ago"], timeDiff) })
		else
			tinsert(text, 1, { left = "|cffffff00" .. "TSM AuctionDB:", right = "|cffffffff" .. L["Not Scanned"] })
		end
		return text
	end
end

function TSM:GetLastCompleteScan()
	local lastScan = {}
	for itemString, data in pairs(TSM.realmData) do
		if data.lastScan >= TSM.db.realm.lastCompleteScan and data.minBuyout then
			lastScan[itemString] = {marketValue=data.marketValue, minBuyout=data.minBuyout, numAuctions=data.numAuctions}
		end
	end

	return lastScan
end

function TSM:GetLastCompleteScanTime()
	return TSM.db.realm.lastCompleteScan
end

function TSM:GetItemData(itemString, key, isGlobal)
	itemString = TSMAPI:GetBaseItemString2(itemString)
	local scanData = nil
	if isGlobal then
		scanData = TSM.globalData
	else
		scanData = TSM.realmData
	end
	if not itemString or not scanData or not scanData[itemString] or not scanData[itemString][key] then return end
	return scanData[itemString][key] > 0 and scanData[itemString][key] or nil
end

function TSM:GetMarketValue(itemString)
	return TSM:GetItemData(itemString, "marketValue")
end

function TSM:GetGlobalPrice(itemString, key)
	return TSM:GetItemData(itemString, key, true)
end

function TSM:GetLastScanTime(itemString)
	return TSM:GetItemData(itemString, "lastScan")
end

function TSM:GetMinBuyout(itemString)
	return TSM:GetItemData(itemString, "minBuyout")
end

function TSM:GetHistoricalPrice(itemString)
	return TSM:GetItemData(itemString, "historical")
end