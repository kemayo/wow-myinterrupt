local myname, ns = ...
local myfullname = C_AddOns.GetAddOnMetadata(myname, "Title")
local debuggable = C_AddOns.GetAddOnMetadata(myname, "Version") == '@'..'project-version@'

local db

-- entire debugging setup:
-- MyInterrupt = ns
-- /script MyInterrupt:Announce(48792, 237525, "Icebound Fortitude")

-- event frame
local f = CreateFrame('Frame')
f:SetScript("OnEvent", function(_, event, ...)
    ns[ns.events[event]](ns, event, ...)
end)
f:Hide()
ns.events = {}
function ns:RegisterEvent(event, method)
    self.events[event] = method or event
    f:RegisterEvent(event)
end
function ns:UnregisterEvent(...) for i=1,select("#", ...) do f:UnregisterEvent((select(i, ...))) end end

local function setDefaults(options, defaults)
    setmetatable(options, { __index = function(t, k)
        if type(defaults[k]) == "table" then
            t[k] = setDefaults({}, defaults[k])
            return t[k]
        end
        return defaults[k]
    end, })
    -- and add defaults to existing tables
    for k, v in pairs(options) do
        if defaults[k] and type(v) == "table" then
            setDefaults(v, defaults[k])
        end
    end
    return options
end

function ns:ADDON_LOADED(event, addon)
    if addon == myname then
        _G[myname.."DB"] = setDefaults(_G[myname.."DB"] or {}, {
            backdrop = true, -- show a backdrop on the frame
            empty = true, -- show when empty
            announce = true,
            log = true,
            clearlog_entercombat = true,
            clearlog_leavecombat = false,
        })
        db = _G[myname.."DB"]
        self:UnregisterEvent("ADDON_LOADED")

        ns:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        ns:RegisterEvent("PLAYER_REGEN_DISABLED")
        ns:RegisterEvent("PLAYER_REGEN_ENABLED")

        ns:RefreshHistory()
    end
end
ns:RegisterEvent("ADDON_LOADED")

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
            if db.announce then
                announce.Icon:SetTexture(iconID)
                announce.Label:SetText(name or UNKNOWN)
                announce:Show()
            end

            ns:Log(spellID, iconID, name)
        end
    end
end

do
    local playerName = UnitName("player")
    local lastInterruptTime, lastSpellID
    function ns:COMBAT_LOG_EVENT_UNFILTERED()
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

local history = CreateFrame("Frame", "MyInterruptLogFrame", UIParent, "BackdropTemplate")
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
    history:SetScript("OnMouseUp", function(w, button)
        if button == "RightButton" then
            return ns:ShowConfigMenu(w)
        end
        if debuggable and button == "MiddleButton" then
            ns:Announce(unpack(GetRandomTableValue{
                {48792, 237525, "Icebound Fortitude"},
                {50977, 135766, "Death Gate"},
            }))
        end
    end)
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
            -- line:EnableMouse(true)
            -- line:RegisterForClicks("AnyUp", "AnyDown")
        end
        line:Hide()
        line:ClearAllPoints()
    end)

    history:Hide()

    local log = {}
    function ns:RefreshHistory()
        history.linePool:ReleaseAll()

        if not db.log then return history:Hide() end

        if #log == 0 and not db.empty then return history:Hide() end

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

                if not InCombatLockdown() then
                    -- this is protected, annoyingly
                    line:SetPropagateMouseClicks(true)
                end
            end
        end

        if db.backdrop then
            history:SetBackdropColor(0, 0, 0, .33)
            history:SetBackdropBorderColor(0, 0, 0, .5)
        else
            history:SetBackdropColor(0, 0, 0, 0)
            history:SetBackdropBorderColor(0, 0, 0, 0)
        end

        history:Show()
    end

    function ns:Log(spellID, iconID, name)
        table.insert(log, 1, {spellID=spellID, iconID=iconID, name=name})
        self:RefreshHistory()
    end
    function ns:ClearLog()
        table.wipe(log)
        self:RefreshHistory()
    end

    function ns:PLAYER_REGEN_DISABLED()
        if db.clear_entercombat then
            self:ClearLog()
        end
    end
    function ns:PLAYER_REGEN_ENABLED()
        if db.clear_leavecombat then
            self:ClearLog()
        end
    end
end

do
    local menuFrame, menuData
    local isChecked = function(key) return db[key] end
    local toggleChecked = function(key)
        db[key] = not db[key]
        ns:RefreshHistory()
    end
    function ns:ShowConfigMenu(frame)
        MenuUtil.CreateContextMenu(frame, function(owner, rootDescription)
            rootDescription:SetTag("MENU_MYINTERRUPT_CONFIG")
            rootDescription:CreateTitle(myfullname)
            rootDescription:CreateCheckbox("Announce interrupts", isChecked, toggleChecked, "announce")
            rootDescription:CreateCheckbox("Show log of interrupts", isChecked, toggleChecked, "log")
            rootDescription:CreateCheckbox("Show a backdrop in the frame", isChecked, toggleChecked, "backdrop")
            rootDescription:CreateCheckbox("Show while empty", isChecked, toggleChecked, "empty")
            local clear = rootDescription:CreateButton("Clear log...")
            clear:CreateCheckbox("When entering combat", isChecked, toggleChecked, "clearlog_entercombat")
            clear:CreateCheckbox("When leaving combat", isChecked, toggleChecked, "clearlog_leavecombat")
            clear:CreateButton("Right now!", function() ns:ClearLog() end)
        end)
    end
end

_G["SLASH_".. myname:upper().."1"] = "/myinterrupt"
SlashCmdList[myname:upper()] = function(msg)
    msg = msg:trim()
    if msg == "" then
        ns:ShowConfigMenu()
    end
end
