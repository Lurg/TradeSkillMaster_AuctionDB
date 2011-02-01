-- ------------------------------------------------------------------------------------- --
-- 					TradeSkillMaster_Crafting - AddOn by Sapu, Mischanix				 		  --
--   http://wow.curse.com/downloads/wow-addons/details/tradeskillmaster_crafting.aspx    --
-- ------------------------------------------------------------------------------------- --

-- The following functions are contained attached to this file:
-- Scan:OnEnable() - initialize a bunch of variables and frames used throughout the module and register some events
-- Scan:AUCTION_HOUSE_SHOW() - fires when the AH is openned and adds the "TradeSkillMaster_Crafting - Run Scan" button to the AH frame
-- Scan:ShowScanButton() - adds the "TradeSkillMaster_Crafting - Run Scan" button to the AH frame
-- Scan:AUCTION_HOUSE_CLOSED() - gets called when the AH is closed
-- Scan:RunScan() - prepares everything to start running a scan
-- Scan:SendQuery() - sends a query to the AH frame once it is ready to be queried (uses frame as a delay)
-- Scan:AUCTION_ITEM_LIST_UPDATE() - gets called whenever the AH window is updated (something is shown in the results section)
-- Scan:ScanAuctions() - scans the currently shown page of auctions and collects all the data
-- Scan:AddAuctionRecord() - Add a new record to the Scan.AucData table
-- Scan:StopScanning() - stops the scan because it was either interupted or it was completed successfully
-- Scan:Calc() - runs calculations and stores the resulting material / craft data in the savedvariables DB (options window)
-- Scan:GetTimeDate() - function for getting a formated time and date for storing time of last scan

-- The following "global" (within the addon) variables are initialized in this file:
-- Scan.staus - stores a ton of information about the status of the current scan
-- Scan.AucData - stores the resulting data before it is saved to the savedDB file

-- ===================================================================================== --


