local addonName, WSK = ...

local DEFAULT_TITLE = "Weapon Skills Forever"
local READY_MESSAGE = "  Ready. Click the gear on the skill box, or type /wsk config, to choose skills."
local UNAVAILABLE = "Weapon Skills Forever is unavailable. Check the WSK login message."
-- Dyre's Toolkit (contract 1), when installed: one layout mode, snapping
-- across Dyre's AddOns and to the grid, and the "Dyre's AddOns" settings home.
local TOOLKIT_CONTRACT = 1
local INSTALL_TOOLKIT = "Install Dyre's Toolkit from CurseForge for one layout mode and settings home for all "
    .. "Dyre's AddOns."
WSK.available = false

function WSK.Report(message)
    DEFAULT_CHAT_FRAME:AddMessage("WSK: " .. tostring(message))
end

-- Reads TOC fields so the banner follows the packaged version; never gates operations.
local function Metadata(field)
    if type(C_AddOns) ~= "table" or type(C_AddOns.GetAddOnMetadata) ~= "function" then
        return nil
    end
    local value = C_AddOns.GetAddOnMetadata(addonName, field)
    if type(value) == "string" and value:find("%S") then
        return value
    end
end

local function ReportLoaded(available)
    local banner = Metadata("Title") or DEFAULT_TITLE
    local version, author = Metadata("Version"), Metadata("Author")
    if version then
        banner = banner .. " " .. version
    end
    if author then
        banner = banner .. " by " .. author
    end
    WSK.Report(banner)
    if available then
        WSK.Report(READY_MESSAGE)
    end
end

-- Functions other runtime files must define. A mixed install of old and new
-- files otherwise fails silently, because the client hides Lua errors by default.
local REQUIRED_NAMESPACE = {
    "ParseCommand", "HandleCommand", "CheckCapabilities", "GetSkill",
    "ListTrackableSkills", "ListSetupEntries", "ExpandHeader", "CollapseHeader", "SkillStatus",
    "SkillType", "OrderSkills", "IsSecret", "Describe", "CountSkillLines", "ReadSkillLine", "IsUnlearned",
    "InitializeUI", "RefreshUI", "OpenSettings", "ApplyLocked", "SetLocked",
}

local function CheckInstalledFiles()
    for _, name in ipairs(REQUIRED_NAMESPACE) do
        if type(WSK[name]) ~= "function" then
            return false, "AddOn files are from different versions (missing " .. name
                .. "). Reinstall every Weapon Skills Forever file, then restart the client."
        end
    end
    return true
end

-- Per-character settings in WeaponSkillsForeverDB, repaired on load so a
-- damaged or older table can never break the UI.
local function IsWholeNumber(value)
    return type(value) == "number" and value == math.floor(value)
end

local function SanitizePosition(position)
    if type(position) ~= "table" or type(position.point) ~= "string"
        or type(position.relativePoint) ~= "string"
        or type(position.x) ~= "number" or type(position.y) ~= "number" then
        return nil
    end
    return {point = position.point, relativePoint = position.relativePoint,
        x = position.x, y = position.y}
end

