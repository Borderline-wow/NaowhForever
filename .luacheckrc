-- luacheck settings for Naowh Forever. From the repo root: luacheck .
-- Lua 5.1, as the game runs it. Libs/ is fetched by the packager and not ours to lint.
std = "lua51"
exclude_files = { "Libs/" }

-- WoW calls handlers with fixed arguments (self, event, ...), so unused ones are normal.
ignore = { "212" }

-- No line length limit: the codebase has never kept one.
max_line_length = false

-- Globals the addon writes on purpose: its namespace and saved variables, slash commands,
-- key bindings, map pin mixins, popups, and the Global Font setting's font paths.
globals = {
    "NaowhForever", "NaowhForeverDB", "NaowhUI_SmartRemindersDB",
    "NaowhForever_OnCompartmentClick", "NaowhForever_BagSpacePickUp", "NaowhForever_BossLoot",
    "SLASH_NAOWHFOREVER1", "SLASH_NAOWHFOREVER2", "SLASH_NAOWHFOREVER3",
    "SLASH_NAOWHFOREVER4", "SLASH_NAOWHFOREVER5",
    "SLASH_NAOWHFOREVERCOPY1", "SLASH_NAOWHFOREVERCOPY2", "SLASH_NAOWHUITANK1",
    "BINDING_HEADER_NAOWHFOREVER", "BINDING_NAME_NAOWHFOREVER_BAGSPACE_PICKUP",
    "BINDING_NAME_NAOWHFOREVER_BOSSLOOT",
    "NaowhForeverTownPinMixin", "NaowhForeverZoneLinkPinMixin", "NaowhForeverLibraryPinMixin",
    "SlashCmdList", "hash_SlashCmdList", "StaticPopupDialogs",
    "STANDARD_TEXT_FONT", "UNIT_NAME_FONT", "DAMAGE_TEXT_FONT",
}

