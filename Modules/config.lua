-- ------------------------------------------------------------------------------ --
--                           TradeSkillMaster_AuctionDB                           --
--           http://www.curse.com/addons/wow/tradeskillmaster_auctiondb           --
--                                                                                --
--             A TradeSkillMaster Addon (http://tradeskillmaster.com)             --
--    All Rights Reserved* - Detailed license information included with addon.    --
-- ------------------------------------------------------------------------------ --

-- load the parent file (TSM) into a local variable and register this file as a module
local TSM = select(2, ...)
local Config = TSM:NewModule("Config")
local AceGUI = LibStub("AceGUI-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("TradeSkillMaster_AuctionDB") -- loads the localization table



function Config:Load(parent)
	local tg = AceGUI:Create("TSMTabGroup")
	tg:SetLayout("Fill")
	tg:SetFullHeight(true)
	tg:SetFullWidth(true)
	tg:SetTabs({{value=1, text=L["Options"]}})
	tg:SetCallback("OnGroupSelected", function(self, _, value)
		tg:ReleaseChildren()
		parent:DoLayout()

		if value == 1 then
			Config:LoadOptions(tg)
		end
		tg.children[1]:DoLayout()
	end)
	parent:AddChild(tg)
	tg:SelectTab(1)
end

function Config:LoadOptions(container)
	local lastScanInfo
	if TSM.db.realm.lastCompleteScan > 0 then
		if TSM.db.realm.hasAppData then
			lastScanInfo = format(L["Last updated from the TSM Application %s ago."], SecondsToTime(time() - TSM.db.realm.lastCompleteScan))
		else
			lastScanInfo = format(L["Last updated from in-game scan %s ago."], SecondsToTime(time() - TSM.db.realm.lastCompleteScan))
		end
	else
		lastScanInfo = L["No scans found."]
	end
	local page = {
		{
			type = "ScrollFrame",
			layout = "Flow",
			children = {
				{
					type = "InlineGroup",
					title = "Last Update Time",
					layout = "Flow",
					children = {
						{
							type = "Label",
							text = lastScanInfo,
							relativeWidth = 1,
						},
					},
				},
				{
					type = "InlineGroup",
					title = "General Options",
					layout = "Flow",
					children = {
						{
							type = "CheckBox",
							label = L["Show AuctionDB AH Tab (Requires Reload)"],
							settingInfo = { TSM.db.profile, "showAHTab" },
							relativeWidth = 0.5,
							tooltip = L["If checked, AuctionDB will add a tab to the AH to allow for in-game scans. If you are using the TSM app exclusively for your scans, you may want to hide it by unchecking this option. This option requires a reload to take effect."],
						},
					},
				},
			},
		},
	}

	TSMAPI.GUI:BuildOptions(container, page)
end

function Config:LoadTooltipOptions(container, options)
	local page = {
		{
			type = "SimpleGroup",
			layout = "Flow",
			fullHeight = true,
			children = {
				{
					type = "CheckBox",
					label = L["Display min buyout in tooltip."],
					settingInfo = { options, "minBuyout" },
					relativeWidth = 1,
					tooltip = L["If checked, the lowest buyout value seen in the last scan of the item will be displayed."],
				},
				{
					type = "CheckBox",
					label = L["Display market value in tooltip."],
					settingInfo = { options, "marketValue" },
					relativeWidth = 1,
					tooltip = L["If checked, the market value of the item will be displayed"],
				},
				{
					type = "HeadingLine",
				},
				{
					type = "CheckBox",
					label = L["Display historical price (via TSM Application) in the tooltip."],
					settingInfo = { options, "historical" },
					relativeWidth = 1,
					tooltip = L["If checked, the historical price of the item will be displayed. This is provided exclusively via the TradeSkillMaster Application."],
				},
				{
					type = "CheckBox",
					label = L["Display global market value avg (via TSM Application) in the tooltip."],
					settingInfo = { options, "globalMarketValue" },
					relativeWidth = 1,
					tooltip = L["If checked, the global market value average of the item will be displayed. This is provided exclusively via the TradeSkillMaster Application."],
				},
				{
					type = "CheckBox",
					label = L["Display global min buyout avg (via TSM Application) in the tooltip."],
					settingInfo = { options, "globalMinBuyout" },
					relativeWidth = 1,
					tooltip = L["If checked, the global minimum buyout average of the item will be displayed. This is provided exclusively via the TradeSkillMaster Application."],
				},
				{
					type = "CheckBox",
					label = L["Display global sale avg (via TSM Application) in the tooltip."],
					settingInfo = { options, "globalSale" },
					relativeWidth = 1,
					tooltip = L["If checked, the global sale average of the item will be displayed. This is provided exclusively via the TradeSkillMaster Application."],
				},
				{
					type = "CheckBox",
					label = L["Display global historical price (via TSM Application) in the tooltip."],
					settingInfo = { options, "globalHistorical" },
					relativeWidth = 1,
					tooltip = L["If checked, the global historical price of the item will be displayed. This is provided exclusively via the TradeSkillMaster Application."],
				},
			},
		},
	}

	TSMAPI.GUI:BuildOptions(container, page)
end