local myname, ns = ...

-- event frame
local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(self, event, ...)
    self[event](self, ...)
end)
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

-- announce frame
local announce = CreateFrame("Frame")
announce:SetSize(30, 30)
announce:SetPoint("TOP", RaidWarningFrame, "BOTTOM", 0, -20)
announce.Icon = announce:CreateTexture(nil, "ARTWORK")
announce.Icon:SetAllPoints()
announce.Interrupted = announce:CreateFontString(nil, "OVERLAY", "TextStatusBarTextLarge")
announce.Interrupted:SetText(ACTION_SPELL_INTERRUPT)
announce.Interrupted:SetPoint("BOTTOM", announce, "TOP")
announce.Label = announce:CreateFontString(nil, "OVERLAY", "TextStatusBarTextLarge")
announce.Label:SetPoint("TOP", announce, "BOTTOM")
announce.FadeIn = announce:CreateAnimationGroup()
local fadeIn = announce.FadeIn:CreateAnimation("Alpha")
announce.FadeIn:SetToFinalAlpha(true)
fadeIn:SetFromAlpha(0)
fadeIn:SetToAlpha(1)
fadeIn:SetDuration(0.3)
fadeIn:SetSmoothing("IN")
announce.FadeOut = announce:CreateAnimationGroup()
announce.FadeOut:SetToFinalAlpha(true)
local fadeOut = announce.FadeOut:CreateAnimation("Alpha")
fadeOut:SetFromAlpha(1)
fadeOut:SetToAlpha(0)
fadeOut:SetDuration(0.3)
fadeOut:SetSmoothing("OUT")
announce.FadeOut:SetScript("OnFinished", function(self)
    announce:Hide()
end)
local function fadeAnnounce() announce.FadeOut:Play() end
announce:SetScript("OnShow", function(self)
    self.FadeIn:Stop()
    self.FadeOut:Stop()
    self:SetAlpha(0)
    C_Timer.After(2, fadeAnnounce)
    self.FadeIn:Play()
end)
announce:Hide()

-- entire debugging setup:
-- MyAnnounce = announce
-- announce.Icon:SetTexture(237525)
-- announce.Label:SetText("Icebound Fortitude")
-- /script MyAnnounce:Show()

local playerName = UnitName("player")
local lastInterruptTime, lastSpellID
function frame:COMBAT_LOG_EVENT_UNFILTERED()
    local timeStamp, subEvent, _, _, sourceName, sourceFlags, _, _, destName, _, destRaidFlags, spellID, _, _, extraSpellID = CombatLogGetCurrentEventInfo()

    if subEvent ~= "SPELL_INTERRUPT" then return end

    -- avoid spam on AOE interrupts
    if timeStamp == lastInterruptTime and spellID == lastSpellID then return end

    -- Update last time and ID
    lastInterruptTime, lastSpellID = timeStamp, spellID

    -- spellID is the spell you used to interrupt, extraSpellID should be the spell you interrupted
    local spellInfo = C_Spell.GetSpellInfo(extraSpellID)
    -- local spellName, _, spellTexture = GetSpellInfo(extraSpellID)
    if sourceName == playerName then
        -- me
        announce.Icon:SetTexture(spellInfo.iconID)
        announce.Label:SetText(spellInfo.name or UNKNOWN)
        announce:Show()
    elseif bit.band(sourceFlags, COMBATLOG_OBJECT_AFFILIATION_MINE) ~= 0 then
        -- my pet
        announce.Icon:SetTexture(spellInfo.iconID)
        announce.Label:SetText(TEXT_MODE_A_STRING_VALUE_TYPE:format(spellInfo.name or UNKNOWN, sourceName or "?")) -- "%s (%s)"
        announce:Show()
    else
        -- Someone else, but we don't announce that
    end
end