-- load the parent file (TSM) into a local variable and register this file as a module
local TSM = select(2, ...)
local Scan = TSM:NewModule("Scan", "AceEvent-3.0")
local AceGUI = LibStub("AceGUI-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("TradeSkillMaster_AuctionDB") -- loads the localization table

local BASE_DELAY = 0.10 -- time to delay for before trying to scan a page again when it isn't fully loaded
local CATEGORIES = {}
CATEGORIES[L["Enchanting"]] = {"4$6", "6$1", "6$4", "6$7", "6$14"}
CATEGORIES[L["Inscription"]] = {"5", "6$6", "6$9"}
CATEGORIES[L["Jewelcrafting"]] = {"6$8", "10"}
CATEGORIES[L["Alchemy"]] = {"4$2", "4$3", "4$4", "6$6"}
CATEGORIES[L["Blacksmithing"]] = {"1$1", "1$2", "1$5", "1$6", "1$7", "1$8", "1$9", "1$13", "1$14", "2$4", 
	"2$5", "2$6", "4$6", "6$1", "6$4", "6$7", "6$12", "6$13", "6$14"}
CATEGORIES[L["Leatherworking"]] = {"2$1$13", "2$3", "2$4", "6$1", "6$3", "6$12", "6$13"}
CATEGORIES[L["Tailoring"]] = {"2$1$13", "2$2", "3$1", "6$1", "6$2", "6$12", "6$13"}
CATEGORIES[L["Engineering"]] = {"1$4", "2$1$2", "2$1$5", "6$9", "6$10"}
CATEGORIES[L["Cooking"]] = {"4$1", "6$5", "6$10", "6$13"}
CATEGORIES[L["Complete AH Scan"]] = {"0"} -- scans the entire AH

local status = {page=0, retries=0, timeDelay=0, AH=false, filterlist = {}}

-- initialize a bunch of variables and frames used throughout the module and register some events
function Scan:OnEnable()
	Scan.AucData = {}
	TSMAPI:RegisterSidebarFunction("TradeSkillMaster_AuctionDB", "auctionDBScan", "Interface\\Icons\\Inv_Inscription_WeaponScroll01", 
		L["AuctionDB - Run Scan"], function(...) Scan:LoadSidebar(...) end, Scan.HideSidebar)
		
	Scan:RegisterEvent("AUCTION_HOUSE_CLOSED")
	Scan:RegisterEvent("AUCTION_HOUSE_SHOW", function() status.AH = true end)
end

-- Scan delay for hard reset
local frame = CreateFrame("Frame")
frame.timeElapsed = 0
frame:Hide()
frame:SetScript("OnUpdate", function(self, elapsed)
	self.timeElapsed = self.timeElapsed + elapsed
	if self.timeElapsed >= 0.05 then
		self.timeElapsed = self.timeElapsed - 0.05
		Scan:SendQuery()
	end
end)

-- Scan delay for soft reset
local frame2 = CreateFrame("Frame")
frame2:Hide()
frame2:SetScript("OnUpdate", function(self, elapsed)
	self.timeLeft = self.timeLeft - elapsed
	if self.timeLeft < 0 then
		self.timeLeft = 0
		self:Hide()

		if status.isScanning ~= "GetAll" then
			Scan:ScanAuctions()
		end
	end
end)

local function CreateLabel(frame, text, fontObject, fontSizeAdjustment, fontStyle, p1, p2, justifyH, justifyV)
	local label = frame:CreateFontString(nil, "OVERLAY", fontObject)
	local tFile, tSize = fontObject:GetFont()
	label:SetFont(tFile, tSize+fontSizeAdjustment, fontStyle)
	if type(p1) == "table" then
		label:SetPoint(unpack(p1))
	elseif type(p1) == "number" then
		label:SetWidth(p1)
	end
	if type(p2) == "table" then
		label:SetPoint(unpack(p2))
	elseif type(p2) == "number" then
		label:SetHeight(p2)
	end
	if justifyH then
		label:SetJustifyH(justifyH)
	end
	if justifyV then
		label:SetJustifyV(justifyV)
	end
	label:SetText(text)
	label:SetTextColor(1, 1, 1, 1)
	return label
end

local function AddHorizontalBar(parent, ofsy)
	local barFrame = CreateFrame("Frame", nil, parent)
	barFrame:SetPoint("TOPLEFT", 4, ofsy)
	barFrame:SetPoint("TOPRIGHT", -4, ofsy)
	barFrame:SetHeight(8)
	local horizontalBarTex = barFrame:CreateTexture()
	horizontalBarTex:SetAllPoints(barFrame)
	horizontalBarTex:SetTexture("Interface\\Tooltips\\UI-Tooltip-Border")
	horizontalBarTex:SetTexCoord(0.577, 0.683, 0.145, 0.309)
	horizontalBarTex:SetVertexColor(0, 0, 0.7, 1)
end

local function ApplyTexturesToButton(btn, isOpenCloseButton)
	local texture = "Interface\\TokenFrame\\UI-TokenFrame-CategoryButton"
	local offset = 6
	if isopenCloseButton then
		offset = 5
		texture = "Interface\\Buttons\\UI-AttributeButton-Encourage-Hilight"
	end
	
	local normalTex = btn:CreateTexture()
	normalTex:SetTexture(texture)
	normalTex:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -offset, -offset)
	normalTex:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", offset, offset)
	
	local disabledTex = btn:CreateTexture()
	disabledTex:SetTexture(texture)
	disabledTex:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -offset, -offset)
	disabledTex:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", offset, offset)
	disabledTex:SetVertexColor(0.1, 0.1, 0.1, 1)
	
	local highlightTex = btn:CreateTexture()
	highlightTex:SetTexture(texture)
	highlightTex:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -offset, -offset)
	highlightTex:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", offset, offset)
	
	local pressedTex = btn:CreateTexture()
	pressedTex:SetTexture(texture)
	pressedTex:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -offset, -offset)
	pressedTex:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", offset, offset)
	pressedTex:SetVertexColor(1, 1, 1, 0.5)
	
	if isopenCloseButton then
		normalTex:SetTexCoord(0.041, 0.975, 0.129, 1.00)
		disabledTex:SetTexCoord(0.049, 0.931, 0.008, 0.121)
		highlightTex:SetTexCoord(0, 1, 0, 1)
		highlightTex:SetVertexColor(0.9, 0.9, 0.9, 0.9)
		pressedTex:SetTexCoord(0.035, 0.981, 0.014, 0.670)
		btn:SetPushedTextOffset(0, -1)
	else
		normalTex:SetTexCoord(0.049, 0.958, 0.066, 0.244)
		disabledTex:SetTexCoord(0.049, 0.958, 0.066, 0.244)
		highlightTex:SetTexCoord(0.005, 0.994, 0.613, 0.785)
		highlightTex:SetVertexColor(0.5, 0.5, 0.5, 0.7)
		pressedTex:SetTexCoord(0.0256, 0.743, 0.017, 0.158)
		btn:SetPushedTextOffset(0, -2)
	end
	
	btn:SetNormalTexture(normalTex)
	btn:SetDisabledTexture(disabledTex)
	btn:SetHighlightTexture(highlightTex)
	btn:SetPushedTexture(pressedTex)
