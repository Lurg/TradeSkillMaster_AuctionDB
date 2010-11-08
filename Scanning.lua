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
-- Scan:SendQuery() - sends a query to the AH frame once it is ready to be queried (uses Scan.frame as a delay)
-- Scan:AUCTION_ITEM_LIST_UPDATE() - gets called whenever the AH window is updated (something is shown in the results section)
-- Scan:ScanAuctions() - scans the currently shown page of auctions and collects all the data
-- Scan:AddAuctionRecord() - Add a new record to the Scan.AucData table
-- Scan:StopScanning() - stops the scan because it was either interupted or it was completed successfully
-- Scan:Calc() - runs calculations and stores the resulting material / craft data in the savedvariables DB (options window)
-- Scan:UpdateStatus() - deals with the statusbar that shows scan progress while scanning
-- Scan:GetTimeDate() - function for getting a formated time and date for storing time of last scan

-- The following "global" (within the addon) variables are initialized in this file:
-- Scan.staus - stores a ton of information about the status of the current scan
-- Scan.AucData - stores the resulting data before it is saved to the savedDB file
-- Scan.frame - way of implementing delays using the "OnUpdate" script
-- Scan.frame2 - way of implementing delays using the "OnUpdate" script

-- ===================================================================================== --


-- load the parent file (TSM) into a local variable and register this file as a module
local TSM = select(2, ...)
local Scan = TSM:NewModule("Scan", "AceEvent-3.0")

local BASE_DELAY = 0.10 -- time to delay for before trying to scan a page again when it isn't fully loaded
local CATEGORIES = {}
CATEGORIES["Enchanting"] = {"4$6", "6$1", "6$4", "6$7", "6$14"}
CATEGORIES["Inscription"] = {"5", "6$6", "6$9"}
CATEGORIES["Jewelcrafting"] = {"6$8", "10"}
CATEGORIES["Alchemy"] = {"4$2", "4$3", "4$4", "6$6"}
CATEGORIES["Blacksmithing"] = {"1$1", "1$2", "1$5", "1$6", "1$7", "1$8", "1$9", "1$13", "1$14", "2$4", 
	"2$5", "2$6", "6$1", "6$4", "6$12", "6$13"}
CATEGORIES["Leatherworking"] = {"2$1$13", "2$3", "2$4", "6$1", "6$3", "6$12", "6$13"}
CATEGORIES["Tailoring"] = {"2$1$13", "2$2", "3$1", "6$1", "6$2", "6$12", "6$13"}
CATEGORIES["Engineering"] = {"5", "6$6", "6$9"}
CATEGORIES["Cooking"] = {"4$1", "6$5", "6$13"}

-- initialize a bunch of variables and frames used throughout the module and register some events
function Scan:OnEnable()
	Scan.status = {page=0, retries=0, timeDelay=0, hardRetry=nil, data=nil, AH=false,
		queued=nil, timeLeft=0, filterlist = {}, filter=nil, data=nil, timeLeft, isScanning=nil, numItems, scantime=nil}
	Scan.AucData = {}

	-- Scan delay for soft reset
	Scan.frame2 = CreateFrame("Frame")
	Scan.frame2:Hide()
	Scan.frame2:SetScript("OnUpdate", function(_, elapsed)
		Scan.status.timeLeft = Scan.status.timeLeft - elapsed
		if Scan.status.timeLeft < 0 then
			Scan.status.timeLeft = 0
			Scan.frame2:Hide()

			Scan:ScanAuctions()
		end
	end)

	-- Scan delay for hard reset
	Scan.frame = CreateFrame("Frame")
	Scan.frame.timeElapsed = 0
	Scan.frame:Hide()
	Scan.frame:SetScript("OnUpdate", function(_, elapsed)
		Scan.frame.timeElapsed = Scan.frame.timeElapsed + elapsed
		if Scan.frame.timeElapsed >= 0.05 then
			Scan.frame.timeElapsed = Scan.frame.timeElapsed - 0.05
			Scan:SendQuery()
		end
	end)

	Scan:RegisterEvent("AUCTION_HOUSE_CLOSED")
	Scan:RegisterEvent("AUCTION_HOUSE_SHOW")
