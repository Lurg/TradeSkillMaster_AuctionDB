-- load the parent file (TSM) into a local variable and register this file as a module
local TSM = select(2, ...)
local Config = TSM:NewModule("Config")
local AceGUI = LibStub("AceGUI-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("TradeSkillMaster_AuctionDB") -- loads the localization table

local page = 0
local filter = {text=nil, class=nil, subClass=nil}
local items = {}

-- options page
function Config:Load(parent)
	local vk = TSMAPI:GetVersionKey("TradeSkillMaster")
	if not vk or vk < 1 then
		local page = {
			{
				type = "ScrollFrame",
				layout = "flow",
				children = {
					{
						type = "Label",
						text = L["Your version of the main TradeSkillMaster addon is out of date. Please update it in order to be able to view this page."],
						fontObject = GameFontNormalLarge,
						relativeWidth = 1,
					},
				},
			},
		}
		
		TSMAPI:BuildPage(parent, page)
		return
	end
	filter = {}
	
	local tg = AceGUI:Create("TSMTabGroup")
	tg:SetLayout("Fill")
	tg:SetFullHeight(true)
	tg:SetFullWidth(true)
	tg:SetTabs({{value=1, text=L["Search"]}, {value=2, text=L["Options"]}})
	tg:SetCallback("OnGroupSelected", function(self,_,value)
		tg:ReleaseChildren()
		parent:DoLayout()
		
		if value == 1 then
			Config:LoadSearch(tg)
		elseif value == 2 then
			Config:LoadOptions(tg)
		end
	end)
	parent:AddChild(tg)
	tg:SelectTab(1)
end

local function getIndex(t, value)
	for i, v in pairs(t) do
		if v == value then
			return i
		end
	end
end

function Config:UpdateItems()
	wipe(items)
	local cache = {}
	local sortMethod = TSM.db.profile.resultsSortMethod
	local fClass = filter.class and select(filter.class, GetAuctionItemClasses())
	local fSubClass = filter.subClass and select(filter.subClass, GetAuctionItemSubClasses(filter.class))
	if filter.text or fClass then
		for itemID, data in pairs(TSM.data) do
			local name, _, rarity, ilvl, minlvl, class, subClass = GetItemInfo(itemID)
			if not name then
				name, _, rarity, ilvl, minlvl, class, subClass = unpack(data.itemInfo or {})
			end
			if (name and filter.text and strfind(strlower(name), strlower(filter.text))) and (not fClass or (class == fClass and (not fSubClass or subClass == fSubClass))) and (not TSM.db.profile.hidePoorQualityItems or rarity > 0) then
				tinsert(items, itemID)
				if sortMethod == "name" then
					cache[itemID] = name
				elseif sortMethod == "ilvl" then
					cache[itemID] = ilvl
				elseif sortMethod == "minlvl" then
					cache[itemID] = minlvl
				elseif sortMethod == "marketvalue" then
					cache[itemID] = data.marketValue
				elseif sortMethod == "minbuyout" then
					cache[itemID] = data.minBuyout
				end
			end
		end
	end
	
	sort(items, function(a, b)
			if TSM.db.profile.resultsSortOrder == "ascending" then
				return (cache[a] or 1/0) < (cache[b] or 1/0)
			else -- descending
				return (cache[a] or 0) > (cache[b] or 0)
			end
		end)
end

function Config:LoadSearch(container)
	local results = {}
	
	local totalResults = #items
	local minIndex = page * TSM.db.profile.resultsPerPage + 1
	local maxIndex = min(TSM.db.profile.resultsPerPage*(page+1), totalResults)
	if totalResults > 0 then
		for i=minIndex, maxIndex do
			local itemID = items[i]
			local data = TSM.data[items[i]]
			local playerQuantity = TSM:GetTotalPlayerAuctions(itemID)
			local timeDiff = data.lastScan and SecondsToTime(time()-data.lastScan)
		
			local temp = {
				{
					type = "InteractiveLabel",
					text = select(2, GetItemInfo(itemID)) or "???",
					fontObject = GameFontHighlight,
					relativeWidth = 0.349,
					callback = function() SetItemRef("item:".. itemID, itemID) end,
					tooltip = itemID,
				},
				{
					type = "MultiLabel",
					labelInfo = {{text=data.currentQuantity..(playerQuantity and " |cffffbb00("..playerQuantity..")|r" or ""), relativeWidth=0.18},
						{text=TSM:FormatMoneyText(data.minBuyout) or "---", relativeWidth=0.20},
						{text=TSM:FormatMoneyText(data.marketValue) or "---", relativeWidth=0.24},
						{text=timeDiff and "|cff99ffff"..format(L["%s ago"], timeDiff).."|r" or "|cff99ffff---|r", relativeWidth=0.33}},
					relativeWidth = 0.65,
				},
				{
					type = "HeadingLine",
				},
			}
			
			for _, widget in ipairs(temp) do
				tinsert(results, widget)
			end
		end
	elseif filter.text then
		results = {
			{
				type = "Spacer",
				quantity = 2,
			},
			{
				type = "Label",
				relativeWidth = 0.4
			},
			{
				type = "Label",
				relativeWidth = 0.6,
				text = L["No items found"],
				fontObject = GameFontNormalLarge,
			},
		}
	else
		results = {
			{
				type = "Spacer",
				quantity = 2,
			},
			{
				type = "Label",
				relativeWidth = 0.05
			},
			{
				type = "Label",
				relativeWidth = 0.949,
				text = L["Use the search box and category filters above to search the AuctionDB data."],
				fontObject = GameFontNormalLarge,
			},
		}
	end
	
	local classes, subClasses = {}, {}
	for i, className in ipairs({GetAuctionItemClasses()}) do
		classes[i] = className
		subClasses[i] = {}
		for j, subClassName in ipairs({GetAuctionItemSubClasses(i)}) do
			subClasses[i][j] = subClassName
		end
		tinsert(subClasses[i], L["<No Item SubType Filter>"])
	end
	tinsert(classes, L["<No Item Type Filter>"])

	local page = {
		{
			type = "SimpleGroup",
			layout = "Flow",
			fullHeight = true,
			children = {
				{
					type = "Label",
					text = L["You can use this page to lookup an item or group of items in the AuctionDB database. Note that this does not perform a live search of the AH."],
					relativeWidth = 1,
				},
				{
					type = "HeadingLine",
				},
				{
					type = "EditBox",
					label = L["Search"],
					value = filter.text,
					relativeWidth = 0.49,
					callback = function(_,_,value)
							filter.text = (value or ""):trim()
							page = 0
							Config:UpdateItems()
							container:SelectTab(1)
						end,
					tooltip = L["Any items in the AuctionDB database that contain the search phrase in their names will be displayed."],
				},
				{
					type = "Dropdown",
					label = L["Item Type Filter"],
					list = classes,
					value = filter.class or #classes,
					relativeWidth = 0.25,
					callback = function(self,_,value)
							filter.text = filter.text or ""
							if value ~= filter.class then
								filter.subClass = nil
							end
							if value == #classes then
								filter.class = nil
							else
								filter.class = value
							end
							page = 0
							Config:UpdateItems()
							container:SelectTab(1)
						end,
					tooltip = L["You can filter the results by item type by using this dropdown. For example, if you want to search for all herbs, you would select \"Trade Goods\" in this dropdown and \"Herbs\" as the subtype filter."],
				},
				{
					type = "Dropdown",
					label = L["Item SubType Filter"],
					disabled = filter.class == nil or (subClasses[filter.class] and #subClasses[filter.class] == 0),
					list = subClasses[filter.class or 0],
					value = filter.subClass or #(subClasses[filter.class or 0] or {}),
					relativeWidth = 0.25,
					callback = function(_,_,value)
							if value == #subClasses[filter.class] then
								filter.subClass = nil
							else
								filter.subClass = value
							end
							page = 0
							Config:UpdateItems()
							container:SelectTab(1)
						end,
					tooltip = L["You can filter the results by item subtype by using this dropdown. For example, if you want to search for all herbs, you would select \"Trade Goods\" in the item type dropdown and \"Herbs\" in this dropdown."],
				},
				{
					type = "Label",
					relativeWidth = 0.15
				},
				{
					type = "Button",
					text = L["Refresh"],
					relativeWidth = 0.2,
					callback = function()
							page = 0
							Config:UpdateItems()
							container:SelectTab(1)
							container:DoLayout()
						end,
					tooltip = L["Refreshes the current search results."],
				},
				{
					type = "Label",
					relativeWidth = 0.15
				},
				{
					type = "Icon",
					image = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up",
					width = 24,
					imageWidth = 24,
					imageHeight = 24,
					disabled = minIndex == 1,
					callback = function(self)
							page = page - 1
							container:SelectTab(1)
						end,
					tooltip = L["Previous Page"],
				},
				{
					type = "Label",
					relativeWidth = 0.03
				},
				{
					type = "Label",
					text = format(L["Items %s - %s (%s total)"], minIndex, maxIndex, totalResults),
					relativeWidth = 0.35,
				},
				{
					type = "Icon",
					image = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up",
					width = 24,
					imageWidth = 24,
					imageHeight = 24,
					disabled = maxIndex == totalResults,
					callback = function(self)
							page = page + 1
							container:SelectTab(1)
						end,
					tooltip = L["Next Page"],
				},
				{
					type = "HeadingLine"
				},
				{
					type = "MultiLabel",
					labelInfo = {{text=L["Item Link"], relativeWidth=0.33}, {text=L["Seen Last Scan (Yours)"], relativeWidth=0.12},
						{relativeWidth=0.03}, {text=L["Minimum Buyout"], relativeWidth=0.15}, {text=L["Market Value"], relativeWidth=0.15},
						{text=L["Last Scanned"], relativeWidth=0.21}},
					relativeWidth = 1,
				},
				{
					type = "HeadingLine",
				},
				{
					type = "ScrollFrame",
					fullHeight = true,
					layout = "Flow",
					children = results,
				},
			},
		},
	}
	
	TSMAPI:BuildPage(container, page)
end

function Config:LoadOptions(container)
	local page = {
		{
			type = "ScrollFrame",
			layout = "Flow",
			children = {
				{
					type = "InlineGroup",
					title = L["General Options"],
					layout = "Flow",
					children = {
						{
							type = "CheckBox",
							label = L["Enable display of AuctionDB data in tooltip."],
							value = TSM.db.profile.tooltip,
							relativeWidth = 0.5,
							callback = function(_,_,value)
									TSM.db.profile.tooltip = value
									if value then
										TSMAPI:RegisterTooltip("TradeSkillMaster_AuctionDB", function(...) return TSM:LoadTooltip(...) end)
									else
										TSMAPI:UnregisterTooltip("TradeSkillMaster_AuctionDB")
									end
								end,
						},
					},
				},
				{
					type = "InlineGroup",
					title = L["Search Options"],
					layout = "Flow",
					children = {
						{
							type = "EditBox",
							label = L["Items per page"],
							value = TSM.db.profile.resultsPerPage,
							relativeWidth = 0.2,
							callback = function(_,_,value)
									value = tonumber(value)
									if value and value <= 500 and value >= 5 then
										TSM.db.profile.resultsPerPage = value
									else
										TSM:Print(L["Invalid value entered. You must enter a number between 5 and 500 inclusive."])
									end
								end,
							tooltip = L["This determines how many items are shown per page in results area of the \"Search\" tab of the AuctionDB page in the main TSM window. You may enter a number between 5 and 500 inclusive. If the page lags, you may want to decrease this number."],
						},
						{
							type = "Label",
							relativeWidth = 0.1
						},
						{
							type = "Dropdown",
							label = L["Sort items by"],
							list = {["name"]=NAME, ["rarity"]=RARITY, ["ilvl"]=STAT_AVERAGE_ITEM_LEVEL, ["minlvl"]=L["Item MinLevel"], ["marketvalue"]=L["Market Value"], ["minbuyout"]=L["Minimum Buyout"]},
							value = TSM.db.profile.resultsSortMethod,
							relativeWidth = 0.34,
							callback = function(_,_,value) TSM.db.profile.resultsSortMethod = value end,
							tooltip = L["Select how you would like the search results to be sorted. After changing this option, you may need to refresh your search results by hitting the \"Refresh\" button."],
						},
						{
							type = "Label",
							relativeWidth = 0.02
						},
						{
							type = "CheckBox",
							label = L["Ascending"],
							cbType = "radio",
							relativeWidth = 0.16,
							value = TSM.db.profile.resultsSortOrder == "ascending",
							disabled = TSM.db.profile.resultsSortOrder == nil,
							callback = function(self,_,value)
									if value then
										TSM.db.profile.resultsSortOrder = "ascending"
										local i = getIndex(self.parent.children, self)
										self.parent.children[i+1]:SetValue(false)
									end
								end,
							tooltip = L["Sort search results in ascending order."],
						},
						{
							type = "CheckBox",
							label = L["Descending"],
							cbType = "radio",
							relativeWidth = 0.16,
							value = TSM.db.profile.resultsSortOrder == "descending",
							disabled = TSM.db.profile.resultsSortOrder == nil,
							callback = function(self,_,value)
									if value then
										TSM.db.profile.resultsSortOrder = "descending"
										local i = getIndex(self.parent.children, self)
										self.parent.children[i-1]:SetValue(false)
									end
								end,
							tooltip = L["Sort search results in descending order."],
						},
						{
							type = "CheckBox",
							label = L["Hide poor quality items"],
							relativeWidth = 0.5,
							value = TSM.db.profile.hidePoorQualityItems,
							callback = function(self,_,value) TSM.db.profile.hidePoorQualityItems = value end,
							tooltip = L["If checked, poor quality items won't be shown in the search results."],
						},
					},
				},
			},
		},
	}
	
	if AucAdvanced then
		tinsert(page[1].children[1].children, {
				type = "CheckBox",
				label = L["Block Auctioneer while Scanning."],
				value = TSM.db.profile.blockAuc,
				relativeWidth = 0.5,
				callback = function(_,_,value) TSM.db.profile.blockAuc = value end,
				tooltip = L["If checked, Auctioneer will be prevented from scanning / processing AuctionDB's scans."],
			})
	end
	
	TSMAPI:BuildPage(container, page)
end