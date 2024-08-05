local myname, ns = ...
local myfullname = C_AddOns.GetAddOnMetadata(myname, "Title")

-- entire debugging setup:
-- MyInterrupt = ns
-- /script MyInterrupt:Announce(48792, 237525, "Icebound Fortitude")

-- event frame
local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(self, event, ...)
    self[event](self, ...)
end)
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")

-- announce frame
local announce = CreateFrame("Frame")
do
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

    function ns:Announce(spellID, iconID, name)
        if spellID and iconID and name then
            announce.Icon:SetTexture(iconID)
            announce.Label:SetText(name or UNKNOWN)
            announce:Show()

            ns:Log(spellID, iconID, name)
        end
    end
end

do
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
            ns:Announce(spellInfo.spellID, spellInfo.iconID, spellInfo.name)
        elseif bit.band(sourceFlags, COMBATLOG_OBJECT_AFFILIATION_MINE) ~= 0 then
            -- my pet
            ns:Announce(
                spellInfo.spellID,
                spellInfo.iconID,
                TEXT_MODE_A_STRING_VALUE_TYPE:format(spellInfo.name or UNKNOWN, sourceName or "?") -- "%s (%s)"
            )
        else
            -- Someone else, but we don't announce that
        end
    end
end

-- history window

local history = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
do
    history:SetPoint("CENTER")
    history:SetSize(180, 100)
    history:SetBackdrop({
        edgeFile = [[Interface\Buttons\WHITE8X8]],
        bgFile = [[Interface\Buttons\WHITE8X8]],
        edgeSize = 1,
    })
    history:EnableMouse(true)
    history:SetMovable(true)
    history:RegisterForDrag("LeftButton")
    history:SetClampedToScreen(true)
    history:SetScript("OnDragStart", history.StartMoving)
    history:SetScript("OnDragStop", history.StopMovingOrSizing)
    local title = history:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
    history.title = title
    title:SetJustifyH("CENTER")
    title:SetJustifyV("MIDDLE")
    title:SetPoint("TOPLEFT", 0, -4)
    title:SetPoint("TOPRIGHT", 0, -4)
    title:SetText(myfullname)

    local function LineTooltip(line)
        if not line.spellID then return end
        local anchor = (line:GetCenter() < (UIParent:GetWidth() / 2)) and "ANCHOR_RIGHT" or "ANCHOR_LEFT"
        GameTooltip:SetOwner(line, anchor, 0, -60)
        GameTooltip:SetSpellByID(line.spellID)
        GameTooltip:Show()
    end
    history.linePool = CreateFramePool("Frame", history, nil, function(pool, line)
        if not line.icon then
            line:SetHeight(20)
            line.icon = line:CreateTexture()
            line.icon:SetSize(18, 18)
            line.icon:SetPoint("LEFT", 2, 0)
            line.name = line:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            line.name:SetPoint("LEFT", line.icon, "RIGHT", 2, 0)
            line.name:SetPoint("RIGHT")
            line.name:SetJustifyH("LEFT")
            line.name:SetMaxLines(1)
            line:SetScript("OnEnter", LineTooltip)
            line:SetScript("OnLeave", GameTooltip_Hide)
            -- line:SetScript("OnMouseUp", Line_OnClick)
            line:EnableMouse(true)
            -- line:RegisterForClicks("AnyUp", "AnyDown")
        end
        line:Hide()
        line:ClearAllPoints()
    end)

    history:Hide()

    local log = {}
    local function refreshHistory()
        history.linePool:ReleaseAll()

        local lastLine = title
        for i, entry in ipairs(log) do
            if i <= 4 then
                local line = history.linePool:Acquire()
                line.spellID = entry.spellID
                line.icon:SetTexture(entry.iconID)
                line.name:SetText(entry.name)
                line:SetPoint("TOPLEFT", lastLine, "BOTTOMLEFT")
                line:SetPoint("TOPRIGHT", lastLine, "BOTTOMRIGHT")
                line:Show()
                lastLine = line
            end
        end

        if true or db.backdrop then
            history:SetBackdropColor(0, 0, 0, .5)
            history:SetBackdropBorderColor(0, 0, 0, .5)
        else
            history:SetBackdropColor(0, 0, 0, 0)
            history:SetBackdropBorderColor(0, 0, 0, 0)
        end

        history:Show()
    end

    function ns:Log(spellID, iconID, name)
        table.insert(log, {spellID=spellID, iconID=iconID, name=name})
        refreshHistory()
    end
    function frame:PLAYER_REGEN_DISABLED()
        table.wipe(log)
        refreshHistory()
    end

    refreshHistory()
end

