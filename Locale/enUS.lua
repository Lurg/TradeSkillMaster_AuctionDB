local L = LibStub("AceLocale-3.0"):NewLocale("TradeSkillMaster_Gathering", "enUS", true)
if not L then return end

-- TradeSkillMaster_Gathering.lua
L["Gathering"] = true
L["Done Gathering"] = true
L["No Gathering Required"] = true

-- config.lua
L["Enchanting"] = true
L["Inscription"] = true
L["Jewelcrafting"] = true
L["Alchemy"] = true
L["Blacksmithing"] = true
L["Leatherworking"] = true
L["Tailoring"] = true
L["Engineering"] = true
L["Cooking"] = true
L["Gather Mats From Alts"] = true
L["Gathering will create a list of task required to collect mats you need for your craft queue from your alts, banks, or guild banks according to the settings below."] = true
L["Profession to gather mats for:"] = true
L["Specify which profession's craft queue you would like to gather mats for."] = true
L["Character you will craft on:"] = true
L["Specify which character you will craft on. All gathered mats will be mailed to this character."] = true
L["Characters (bags/banks) to gather from:"] = true
L["Select which characters you would like to gather mats from. This will include their bags and personal banks."] = true
L["Guilds (guild banks) to gather from:"] = true
L["Select which guild's guild banks you ould like to gather mats from."] = true
L["Start Gathering"] = true
L["Creates a task list to gather mats according to the above settings."] = true


-- gather.lua
L["Finished gathering from bank."] = true
L["Finished gathering from guild bank."] = true
L["Your bags are full and nothing in your bags is ready to be mailed. Please clear some items from your bags and try again."] = true


-- gui.lua
L["Stop Gathering"] = true
L["Currently Gathering for:"] = true
L["Log onto %s"] = true
L["Visit the Mailbox"] = true
L["Visit the Bank"] = true
L["Visit the Guild Bank"] = true
L["Task:"] = true
L["Buy Merchant Items"] = true

-- mail.lua
L["Mailed items off to %s!"] = true