end

-- fires when the AH is openned and adds the "TradeSkillMaster_Crafting - Run Scan" button to the AH frame
function Scan:AUCTION_HOUSE_SHOW()
	Scan.status.AH = true
	
	-- delay to make sure the AH frame is completely loaded before we try and attach the scan button to it
	local delay = CreateFrame("Frame")
	delay:Show()
	delay:SetScript("OnUpdate", function()
		if AuctionFrameBrowse:GetPoint() then
			Scan:ShowScanButton()
			delay:Hide()
		end
	end)
end

-- adds the "TSM_Crafting - Scan" button to the AH frame
function Scan:ShowScanButton()
	if Scan.scanButtonFrame and Scan.scanButtonFrame:GetPoint() then
		Scan.scanButtonFrame:Show()
		return
	end
	-- Scan Button Frame
	local frame3 = CreateFrame("Frame", nil, AuctionFrameBrowse)
	frame3:SetWidth(180)
	frame3:SetHeight(30)
	frame3:SetPoint("TOPRIGHT", AuctionFrameBrowse, "TOPRIGHT", 52, -13)
	frame3:SetClampedToScreen(true)
	frame3:SetFrameStrata("HIGH")
	
	-- make sure the frame attached to the AH frame properly
	-- if it didn't, wait a bit and try again
	if not select(2, frame3:GetPoint()) then
		frame3:Hide()
		Scan:AUCTION_HOUSE_SHOW()
		return
	end
	
	-- Button to Start Scanning
	local button = CreateFrame("Button", nil, frame3, "UIPanelButtonTemplate")
	local DropDownMenu = CreateFrame("Frame", "TSM_DropDownMenu", dropDownButton, "UIDropDownMenuTemplate")
	local dropDownButton = CreateFrame("Button", "TSM_DropDownButton", frame3)
	DropDownMenu.info = {}
	button:SetPoint("TOPRIGHT", frame3, "TOPRIGHT", 0, 0)
	button:SetText("TSM_AuctionDB Scan")
	button:SetWidth(155)
	button:SetHeight(20)
	button:SetScript("OnClick", Scan.RunScan)
	
	dropDownButton:SetPoint("TOPLEFT", frame3, "TOPLEFT", 0, 4)
	dropDownButton:SetWidth(30)
	dropDownButton:SetHeight(30)
	dropDownButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
	dropDownButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Round")
	dropDownButton:SetDisabledTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Disabled")
	dropDownButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
	UIDropDownMenu_Initialize(DropDownMenu, Scan.MenuList, "MENU", 1)
	dropDownButton:SetScript("OnClick", function(self, button, down)
		ToggleDropDownMenu(1, nil, DropDownMenu, self:GetName(), 0, 0)
	end)
	DropDownMenu:SetPoint("TOPLEFT",dropDownButton,"BOTTOMLEFT");
	Scan.scanButtonFrame = frame3
end

-- Setter function for dropdownmenu options
function Scan:UpdateScanSelection(skillName)
	if TSM.db.profile.scanSelections[skillName] == nil then
		TSM.db.profile.scanSelections[skillName] = false
	else
		TSM.db.profile.scanSelections[skillName] = not TSM.db.profile.scanSelections[skillName]
	end
end

-- Generates the dropdownmenu content
function Scan.MenuList(self, level)
	if not level then level = 1 end
	local info = self.info
	wipe(info)
	if level == 1 then
		info.isTitle = 1
		info.text = "Scan Options"
		info.notCheckable = 1
		UIDropDownMenu_AddButton(info, level)

		wipe(info)
		info.disabled = 1
		UIDropDownMenu_AddButton(info, level)
		info.disabled = nil

		info.text = "Professions"
		info.notCheckable = 1
		info.keepShownOnClick = 1
		info.hasArrow = 1
		info.value = "PROFESSIONS"
		UIDropDownMenu_AddButton(info, level)
		
	elseif level == 2 then
		wipe(info)
		if UIDROPDOWNMENU_MENU_VALUE == "PROFESSIONS" then
			info.keepShownOnClick = 1
			for name in pairs(CATEGORIES) do
				info.text = name
				info.func = Scan.UpdateScanSelection
				info.arg1 = name
				if TSM.db.profile.scanSelections[name] == nil then
					TSM.db.profile.scanSelections[name] = false
				end
				info.checked = TSM.db.profile.scanSelections[name]
				UIDropDownMenu_AddButton(info, level)
			end
		end
	end