end

-- Tooltips!
local function ShowTooltip(self)
	if self.link then
		GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
		GameTooltip:SetHyperlink(self.link)
		GameTooltip:Show()
	elseif self.tooltip then
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
		GameTooltip:SetText(self.tooltip, 1, 1, 1, 1, true)
		GameTooltip:Show()
	else
		GameTooltip:SetOwner(self.frame, "ANCHOR_BOTTOMRIGHT")
		GameTooltip:SetText(self.frame.tooltip, 1, 1, 1, 1, true)
		GameTooltip:Show()
	end
end

local function HideTooltip()
	GameTooltip:Hide()
end

local function CreateButton(text, parentFrame, frameName, inheritsFrame, width, height, point, arg1, arg2)
	local btn = CreateFrame("Button", frameName, parentFrame, inheritsFrame)
	btn:SetHeight(height or 0)
	btn:SetWidth(width or 0)
	btn:SetPoint(unpack(point))
	btn:SetText(text)
	btn:Raise()
	btn:GetFontString():SetPoint("CENTER")
	local tFile, tSize = GameFontHighlight:GetFont()
	btn:GetFontString():SetFont(tFile, tSize, "OUTLINE")
	btn:GetFontString():SetTextColor(1, 1, 1, 1)
	if type(arg1) == "string" then
		btn.tooltip = arg1
		btn:SetScript("OnEnter", ShowTooltip)
		btn:SetScript("OnLeave", HideTooltip)
	elseif type(arg2) == "string" then
		btn:SetPoint(unpack(arg1))
		btn.tooltip = arg2
		btn:SetScript("OnEnter", ShowTooltip)
		btn:SetScript("OnLeave", HideTooltip)
	end
	btn:SetBackdrop({
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 18,
			insets = {left = 0, right = 0, top = 0, bottom = 0},
		})
	btn:SetScript("OnDisable", function(self) self:GetFontString():SetTextColor(0.5, 0.5, 0.5, 1) end)
	btn:SetScript("OnEnable", function(self) self:GetFontString():SetTextColor(1, 1, 1, 1) end)
	ApplyTexturesToButton(btn)
	return btn
end

local function CreateCheckBox(parent, label, width, point, tooltip)
	local cb = AceGUI:Create("TSMCheckBox")
	cb:SetType("checkbox")
	cb:SetWidth(width)
	cb:SetLabel(label)
	cb.frame:SetParent(parent)
	cb.frame:SetPoint(unpack(point))
	cb.frame:Show()
	cb.frame.tooltip = tooltip
	cb:SetCallback("OnEnter", ShowTooltip)
	cb:SetCallback("OnLeave", HideTooltip)
	return cb
end

