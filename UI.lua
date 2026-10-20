local _, WSK = ...

local TRACKER_NAME = "WeaponSkillsForeverTracker"
local CONFIG_NAME = "WeaponSkillsForeverConfig"
local SETTINGS_NAME = "WeaponSkillsForeverSettings"
local TITLE = "Weapon Skills Forever"
local LOCK_LABEL = "Lock the skill box position"
-- The gear panel's lock checkbox row, between the list and the pager.
local LOCK_ROW_HEIGHT = 28
local TRACKER_WIDTH = 220
local CONFIG_WIDTH = 300
local PAD = 10
local HEADER_HEIGHT = 28
-- The skill box header is taller than the panels' so its icon buttons have room.
local TRACKER_HEADER_HEIGHT = 32
local ROW_HEIGHT = 34
local BAR_HEIGHT = 14
local LIST_ROW_HEIGHT = 24
local LIST_ROWS = 12
local SETTINGS_ROWS = 10
local SETTINGS_LIST_WIDTH = 280
local OPACITY_SLIDER_WIDTH = 200
-- Settings page list border: the rounded tooltip edge at size 8 draws a line
-- about 2 pixels wide at UI scale 1.
local LIST_BORDER_PAD = 8
local LIST_BORDER = {
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 8,
}
local COMING_LATER = "Coming in a later version."
-- Atlases from Blizzard's Skills tab headers (pinned SkillsFrame.xml/.lua).
local HEADER_ATLAS = "common-button-list-collapseExpand"
local PLUS_ATLAS = "common-button-list-plus"
local MINUS_ATLAS = "common-button-list-minus"
-- Header icon buttons: a little larger than the title text.
local ICON_SIZE = 20
local ICON_GAP = 10
local GEAR_ICON = "Interface\\Icons\\INV_Misc_Gear_01"
-- Built-in icons, author-selected: a sword for weapons, a book for other skills.
local VIEW_ICONS = {
    weapons = "Interface\\Icons\\INV_Sword_04",
    other = "Interface\\Icons\\INV_Misc_Book_09",
}
local EMPTY_TEXT = {
    weapons = "No weapon skills tracked. Click the gear to choose some.",
    other = "No other skills tracked. Click the gear to choose some.",
}
local HIDDEN_TEXT = "The game hides skill values right now. They show again when it allows."
local HIGHLIGHT = "Interface\\Buttons\\ButtonHilight-Square"
local BUTTON_TEMPLATE = "SharedButtonSmallTemplate"
local GOLD = {1, 0.82, 0}
local BROWN = {0.28, 0.16, 0.07}
local CONFIG_ALPHA = 0.95
local BAR_BACKGROUND = {0, 0, 0, 0.5}
local BONUS_COLOR = "|cff20ff20"
local STATUS_COLORS = {
    low = {0.8, 0.1, 0.1},
    near = {0.9, 0.75, 0.1},
    capped = {0.15, 0.7, 0.2},
}
-- Rounded tooltip border tinted gold; both textures are built into the client.
local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = {left = 4, right = 4, top = 4, bottom = 4},
}
local DEFAULT_POINT = {point = "RIGHT", relativePoint = "RIGHT", x = -60, y = 120}

local tracker
local config
local settings
local settingsCategory
local rows = {}
local selectors = {}

local function StyleBox(frame, alpha)
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(BROWN[1], BROWN[2], BROWN[3], alpha)
    frame:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
end

local function Title(frame)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    title:SetText(TITLE)
    title:SetPoint("TOPLEFT", PAD, -PAD)
    return title
end