-- The game's API and constants the addon reads. A name missing here is flagged, which is
-- how a misspelled global, or one Forever does not have, gets caught.
read_globals = {
    "AcceptQuest", "ActionBarButtonEventsFrame", "ActionStatus", "AlertFrame", "Ambiguate",
    "AnchorUtil", "AuraContainerSortMethod", "AuraUtil", "BACKPACK_CONTAINER", "BigWigsLoader",
    "bit", "BNET_CLIENT_WOW", "BNGetInfo", "BNGetNumFriends", "BreakUpLargeNumbers", "BuyMerchantItem", "BuyTrainerService",
    "canaccessallvalues", "canaccesstable", "canaccessvalue", "CanMerchantRepair",
    "ChatEdit_InsertLink", "ChatFrame1EditBox", "ChatFrameUtil", "CinematicFrame_CancelCinematic",
    "ClearCursor", "CloseQuest", "ColorPickerFrame", "CombatTextFont",
    "CombatTextFontOutline", "CompleteQuest", "ConfirmAcceptQuest",
    "Constants", "COPPER_AMOUNT", "CopyTable", "CreateAndInitFromMixin", "CreateAtlasMarkup", "CreateColor",
    "CreateFrame", "CreateFromMixins", "CreateMacro", "CreateVector2D", "CUSTOM_CLASS_COLORS",
    "CVarCallbackRegistry", "C_AddOns", "C_AuctionHouse", "C_BattleNet", "C_ChallengeMode",
    "C_ChatInfo", "C_ClassColor", "C_ClassTalents", "C_CombatLog", "C_Container", "C_CooldownViewer",
    "C_CurrencyInfo", "C_CurveUtil", "C_CVar", "C_DeathInfo", "C_DurationUtil",
    "C_EncounterEvents", "C_EncounterJournal", "C_EncounterTimeline", "C_EquipmentSet",
    "C_ActionBar", "C_FriendList", "C_GamepadUI", "C_GossipInfo", "C_GuildInfo", "C_InstanceEncounter",
    "C_Item", "C_LootHistory", "C_MajorFactions", "C_Map", "C_MountJournal", "C_Transmog", "C_MerchantFrame", "C_NamePlate", "C_PaperDollInfo",
    "C_PartyInfo", "C_QuestLog", "C_Reputation", "C_SeasonInfo",
    "C_RestrictedActions", "C_Secrets", "C_SpecializationInfo", "C_Spell", "C_SpellBook",
    "C_StringUtil", "C_SuperTrack", "C_SwingTimer", "C_TaxiMap", "C_Texture", "C_Timer",
    "C_TooltipInfo", "C_TradeSkillUI", "C_Traits", "C_TransmogCollection", "C_TTSSettings",
    "C_UnitAuras", "C_VoiceChat", "date", "debugprofilestop", "DEFAULT_CHAT_FRAME",
    "DeleteCursorItem", "DeleteMacro", "DELETE_GOOD_ITEM", "DELETE_ITEM_CONFIRM_STRING",
    "EditMacro", "EJ_GetCurrentTier", "EJ_GetEncounterInfo", "EJ_GetEncounterInfoByIndex",
    "EJ_GetInstanceByIndex", "EJ_GetInstanceInfo", "EJ_SelectInstance", "EJ_SelectTier",
    "COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED", "CommunitiesFrame", "EncounterJournal", "Enum", "EnumerateFrames", "ERR_BAG_FULL", "ERR_INV_FULL", "ERR_QUEST_PUSH_BUSY_S", "ERR_QUEST_PUSH_SUCCESS_S",
    "EventRegistry", "EventToastManagerFrame", "EventUtil", "ScrollBoxListMixin",
    "FACTION_STANDING_INCREASED", "GameFontHighlight", "GameTooltip",
    "GameTooltipTextLeft1", "GameTooltip_Hide", "GetActionInfo", "GetActiveTitle",
    "GetAddOnMemoryUsage", "GetBindingAction", "GetBindingKey", "GetBindingName",
    "GetBindingText", "GetBindLocation", "GetClassInfo", "GetCurrentBindingSet",
    "GetCurrentArenaSeason", "GetCurrentKeyBoardFocus", "GetCurrentRegion", "GetText", "UnitSex",
    "GetCursorInfo", "GetCursorPosition", "GetCVar",
    "PVP_RANK_0_NAME", "PVP_RANK_REWARDS_VENDOR_ALLIANCE", "PVP_RANK_REWARDS_VENDOR_HORDE", "ITEM_SPELL_KNOWN",
    "GetDifficultyInfo", "GetFonts", "GetFramerate", "GetGuildInfo", "GetGuildRosterInfo",
    "GetInstanceInfo", "GetInventoryItemDurability", "GetInventoryItemID",
    "GetInventoryItemLink", "GetInventoryItemQuality", "GetInventoryItemTexture",
    "GetLootRollItemLink", "GetLootSlotInfo", "GetLootSlotLink", "GetLootThreshold",
    "GetMacroBody", "GetMacroInfo", "GetMacroIndexByName", "GetMaxLevelForPlayerExpansion",
    "GetMerchantItemID", "GetMerchantItemInfo", "GetMerchantItemLink",
    "GetMerchantItemMaxStack", "GetMerchantNumItems", "GetMoney", "GetMoneyString",
    "GetMouseFoci", "GetNetStats", "GetNormalizedRealmName", "GetNumActiveQuests",
    "GetNumAvailableQuests", "GetNumClasses", "GetNumGroupMembers", "GetNumGuildMembers", "GetNumSavedInstances",
    "GetNumLootItems", "GetNumMacros", "GetNumQuestChoices", "GetNumRoutes",
    "GetNumShapeshiftForms", "GetNumSubgroupMembers", "GetNumTrainerServices",
    "GetPartyAssignment", "GetPetActionInfo", "GetPhysicalScreenSize", "GetPlayerInfoByGUID",
    "GetProfessionInfo", "GetProfessions", "GetQuestDifficultyColor", "GetQuestID", "GetQuestLink", "GetQuestLogChoiceInfo",
    "GetQuestLogQuestText", "GetQuestLogRewardInfo", "GetQuestLogRewardMoney", "GetQuestLogRewardXP",
    "GetNumQuestLogChoices", "GetNumQuestLogRewards", "QuestUtils_IsQuestWatched",
    "GetQuestItemInfo", "GetQuestItemLink", "GetQuestLogChoiceInfo", "GetQuestLogItemLink",
    "GetQuestLogRewardXP", "GetQuestReward", "GetRaidRosterInfo", "GetRealmName", "GetSavedInstanceInfo",
    "GetRepairAllCost", "GetShapeshiftForm", "GetShapeshiftFormID",
    "GetSpecializationInfoByID", "GetSpellBaseCooldown", "GetSubZoneText", "GetTaxiMapID",
    "GetTime", "GetTitleText", "GetTrainerServiceCost", "GetTrainerServiceIcon", "GetTrainerServiceInfo",
    "GetTrainerServiceSkillReq", "GetUnitName", "GetXPExhaustion", "GetZoneText", "GOLD_AMOUNT",
    "HandleModifiedItemClick", "hash_EmoteTokenList", "HideUIPanel", "hooksecurefunc", "IconDataProviderExtraType",
    "IconDataProviderMixin",
    "InCinematic", "InCombatLockdown", "InviteUnit", "INVSLOT_FIRST_EQUIPPED", "INVSLOT_LAST_EQUIPPED",
    "INVSLOT_TRINKET1", "INVSLOT_TRINKET2", "IsAltKeyDown", "IsControlKeyDown", "IsInGroup",
    "IsInGuild", "IsInInstance", "IsInRaid", "IsModifiedClick", "IsMounted",
    "IsMouseButtonDown", "IsPlayerMoving", "IsPlayerSpell", "IsQuestCompletable", "IsResting",
    "issecrettable", "issecretvalue", "IsSecureCmd", "IsShiftKeyDown", "IsStealthed", "IsTradeskillTrainer",
    "IsXPUserDisabled", "Item", "ItemEventListener", "ItemRefTooltip",
    "ItemRefTooltipTextLeft1", "ITEM_QUALITY_COLORS", "LE_PARTY_CATEGORY_INSTANCE", "LibStub",
    "LOCALIZED_CLASS_NAMES_MALE", "LoggingCombat", "LootFrame", "LootSlot",
    "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_SELF",
    "LOOT_ITEM_SELF_MULTIPLE", "MainMenuBarVehicleLeaveButton", "MapCanvasDataProviderMixin", "MapCanvasPinMixin",
    "MAX_PARTY_MEMBERS", "MAX_RAID_MEMBERS", "Menu", "MenuUtil", "MenuVariants",
    "MerchantFrame", "Mixin", "MovieFrame", "MuteSoundFile", "NumTaxiNodes",
    "NUM_BAG_SLOTS", "NUM_CHAT_WINDOWS", "NUM_PET_ACTION_SLOTS",
    "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "OTHER", "PetHasActionBar", "PickupAction", "PickupMacro", "PlaceAction",
    "PlaySound", "PlaySoundFile", "ProfessionsFrame", "PROFESSIONS_COOKING",
    "PROFESSIONS_FIRST_AID", "PROFESSIONS_FIRST_PROFESSION", "PROFESSIONS_FISHING",
    "PROFESSIONS_MISSING_PROFESSION", "QuestDifficultyColors", "QuestFrameRewardPanel",
    "QuestGetAutoAccept", "QuestInfoFrame", "QuestInfoItem_OnClick", "QuestInfoRewardsFrame", "QuestLogPushQuest",
    "RAID_CLASS_COLORS", "RegisterStateDriver", "RequestRaidInfo", "ReloadUI", "RepairAllItems",
    "RequestTimePlayed", "SaveBindings", "SEARCH", "SecondsToTime", "SecureHandlerWrapScript",
    "SelectActiveQuest", "SelectAvailableQuest", "SendChatMessage", "SetBinding", "SetCVar", "SetItemRef", "C_Minimap", "GameTooltip_SetTitle",
    "GameTooltip_AddNormalLine",
    "SHARE_QUEST", "ShoppingTooltip1", "ShoppingTooltip2", "SILVER_AMOUNT", "SOUNDKIT",
    "StaticPopup_FindVisible", "StaticPopup_Hide", "StaticPopup_Show", "StatusTrackingBarInfo",
    "StatusTrackingBarManager", "strlower", "strsplit", "strsub", "strtrim", "strupper",
    "SubZoneTextFrame", "TaxiGetNodeSlot", "TaxiNodeGetType", "TaxiNodeName", "TaxiRequestEarlyLanding",
    "tContains", "TextToSpeech_GetSelectedVoice", "time", "ToggleCalendar", "TomTom",
    "TooltipDataProcessor", "TRADE_SKILLS", "TSM_API", "UIErrorsFrame", "UiMapPoint",
    "UIParent", "UNKNOWNOBJECT", "UnitAffectingCombat", "UnitAttackSpeed", "UnitCanAttack",
    "UnitCastingDuration", "UnitCastingInfo", "UnitChannelDuration", "UnitChannelInfo",
    "UnitClass", "UnitDetailedThreatSituation", "UnitExists", "UnitFactionGroup",
    "UnitFullName", "UnitGroupRolesAssigned", "UnitGUID", "UnitHealth", "UnitHealthMax",
    "UnitHealthPercent", "UnitIsAFK", "UnitIsConnected", "UnitIsDead", "UnitIsDeadOrGhost",
    "UnitIsFriend", "UnitIsGroupAssistant", "UnitIsGroupLeader", "UnitIsInMyGuild", "UnitIsPlayer",
    "UnitIsUnit", "UnitIsVisible",
    "UnitLevel", "UnitName", "UnitNameFromGUID", "UnitOnTaxi",
    "UnitShouldDisplaySpellTargetName", "UnitSpellTargetClass", "UnitSpellTargetName",
    "UnitThreatSituation", "UnitXP", "UnitXPMax", "UnmuteSoundFile", "UnregisterStateDriver",
    "UpdateAddOnMemoryUsage", "WHITE_FONT_COLOR", "wipe", "WorldFrame", "WorldMapFrame",
    "ZoneTextFrame",
    "ClickSendMailItemButton", "GetInboxHeaderInfo", "GetInboxItem", "GetInboxNumItems",
    "GetLooseMacroIcons", "GetLooseMacroItemIcons", "GetMacroIcons", "GetMacroItemIcons",
    "HasSendMailItem", "MailFrame", "SendMailFrame", "SendMailNameEditBox", "SendMailSubjectEditBox",
}

-- The offline tests run on plain Lua 5.1 and stub the game themselves.
files["Tools/regression/"] = {
    globals = { "strmatch" },
}

-- Baseline: warnings that were already in the code when this config was added, silenced
-- only where they are (file, warning code, name) so any new warning still fails. Remove
-- an entry once its warning is fixed; don't add new ones to get a check passing.
files["Core/NaowhForever_Core.lua"] = { ignore = { "432/key" } }
files["DungeonQuests/NaowhForever_DungeonQuests.lua"] = { ignore = { "421/id" } }
files["Professions/NaowhForever_Professions.lua"] = { ignore = { "431/rows", "421/bar", "431/W" } }
files["Professions/NaowhForever_RecipeFinder.lua"] = { ignore = { "431/list" } }
files["QoL/NaowhForever_QoL.lua"] = { ignore = { "211/DRUID_FORM_VALUES", "211/DRUID_FORM_ORDER" } }
files["SmartReminders/NaowhForever_Bosses.lua"] = { ignore = { "311/y", "431/set" } }
files["Tools/regression/test-buff-reminders.lua"] = { ignore = { "432/self" } }
