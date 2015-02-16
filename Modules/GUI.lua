-- ------------------------------------------------------------------------------ --
--                           TradeSkillMaster_AuctionDB                           --
--           http://www.curse.com/addons/wow/tradeskillmaster_auctiondb           --
--                                                                                --
--             A TradeSkillMaster Addon (http://tradeskillmaster.com)             --
--    All Rights Reserved* - Detailed license information included with addon.    --
-- ------------------------------------------------------------------------------ --

-- load the parent file (TSM) into a local variable and register this file as a module
local TSM = select(2, ...)
local GUI = TSM:NewModule("GUI")
local L = LibStub("AceLocale-3.0"):GetLocale("TradeSkillMaster_AuctionDB") -- loads the localization table
local private = {frame=nil}

function GUI:Show(frame)
	private:Create(frame)
	private.frame:Show()
	GUI:UpdateStatus("", 0, 0)
	TSMAPI:CreateTimeDelay("auctionDBGetAllStatus", 0, private.UpdateGetAllStatus, 0.2)
end

function GUI:Hide()
	private.frame:Hide()
	TSM.Scan:DoneScanning()
	TSMAPI.AuctionScan:StopScan()
	TSMAPI:CancelFrame("auctionDBGetAllStatus")
end

function GUI:UpdateStatus(text, major, minor)
	if text then
		private.frame.statusBar:SetStatusText(text)
	end
	if major or minor then
		private.frame.statusBar:UpdateStatus(major, minor)
	end
end



function private:Create(parent)
	if private.frame then return end
	
	local function UpdateGetAllButton()
	end
	
	local BFC = TSMAPI:GetBuildFrameConstants()
	local frameInfo = {
		type = "Frame",
		parent = parent,
		points = "ALL",
		children = {
			{
				type = "Text",
				key = "appAd",
				text = TSMAPI.Design:GetInlineColor("link")..L["Scanning the auction house in game is no longer necessary!"].."|r",
				textHeight = 20,
				justify = {"CENTER", "MIDDLE"},
				size = {0, 20},
				points = {{"TOP", 45, -5}},
			},
			{
				type = "Text",
				text = format(L["Download the FREE TSM desktop application which will automatically update your TSM_AuctionDB prices using Blizzard's online APIs (and does MUCH more). Visit %s for more info and never scan the AH again! This is the best way to update your AuctionDB prices."], TSMAPI.Design:GetInlineColor("link").."http://tradeskillmaster.com/app/overview".."|r"),
				justify = {"LEFT", "TOP"},
				size = {0, 55},
				points = {{"TOPLEFT", 90, -30}, {"TOPRIGHT", -5, -30}},
			},
			{
				type = "Frame",
				key = "content",
				points = {{"TOPLEFT", parent.content}, {"BOTTOMRIGHT", parent.content}},
				children = {
					{
						type = "GroupTreeFrame",
						key = "groupTree",
						groupTreeInfo = {nil, "AuctionDB"},
						points = {{"TOPLEFT", 5, -35}, {"BOTTOMRIGHT", -205, 5}},
					},
					{
						type = "VLine",
						points = {{"TOPRIGHT", -200, -30}, {"BOTTOMRIGHT", -200, 0}},
					},
					{
						type = "Frame",
						key = "buttonFrame",
						points = {{"TOPLEFT", BFC.PARENT, "TOPRIGHT", -200, 0}, {"BOTTOMRIGHT"}},
						children = {
							-- row 1 - getall scan
							{
								type = "Button",
								key = "getAllBtn",
								text = L["Run GetAll Scan"],
								textHeight = 18,
								tooltip = L["A GetAll scan is the fastest in-game method for scanning every item on the auction house. However, there are many possible bugs on Blizzard's end with it including the chance for it to disconnect you from the game. Also, it has a 15 minute cooldown."],
								size = {0, 22},
								points = {{"TOPLEFT", 6, -50}, {"TOPRIGHT", -6, -50}},
								scripts = {"OnClick"},
							},
							{
								type = "Text",
								key = "getAllStatusText",
								text = "",
								justify = {"CENTER", "MIDDLE"},
								size = {0, 16},
								points = {{"TOPLEFT", BFC.PREV, "BOTTOMLEFT", 0, -3}, {"TOPRIGHT", BFC.PREV, "BOTTOMRIGHT", 0, -3}},
							},
							{
								type = "HLine",
								offset = -110,
							},
							-- row 2 - full scan
							{
								type = "Button",
								key = "fullBtn",
								text = L["Run Full Scan"],
								textHeight = 18,
								tooltip = L["A full auction house scan will scan every item on the auction house but is far slower than a GetAll scan. Expect this scan to take several minutes or longer."],
								size = {0, 22},
								points = {{"TOPLEFT", 6, -150}, {"TOPRIGHT", -6, -150}},
								scripts = {"OnClick"},
							},
							{
								type = "HLine",
								offset = -200,
							},
							-- row 3 - group scan
							{
								type = "Button",
								key = "groupBtn",
								text = L["Scan Selected Groups"],
								textHeight = 18,
								tooltip = L["This will do a slow auction house scan of every item in the selected groups and update their AuctionDB prices. This may take several minutes."],
								size = {0, 22},
								points = {{"TOPLEFT", 6, -225}, {"TOPRIGHT", -6, -225}},
								scripts = {"OnClick"},
							},
						},
					},
				},
			},
		},
		handlers = {
			content = {
				buttonFrame = {
					getAllBtn = {
						OnClick = TSM.Scan.StartGetAllScan,
					},
					fullBtn = {
						OnClick = TSM.Scan.StartFullScan,
					},
					groupBtn = {
						OnClick = function()
							local items = {}
							for groupName, data in pairs(private.frame.content.groupTree:GetSelectedGroupInfo()) do
								groupName = TSMAPI:FormatGroupPath(groupName, true)
								for itemString in pairs(data.items) do
									tinsert(items, itemString)
								end
							end
							TSM.Scan:StartGroupScan(items)
						end,
					},
				},
			},
		},
	}
	private.frame = TSMAPI:BuildFrame(frameInfo)
	TSMAPI.Design:SetFrameBackdropColor(private.frame.content)
	private.frame.statusBar = private.frame.statusBar or private:CreateStatusBar(private.frame.content)
	
	-- create animation for app ad
	local ag = private.frame.appAd:CreateAnimationGroup()
	local a1 = ag:CreateAnimation("Alpha")
	a1:SetChange(-.4)
	a1:SetDuration(.5)
	ag:SetLooping("BOUNCE")
	ag:Play()
end

function private:UpdateGetAllStatus()
	if TSM.Scan.isScanning then
		private.frame.content.buttonFrame.getAllBtn:Disable()
		private.frame.content.buttonFrame.fullBtn:Disable()
		private.frame.content.buttonFrame.groupBtn:Disable()
	elseif not select(2, CanSendAuctionQuery()) then
		local previous = TSM.db.profile.lastGetAll or time()
		if previous > (time() - 15*60) then
			local diff = previous + 15*60 - time()
			local diffMin = math.floor(diff/60)
			local diffSec = diff - diffMin*60
			private.frame.content.buttonFrame.getAllStatusText:SetText("|cff990000"..format(L["Ready in %s min and %s sec"], diffMin, diffSec))
		else
			private.frame.content.buttonFrame.getAllStatusText:SetText("|cff990000"..L["Not Ready"])
		end
		private.frame.content.buttonFrame.getAllBtn:Disable()
		private.frame.content.buttonFrame.fullBtn:Enable()
		private.frame.content.buttonFrame.groupBtn:Enable()
	else
		private.frame.content.buttonFrame.getAllBtn:Enable()
		private.frame.content.buttonFrame.fullBtn:Enable()
		private.frame.content.buttonFrame.groupBtn:Enable()
		private.frame.content.buttonFrame.getAllStatusText:SetText("|cff009900"..L["Ready"])
	end
end


function private:CreateStatusBar(parent)
	local frame = TSMAPI.GUI:CreateStatusBar(parent, "TSMAuctionDBStatusBar")
	TSMAPI.GUI:CreateHorizontalLine(frame, -30, parent)
	
	return frame
end