end
-- gets called when the AH is closed
function Scan:AUCTION_HOUSE_CLOSED()
	if Scan.AHFrame then Scan.AHFrame:Hide() end -- hide the statusbar
	Scan:UnregisterEvent("AUCTION_ITEM_LIST_UPDATE")
	Scan.status.AH = false
	if Scan.status.isScanning then -- stop scanning if we were scanning (pass true to specify it was interupted)
		Scan:StopScanning(true)
	end
end

-- prepares everything to start running a scan
function Scan:RunScan()
	local alreadyAdded = {}
	local scanQueue = {}
	local num = 1
	
	if not Scan.status.AH then
		TSM:Print("Auction house must be open in order to scan.")
		return
	end
	
	-- builds the scanQueue
	for name, selected in pairs(TSM.db.profile.scanSelections) do
		if selected then
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
					tinsert(scanQueue, {class=class, subClass=(subClass or 0), invSlot=(invSlot or 0)})
				end
			end
		end
	end

	if #(scanQueue) == 0 then
		return TSM:Print("Nothing to scan.")
	end
	
	if not CanSendAuctionQuery() then
		TSM:Print("Error: AuctionHouse window busy.")
		return
	end
	
	-- sets up the non-function-local variables
	-- filter = current category being scanned for {class, subClass, invSlot}
	-- filterList = queue of categories to scan for
	wipe(Scan.AucData)
	Scan.status.page = 0
	Scan.status.retries = 0
	Scan.status.hardRetry = nil
	Scan.status.filterList = scanQueue
	Scan.status.filter = scanQueue[1]
	Scan.status.isScanning = true
	Scan.status.numItems = #(scanQueue)
	Scan:UpdateStatus("", 0)
	Scan:UpdateStatus("", 0, true)
	TSM:Start()
	
	--starts scanning
	Scan:SendQuery()
end

-- sends a query to the AH frame once it is ready to be queried (uses Scan.frame as a delay)
function Scan:SendQuery(forceQueue)
	Scan.status.queued = not CanSendAuctionQuery()
	if (not Scan.status.queued and not forceQueue) then
		-- stop delay timer
		Scan.frame:Hide()
		Scan:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
		
		-- Query the auction house (then waits for AUCTION_ITEM_LIST_UPDATE to fire)
		QueryAuctionItems("", nil, nil, Scan.status.filter.invSlot, Scan.status.filter.class, Scan.status.filter.subClass, Scan.status.page, 0, 0)
	else
		-- run delay timer then try again to scan
		Scan.frame:Show()
	end
end

-- gets called whenever the AH window is updated (something is shown in the results section)
function Scan:AUCTION_ITEM_LIST_UPDATE()
	if Scan.status.isScanning then
		Scan.status.timeDelay = 0

		Scan.frame2:Hide()
		
		-- now that our query was successful we can get our data
		Scan:ScanAuctions()
	else
		Scan:UnregisterEvent("AUCTION_ITEM_LIST_UPDATE")
		Scan.AHFrame:Hide()
	end
end