function WSK.SanitizeDB(db)
    if type(db) ~= "table" then
        db = {}
    end
    -- Skill types are unknown until skill data arrives, so the load-time cap
    -- covers both types; SetTracked enforces the limit per type.
    local tracked, seen = {}, {}
    if type(db.tracked) == "table" then
        for _, id in ipairs(db.tracked) do
            if IsWholeNumber(id) and id > 0 and not seen[id] and #tracked < 2 * WSK.MAX_TRACKED then
                tracked[#tracked + 1] = id
                seen[id] = true
            end
        end
    end
    db.tracked = tracked
    db.shown = db.shown ~= false
    db.locked = db.locked == true
    db.position = SanitizePosition(db.position)
    db.view = db.view == WSK.OTHER and WSK.OTHER or WSK.WEAPONS
    for key in pairs(WSK.OPACITY) do
        db[key] = WSK.ClampOpacity(key, db[key])
    end
    return db
end

-- Opacity settings: saved key -> default, minimum, and maximum, from 0 to 1.
-- Skill rows keep a minimum so they can never disappear completely.
WSK.OPACITY = {
    backgroundAlpha = {default = 0.5, min = 0, max = 1},
    contentAlpha = {default = 0.9, min = 0.2, max = 1},
}
WSK.OPACITY_STEP = 0.05

-- Rounds to the slider step and clamps to the range; anything else becomes the default.
function WSK.ClampOpacity(key, value)
    local limits = WSK.OPACITY[key]
    if type(value) ~= "number" or value ~= value then
        return limits.default
    end
    value = math.floor(value / WSK.OPACITY_STEP + 0.5) * WSK.OPACITY_STEP
    return math.max(limits.min, math.min(limits.max, value))
end

function WSK.SetOpacity(key, value)
    WSK.db[key] = WSK.ClampOpacity(key, value)
    WSK.RefreshUI()
end

-- Restores the default opacities only; tracked skills and position are kept.
function WSK.ResetOpacity()
    for key, limits in pairs(WSK.OPACITY) do
        WSK.db[key] = limits.default
    end
    WSK.RefreshUI()
end

-- Number of tracked, learned skills of one type.
function WSK.CountTracked(skillType)
    local count = 0
    for _, id in ipairs(WSK.db.tracked) do
        local skill = WSK.GetSkill(id)
        if skill and WSK.SkillType(skill) == skillType then
            count = count + 1
        end
    end
    return count
end

-- The skill box shows one type at a time; the choice is saved per character.
function WSK.GetView()
    return WSK.db.view
end

function WSK.SetView(view)
    WSK.db.view = view == WSK.OTHER and WSK.OTHER or WSK.WEAPONS
    WSK.RefreshUI()
end

function WSK.ToggleView()
    WSK.SetView(WSK.db.view == WSK.WEAPONS and WSK.OTHER or WSK.WEAPONS)
end

function WSK.GetTracked()
    local tracked = {}
    for index, id in ipairs(WSK.db.tracked) do
        tracked[index] = id
    end
    return tracked
end

function WSK.IsTracked(id)
    for _, tracked in ipairs(WSK.db.tracked) do
        if tracked == id then
            return true
        end
    end
    return false
end

-- Returns true, or false plus a message for expected failures.
function WSK.SetTracked(id, enabled)
    if not WSK.available then
        return false, UNAVAILABLE
    end
    local tracked = WSK.db.tracked
    if enabled then
        if WSK.IsTracked(id) then
            return true
        end
        local skill = WSK.GetSkill(id)
        if not skill then
            return false, "That skill is not learned or has no ranks to track."
        end
        if WSK.CountTracked(WSK.SkillType(skill)) >= WSK.MAX_TRACKED then
            local kind = WSK.SkillType(skill) == WSK.WEAPONS and "weapon" or "non-weapon"
            return false, string.format("You can track up to %d %s skills. Untrack one first.",
                WSK.MAX_TRACKED, kind)
        end
        tracked[#tracked + 1] = id
    else
        for index = #tracked, 1, -1 do
            if tracked[index] == id then
                table.remove(tracked, index)
            end
        end
    end
    WSK.RefreshUI()
    return true
end

-- Drops skills the character no longer has (an abandoned profession, for
-- example). Skipped while the client reports no skill lines at all, which can
-- happen before skill data arrives.
-- Secret values (and a secret line count) count as unknown, never as unlearned.
local function PruneUnlearned()
    if WSK.CountSkillLines() == 0 then
        return
    end
    local tracked = WSK.db.tracked
    for index = #tracked, 1, -1 do
        if WSK.IsUnlearned(tracked[index]) then
            table.remove(tracked, index)
        end
    end
end

-- /wsk debug_skills: every line the client reports, including whether collapsed
-- headers hide skills and which category and parent each line has. Raw values
-- are printed, a secret one as <secret>; decisions use the plain copy.
function WSK.ReportSkillDebug()
    local lines, headers, collapsed, children = WSK.CountSkillLines(), 0, 0, 0
    local details = {}
    local D = WSK.Describe
    for index = 1, lines do
        local info = C_SkillInfo.GetSkillLineInfo(index)
        local line = WSK.ReadSkillLine(index)
        if type(line) == "table" and line.isHeader then
            headers = headers + 1
            if line.isCollapsed then
                collapsed = collapsed + 1
            end
            details[#details + 1] = string.format("debug_skills header id=%s name=%s collapsed=%s",
                D(info.skillID), D(info.name), D(info.isCollapsed))
        elseif type(line) == "table" then
            if (line.parentSkillLineID or 0) ~= 0 then
                children = children + 1
            end
            local id = type(line.skillID) == "number" and line.skillID or nil
            details[#details + 1] = string.format(
                "debug_skills id=%s name=%s category=%s parent=%s rank=%s max=%s trackable=%s tracked=%s",
                D(info.skillID), D(info.name), D(info.skillLineCategoryID),
                D(info.parentSkillLineID), D(info.rank), D(info.maxRank),
                tostring(id ~= nil and WSK.GetSkill(id) ~= nil),
                tostring(id ~= nil and WSK.IsTracked(id)))
        end
    end
    WSK.Report(string.format("debug_skills lines=%d headers=%d collapsed=%d children=%d trackable=%d tracked=%d",
        lines, headers, collapsed, children, #WSK.ListTrackableSkills(), #WSK.db.tracked))
    for _, detail in ipairs(details) do
        WSK.Report(detail)
    end
end

-- /wsk, and /weaponskills in case another AddOn uses /wsk. Never /wsf: that
-- belongs to Weapon Sets Forever.
local SLASH_KEY = "WEAPONSKILLSFOREVER"
local SLASH_ALIASES = {"/wsk", "/weaponskills"}
-- Aliases checked per other command key (SLASH_<KEY>1 to this).
local MAX_SLASH_ALIASES = 10

-- Another AddOn can register the same slash command; the last one loaded
-- wins. Returns {alias = other command key} for each alias another key uses.
local function FindSlashConflicts()
    local conflicts = {}
    for key in pairs(SlashCmdList) do
        if key ~= SLASH_KEY then
            for index = 1, MAX_SLASH_ALIASES do
                local alias = _G["SLASH_" .. key .. index]
                if type(alias) == "string" then
                    for _, ours in ipairs(SLASH_ALIASES) do
                        if alias:lower() == ours then
                            conflicts[ours] = key
                        end
                    end
                end
            end
        end
    end
    return conflicts
end

local function ReportSlashConflicts()
    local conflicts = FindSlashConflicts()
    for index, alias in ipairs(SLASH_ALIASES) do
        local other = SLASH_ALIASES[3 - index]
        if conflicts[alias] then
            local advice = conflicts[other] and "" or (" Use " .. other .. " instead.")
            WSK.Report("Another AddOn (" .. conflicts[alias] .. ") also uses " .. alias .. "." .. advice)
        end
    end
end

for index, alias in ipairs(SLASH_ALIASES) do
    _G["SLASH_" .. SLASH_KEY .. index] = alias
end
SlashCmdList[SLASH_KEY] = function(message) WSK.HandleCommand(message) end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("SKILL_LINES_CHANGED")
events:SetScript("OnEvent", function(self, event, loadedName)
    if event == "ADDON_LOADED" then
        if loadedName == addonName then
            self:UnregisterEvent("ADDON_LOADED")
            WeaponSkillsForeverDB = WSK.SanitizeDB(WeaponSkillsForeverDB)
            WSK.db = WeaponSkillsForeverDB
        end
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        if not WSK.db then
            WeaponSkillsForeverDB = WSK.SanitizeDB(WeaponSkillsForeverDB)
            WSK.db = WeaponSkillsForeverDB
        end
        local available, message = CheckInstalledFiles()
        if available then
            available, message = WSK.CheckCapabilities()
        end
        WSK.available = available
        ReportLoaded(available)
        ReportSlashConflicts()
        if not available then
            WSK.Report(message)
            return
        end
        local toolkit = _G.DyresToolkit
        if type(toolkit) == "table" and type(toolkit.RequireContract) == "function" then
            WSK.toolkit = toolkit.RequireContract(TOOLKIT_CONTRACT)
        end
        if WSK.toolkit then
            -- The toolkit's frames start locked at login; the box follows.
            WSK.db.locked = WSK.toolkit.IsLocked()
        else
            WSK.Report(INSTALL_TOOLKIT)
        end
        -- Called directly rather than from UI's own PLAYER_LOGIN handler, so
        -- startup never depends on event handler order.
        WSK.InitializeUI()
        if WSK.toolkit then
            WSK.toolkit.RegisterAddOn({addon = addonName, title = DEFAULT_TITLE, setLocked = WSK.ApplyLocked,
                openSettings = WSK.OpenSettings})
        end
    elseif WSK.available then
        PruneUnlearned()
        WSK.RefreshUI()
    end
end)