local function SetTooltip(widget, title, text)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(title)
        GameTooltip:AddLine(text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-- Tracker box ----------------------------------------------------------------

local function ApplyPosition()
    local position = WSK.db.position or DEFAULT_POINT
    tracker:ClearAllPoints()
    tracker:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
end

local function SavePosition()
    local point, _, relativePoint, x, y = tracker:GetPoint(1)
    WSK.db.position = {point = point, relativePoint = relativePoint, x = x, y = y}
end

local function CreateRow(index)
    local row = {}
    row.name = tracker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("TOPLEFT", PAD, -(TRACKER_HEADER_HEIGHT + (index - 1) * ROW_HEIGHT))
    row.name:SetJustifyH("LEFT")
    row.bar = CreateFrame("StatusBar", nil, tracker)
    row.bar:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
    row.bar:SetSize(TRACKER_WIDTH - 2 * PAD, BAR_HEIGHT)
    -- A plain color texture as the fill, tinted by status: no texture file needed.
    local fill = row.bar:CreateTexture(nil, "ARTWORK")
    fill:SetColorTexture(1, 1, 1, 1)
    row.bar:SetStatusBarTexture(fill)
    local background = row.bar:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(unpack(BAR_BACKGROUND))
    row.text = row.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("CENTER")
    -- The bar's alpha also covers its fill, background, and text.
    row.name:SetAlpha(WSK.db.contentAlpha)
    row.bar:SetAlpha(WSK.db.contentAlpha)
    rows[index] = row
    return row
end

local function ShowRow(row, shown)
    if shown then
        row.name:Show()
        row.bar:Show()
    else
        row.name:Hide()
        row.bar:Hide()
    end
end

local function BarText(skill)
    if skill.modifier > 0 then
        return string.format("%d %s(+%d)|r / %d", skill.rank, BONUS_COLOR, skill.modifier, skill.maxRank)
    end
    return string.format("%d / %d", skill.rank, skill.maxRank)
end

-- Applies the saved opacities: the box background, and the skill rows
-- (names, bars, and empty hint). The title and header icons stay opaque.
local function ApplyOpacity()
    tracker:SetBackdropColor(BROWN[1], BROWN[2], BROWN[3], WSK.db.backgroundAlpha)
    for _, row in ipairs(rows) do
        row.name:SetAlpha(WSK.db.contentAlpha)
        row.bar:SetAlpha(WSK.db.contentAlpha)
    end
    tracker.empty:SetAlpha(WSK.db.contentAlpha)
end

-- The box shows one type at a time, in Skills tab order.
local function RefreshTracker()
    ApplyOpacity()
    local view = WSK.GetView()
    local shown = 0
    local tracked = WSK.GetTracked()
    local skills = WSK.OrderSkills(tracked)
    for _, skill in ipairs(skills) do
        if WSK.SkillType(skill) == view then
            shown = shown + 1
            local row = rows[shown] or CreateRow(shown)
            row.name:SetText(skill.name)
            row.bar:SetMinMaxValues(0, skill.maxRank)
            row.bar:SetValue(math.min(skill.rank, skill.maxRank))
            row.bar:SetStatusBarColor(unpack(STATUS_COLORS[WSK.SkillStatus(skill.rank, skill.maxRank)]))
            row.text:SetText(BarText(skill))
            row.skillID = skill.id
            ShowRow(row, true)
        end
    end
    for index = shown + 1, #rows do
        rows[index].skillID = nil
        ShowRow(rows[index], false)
    end
    tracker.view:SetNormalTexture(VIEW_ICONS[view])
    if shown == 0 then
        -- Tracked skills the client hides (secret values, none seen plain
        -- this session) are kept, and the hint says so.
        local hidden = false
        if #skills < #tracked then
            for _, id in ipairs(tracked) do
                if not WSK.GetSkill(id) and not WSK.IsUnlearned(id) then
                    hidden = true
                end
            end
        end
        tracker.empty:SetText(hidden and HIDDEN_TEXT or EMPTY_TEXT[view])
        tracker.empty:Show()
        tracker:SetHeight(TRACKER_HEADER_HEIGHT + 2 * PAD + 14)
    else
        tracker.empty:Hide()
        tracker:SetHeight(TRACKER_HEADER_HEIGHT + shown * ROW_HEIGHT + PAD)
    end
end

local function CreateTracker()
    tracker = CreateFrame("Frame", TRACKER_NAME, UIParent, "BackdropTemplate")
    tracker:SetSize(TRACKER_WIDTH, TRACKER_HEADER_HEIGHT + PAD)
    tracker:SetFrameStrata("MEDIUM")
    tracker:SetClampedToScreen(true)
    tracker:SetMovable(true)
    tracker:EnableMouse(true)
    tracker:RegisterForDrag("LeftButton")
    -- With Dyre's Toolkit, the toolkit drags, snaps (to other Dyre's frames
    -- and the grid), and saves the box; without it, the box moves on its own.
    local toolkit = WSK.toolkit
    if toolkit then
        toolkit.RegisterMovable(tracker, function(position) WSK.db.position = position end)
    end
    tracker:SetScript("OnDragStart", function(self)
        if toolkit then
            toolkit.BeginDrag(self)
        elseif not WSK.db.locked then
            self:StartMoving()
        end
    end)
    tracker:SetScript("OnDragStop", function(self)
        if toolkit then
            toolkit.EndDrag(self)
            return
        end
        self:StopMovingOrSizing()
        SavePosition()
    end)
    StyleBox(tracker, WSK.db.backgroundAlpha)
    Title(tracker)

    tracker.gear = CreateFrame("Button", nil, tracker)
    tracker.gear:SetSize(ICON_SIZE, ICON_SIZE)
    tracker.gear:SetPoint("TOPRIGHT", -PAD + 2, -6)
    tracker.gear:SetNormalTexture(GEAR_ICON)
    tracker.gear:SetHighlightTexture(HIGHLIGHT, "ADD")
    tracker.gear:SetScript("OnClick", function()
        WSK.ToggleConfig()
    end)
    SetTooltip(tracker.gear, "WSK: Choose skills",
        string.format("Choose up to %d weapon skills and %d other skills to track. Drag the box to move it.",
            WSK.MAX_TRACKED, WSK.MAX_TRACKED))

    -- Icon toggle between weapon skills and other skills, left of the gear.
    tracker.view = CreateFrame("Button", nil, tracker)
    tracker.view:SetSize(ICON_SIZE, ICON_SIZE)
    tracker.view:SetPoint("RIGHT", tracker.gear, "LEFT", -ICON_GAP, 0)
    tracker.view:SetHighlightTexture(HIGHLIGHT, "ADD")
    tracker.view:SetScript("OnClick", function(self)
        WSK.ToggleView()
        local onEnter = self:GetScript("OnEnter")
        if GameTooltip:IsOwned(self) and onEnter then
            onEnter(self)
        end
    end)
    tracker.view:SetScript("OnEnter", function(self)
        local weapons = WSK.GetView() == WSK.WEAPONS
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(weapons and "WSK: Showing weapon skills" or "WSK: Showing other skills")
        GameTooltip:AddLine(weapons and "Click to show other skills, such as professions."
            or "Click to show weapon skills.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    tracker.view:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    tracker.empty = tracker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tracker.empty:SetPoint("TOPLEFT", PAD, -TRACKER_HEADER_HEIGHT)
    tracker.empty:SetWidth(TRACKER_WIDTH - 2 * PAD)
    tracker.empty:SetJustifyH("LEFT")
    tracker.empty:SetAlpha(WSK.db.contentAlpha)

    ApplyPosition()
    if WSK.db.shown then
        tracker:Show()
    else
        tracker:Hide()
    end
end

-- Skill selector -------------------------------------------------------------
-- One implementation serves both the gear panel and the AddOn settings page.
-- Each selector pages its own rows; all of them re-render on skill changes.

local function RenderSelector(selector)
    local entries = selector.entries
    local pageCount = math.max(1, math.ceil(#entries / selector.rowCount))
    selector.page = math.min(selector.page, pageCount)
    local counts = {[WSK.WEAPONS] = WSK.CountTracked(WSK.WEAPONS), [WSK.OTHER] = WSK.CountTracked(WSK.OTHER)}
    for index, row in ipairs(selector.rows) do
        local entry = entries[(selector.page - 1) * selector.rowCount + index]
        row.skillID = nil
        row.header.index = nil
        row.header.collapsed = nil
        row.header:Hide()
        if entry and entry.kind == "header" then
            row.check:Hide()
            row.label:Hide()
            row.header.name:SetText(entry.name)
            -- The same +/- atlases Blizzard's Skills tab uses for its headers.
            if WSK.CanToggleHeaders() then
                row.header.index = entry.index
                row.header.collapsed = entry.collapsed
                row.header.stateIcon:SetAtlas(entry.collapsed and PLUS_ATLAS or MINUS_ATLAS, true)
                row.header.stateIcon:Show()
                row.header:Enable()
            else
                row.header.stateIcon:Hide()
                row.header:Disable()
            end
            row.header:Show()
        elseif entry then
            local tracked = WSK.IsTracked(entry.skill.id)
            row.skillID = entry.skill.id
            row.check:SetChecked(tracked)
            row.check:SetEnabled(tracked or counts[WSK.SkillType(entry.skill)] < WSK.MAX_TRACKED)
            row.check:Show()
            row.label:SetTextColor(1, 1, 1)
            row.label:SetText(string.format("%s  (%d / %d)", entry.skill.name,
                entry.skill.rank, entry.skill.maxRank))
            row.label:Show()
        else
            row.check:Hide()
            row.label:Hide()
        end
    end
    selector.count:SetText(string.format("Weapons %d of %d, other skills %d of %d", counts[WSK.WEAPONS],
        WSK.MAX_TRACKED, counts[WSK.OTHER], WSK.MAX_TRACKED))
    selector.pageText:SetText(selector.page .. " / " .. pageCount)
    selector.previous:SetEnabled(selector.page > 1)
    selector.next:SetEnabled(selector.page < pageCount)
end

local function RebuildSelector(selector)
    selector.entries = WSK.ListSetupEntries()
    RenderSelector(selector)
end

local function CreateSelectorRow(selector, index)
    local parent, left = selector.parent, selector.left
    local row = {}
    local offset = selector.top - (index - 1) * LIST_ROW_HEIGHT
    row.check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    row.check:SetSize(22, 22)
    row.check:SetPoint("TOPLEFT", left, offset)
    row.check:SetScript("OnClick", function(self)
        local ok, message = WSK.SetTracked(row.skillID, self:GetChecked())
        if not ok then
            WSK.Report(message)
        end
        RenderSelector(selector)
    end)
    row.label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("TOPLEFT", left + 26, offset - 5)
    row.label:SetJustifyH("LEFT")

    -- A group header mirrors the Skills tab: the whole row is the button, with
    -- the list background, a hover highlight, and a +/- state icon on the right.
    local header = CreateFrame("Button", nil, parent)
    header:SetSize(selector.width, LIST_ROW_HEIGHT - 2)
    header:SetPoint("TOPLEFT", left, offset)
    local background = header:CreateTexture(nil, "BACKGROUND")
    background:SetAtlas(HEADER_ATLAS)
    background:SetAllPoints()
    local highlight = header:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAtlas(HEADER_ATLAS)
    highlight:SetAllPoints()
    highlight:SetBlendMode("ADD")
    highlight:SetAlpha(0.3)
    header.stateIcon = header:CreateTexture(nil, "BORDER")
    header.stateIcon:SetPoint("RIGHT", -8, -1)
    header.name = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLeft")
    header.name:SetPoint("LEFT", 10, 0)
    header:SetScript("OnClick", function(self)
        if not self.index then
            return
        end
        if self.collapsed then
            WSK.ExpandHeader(self.index)
        else
            WSK.CollapseHeader(self.index)
        end
        RebuildSelector(selector)
    end)
    header:SetScript("OnEnter", function(self)
        if not self.index then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(self.collapsed and "WSK: Expand group" or "WSK: Collapse group")
        GameTooltip:AddLine("Same as clicking this group on the Skills tab.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    header:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    header:Hide()
    row.header = header
    selector.rows[index] = row
end

-- Builds a selector in parent: a count line at countTop, rowCount rows below
-- it, and paging controls at pagerTop. Offsets are from the parent's top left.
local function CreateSelector(parent, left, countTop, width, rowCount, pagerTop)
    local selector = {parent = parent, left = left, width = width, rowCount = rowCount,
        top = countTop - 20, page = 1, entries = {}, rows = {}}
    selector.count = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    selector.count:SetPoint("TOPLEFT", left, countTop)
    for index = 1, rowCount do
        CreateSelectorRow(selector, index)
    end
    selector.previous = CreateFrame("Button", nil, parent, BUTTON_TEMPLATE)
    selector.previous:SetSize(36, 22)
    selector.previous:SetText("<")
    selector.previous:SetPoint("TOPLEFT", left, pagerTop)
    selector.previous:SetScript("OnClick", function()
        selector.page = math.max(1, selector.page - 1)
        RenderSelector(selector)
    end)
    selector.next = CreateFrame("Button", nil, parent, BUTTON_TEMPLATE)
    selector.next:SetSize(36, 22)
    selector.next:SetText(">")
    selector.next:SetPoint("TOPLEFT", left + width - 36, pagerTop)
    selector.next:SetScript("OnClick", function()
        selector.page = selector.page + 1
        RenderSelector(selector)
    end)
    selector.pageText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    selector.pageText:SetPoint("TOP", parent, "TOPLEFT", left + width / 2, pagerTop - 4)
    selectors[#selectors + 1] = selector
    return selector
end

-- Gear panel -----------------------------------------------------------------

local function CreateConfig()
    local listTop = -(HEADER_HEIGHT + 22)
    -- With Dyre's Toolkit, the toolkit's own switch locks every Dyre's
    -- AddOn, so the panel has no lock checkbox and no row for it.
    local lockRow = WSK.toolkit and 0 or LOCK_ROW_HEIGHT
    local pagerTop = listTop - LIST_ROWS * LIST_ROW_HEIGHT - 6 - lockRow
    config = CreateFrame("Frame", CONFIG_NAME, UIParent, "BackdropTemplate")
    config:SetSize(CONFIG_WIDTH, -pagerTop + 22 + PAD)
    config:SetPoint("CENTER")
    config:SetFrameStrata("DIALOG")
    config:SetClampedToScreen(true)
    config:EnableMouse(true)
    config:Hide()
    StyleBox(config, CONFIG_ALPHA)
    Title(config)
    table.insert(UISpecialFrames, CONFIG_NAME)

    local close = CreateFrame("Button", nil, config, BUTTON_TEMPLATE)
    close:SetSize(28, 22)
    close:SetText("X")
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() config:Hide() end)

    config.selector = CreateSelector(config, PAD, -HEADER_HEIGHT, CONFIG_WIDTH - 2 * PAD,
        LIST_ROWS, pagerTop)
    config.count = config.selector.count
    config.pageText = config.selector.pageText
    config.previous = config.selector.previous
    config.next = config.selector.next

    if not WSK.toolkit then
        config.lock = CreateFrame("CheckButton", nil, config, "UICheckButtonTemplate")
        config.lock:SetSize(22, 22)
        config.lock:SetPoint("TOPLEFT", PAD, pagerTop + LOCK_ROW_HEIGHT)
        config.lock:SetScript("OnClick", function(self)
            WSK.SetLocked(self:GetChecked() and true or false)
        end)
        local lockLabel = config:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lockLabel:SetPoint("LEFT", config.lock, "RIGHT", 4, 0)
        lockLabel:SetText(LOCK_LABEL)
    end

    config:SetScript("OnShow", function()
        config.selector.page = 1
        if config.lock then
            config.lock:SetChecked(WSK.db.locked)
        end
        RebuildSelector(config.selector)
    end)
    config:SetScript("OnHide", function()
        GameTooltip:Hide()
    end)
end

-- AddOn settings page ----------------------------------------------------------
-- A canvas category in Blizzard's Settings panel (Options > AddOns). Layout and
-- theme are shown disabled until those features exist; nothing is saved for them.

local function SettingsCheck(parent, x, y, text)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", x, y)
    check.text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    check.text:SetPoint("LEFT", check, "RIGHT", 4, 0)
    check.text:SetText(text)
    return check
end

local function SettingsHeading(parent, x, y, text)
    local heading = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", x, y)
    heading:SetText(text)
    return heading
end

local function DisabledChoice(parent, x, y, text, checked)
    local check = SettingsCheck(parent, x, y, text)
    check:SetChecked(checked)
    check:Disable()
    check.text:SetTextColor(0.5, 0.5, 0.5)
    return check
end

local function OpacityLabel(slider)
    return string.format("%s opacity: %d%%", slider.labelText, math.floor(WSK.db[slider.key] * 100 + 0.5))
end

-- Sets each slider and label from saved values. The updating flag stops the
-- programmatic SetValue from being treated as a user change.
local function UpdateOpacitySliders()
    for _, slider in ipairs(settings.opacity) do
        slider.updating = true
        slider:SetValue(WSK.db[slider.key])
        slider.updating = false
        slider.label:SetText(OpacityLabel(slider))
    end
end

-- A labelled MinimalSliderTemplate slider (Blizzard's settings slider) for one
-- opacity setting.
local function OpacitySlider(parent, x, y, key, labelText)
    local limits = WSK.OPACITY[key]
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", x, y)
    local slider = CreateFrame("Slider", nil, parent, "MinimalSliderTemplate")
    slider:SetPoint("TOPLEFT", x, y - 20)
    slider:SetWidth(OPACITY_SLIDER_WIDTH)
    slider:SetMinMaxValues(limits.min, limits.max)
    slider:SetValueStep(WSK.OPACITY_STEP)
    slider:SetObeyStepOnDrag(true)
    slider.key, slider.label, slider.labelText = key, label, labelText
    slider:SetScript("OnValueChanged", function(self, value)
        if not self.updating then
            WSK.SetOpacity(key, value)
        end
    end)
    return slider
end

local function RefreshSettings()
    if not settings then
        return
    end
    settings.shown:SetChecked(WSK.db.shown)
    if settings.locked then
        settings.locked:SetChecked(WSK.db.locked)
    end
    UpdateOpacitySliders()
    RebuildSelector(settings.selector)
end

local function CreateSettings()
    if type(Settings) ~= "table" or type(Settings.RegisterCanvasLayoutCategory) ~= "function"
        or type(Settings.RegisterAddOnCategory) ~= "function" then
        return
    end
    settings = CreateFrame("Frame", SETTINGS_NAME)
    local left, column = 16, 330
    local title = settings:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
    title:SetPoint("TOPLEFT", left, -16)
    title:SetText(TITLE)

    SettingsHeading(settings, left, -56, "Display")
    settings.shown = SettingsCheck(settings, left, -80, "Show the skill box")
    settings.shown:SetScript("OnClick", function(self)
        if self:GetChecked() then
            WSK.ShowTracker()
        else
            WSK.HideTracker(true)
        end
    end)
    -- With Dyre's Toolkit, its "Unlock frames" switch locks every Dyre's
    -- AddOn, so this page has no lock checkbox and the reset button moves up.
    local resetTop = -112
    if not WSK.toolkit then
        settings.locked = SettingsCheck(settings, left, -108, LOCK_LABEL)
        settings.locked:SetScript("OnClick", function(self)
            WSK.SetLocked(self:GetChecked() and true or false)
        end)
        resetTop = -140
    end
    settings.reset = CreateFrame("Button", nil, settings, BUTTON_TEMPLATE)
    settings.reset:SetSize(140, 22)
    settings.reset:SetText("Reset position")
    settings.reset:SetPoint("TOPLEFT", left + 4, resetTop)
    settings.reset:SetScript("OnClick", function()
        WSK.ResetTrackerPosition()
    end)

    SettingsHeading(settings, left, -184, "Tracked skills")
    local listTop = -210
    local pagerTop = listTop - 20 - SETTINGS_ROWS * LIST_ROW_HEIGHT - 8
    local listBottom = pagerTop - 22
    -- A thin rounded gold border around the list; drawn first, with no fill,
    -- so it sits behind the selector's controls.
    settings.skillsBorder = CreateFrame("Frame", nil, settings, "BackdropTemplate")
    settings.skillsBorder:SetPoint("TOPLEFT", left - LIST_BORDER_PAD, listTop + LIST_BORDER_PAD)
    settings.skillsBorder:SetSize(SETTINGS_LIST_WIDTH + 2 * LIST_BORDER_PAD,
        listTop - listBottom + 2 * LIST_BORDER_PAD)
    settings.skillsBorder:SetBackdrop(LIST_BORDER)
    settings.skillsBorder:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
    settings.selector = CreateSelector(settings, left, listTop, SETTINGS_LIST_WIDTH, SETTINGS_ROWS, pagerTop)

    SettingsHeading(settings, column, -56, "Layout")
    settings.vertical = DisabledChoice(settings, column, -80, "Vertical", true)
    settings.horizontal = DisabledChoice(settings, column, -108, "Horizontal", false)
    local layoutNote = settings:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    layoutNote:SetPoint("TOPLEFT", column + 4, -138)
    layoutNote:SetText(COMING_LATER)

    SettingsHeading(settings, column, -184, "Theme")
    settings.theme = DisabledChoice(settings, column, -208, "Classic gold", true)
    local themeNote = settings:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    themeNote:SetPoint("TOPLEFT", column + 4, -238)
    themeNote:SetText("More themes are planned. " .. COMING_LATER)

    SettingsHeading(settings, column, -280, "Opacity")
    settings.opacity = {
        OpacitySlider(settings, column, -306, "backgroundAlpha", "Background"),
        OpacitySlider(settings, column, -360, "contentAlpha", "Skill rows"),
    }
    UpdateOpacitySliders()

    -- Called by the Settings panel each time this category is shown.
    settings.OnRefresh = RefreshSettings
    -- Called by the Settings panel's Defaults button: opacities only, so tracked
    -- skills and the box position are kept.
    settings.OnDefault = WSK.ResetOpacity
    settings:SetScript("OnShow", RefreshSettings)
    -- Under Dyre's Toolkit's "Dyre's AddOns" home when it is there.
    local home = WSK.toolkit and WSK.toolkit.SettingsCategory()
    if home and type(Settings.RegisterCanvasLayoutSubcategory) == "function" then
        settingsCategory = Settings.RegisterCanvasLayoutSubcategory(home, settings, TITLE)
    else
        settingsCategory = Settings.RegisterCanvasLayoutCategory(settings, TITLE)
        Settings.RegisterAddOnCategory(settingsCategory)
    end
end

-- Namespace API used by Core and Commands -----------------------------------

function WSK.InitializeUI()
    if tracker then
        return
    end
    CreateTracker()
    CreateConfig()
    CreateSettings()
    RefreshTracker()
end

function WSK.RefreshUI()
    if not tracker then
        return
    end
    RefreshTracker()
    if config:IsShown() and config.lock then
        config.lock:SetChecked(WSK.db.locked)
    end
    if settings then
        settings.shown:SetChecked(WSK.db.shown)
        if settings.locked then
            settings.locked:SetChecked(WSK.db.locked)
        end
        UpdateOpacitySliders()
    end
    for _, selector in ipairs(selectors) do
        if selector.parent:IsVisible() then
            RebuildSelector(selector)
        end
    end
end

function WSK.ToggleConfig()
    if config:IsShown() then
        config:Hide()
    else
        config:Show()
    end
end

-- Opens Options > AddOns > Weapon Skills Forever, when the client supports it.
function WSK.OpenSettings()
    if not settingsCategory or type(Settings.OpenToCategory) ~= "function" then
        WSK.Report("The AddOn settings page is unavailable on this client. Use /wsk config.")
        return
    end
    if WSK.toolkit then
        -- The toolkit opens nothing in combat, and says so.
        WSK.toolkit.OpenSettings(settingsCategory)
        return
    end
    Settings.OpenToCategory(settingsCategory:GetID())
end

function WSK.ShowTracker()
    WSK.db.shown = true
    tracker:Show()
    WSK.RefreshUI()
end

-- quiet: from the settings checkbox, where the hint about /wsk is not needed.
function WSK.HideTracker(quiet)
    WSK.db.shown = false
    tracker:Hide()
    WSK.RefreshUI()
    if not quiet then
        WSK.Report("Skill box hidden. Type /wsk to show it again.")
    end
end

function WSK.ToggleTracker()
    if tracker:IsShown() then
        WSK.HideTracker()
    else
        WSK.ShowTracker()
    end
end

-- The toolkit's lock callback: quiet, the toolkit says one line for all.
function WSK.ApplyLocked(locked)
    WSK.db.locked = locked == true
    WSK.RefreshUI()
end

-- From the settings and config checkboxes: with the toolkit, every Dyre's
-- AddOn's frames lock or unlock together.
function WSK.SetLocked(locked)
    if WSK.toolkit then
        WSK.toolkit.SetLocked(locked)
        return
    end
    WSK.ApplyLocked(locked)
end

function WSK.LockTracker()
    if WSK.toolkit then
        WSK.toolkit.Lock()
        return
    end
    WSK.ApplyLocked(true)
    WSK.Report("Skill box locked.")
end

function WSK.UnlockTracker()
    if WSK.toolkit then
        WSK.toolkit.Unlock()
        return
    end
    WSK.ApplyLocked(false)
    WSK.Report("Skill box unlocked. Drag it to move it.")
end

function WSK.ResetTrackerPosition()
    WSK.db.position = nil
    ApplyPosition()
    WSK.Report("Skill box moved back to its default position.")
end