-- scans the currently shown page of auctions and collects all the data
function Scan:ScanAuctions()
	-- collects data on the query:
		-- # of auctions on current page
		-- # of pages total
	local shown, total = GetNumAuctionItems("list")
	local totalPages = math.ceil(total / 50)
	local name, quantity, bid, buyout, owner = {}, {}, {}, {}, {}
	
	-- Check for bad data
	if Scan.status.retries < 3 then
		local badData
		for i=1, shown do
			-- checks whether or not the name and owner of the auctions are valid
			-- if either are invalid, the data is bad
			name[i], _, quantity[i], _, _, _, bid[i], _, buyout[i], _, _, owner[i] = GetAuctionItemInfo("list", i)
			if not (name[i] and owner[i]) then
				badData = true
			end
		end
		
		if badData then
			if Scan.status.hardRetry then
				-- Hard retry
				-- re-sends the entire query
				Scan.status.retries = Scan.status.retries + 1
				Scan:SendQuery()
			else
				-- Soft retry
				-- runs a delay and then tries to scan the query again
				Scan.status.timeDelay = Scan.status.timeDelay + BASE_DELAY
				Scan.status.timeLeft = BASE_DELAY
				Scan.frame2:Show()
	
				-- If after 4 seconds of retrying we still don't have data, will go and requery to try and solve the issue
				-- if we still don't have data, we try to scan it anyway and move on.
				if Scan.status.timeDelay >= 4 then
					Scan.status.hardRetry = true
					Scan.status.retries = 0
				end
			end
			
			return
		end
	end
	
	Scan.status.hardRetry = nil
	Scan.status.retries = 0
	Scan:UpdateStatus("", floor(Scan.status.page/totalPages*100 + 0.5), true)
	Scan:UpdateStatus("", floor((1-(#(Scan.status.filterList)-Scan.status.page/totalPages)/Scan.status.numItems)*100 + 0.5))
	
	-- now that we know our query is good, time to verify and then store our data
	-- ex. "Eternal Earthsiege Diamond" will not get stored when we search for "Eternal Earth"
	for i=1, shown do
		local link = TSM:GetSafeLink(GetAuctionItemLink("list", i))
		Scan:AddAuctionRecord(link, owner[i], quantity[i], bid[i], buyout[i])
	end
	
	-- we are done scanning so add this data to the main table
	if (Scan.status.page == 0 and shown == 0) then
		Scan:AddAuctionRecord(link, "", 0, 0, 0.1)
	end

	-- This query has more pages to scan
	-- increment the page # and send the new query
	if shown == 50 then
		Scan.status.page = Scan.status.page + 1
		Scan:SendQuery()
		return
	end
	
	-- Removes the current filter from the filterList as we are done scanning for that item
	for i=#(Scan.status.filterList), 1, -1 do
		if Scan.status.filterList[i] == Scan.status.filter then
			tremove(Scan.status.filterList, i)
			break
		end
	end
	Scan.status.filter = Scan.status.filterList[1]
	
	-- Query the next filter if we have one
	if Scan.status.filter then
		Scan:UpdateStatus("", floor((1-#(Scan.status.filterList)/Scan.status.numItems)*100 + 0.5))
		Scan.status.page = 0
		Scan:SendQuery()
		return
	end
	
	-- we are done scanning!
	Scan:StopScanning()
end

-- Add a new record to the Scan.AucData table
function Scan:AddAuctionRecord(itemID, owner, quantity, bid, buyout)
	-- Don't add this data if it has no buyout
	if (not buyout) or (buyout <= 0) then return end
	
	if buyout > 1 then
		TSM:OneIteration(buyout/quantity, itemID)
	end

	Scan.AucData[itemID] = Scan.AucData[itemID] or {quantity = 0, onlyPlayer = 0, records = {}}
	Scan.AucData[itemID].quantity = Scan.AucData[itemID].quantity + quantity

	-- Keeps track of how many the player has on the AH
	if owner == select(1, UnitName("player")) then
		Scan.AucData[itemID].onlyPlayer = Scan.AucData[itemID].onlyPlayer + quantity
	end
	
	-- Calculate the bid / buyout per 1 item
	buyout = buyout / quantity
	bid = bid / quantity
	
	-- No sense in using a record for each entry if they are all the exact same data
	for _, record in pairs(Scan.AucData[itemID].records) do
		if (record.owner == owner and record.buyout == buyout and record.bid == bid) then
			record.buyout = buyout
			record.bid = bid
			record.owner = owner
			record.quantity = record.quantity + quantity
			record.isPlayer = (owner==select(1,UnitName("player")))
			return
		end
	end
	
	-- Create a new entry in the table
	tinsert(Scan.AucData[itemID].records, {owner = owner, buyout = buyout, bid = bid,
		isPlayer = (owner==select(1,UnitName("player"))), quantity = quantity})
end

-- stops the scan because it was either interupted or it was completed successfully
function Scan:StopScanning(interupted)
	if interupted then
		-- fires if the scan was interupted (auction house was closed while scanning)
		TSM:Print("Scan interupted due to auction house being closed.")
	else
		-- fires if the scan completed sucessfully
		-- validates the scan data
		TSM:Print("Scan complete!")
		if Scan.AHFrame then 
			Scan.AHFrame:Hide()
		end
		
		for itemID, data in pairs(Scan.AuctionData) do
			TSM:SetQuantity(itemID, data.quantity)
		end
	end
	
	Scan.status.isScanning = nil
	Scan.status.queued = nil
	
	Scan.frame:Hide()
	Scan.frame2:Hide()
end

-- runs calculations and stores the resulting material / craft data in the savedvariables DB (options window)
function Scan:Calc(scanType)
	local matList = TSM.Data:GetMats()

	-- calculates the material costs
	if (scanType == "mats" or scanType == "full") then
		local t, total, quantity
		local result = {}
		local itemVar = {[34054]=80, [34055]=15, [34056]=5, [34052]=15, [34057]=10, [41163]=2, [37705]=1,
						[35624]=5, [35623]=4, [37663]=1, [36918]=1, [43146]=4, [43145]=10}
		for mat=1, #(matList) do
			total = 0
			quantity = 0
			t = TSM.db.factionrealm.AucData[matList[mat]]
			if TSM.db.profile.matCostMethod == "lowest" then
				if (not t) or (not t.records) then
					result[mat] = nil
				else
					sort(t.records, function(a, b) return a.buyout<b.buyout end)
					if t.quantity > 0 then
						result[mat] = tonumber(string.format("%.2f", ((t.records[1].buyout/100) + 0.5)/100))
					end
				end
			elseif TSM.db.profile.matCostMethod == "smart" then
				if (not t) or (not t.records) then
					result[mat] = nil
				else
					if not itemVar[matList[mat]] then
						itemVar[matList[mat]] = 5
					end
					sort(t.records, function(a, b) return a.buyout<b.buyout end)
					if t.quantity < (itemVar[matList[mat]]*1.1) then
						itemVar[matList[mat]] = t.quantity*0.9
					end
					itemVar[matList[mat]] = math.floor(itemVar[matList[mat]])
					
					if t.quantity > 0 then
						for i=1, #(t.records) do
							if i>1 and t.records[i].buyout > t.records[i-1].buyout*1.5 and
								quantity > itemVar[matList[mat]]*0.5 then break end
							
							total = total + t.records[i].buyout*t.records[i].quantity
							quantity = quantity + t.records[i].quantity
							if quantity > itemVar[matList[mat]] then break end
						end
						result[mat] = tonumber(string.format("%.2f", (total/quantity)/10000))
					end
				end
			elseif TSM.db.profile.matCostMethod == "auc" and select(4, GetAddOnInfo("Auc-Advanced")) then
				local itemLink = select(2, GetItemInfo(matList[mat])) or matList[mat]
				if TSM.db.profile.aucMethod == "appraiser" then
					local cost = AucAdvanced.Modules.Util.Appraiser.GetPrice(itemLink)
					if cost then
						result[mat] = tonumber(string.format("%.2f", cost/10000))
					end
				elseif TSM.db.profile.aucMethod == "minBuyout" then
					local cost = select(6, AucAdvanced.Modules.Util.SimpleAuction.Private.GetItems(itemLink))
					if cost then
						result[mat] = tonumber(string.format("%.2f", cost/10000))
					end
				else
					local cost = AucAdvanced.API.GetMarketValue(itemLink)
					if cost then
						result[mat] = tonumber(string.format("%.2f", cost/10000))
					end
				end
			end
			
			if result[mat] and (not TSM.db.profile.matLock[matList[mat]]) then
				TSM.db.profile[TSM.mode].mats[matList[mat]].cost = result[mat]
			end
		end
	end
	
	-- takes care of the craft prices
	-- stores the prices in the main TSM.Data table
	if (scanType == "crafts" or scanType == "full") then
		for itemID, data in pairs(TSM.Data[TSM.mode].crafts) do
			t = TSM.db.factionrealm.AucData[itemID]
			if t and t.records and t.records[1].buyout then
				sort(t.records, function(a, b) return a.buyout<b.buyout end)
				data.sell = floor(t.records[1].buyout/10000+0.5)
				data.posted = t.onlyPlayer
			else
				data.posted = 0
				data.sell = nil
			end
		end
	end
end

-- deals with the statusbar that shows scan progress while scanning
function Scan:UpdateStatus(text, progress, bar2)
	if not Scan.AHFrame then
		-- Frame that containes the StatusBar
		Scan.AHFrame = CreateFrame("Frame", nil, AuctionFrame)
		Scan.AHFrame:SetHeight(25)
		Scan.AHFrame:SetWidth(619)
		Scan.AHFrame:SetBackdrop({
				bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
				edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				tile = true,
				tileSize = 16,
				edgeSize = 16,
				insets = { left = 3, right = 3, top = 5, bottom = 3 }
			})
		Scan.AHFrame:SetBackdropColor(0,0,0, 0.9)
		Scan.AHFrame:SetBackdropBorderColor(0.75, 0.75, 0.75, 0.90)
		Scan.AHFrame:SetPoint("TOPRIGHT", AuctionFrame, "TOPRIGHT", -28, -81)
		Scan.AHFrame:SetFrameStrata("HIGH")
		
		-- StatusBar to show the status of the entire scan (the green statusbar)
		Scan.statusBar = CreateFrame("STATUSBAR", nil, Scan.AHFrame,"TextStatusBar")
		Scan.statusBar:SetOrientation("HORIZONTAL")
		Scan.statusBar:SetHeight(17)
		Scan.statusBar:SetWidth(610)
		Scan.statusBar:SetMinMaxValues(0, 100)
		Scan.statusBar:SetPoint("TOPLEFT", Scan.AHFrame, "TOPLEFT", 5, -4)
		Scan.statusBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-TargetingFrame-BarFill")
		Scan.statusBar:SetStatusBarColor(0,100,20, 0.9)
		
		-- StatusBar to show the status of scanning the current item (the gray statusbar)
		Scan.statusBar2 = CreateFrame("STATUSBAR", nil, Scan.AHFrame,"TextStatusBar")
		Scan.statusBar2:SetOrientation("HORIZONTAL")
		Scan.statusBar2:SetHeight(17)
		Scan.statusBar2:SetWidth(610)
		Scan.statusBar2:SetMinMaxValues(0, 100)
		Scan.statusBar2:SetPoint("TOPLEFT", Scan.AHFrame, "TOPLEFT", 5, -4)
		Scan.statusBar2:SetStatusBarTexture("Interface\\TargetingFrame\\UI-TargetingFrame-BarFill")
		Scan.statusBar2:SetStatusBarColor(200,10,20, 0.5)
		Scan.statusBar2:SetValue(25)
		
		-- Text for the StatusBar
		local tFile, tSize = GameFontNormal:GetFont()
		Scan.statusBar.text = Scan.statusBar:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		Scan.statusBar.text:SetFont(tFile, tSize, "OUTLINE")
		Scan.statusBar.text:SetPoint("CENTER")
	end
	Scan.AHFrame:Show()
	
	-- update the text of the statusBar
	if text == "" then
		Scan.statusBar.text:SetText("TradeSkillMaster_AuctionDB - Scanning")
	elseif text then
		Scan.statusBar.text:SetText(text)
	end
	
	-- update the value of the main status bar (% filled)
	if progress then
		if bar2 then
			Scan.statusBar2:SetValue(progress)
		else
			Scan.statusBar:SetValue(progress)
		end
	end
end

-- function for getting a formated time and date for storing time of last scan
function Scan:GetTimeDate()
	local t = date("*t")
	local AMPM = ""
	
	if t.hour == 0 then
		t.hour = 12
		AMPM = "AM"
	elseif t.hour > 12 then
		t.hour = t.hour - 12
		AMPM = " " .. "PM"
	else
		AMPM = " " .. "AM"
	end
	
	if t.min < 10 then
		t.min = "0" .. t.min
	end
	
	return (t.hour .. ":" .. t.min .. AMPM .. ", " .. date("%a %b %d"))
end