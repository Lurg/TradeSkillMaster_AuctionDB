-- ------------------------------------------------------------------------------ --
--                           TradeSkillMaster_AuctionDB                           --
--           http://www.curse.com/addons/wow/tradeskillmaster_auctiondb           --
--                                                                                --
--             A TradeSkillMaster Addon (http://tradeskillmaster.com)             --
--    All Rights Reserved* - Detailed license information included with addon.    --
-- ------------------------------------------------------------------------------ --

-- load the parent file (TSM) into a local variable and register this file as a module
local TSM = select(2, ...)
local Scan = TSM:NewModule("Scan", "AceEvent-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("TradeSkillMaster_AuctionDB") -- loads the localization table
local private = {threadId=nil}



-- ============================================================================
-- Module Functions
-- ============================================================================

function Scan:StartFullScan2()
	Scan:StopScanning()
	private.threadId = TSMAPI.Threading:Start(private.FullScanThread, 0.7, Scan.StopScanning)
end
function Scan:StartGroupScan2(itemList)
	Scan:StopScanning()
	private.threadId = TSMAPI.Threading:Start(private.GroupScanThread, 0.7, Scan.StopScanning, itemList)
end

function Scan:StopScanning()
	TSMAPI.Threading:Kill(private.threadId)
	private.threadId = nil
end

function Scan:IsScanning()
	return private.threadId and true or false
end



-- ============================================================================
-- Scan Threads
-- ============================================================================

function private.FullScanThread(self)
	self:SetThreadName("AUCTIONDB_FULL_SCAN")
	TSMAPI.AuctionScan2:StopScan()
	TSM.GUI:UpdateStatus(L["Running query..."], 0, 0)
	
	local database = TSMAPI:NewAuctionRecordDatabase()
	TSMAPI.AuctionScan2:ScanQuery({name=""}, self:GetSendMsgToSelfCallback(), nil, database)
	local startTime = time()
	while true do
		local args = self:ReceiveMsg()
		local event = tremove(args, 1)
		if event == "SCAN_PAGE_UPDATE" then
			-- the page we're scanning has changed
			local page, total = unpack(args)
			local remainingPages = total - page
			local statusText = format(L["Scanning page %s/%s"], page, total)
			if page > 50 and remainingPages > 0 then
				-- add approximate time remaining to the status text
				statusText = format(L["Scanning page %s/%s - Approximately %s remaining"], page, total, SecondsToTime(floor((page / (time() - startTime)) * remainingPages)))
			end
			TSM.GUI:UpdateStatus(statusText, page*100/total)
		elseif event == "SCAN_COMPLETE" then
			-- we're done scanning
			break
		elseif event == "INTERRUPTED" then
			-- scan was interrupted
			TSM.GUI:UpdateStatus(L["Done Scanning"], 100)
			return
		else
			error("Unexpected message: "..tostring(event))
		end
	end
	
	TSM.GUI:UpdateStatus("Processing data...", 100)
	private:ProcessScanDataThread(self, database)
	TSM.GUI:UpdateStatus(L["Done Scanning"], 100)
end

function private.GroupScanThread(self, itemList)
	self:SetThreadName("AUCTIONDB_GROUP_SCAN")
	TSMAPI.AuctionScan2:StopScan()
	
	-- generate queries
	TSM.GUI:UpdateStatus(L["Preparing Filters..."], 0, 0)
	TSMAPI:GenerateQueries(itemList, self:GetSendMsgToSelfCallback())
	local queries = nil
	while true do
		local args = self:ReceiveMsg()
		local event = tremove(args, 1)
		if event == "QUERY_COMPLETE" then
			-- we've got the queries
			queries = unpack(args)
			break
		elseif event == "INTERRUPTED" then
			-- we were interrupted
			TSM.GUI:UpdateStatus(L["Done Scanning"], 100)
			return
		else
			error("Unexpected message: "..tostring(event))
		end
	end
	
	-- scan queries
	TSM.GUI:UpdateStatus(L["Running query..."])
	local numQueries = #queries
	local database = TSMAPI:NewAuctionRecordDatabase()
	for i=1, numQueries do
		TSM.GUI:UpdateStatus(format(L["Scanning %d / %d (Page %d / %d)"], i, numQueries, 1, 1), (i-1)*100/numQueries, 0)
		TSMAPI.AuctionScan2:ScanQuery(queries[i], self:GetSendMsgToSelfCallback(), nil, database)
		while true do
			local args = self:ReceiveMsg()
			local event = tremove(args, 1)
			if event == "SCAN_PAGE_UPDATE" then
				-- the page we're scanning has changed
				local page, numPages = unpack(args)
				TSM.GUI:UpdateStatus(format(L["Scanning %d / %d (Page %d / %d)"], i, numQueries, page+1, numPages), (i-1)*100/numQueries, page*100/numPages)
			elseif event == "SCAN_COMPLETE" then
				-- we're done scanning this query
				break
			elseif event == "INTERRUPTED" then
				-- scan was interrupted
				TSM.GUI:UpdateStatus(L["Done Scanning"], 100)
				return
			else
				error("Unexpected message: "..tostring(event))
			end
		end
	end
	
	TSM.GUI:UpdateStatus("Processing data...", 100)
	private:ProcessScanDataThread(self, database, itemList)
	TSM.GUI:UpdateStatus(L["Done Scanning"], 100)
end

function private.GetAllScanThread(self)
	self:SetThreadName("AUCTIONDB_GETALL_SCAN")
	TSMAPI.AuctionScan2:StopScan()
	TSM.GUI:UpdateStatus(L["Running query..."], 0, 0)
	
	local database = TSMAPI:NewAuctionRecordDatabase()
	TSMAPI.AuctionScan2:ScanQuery({name=""}, self:GetSendMsgToSelfCallback(), nil, database)
	local startTime = time()
	while true do
		local args = self:ReceiveMsg()
		local event = tremove(args, 1)
		if event == "SCAN_PAGE_UPDATE" then
			-- the page we're scanning has changed
			local page, total = unpack(args)
			local remainingPages = total - page
			local statusText = format(L["Scanning page %s/%s"], page, total)
			if page > 50 and remainingPages > 0 then
				-- add approximate time remaining to the status text
				statusText = format(L["Scanning page %s/%s - Approximately %s remaining"], page, total, SecondsToTime(floor((page / (time() - startTime)) * remainingPages)))
			end
			TSM.GUI:UpdateStatus(statusText, page*100/total)
		elseif event == "SCAN_COMPLETE" then
			-- we're done scanning
			break
		elseif event == "INTERRUPTED" then
			-- scan was interrupted
			TSM.GUI:UpdateStatus(L["Done Scanning"], 100)
			return
		else
			error("Unexpected message: "..tostring(event))
		end
	end
	
	TSM.GUI:UpdateStatus("Processing data...", 100)
	private:ProcessScanDataThread(self, database)
	TSM.GUI:UpdateStatus(L["Done Scanning"], 100)
end



-- ============================================================================
-- Helper Functions
-- ============================================================================

function private:ProcessScanDataThread(self, database, itemList)
	local data = {}
	
	for _, record in ipairs(database) do
		local itemID = TSMAPI:GetItemID(record.itemString)
		if not data[itemID] then
			data[itemID] = {buyouts={}, minBuyout=0, numAuctions=0}
		end
		if record.itemBuyout > 0 then
			if data[itemID].minBuyout == 0 or record.itemBuyout < data[itemID].minBuyout then
				data[itemID].minBuyout = record.itemBuyout
			end
			for i=1, record.stackSize do
				tinsert(data[itemID].buyouts, record.itemBuyout)
			end
		end
		data[itemID].numAuctions = data[itemID].numAuctions + 1
	end
	
	if not itemList then
		TSM.db.realm.lastCompleteScan = time()
	end
	print("PROCESS DATA", data, itemList)
	-- TSM.Data:ProcessData(data, itemList)
end





Scan.groupScanData = {}
Scan.filterList = {}
Scan.numFilters = 0

function Scan.ProcessGetAllScan(self)
	local temp = 0
	while true do
		temp = min(temp + 1, 100)
		self:Sleep(0.2)
		if not Scan.isScanning then return end
		if Scan.getAllLoaded then
			break
		end
		TSM.GUI:UpdateStatus(L["Running query..."], nil, temp)
	end

	local data = {}
	for i=1, Scan.getAllLoaded do
		TSM.GUI:UpdateStatus(format(L["Scanning page %s/%s"], 1, 1), i*100/Scan.getAllLoaded)
		if i % 100 == 0 then
			self:Yield()
			if GetNumAuctionItems("list") ~= Scan.getAllLoaded then
				TSM:Print(L["GetAll scan did not run successfully due to issues on Blizzard's end. Using the TSM application for your scans is recommended."])
				Scan:DoneScanning()
				return
			end
		end
		
		local itemID = TSMAPI:GetItemID(GetAuctionItemLink("list", i))
		local _, _, count, _, _, _, _, _, _, buyout = GetAuctionItemInfo("list", i)
		if itemID and buyout and buyout > 0 then
			data[itemID] = data[itemID] or {records={}, minBuyout=math.huge, quantity=0}
			data[itemID].minBuyout = min(data[itemID].minBuyout, floor(buyout/count))
			data[itemID].quantity = data[itemID].quantity + count
			for j=1, count do
				tinsert(data[itemID].records, floor(buyout/count))
			end
		end
	end
	
	TSM.db.realm.lastCompleteScan = time()
	TSM.Data:ProcessData(data)
	
	TSM.GUI:UpdateStatus(L["Processing data..."])
	while TSM.processingData do
		self:Sleep(0.2)
	end
	
	TSM:Print(L["It is strongly recommended that you reload your ui (type '/reload') after running a GetAll scan. Otherwise, any other scans (Post/Cancel/Search/etc) will be much slower than normal."])
end

function Scan:AUCTION_ITEM_LIST_UPDATE()
	Scan:UnregisterEvent("AUCTION_ITEM_LIST_UPDATE")
	local num, total = GetNumAuctionItems("list")
	if num ~= total or num == 0 then
		TSM:Print(L["GetAll scan did not run successfully due to issues on Blizzard's end. Using the TSM application for your scans is recommended."])
		Scan:DoneScanning()
		return
	end
	Scan.getAllLoaded = num
end

function Scan:GetAllScanQuery()
	local canScan, canGetAll = CanSendAuctionQuery()
	if not canGetAll then return TSM:Print(L["Can't run a GetAll scan right now."]) end
	if not canScan then return TSMAPI:CreateTimeDelay(0.5, Scan.GetAllScanQuery) end
	QueryAuctionItems("", nil, nil, 0, 0, 0, 0, 0, 0, true)
	Scan:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
	TSMAPI.Threading:Start(Scan.ProcessGetAllScan, 1, function() Scan:DoneScanning() end)
end

function Scan:StartGetAllScan()
	TSM.db.profile.lastGetAll = time()
	Scan.isScanning = "GetAll"
	Scan.isBuggedGetAll = nil
	Scan.groupItems = nil
	TSMAPI.AuctionScan:StopScan()
	Scan:GetAllScanQuery()
end

function Scan:DoneScanning()
	TSM.GUI:UpdateStatus(L["Done Scanning"], 100)
	Scan.isScanning = nil
	Scan.getAllLoaded = nil
end