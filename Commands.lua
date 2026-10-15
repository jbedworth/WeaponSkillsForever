local _, WSK = ...

local USAGE = "Use /wsk, /wsk config, /wsk options, /wsk show, /wsk hide, /wsk lock, /wsk unlock, /wsk reset, or /wsk debug_skills."
local UNAVAILABLE = "Weapon Skills Forever is unavailable. Check the WSK login message."

-- Each command is one word; "" toggles the tracker. Handlers live in Core and UI.
local COMMANDS = {
    [""] = "ToggleTracker",
    config = "ToggleConfig",
    options = "OpenSettings",
    show = "ShowTracker",
    hide = "HideTracker",
    lock = "LockTracker",
    unlock = "UnlockTracker",
    reset = "ResetTrackerPosition",
    debug_skills = "ReportSkillDebug",
}

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
    if not WSK.available then
        WSK.Report(UNAVAILABLE)
        return
    end
    WSK[COMMANDS[command]]()
end
