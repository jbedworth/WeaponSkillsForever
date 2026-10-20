local _, WSK = ...

local USAGE = "Use /wsk (settings), /wsk config, /wsk show, /wsk hide, /wsk lock, /wsk unlock, /wsk reset, "
    .. "/wsk debug_skills, or /wsk help. /weaponskills works the same."
local UNAVAILABLE = "Weapon Skills Forever is unavailable. Check the WSK login message."

-- Each command is one word; "" opens the settings, as options does
-- (author-approved). Handlers live in Core and UI.
local COMMANDS = {
    [""] = "OpenSettings",
    options = "OpenSettings",
    config = "ToggleConfig",
    show = "ShowTracker",
    hide = "HideTracker",
    lock = "LockTracker",
    unlock = "UnlockTracker",
    reset = "ResetTrackerPosition",
    debug_skills = "ReportSkillDebug",
    help = "ReportUsage",
}

function WSK.ReportUsage()
    WSK.Report(USAGE)
end

function WSK.ParseCommand(message)
    if type(message) ~= "string" then
        return nil, USAGE
    end
    local command = message:match("^%s*(.-)%s*$"):lower()
    if command:find("%s") or not COMMANDS[command] then
        return nil, USAGE
    end
    return command
end

function WSK.HandleCommand(message)
    local command, usage = WSK.ParseCommand(message)
    if not command then
        WSK.Report(usage)
        return
    end
    -- help also works when WSK is unavailable.
    if not WSK.available and command ~= "help" then
        WSK.Report(UNAVAILABLE)
        return
    end
    WSK[COMMANDS[command]]()
end