function Scan:LoadSidebar(frame)
	local function GetAllReady()
		if not select(2, CanSendAuctionQuery()) then
			local previous = TSM.db.profile.lastGetAll or 1/0
			if previous > (time() - 15*60) then
				local diff = previous + 15*60 - time()
				local diffMin = math.floor(diff/60)
				local diffSec = diff - diffMin*60
				return "|cffff0000"..format(L["Ready in %s min and %s sec"], diffMin, diffSec), false
			else
				return "|cffff0000"..L["Not Ready"], false
			end
		else
			return "|cff00ff00"..L["Ready"], true
		end
	end

	if not Scan.frame then
		local container = CreateFrame("Frame", nil, frame)
		container:SetAllPoints(frame)
		container:Raise()
		
		-- title text and first horizontal bar
		container.title = CreateLabel(container, L["AuctionDB - Auction House Scanning"], GameFontHighlight, 0, "OUTLINE", 300, {"TOP", 0, -20})
		AddHorizontalBar(container, -50)
		
		-- "Run <Regular/GetAll>s Scan" button + another horizontal bar
		local button = CreateButton(L["Run Scan"], container, "TSMAuctionDBRunScanButton", "UIPanelButtonTemplate", 150, 30, {"TOP", 0, -70},
			L["Starts scanning the auction house based on the below settings.\n\nIf you are running a GetAll scan, your game client may temporarily lock up."])
		button:SetScript("OnClick", Scan.RunScan)
		container.startScanButton = button
		AddHorizontalBar(container, -110)
		
		-- GetAll scan checkbox + label
		local cb = CreateCheckBox(container, L["Run GetAll Scan if Possible"], 200, {"TOPLEFT", 12, -130}, L["If checked, a GetAll scan will be used whenever possible.\n\nWARNING: With any GetAll scan there is a risk you may get disconnected from the game."])
		cb:SetCallback("OnValueChanged", function(_,_,value) TSM.db.profile.getAll = value end)
		container.getAllCheckBox = cb
		container.getAllLabel = CreateLabel(container, "", GameFontHighlight, 0, nil, 300, {"TOPLEFT", 12, -160}, "LEFT")
		
		-- timer frame for updating the getall label as well as the "Run <Regular/GetAll> Scan" button + another horizontal bar
		local timer = CreateFrame("Frame", nil, container)
		timer.timeLeft = 0
		timer:SetScript("OnUpdate", function(self, elapsed)
				self.timeLeft = self.timeLeft - elapsed
				if self.timeLeft <= 0 then
					self.timeLeft = 1
					if status.isScanning then return end
					local readyText, isReady = GetAllReady()
					Scan.frame.getAllLabel:SetText("|cffffbb00"..L["GetAll Scan:"].." "..readyText)
					if isReady and TSM.db.profile.getAll then
						Scan.frame.startScanButton:SetText(L["Run GetAll Scan"])
					else
						Scan.frame.startScanButton:SetText(L["Run Regular Scan"])
					end
				end
			end)
		AddHorizontalBar(container, -180)
		
		container.professionLabel = CreateLabel(container, L["Professions to scan for:"], GameFontHighlight, 0, nil, 300, {"TOP", 0, -190})
		-- profession checkboxes
		local i = 0
		local columnStart = frame:GetWidth() / 2
		for name in pairs(CATEGORIES) do
			i = i + 1
			if TSM.db.profile.scanSelections[name] == nil then
				TSM.db.profile.scanSelections[name] = false
			end
			local ofsx = 10+columnStart*((i+1)%2)-- alternating columns
			local ofsy = -190-ceil(i/2)*25 -- two per row
			local cb = CreateCheckBox(container, name, 150, {"TOPLEFT", ofsx, ofsy}, L["If checked, a regular scan will scan for this profession."])
			cb:SetCallback("OnValueChanged", function(_,_,value) TSM.db.profile.scanSelections[name] = value end)
			container[strlower(name).."CheckBox"] = cb
		end
		
		Scan.frame = container
	end
	
	Scan.frame.getAllCheckBox:SetValue(TSM.db.profile.getAll)
	for name in pairs(CATEGORIES) do
		Scan.frame[strlower(name).."CheckBox"]:SetValue(TSM.db.profile.scanSelections[name])
	end
	
	Scan.frame:Show()
end

function Scan:HideSidebar()
	Scan.frame:Hide()
end

-- gets called when the AH is closed
function Scan:AUCTION_HOUSE_CLOSED()
	Scan:UnregisterEvent("AUCTION_ITEM_LIST_UPDATE")
	status.AH = false
	if status.isScanning then -- stop scanning if we were scanning (pass true to specify it was interupted)
		Scan:StopScanning(true)
	end
end

-- prepares everything to start running a scan
function Scan:RunScan()
	local alreadyAdded = {}
	local scanQueue = {}
	local num = 1
	
	if not status.AH then
		TSM:Print(L["Auction house must be open in order to scan."])
		return
	end
	
	if TSM.db.profile.getAll and select(2, CanSendAuctionQuery()) then
		status.isScanning = "GetAll"
		wipe(Scan.AucData)
		status.page = 0
		status.retries = 3
		status.hardRetry = nil
		TSMAPI:LockSidebar()
		TSMAPI:ShowSidebarStatusBar()
		TSMAPI:SetSidebarStatusBarText(L["AuctionDB - Scanning"])
		TSMAPI:UpdateSidebarStatusBar(0)
		TSMAPI:UpdateSidebarStatusBar(0, true)
		Scan:StartGetAllScan()
		return
	end
	
	-- builds the scanQueue
	for name, selected in pairs(TSM.db.profile.scanSelections) do
		-- if we are doing a complete AH scan then no need to figure out what else we want to scan
		if selected and name == L["Complete AH Scan"] then
			scanQueue = {{id=1, class=0, subClass=0, invSlot=0}}
			break
		end
		if selected and CATEGORIES[name] then
			for i=1, #(CATEGORIES[name]) do
				local class, subClass, invSlot = strsplit("$", CATEGORIES[name][i])
				local valid = false
				
				if subClass then
					if invSlot then
						if not (alreadyAdded[class] or alreadyAdded[class.."$"..subClass] or alreadyAdded[class.."$"..subClass.."$"..invSlot]) then
							valid = true
							alreadyAdded[class.."$"..subClass.."$"..invSlot] = true
						end
					else
						if not (alreadyAdded[class] or alreadyAdded[class.."$"..subClass]) then
							valid = true
							alreadyAdded[class.."$"..subClass] = true
						end
					end
				else
					if not alreadyAdded[class] then
						valid = true
						alreadyAdded[class] = true
					end
				end
				
				if valid then
					tinsert(scanQueue, {id=#scanQueue, class=class, subClass=(subClass or 0), invSlot=(invSlot or 0)})
				end
			end
		end
	end

	if #(scanQueue) == 0 then
		return TSM:Print(L["Nothing to scan."])
	end
	
	if not CanSendAuctionQuery() then
		TSM:Print(L["Error: AuctionHouse window busy."])
		return
	end
	
	-- sets up the non-function-local variables
	-- filter = current category being scanned for {class, subClass, invSlot}
	-- filterList = queue of categories to scan for
	wipe(Scan.AucData)
	status.page = 0
	status.retries = 0
	status.hardRetry = nil
	status.filterList = scanQueue
	status.class = scanQueue[1].class
	status.subClass = scanQueue[1].subClass
	status.invSlot = scanQueue[1].invSlot
	status.id = scanQueue[1].id
	status.isScanning = "Category"
	status.numItems = #(scanQueue)
	TSMAPI:LockSidebar()
	TSMAPI:ShowSidebarStatusBar()
	TSMAPI:SetSidebarStatusBarText(L["AuctionDB - Scanning"])
	TSMAPI:UpdateSidebarStatusBar(0)
	TSMAPI:UpdateSidebarStatusBar(0, true)
	
	--starts scanning
	Scan:SendQuery()
end

-- sends a query to the AH frame once it is ready to be queried (uses frame as a delay)
function Scan:SendQuery(forceQueue)
	status.queued = not CanSendAuctionQuery()
	if (not status.queued and not forceQueue) then
		-- stop delay timer
		frame:Hide()
		
		-- Query the auction house (then waits for AUCTION_ITEM_LIST_UPDATE to fire)
		Scan:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
		QueryAuctionItems("", nil, nil, status.invSlot, status.class, status.subClass, status.page, 0, 0)
	else
		-- run delay timer then try again to scan
		frame:Show()
	end
end

-- gets called whenever the AH window is updated (something is shown in the results section)
function Scan:AUCTION_ITEM_LIST_UPDATE()
	if status.isScanning then
		status.timeDelay = 0

		frame2:Hide()
		
		-- now that our query was successful we can get our data
		Scan:UnregisterEvent("AUCTION_ITEM_LIST_UPDATE")
		Scan:ScanAuctions()
	else
		Scan:UnregisterEvent("AUCTION_ITEM_LIST_UPDATE")
	end
end

-- scans the currently shown page of auctions and collects all the data
function Scan:ScanAuctions()
	-- collects data on the query:
		-- # of auctions on current page
		-- # of pages total
	local shown, total = GetNumAuctionItems("list")
	local totalPages = math.ceil(total / 50)
	local name, quantity, bid, buyout = {}, {}, {}, {}
	
	-- Check for bad data
	if status.retries < 3 then
		local badData
		
		for i=1, shown do
			-- checks whether or not the name of the auctions are valid
			-- if not, the data is bad
			name[i], _, quantity[i], _, _, _, bid[i], _, buyout[i] = GetAuctionItemInfo("list", i)
			if not (name[i] and quantity[i] and bid[i] and buyout[i]) then
				badData = true
			end
		end
		
		if badData then
			if status.hardRetry then
				-- Hard retry
				-- re-sends the entire query
				status.retries = status.retries + 1
				Scan:SendQuery()
			else
				-- Soft retry
				-- runs a delay and then tries to scan the query again
				status.timeDelay = status.timeDelay + BASE_DELAY
				frame2.timeLeft = BASE_DELAY
				frame2:Show()
	
				-- If after 4 seconds of retrying we still don't have data, will go and requery to try and solve the issue
				-- if we still don't have data, we try to scan it anyway and move on.
				if status.timeDelay >= 4 then
					status.hardRetry = true
					status.retries = 0
				end
			end
			
			return
		end
	end
	
	status.hardRetry = nil
	status.retries = 0
	TSMAPI:UpdateSidebarStatusBar(floor(status.page/totalPages*100 + 0.5), true)
	TSMAPI:UpdateSidebarStatusBar(floor((1-(#(status.filterList)-status.page/totalPages)/status.numItems)*100 + 0.5))
	
	-- now that we know our query is good, time to verify and then store our data
	-- ex. "Eternal Earthsiege Diamond" will not get stored when we search for "Eternal Earth"
	for i=1, shown do
		local itemID = TSMAPI:GetItemID(GetAuctionItemLink("list", i))
		Scan:AddAuctionRecord(itemID, quantity[i], bid[i], buyout[i])
	end

	-- This query has more pages to scan
	-- increment the page # and send the new query
	if totalPages > (status.page + 1) then
		status.page = status.page + 1
		Scan:SendQuery()
		return
	end
	
	-- Removes the current filter from the filterList as we are done scanning for that item
	for i=#(status.filterList), 1, -1 do
		if status.filterList[i].id == status.id then
			tremove(status.filterList, i)
			break
		end
	end
	
	-- Query the next filter if we have one
	if status.filterList[1] then
		status.class = status.filterList[1].class
		status.subClass = status.filterList[1].subClass
		status.invSlot = status.filterList[1].invSlot
		status.id = status.filterList[1].id
		TSMAPI:UpdateSidebarStatusBar(floor((1-#(status.filterList)/status.numItems)*100 + 0.5))
		status.page = 0
		Scan:SendQuery()
		return
	end
	
	-- we are done scanning!
	Scan:StopScanning()
end

-- Add a new record to the Scan.AucData table
function Scan:AddAuctionRecord(itemID, quantity, bid, buyout)
	-- Don't add this data if it has no buyout
	if (not buyout) or (buyout <= 0) then return true end
	
	for i=1, quantity do
		TSM:OneIteration(buyout/quantity, itemID)
	end

	Scan.AucData[itemID] = Scan.AucData[itemID] or {quantity = 0, records = {}, minBuyout=0}
	Scan.AucData[itemID].quantity = Scan.AucData[itemID].quantity + quantity
	
	-- Calculate the bid / buyout per 1 item
	buyout = buyout / quantity
	bid = bid / quantity
	
	if (buyout < Scan.AucData[itemID].minBuyout or Scan.AucData[itemID].minBuyout == 0) then
		Scan.AucData[itemID].minBuyout = buyout
	end
	
	-- No sense in using a record for each entry if they are all the exact same data
	for _, record in pairs(Scan.AucData[itemID].records) do
		if (record.buyout == buyout and record.bid == bid) then
			record.buyout = buyout
			record.bid = bid
			record.quantity = record.quantity + quantity
			return
		end
	end
	
	-- Create a new entry in the table
	tinsert(Scan.AucData[itemID].records, {buyout = buyout, bid = bid, quantity = quantity})
end

-- stops the scan because it was either interupted or it was completed successfully
function Scan:StopScanning(interupted)
	TSMAPI:UnlockSidebar()
	TSMAPI:HideSidebarStatusBar()
	if interupted then
		-- fires if the scan was interupted (auction house was closed while scanning)
		TSM:Print(L["Scan interupted due to auction house being closed."])
	else
		-- fires if the scan completed sucessfully
		TSM:Print(L["Scan complete!"])
		
		-- wipe all the minBuyout data
		for _, data in pairs(TSM.data) do
			data.minBuyout = nil
		end
		
		for itemID, data in pairs(Scan.AucData) do
			TSM:SetQuantity(itemID, data.quantity)
			TSM.data[itemID].lastSeen = time()
			TSM.data[itemID].minBuyout = data.minBuyout
		end
	end
	
	status.isScanning = nil
	status.queued = nil
	
	frame:Hide()
	frame2:Hide()
end
	
function Scan:StartGetAllScan()
	TSM.db.profile.lastGetAll = time()
	QueryAuctionItems("", "", "", nil, nil, nil, nil, nil, nil, true)
	
	local scanFrame = CreateFrame("Frame")
	scanFrame:Hide()
	scanFrame.num = 0
	scanFrame:SetScript("OnUpdate", function(self, elapsed)
			if not AuctionFrame:IsVisible() then self:Hide() end
			for i=1, 200 do
				self.num = self.num + 1
				local itemID = TSMAPI:GetItemID(GetAuctionItemLink("list", self.num))
				local name, _, quantity, _, _, _, bid, _, buyout = GetAuctionItemInfo("list", self.num)
				Scan:AddAuctionRecord(itemID, quantity, bid, buyout)
				TSMAPI:UpdateSidebarStatusBar(100-floor(i/2), true)
				TSMAPI:UpdateSidebarStatusBar(floor((1+(self.num-self.numShown)/self.numShown)*100 + 0.5))
				
				if self.num == self.numShown then
					if self.num == 42554 then TSM:Print(L["|cffff0000WARNING:|r As of 4.0.1 there is a bug with GetAll scans only scanning a maximum of 42554 auctions from the AH which is less than your auction house currently contains. As a result, thousands of items may have been missed. Please use regular scans until blizzard fixes this bug."]) end
					self:Hide()
					Scan:StopScanning()
					break
				elseif not AuctionFrame:IsVisible() then
					self:Hide()
					break
				end
			end
		end)
	
	local	frame1 = CreateFrame("Frame")
	frame1:Hide()
	frame1.totalDelay = 20
	frame1.delay = 1
	frame1:SetScript("OnUpdate", function(self, elapsed)
			if not AuctionFrame:IsVisible() then self:Hide() end
			self.delay = self.delay - elapsed
			self.totalDelay = self.totalDelay - elapsed
			TSMAPI:UpdateSidebarStatusBar(100-floor((self.totalDelay/20)*100), true)
			if self.delay <= 0 then
				if GetNumAuctionItems("list") > 50 then
					scanFrame.numShown = GetNumAuctionItems("list")
					self:Hide()
					scanFrame:Show()
				else
					self.delay = 1
				end
			end
		end)
	frame1:Show()
end