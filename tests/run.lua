-- Run from the repository root: lua tests/run.lua
-- These mocks test AddOn logic, not Forever compatibility, layout, or taint.
-- Every test gets its own globals, skill data, event frames, and namespace.
if _VERSION ~= "Lua 5.1" then
    io.stderr:write("This suite requires Lua 5.1; found " .. tostring(_VERSION) .. "\n")
    os.exit(1)
end

local tests = {}
local function test(name, body)
    tests[#tests + 1] = {name = name, body = body}
end
local function equal(actual, expected, context)
    if actual ~= expected then
        error((context or "value") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual), 2)
    end
end
local function contains(actual, fragment)
    if type(actual) ~= "string" or not actual:find(fragment, 1, true) then
        error("expected text containing " .. fragment .. ", got " .. tostring(actual), 2)
    end
end
local function same(actual, expected, context)
    if actual == expected then return end
    equal(type(actual), type(expected), context)
    if type(expected) ~= "table" then
        equal(actual, expected, context)
        return
    end
    for key, value in pairs(expected) do
        same(actual[key], value, (context or "table") .. "[" .. tostring(key) .. "]")
    end
    for key in pairs(actual) do
        if expected[key] == nil then
            error((context or "table") .. ": unexpected key " .. tostring(key), 2)
        end
    end
end

-- A secret value: any compare, arithmetic, concatenation, length, or
-- tostring is an error, as using one is in client.
local SECRET = {}
local function secretError()
    error("attempt to use a secret value", 2)
end
for _, event in ipairs({"__lt", "__le", "__eq", "__add", "__sub", "__mul", "__div", "__mod", "__pow",
    "__unm", "__concat", "__len", "__tostring", "__index", "__call"}) do
    SECRET[event] = secretError
end
-- kind: the type the client reports for it (type() of a secret number is "number").
local secretKinds = setmetatable({}, {__mode = "k"})
local function secretValue(kind)
    local value = setmetatable({}, SECRET)
    secretKinds[value] = kind or "number"
    return value
end
local function isSecret(value) return type(value) == "table" and getmetatable(value) == SECRET end

-- Skill lines as C_SkillInfo reports them, in client order.
local function line(id, name, rank, maxRank, extra)
    local info = {skillID = id, name = name, isHeader = false, isCollapsed = false,
        rank = rank, tempPoints = 0, modifier = 0, maxRank = maxRank,
        skillLineCategoryID = 6, parentSkillLineID = 0}
    for key, value in pairs(extra or {}) do info[key] = value end
    return info
end
local function header(id, name, collapsed)
    return {skillID = id, name = name, isHeader = true, isCollapsed = collapsed or false,
        rank = 0, modifier = 0, maxRank = 0, skillLineCategoryID = 0, parentSkillLineID = 0}
end
-- Mirrors a client debug_skills capture: a header's skillID is the category of
-- the skills under it, and professions repeat as child lines.
local function defaultSkills()
    return {
        header(7, "Class Skills"),
        line(633, "Lockpicking", 50, 100, {skillLineCategoryID = 7}),
        header(6, "Weapon Skills"),
        line(43, "Swords", 297, 300, {modifier = 5}),
        line(44, "Axes", 120, 300),
        line(173, "Daggers", 300, 300),
        line(95, "Defense", 280, 300),
        line(54, "Maces", 200, 300),
        line(136, "Staves", 15, 300),
        line(162, "Unarmed", 5, 300),
        header(8, "Armor Proficiencies"),
        line(415, "Cloth", 1, 1, {skillLineCategoryID = 8}),
        header(10, "Languages"),
        line(98, "Language: Common", 300, 300, {skillLineCategoryID = 10}),
        header(11, "Professions"),
        line(333, "Enchanting", 72, 75, {skillLineCategoryID = 11}),
        line(2486, "Enchanting", 72, 75, {skillLineCategoryID = 11, parentSkillLineID = 333}),
        header(9, "Secondary Skills"),
        line(356, "Fishing", 10, 75, {skillLineCategoryID = 9}),
        line(185, "Cooking", 40, 75, {skillLineCategoryID = 9}),
    }
end

local function fixture(options)
    options = options or {}
    local state = {frames = {}, messages = {}, widgets = {}, skills = options.skills or defaultSkills(),
        defense = {300, 0}}
    local env = setmetatable({}, {__index = _G})
    env._G = env
    env.SlashCmdList = {}
    -- Another AddOn's slash commands, registered before WSK loads.
    for key, aliases in pairs(options.otherSlash or {}) do
        env.SlashCmdList[key] = function() end
        for index, alias in ipairs(aliases) do env["SLASH_" .. key .. index] = alias end
    end
    env.InCombatLockdown = function() return state.combat == true end
    env.UISpecialFrames = {}
    env.IsLoggedIn = function() return false end
    env.DEFAULT_CHAT_FRAME = {AddMessage = function(_, message)
        state.messages[#state.messages + 1] = message
    end}
    state.toc = {}
    for text in io.lines("WeaponSkillsForever.toc") do
        local key, value = text:match("^##%s*([^:]+):%s*(.-)%s*$")
        if key then state.toc[key] = value end
    end
    env.C_AddOns = {GetAddOnMetadata = function(name, field)
        equal(name, "WeaponSkillsForever", "metadata uses the AddOn folder name")
        return state.toc[field] or ""
    end}
    -- As in client: a collapsed header hides its lines from the index list,
    -- but lookup by ID still finds them.
    local function visibleLines()
        local lines, hidden = {}, false
        for _, info in ipairs(state.skills) do
            if info.isHeader then
                hidden = info.isCollapsed
                lines[#lines + 1] = info
            elseif not hidden then
                lines[#lines + 1] = info
            end
        end
        return lines
    end
    state.expanded = {}
    -- Secret values, as in client under combat restrictions: state.secret
    -- names the line fields to hide ({rank = true, ...}); state.secretCount
    -- and state.secretDefense hide the line count and Defense's bonus.
    env.issecretvalue = function(value) return isSecret(value) end
    env.type = function(value)
        if isSecret(value) then return secretKinds[value] end
        return type(value)
    end
    local function reveal(info)
        if not info or not state.secret then return info end
        local copy = {}
        for key, value in pairs(info) do
            copy[key] = state.secret[key] and secretValue(type(value)) or value
        end
        return copy
    end
    env.C_SkillInfo = {
        GetNumSkillLines = function()
            if state.secretCount then return secretValue() end
            return #visibleLines()
        end,
        GetSkillLineInfo = function(index) return reveal(visibleLines()[index]) end,
        GetSkillLineInfoByID = function(id)
            for _, info in ipairs(state.skills) do
                if info.skillID == id then return reveal(info) end
            end
        end,
        ExpandSkillHeader = function(index)
            local info = visibleLines()[index]
            equal(info and info.isHeader, true, "expand targets a header")
            state.expanded[#state.expanded + 1] = "+" .. info.name
            info.isCollapsed = false
            state.emit("SKILL_LINES_CHANGED")
        end,
        CollapseSkillHeader = function(index)
            local info = visibleLines()[index]
            equal(info and info.isHeader, true, "collapse targets a header")
            state.expanded[#state.expanded + 1] = "-" .. info.name
            info.isCollapsed = true
            state.emit("SKILL_LINES_CHANGED")
        end,
    }
    env.UnitDefenseSkill = function(unit)
        equal(unit, "player")
        if state.secretDefense then return secretValue(), secretValue() end
        return state.defense[1], state.defense[2]
    end

    local function widget(kind, name, parent, template)
        local object = {kind = kind, name = name, parent = parent, template = template,
            scripts = {}, points = {}, children = {}, shown = kind ~= "Frame" or name == nil,
            enabled = true, checked = false, text = "", events = {}}
        state.widgets[#state.widgets + 1] = object
        if parent then parent.children[#parent.children + 1] = object end
        if name then env[name] = object end
        function object:RegisterEvent(event) self.events[event] = true end
        function object:UnregisterEvent(event) self.events[event] = nil end
        function object:SetScript(script, callback) self.scripts[script] = callback end
        function object:GetScript(script) return self.scripts[script] end
        function object:IsShown() return self.shown end
        function object:IsVisible()
            return self.shown and (not self.parent or self.parent:IsVisible())
        end
        function object:Show()
            local before = self.shown
            self.shown = true
            if not before and self.scripts.OnShow then self.scripts.OnShow(self) end
        end
        function object:Hide()
            local before = self.shown
            self.shown = false
            if before and self.scripts.OnHide then self.scripts.OnHide(self) end
        end
        function object:SetPoint(...) self.points[#self.points + 1] = {...} end
        function object:ClearAllPoints() self.points = {} end
        function object:GetPoint()
            local point = self.points[#self.points]
            return point[1], point[2], point[3], point[4], point[5]
        end
        function object:SetSize(width, height) self.width, self.height = width, height end
        function object:SetWidth(width) self.width = width end
        function object:SetHeight(height) self.height = height end
        function object:SetText(text) self.text = text end
        function object:GetText() return self.text end
        function object:SetTextColor(...) self.textColor = {...} end
        function object:SetChecked(value) self.checked = value and true or false end
        function object:GetChecked() return self.checked end
        function object:SetEnabled(value) self.enabled = value and true or false end
        function object:IsEnabled() return self.enabled end
        function object:SetMinMaxValues(low, high) self.min, self.max = low, high end
        -- As in client, SetValue on a slider fires OnValueChanged.
        function object:SetValue(value)
            self.value = value
            if self.kind == "Slider" and self.scripts.OnValueChanged then
                self.scripts.OnValueChanged(self, value)
            end
        end
        function object:GetValue() return self.value end
        function object:SetValueStep(step) self.step = step end
        function object:SetObeyStepOnDrag(value) self.obeyStep = value end
        function object:SetStatusBarColor(...) self.barColor = {...} end
        function object:SetStatusBarTexture(texture) self.barTexture = texture end
        function object:SetBackdrop(backdrop) self.backdrop = backdrop end
        function object:SetBackdropColor(...) self.backdropColor = {...} end
        function object:SetBackdropBorderColor(...) self.borderColor = {...} end
        function object:SetColorTexture(...) self.color = {...} end
        function object:SetAtlas(atlas, useSize) self.atlas, self.atlasSize = atlas, useSize end
        function object:SetBlendMode(mode) self.blend = mode end
        function object:SetAlpha(alpha) self.alpha = alpha end
        function object:Enable() self.enabled = true end
        function object:Disable() self.enabled = false end
        function object:SetNormalTexture(path) self.normalTexture = path end
        function object:SetHighlightTexture(path, mode) self.highlight = {path, mode} end
        function object:SetMovable(value) self.movable = value end
        function object:EnableMouse(value) self.mouse = value end
        function object:RegisterForDrag(button) self.drag = button end
        function object:StartMoving() self.moving = true end
        function object:StopMovingOrSizing() self.moving = false end
        function object:SetClampedToScreen(value) self.clamped = value end
        function object:SetFrameStrata(strata) self.strata = strata end
        function object:SetJustifyH(value) self.justify = value end
        function object:SetAllPoints() self.allPoints = true end
        function object:CreateTexture(_, layer)
            local texture = widget("Texture", nil, self)
            texture.layer = layer
            return texture
        end
        function object:CreateFontString(_, layer, font)
            local label = widget("FontString", nil, self, font)
            label.layer = layer
            return label
        end
        return object
    end
    env.UIParent = widget("Frame")
    env.CreateFrame = function(kind, name, parent, template)
        local frame = widget(kind, name, parent, template)
        frame.shown = true
        state.frames[#state.frames + 1] = frame
        return frame
    end
    -- Blizzard's Settings API (canvas categories), as in the pinned source.
    state.settingsOpened = {}
    if options.settings ~= false then
        env.Settings = {
            RegisterCanvasLayoutCategory = function(frame, name)
                local category = {frame = frame, name = name}
                function category:GetID() return 77 end
                state.settingsCategory = category
                return category, {}
            end,
            RegisterCanvasLayoutSubcategory = function(parent, frame, name)
                local category = {parent = parent, frame = frame, name = name}
                function category:GetID() return 78 end
                state.settingsCategory = category
                return category, {}
            end,
            RegisterAddOnCategory = function(category) state.settingsRegistered = category end,
            OpenToCategory = function(id) state.settingsOpened[#state.settingsOpened + 1] = id end,
        }
    end
    -- Dyre's Toolkit (contract 1), recording what WSK asks of it.
    if options.toolkit then
        local kit = {locked = options.toolkitUnlocked ~= true, movables = {}, addons = {}, calls = {}, opened = {},
            home = {name = "Dyre's AddOns"}}
        state.toolkit = kit
        local function record(name)
            kit.calls[#kit.calls + 1] = name
        end
        local toolkit = {}
        function toolkit.RequireContract(required)
            if required >= 1 and required <= (options.toolkitContract or 1) then return toolkit end
        end
        function toolkit.IsLocked() return kit.locked end
        function toolkit.SetLocked(locked)
            record("SetLocked")
            kit.locked = locked == true
            for _, info in ipairs(kit.addons) do
                if info.setLocked then info.setLocked(kit.locked) end
            end
        end
        function toolkit.Lock() record("Lock"); toolkit.SetLocked(true) end
        function toolkit.Unlock() record("Unlock"); toolkit.SetLocked(false) end
        function toolkit.RegisterAddOn(info)
            kit.addons[#kit.addons + 1] = info
            if not kit.locked and info.setLocked then info.setLocked(false) end
            return true
        end
        function toolkit.RegisterMovable(frame, save)
            kit.movables[frame] = save
            return true
        end
        function toolkit.BeginDrag(frame)
            record("BeginDrag")
            if kit.locked or not kit.movables[frame] then return end
            kit.dragging = frame
            frame:StartMoving()
        end
        -- As the toolkit: drops the frame on a grid point and saves its center.
        function toolkit.EndDrag(frame)
            record("EndDrag")
            if kit.dragging ~= frame then return end
            kit.dragging = nil
            frame:StopMovingOrSizing()
            local position = {point = "CENTER", relativePoint = "BOTTOMLEFT", x = 320, y = 256}
            frame:ClearAllPoints()
            frame:SetPoint(position.point, env.UIParent, position.relativePoint, position.x, position.y)
            kit.movables[frame](position)
        end
        function toolkit.SettingsCategory() return kit.home end
        function toolkit.OpenSettings(category)
            kit.opened[#kit.opened + 1] = category
            return true
        end
        env.DyresToolkit = toolkit
    end
    env.GameTooltip = widget("Tooltip")
    function env.GameTooltip:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor end
    function env.GameTooltip:IsOwned(owner) return self.owner == owner and self.shown end
    function env.GameTooltip:AddLine(...) self.lines = self.lines or {}; self.lines[#self.lines + 1] = {...} end

    function state.emit(event, ...)
        for _, frame in ipairs(state.frames) do
            if frame.events[event] and frame.scripts.OnEvent then
                frame.scripts.OnEvent(frame, event, ...)
            end
        end
    end
    function state.fire(object, script, ...)
        local callback = object:GetScript(script)
        equal(type(callback), "function", script)
        return callback(object, ...)
    end
    local namespace = {}
    function state.load(path)
        local chunk, message = loadfile(path)
        if not chunk then error(message, 2) end
        setfenv(chunk, env)
        chunk("WeaponSkillsForever", namespace)
    end
    state.env, state.wsk = env, namespace
    env.WeaponSkillsForeverDB = options.db
    for _, path in ipairs(options.files or {"Commands.lua", "Skills.lua", "Core.lua", "UI.lua"}) do
        state.load(path)
    end
    if options.login ~= false then
        state.emit("ADDON_LOADED", "WeaponSkillsForever")
        state.emit("PLAYER_LOGIN")
        state.tracker = env.WeaponSkillsForeverTracker
        state.config = env.WeaponSkillsForeverConfig
        state.settings = env.WeaponSkillsForeverSettings
        if namespace.available then
            if namespace.toolkit then
                equal(#state.messages, 2, "banner and ready hint")
            else
                equal(#state.messages, 3, "banner, ready hint, and where to get Dyre's Toolkit")
                contains(state.messages[3], "Install Dyre's Toolkit from CurseForge")
            end
            state.messages = {}
        end
    end
    return state
end

local function trackedRows(state)
    local rows = {}
    for _, child in ipairs(state.tracker.children) do
        if child.kind == "StatusBar" and child.shown then rows[#rows + 1] = child end
    end
    return rows
end
local function rowsFor(state)
    local result = {}
    for _, bar in ipairs(trackedRows(state)) do
        local label
        for _, child in ipairs(bar.children) do
            if child.kind == "FontString" then label = child end
        end
        result[#result + 1] = {value = bar.value, max = bar.max, color = bar.barColor, text = label.text}
    end
    return result
end
local function listRows(state)
    local result = {}
    for _, child in ipairs(state.config.children) do
        if child.kind == "CheckButton" and child ~= state.config.lock then
            result[#result + 1] = child
        end
    end
    return result
end
local RED, YELLOW, GREEN = {0.8, 0.1, 0.1}, {0.9, 0.75, 0.1}, {0.15, 0.7, 0.2}

for _, path in ipairs({"Commands.lua", "Skills.lua", "Core.lua", "UI.lua"}) do
    local file = path
    test("Lua 5.1 syntax: " .. file, function()
        local chunk, message = loadfile(file)
        equal(type(chunk), "function", message or file)
    end)
end

-- Commands -------------------------------------------------------------------

for _, case in ipairs({{"", ""}, {"  ", ""}, {"config", "config"}, {" CONFIG ", "config"},
    {"show", "show"}, {"hide", "hide"}, {"lock", "lock"}, {"unlock", "unlock"},
    {"reset", "reset"}, {"debug_skills", "debug_skills"}, {"options", "options"}, {"help", "help"}, {" HELP ", "help"}}) do
    local input, expected = case[1], case[2]
    test("command accepts '" .. input .. "'", function()
        equal(fixture({login = false}).wsk.ParseCommand(input), expected)
    end)
end
for _, input in ipairs({"set", "config now", "lock it", "debug", false, 3}) do
    local message = input
    test("command rejects " .. tostring(message) .. " with usage", function()
        local state = fixture()
        state.wsk.HandleCommand(message)
        equal(#state.messages, 1)
        contains(state.messages[1], "WSK: Use /wsk")
    end)
end
test("commands report unavailability instead of acting", function()
    local unavailable = fixture()
    unavailable.wsk.available = false
    unavailable.wsk.HandleCommand("hide")
    equal(unavailable.tracker:IsShown(), true)
    contains(unavailable.messages[1], "unavailable")
end)

-- Skill data -----------------------------------------------------------------

test("trackable skills skip headers, Class Skills, and single-rank lines", function()
    local skills = fixture().wsk.ListTrackableSkills()
    local names = {}
    for index, skill in ipairs(skills) do names[index] = skill.name .. "@" .. tostring(skill.group) end
    same(names, {"Swords@Weapon Skills", "Axes@Weapon Skills", "Daggers@Weapon Skills",
        "Defense@Weapon Skills", "Maces@Weapon Skills", "Staves@Weapon Skills",
        "Unarmed@Weapon Skills", "Enchanting@Professions",
        "Fishing@Secondary Skills", "Cooking@Secondary Skills"})
end)
test("languages are neither listed nor trackable", function()
    local state = fixture()
    for _, skill in ipairs(state.wsk.ListTrackableSkills()) do
        equal(skill.group == "Languages", false, "no Languages entries")
    end
    equal(state.wsk.GetSkill(98), nil)
    local ok = state.wsk.SetTracked(98, true)
    equal(ok, false)
end)
test("child skill lines are neither listed nor trackable", function()
    local state = fixture()
    local count = 0
    for _, skill in ipairs(state.wsk.ListTrackableSkills()) do
        if skill.name == "Enchanting" then count = count + 1 end
    end
    equal(count, 1, "Enchanting listed once, as on the Skills tab")
    equal(state.wsk.GetSkill(2486), nil)
    local ok = state.wsk.SetTracked(2486, true)
    equal(ok, false)
    equal(state.wsk.GetSkill(333).id, 333)
end)
test("GetSkill describes a learned skill and rejects unknown or untrackable ones", function()
    local wsk = fixture().wsk
    same(wsk.GetSkill(43), {id = 43, name = "Swords", rank = 297, modifier = 5, maxRank = 300,
        categoryID = 6})
    equal(wsk.GetSkill(999), nil)
    equal(wsk.GetSkill(415), nil, "single-rank")
    equal(wsk.GetSkill(633), nil, "class skill")
    equal(wsk.GetSkill(6), nil, "header")
end)
test("Defense takes its bonus from UnitDefenseSkill", function()
    local state = fixture()
    state.defense = {287, 7}
    equal(state.wsk.GetSkill(95).modifier, 7)
    state.env.UnitDefenseSkill = nil
    equal(state.wsk.GetSkill(95).modifier, 0)
end)
for _, case in ipairs({{300, 300, "capped"}, {301, 300, "capped"}, {299, 300, "near"},
    {295, 300, "near"}, {294, 300, "low"}, {0, 300, "low"}, {72, 75, "near"},
    {3, 5, "near"}, {4, 10, "low"}}) do
    local rank, maxRank, expected = case[1], case[2], case[3]
    test(string.format("status %d/%d is %s", rank, maxRank, expected), function()
        equal(fixture({login = false}).wsk.SkillStatus(rank, maxRank), expected)
    end)
end

-- Capabilities and startup ---------------------------------------------------

for _, name in ipairs({"GetNumSkillLines", "GetSkillLineInfo", "GetSkillLineInfoByID"}) do
    local missing = name
    test("capability rejects missing " .. missing, function()
        local state = fixture({login = false})
        state.env.C_SkillInfo[missing] = nil
        state.emit("ADDON_LOADED", "WeaponSkillsForever")
        state.emit("PLAYER_LOGIN")
        equal(state.wsk.available, false)
        equal(#state.messages, 2)
        contains(state.messages[2], missing)
        equal(state.env.WeaponSkillsForeverTracker, nil, "no UI without capabilities")
        state.emit("SKILL_LINES_CHANGED")
        equal(#state.messages, 2, "reported once")
    end)
end
test("login banner shows TOC title, version, and author, then a ready hint", function()
    local state = fixture({login = false})
    state.emit("ADDON_LOADED", "WeaponSkillsForever")
    state.emit("PLAYER_LOGIN")
    same(state.messages, {
        "WSK: Weapon Skills Forever " .. state.toc.Version .. " by Dyre",
        "WSK:   Ready. Click the gear on the skill box, or type /wsk config, to choose skills.",
        "WSK: Install Dyre's Toolkit from CurseForge for one layout mode and settings home for all Dyre's AddOns.",
    })
end)
test("login reports a mixed install", function()
    local state = fixture({login = false, files = {"Commands.lua", "Core.lua", "UI.lua"}})
    state.emit("ADDON_LOADED", "WeaponSkillsForever")
    state.emit("PLAYER_LOGIN")
    equal(state.wsk.available, false)
    contains(state.messages[2], "different versions (missing CheckCapabilities)")
end)
test("other AddOns loading do not touch saved settings", function()
    local state = fixture({login = false, db = {tracked = {43}}})
    state.emit("ADDON_LOADED", "SomeOtherAddOn")
    equal(state.wsk.db, nil)
    state.emit("ADDON_LOADED", "WeaponSkillsForever")
    same(state.wsk.db.tracked, {43})
end)

-- Saved settings -------------------------------------------------------------

test("saved settings are repaired on load", function()
    local state = fixture({db = {tracked = {43, 43, "44", 1.5, -2, 44, 173, 95, 333, 54, 356, 185},
        shown = "yes", locked = 1, position = {point = "TOP"}}})
    same(state.wsk.db.tracked, {43, 44, 173, 95, 333, 54, 356, 185},
        "deduplicated, whole positive IDs, at most 6 of each type")
    equal(state.wsk.db.shown, true)
    equal(state.wsk.db.locked, false)
    equal(state.wsk.db.position, nil)
    equal(state.env.WeaponSkillsForeverDB, state.wsk.db, "saved per character by the client")
end)
test("missing saved settings start empty and shown", function()
    local state = fixture()
    same(state.wsk.db, {tracked = {}, shown = true, locked = false, view = "weapons",
        backgroundAlpha = 0.5, contentAlpha = 0.9})
end)
test("saved settings keep at most twelve IDs and a valid view", function()
    local ids = {}
    for id = 1, 20 do ids[id] = 5000 + id end
    local state = fixture({db = {tracked = ids, view = "sideways"}})
    equal(#state.wsk.db.tracked, 12)
    equal(state.wsk.db.view, "weapons")
    equal(fixture({db = {view = "other"}}).wsk.db.view, "other")
end)

-- Tracking ---------------------------------------------------------------------

test("tracking is limited to six weapon skills, with a clear message", function()
    local state = fixture()
    for _, id in ipairs({43, 44, 173, 95, 54, 136}) do
        equal(state.wsk.SetTracked(id, true), true)
    end
    local ok, message = state.wsk.SetTracked(162, true)
    equal(ok, false)
    contains(message, "up to 6 weapon skills")
    equal(state.wsk.SetTracked(333, true), true, "other skills have their own limit")
    equal(state.wsk.CountTracked("weapons"), 6)
    equal(state.wsk.CountTracked("other"), 1)
    equal(state.wsk.SetTracked(44, false), true)
    equal(state.wsk.SetTracked(162, true), true)
end)
test("other skills have their own limit, with a clear message", function()
    local state = fixture()
    state.wsk.MAX_TRACKED = 2
    equal(state.wsk.SetTracked(333, true), true)
    equal(state.wsk.SetTracked(356, true), true)
    local ok, message = state.wsk.SetTracked(185, true)
    equal(ok, false)
    contains(message, "up to 2 non-weapon skills")
    equal(state.wsk.SetTracked(43, true), true)
end)
test("skill type comes from the Weapon Skills category", function()
    local wsk = fixture().wsk
    equal(wsk.SkillType(wsk.GetSkill(43)), "weapons")
    equal(wsk.SkillType(wsk.GetSkill(95)), "weapons", "Defense is grouped with weapons")
    equal(wsk.SkillType(wsk.GetSkill(333)), "other")
    equal(wsk.SkillType(wsk.GetSkill(356)), "other")
end)
test("tracking rejects unknown and untrackable skills", function()
    local state = fixture()
    for _, id in ipairs({999, 415, 633}) do
        local ok, message = state.wsk.SetTracked(id, true)
        equal(ok, false)
        contains(message, "not learned")
    end
    same(state.wsk.GetTracked(), {})
end)
test("tracking the same skill twice keeps one entry", function()
    local state = fixture()
    state.wsk.SetTracked(43, true)
    state.wsk.SetTracked(43, true)
    same(state.wsk.GetTracked(), {43})
end)
test("unlearned skills are pruned when skill lines change", function()
    local state = fixture({db = {tracked = {43, 333}}})
    -- Abandoning Enchanting removes its line and its child line.
    for index = #state.skills, 1, -1 do
        local id = state.skills[index].skillID
        if id == 333 or id == 2486 then table.remove(state.skills, index) end
    end
    state.emit("SKILL_LINES_CHANGED")
    same(state.wsk.GetTracked(), {43})
end)
test("an empty skill list before data arrives never prunes", function()
    local state = fixture({db = {tracked = {43, 333}}})
    state.skills = {}
    state.emit("SKILL_LINES_CHANGED")
    same(state.wsk.GetTracked(), {43, 333})
end)

-- Tracker box ----------------------------------------------------------------

test("tracker box is a gold-bordered, half-transparent brown box with the title", function()
    local state = fixture()
    local tracker = state.tracker
    equal(tracker.template, "BackdropTemplate")
    contains(tracker.backdrop.edgeFile, "UI-Tooltip-Border")
    same(tracker.backdropColor, {0.28, 0.16, 0.07, 0.5})
    same(tracker.borderColor, {1, 0.82, 0, 1})
    local title
    for _, child in ipairs(tracker.children) do
        if child.kind == "FontString" and child.text == "Weapon Skills Forever" then title = child end
    end
    equal(type(title), "table", "title")
    same(title.textColor, {1, 0.82, 0})
end)
test("tracker shows an empty hint when nothing is tracked", function()
    local state = fixture()
    equal(#trackedRows(state), 0)
    equal(state.tracker.empty:IsShown(), true)
end)
test("tracked bars show base rank against cap with status colors, in Skills tab order", function()
    local state = fixture({db = {tracked = {173, 44, 43, 333}}})
    same(rowsFor(state), {
        {value = 297, max = 300, color = YELLOW, text = "297 |cff20ff20(+5)|r / 300"},
        {value = 120, max = 300, color = RED, text = "120 / 300"},
        {value = 300, max = 300, color = GREEN, text = "300 / 300"},
    }, "weapons view: Swords, Axes, Daggers as on the Skills tab, not as added")
    equal(state.tracker.empty:IsShown(), false)
    state.wsk.ToggleView()
    same(rowsFor(state), {{value = 72, max = 75, color = YELLOW, text = "72 / 75"}})
end)
test("skill rows are muted to 90% opacity while the title area stays full", function()
    local state = fixture({db = {tracked = {43, 44}}})
    for _, bar in ipairs(trackedRows(state)) do
        equal(bar.alpha, 0.9, "bar, fill, and value text")
    end
    for _, child in ipairs(state.tracker.children) do
        if child.kind == "FontString" and (child.text == "Swords" or child.text == "Axes") then
            equal(child.alpha, 0.9, child.text .. " name")
        elseif child.kind == "FontString" and child.text == "Weapon Skills Forever" then
            equal(child.alpha, nil, "title not muted")
        end
    end
    equal(state.tracker.empty.alpha, 0.9)
    equal(state.tracker.gear.alpha, nil, "header icons not muted")
    equal(state.tracker.view.alpha, nil)
    equal(state.tracker.alpha, nil, "the box itself is not muted")
end)
test("header icon buttons are 20 pixels, a little larger than the title", function()
    local state = fixture()
    for _, button in ipairs({state.tracker.gear, state.tracker.view}) do
        equal(button.width, 20)
        equal(button.height, 20)
    end
    same(state.tracker.view.points[1], {"RIGHT", state.tracker.gear, "LEFT", -10, 0})
end)
test("the view toggle switches the box between weapon and other skills", function()
    local state = fixture({db = {tracked = {43, 333}}})
    local toggle = state.tracker.view
    equal(toggle.normalTexture, "Interface\\Icons\\INV_Sword_04")
    state.fire(toggle, "OnEnter")
    equal(state.env.GameTooltip.text, "WSK: Showing weapon skills")
    state.fire(toggle, "OnClick")
    equal(state.wsk.db.view, "other", "saved per character")
    equal(toggle.normalTexture, "Interface\\Icons\\INV_Misc_Book_09")
    equal(state.env.GameTooltip.text, "WSK: Showing other skills", "tooltip follows the click")
    equal(#trackedRows(state), 1)
    state.fire(toggle, "OnClick")
    equal(state.wsk.db.view, "weapons")
end)
test("each view has its own empty hint", function()
    local state = fixture({db = {tracked = {333}}})
    equal(#trackedRows(state), 0)
    contains(state.tracker.empty.text, "No weapon skills tracked")
    state.wsk.ToggleView()
    equal(state.tracker.empty:IsShown(), false)
    state.wsk.SetTracked(333, false)
    contains(state.tracker.empty.text, "No other skills tracked")
end)
test("the saved view is applied at login", function()
    local state = fixture({db = {tracked = {43, 333}, view = "other"}})
    same(rowsFor(state), {{value = 72, max = 75, color = YELLOW, text = "72 / 75"}})
end)
test("a tracked skill under a collapsed group keeps its place in the order", function()
    local state = fixture({db = {tracked = {356, 333, 185}}})
    state.wsk.SetView("other")
    for _, info in ipairs(state.skills) do
        if info.isHeader and info.name == "Secondary Skills" then info.isCollapsed = true end
    end
    state.emit("SKILL_LINES_CHANGED")
    local names = {}
    for _, skill in ipairs(state.wsk.OrderSkills(state.wsk.GetTracked())) do names[#names + 1] = skill.name end
    same(names, {"Enchanting", "Fishing", "Cooking"},
        "collapsed Secondary Skills keeps the Skills tab order remembered while expanded")
    same(rowsFor(state)[2].text, "10 / 75", "the box shows Fishing second, as on the Skills tab")
end)
test("a group never seen expanded falls back to name order at its header", function()
    local skills = defaultSkills()
    for _, info in ipairs(skills) do
        if info.isHeader and info.name == "Secondary Skills" then info.isCollapsed = true end
    end
    local state = fixture({skills = skills, db = {tracked = {356, 333, 185}, view = "other"}})
    local names = {}
    for _, skill in ipairs(state.wsk.OrderSkills(state.wsk.GetTracked())) do names[#names + 1] = skill.name end
    same(names, {"Enchanting", "Cooking", "Fishing"})
end)
test("bars update when skill lines change", function()
    local state = fixture({db = {tracked = {43}}})
    state.skills[4].rank = 300
    state.emit("SKILL_LINES_CHANGED")
    same(rowsFor(state), {{value = 300, max = 300, color = GREEN, text = "300 |cff20ff20(+5)|r / 300"}})
end)
test("untracking hides its bar and shrinks the box", function()
    local state = fixture({db = {tracked = {43, 44}}})
    local tall = state.tracker.height
    state.wsk.SetTracked(43, false)
    equal(#trackedRows(state), 1)
    equal(state.tracker.height < tall, true)
end)
test("dragging moves the box and saves its position unless locked", function()
    local state = fixture()
    state.fire(state.tracker, "OnDragStart")
    equal(state.tracker.moving, true)
    state.tracker:SetPoint("TOPLEFT", state.env.UIParent, "TOPLEFT", 50, -60)
    state.fire(state.tracker, "OnDragStop")
    same(state.wsk.db.position, {point = "TOPLEFT", relativePoint = "TOPLEFT", x = 50, y = -60})
    state.wsk.HandleCommand("lock")
    state.tracker.moving = false
    state.fire(state.tracker, "OnDragStart")
    equal(state.tracker.moving, false, "locked box does not move")
end)
test("saved position is applied at login and reset restores the default", function()
    local state = fixture({db = {position = {point = "TOP", relativePoint = "TOP", x = 1, y = -2}}})
    same(state.tracker.points[#state.tracker.points], {"TOP", state.env.UIParent, "TOP", 1, -2})
    state.wsk.HandleCommand("reset")
    equal(state.wsk.db.position, nil)
    same(state.tracker.points[#state.tracker.points], {"RIGHT", state.env.UIParent, "RIGHT", -60, 120})
end)
test("hide and show persist", function()
    local state = fixture()
    state.wsk.HandleCommand("hide")
    equal(state.tracker:IsShown(), false)
    equal(state.wsk.db.shown, false)
    contains(state.messages[1], "/wsk show to show")
    state.wsk.HandleCommand("show")
    equal(state.tracker:IsShown(), true)
    local hidden = fixture({db = {shown = false}})
    equal(hidden.tracker:IsShown(), false, "hidden state survives reload")
end)
test("gear button opens the setup panel and explains itself", function()
    local state = fixture()
    equal(state.config:IsShown(), false)
    state.fire(state.tracker.gear, "OnClick")
    equal(state.config:IsShown(), true)
    state.fire(state.tracker.gear, "OnEnter")
    equal(state.env.GameTooltip.text, "WSK: Choose skills")
end)

-- Setup panel ----------------------------------------------------------------

test("setup panel lists groups and ranked skills with checkboxes", function()
    local state = fixture({db = {tracked = {43}}})
    state.wsk.HandleCommand("config")
    local labels = {}
    for _, child in ipairs(state.config.children) do
        if child.kind == "FontString" and child.shown and child.text ~= "" and child.layer == "OVERLAY" then
            labels[#labels + 1] = child.text
        elseif child.kind == "Button" and child.stateIcon and child.shown then
            labels[#labels + 1] = child.name.text
        end
    end
    contains(table.concat(labels, "|"), "Weapon Skills|Swords  (297 / 300)|Axes  (120 / 300)")
    contains(table.concat(labels, "|"), "Professions|Enchanting  (72 / 75)")
    contains(state.config.count.text, "Weapons 1 of 6, other skills 0 of 6")
    local checks = listRows(state)
    equal(checks[1].shown, false, "group header row has no checkbox")
    equal(checks[2].checked, true, "Swords tracked")
    equal(checks[3].checked, false, "Axes not tracked")
end)
test("checking and unchecking in the setup panel updates tracking and bars", function()
    local state = fixture()
    state.wsk.HandleCommand("config")
    local checks = listRows(state)
    checks[3]:SetChecked(true)
    state.fire(checks[3], "OnClick")
    same(state.wsk.GetTracked(), {44})
    equal(#trackedRows(state), 1)
    checks[3]:SetChecked(false)
    state.fire(checks[3], "OnClick")
    same(state.wsk.GetTracked(), {})
end)
test("at the limit, unchecked skills are disabled and tracked ones stay enabled", function()
    local state = fixture({db = {tracked = {43, 44, 173, 95, 54, 136}}})
    state.wsk.HandleCommand("config")
    local checks = listRows(state)
    equal(checks[2].enabled, true, "tracked Swords can be unchecked")
    equal(checks[8].checked, false, "Unarmed untracked")
    equal(checks[8].enabled, false, "weapons are full")
    equal(checks[10].checked, false, "Enchanting untracked")
    equal(checks[10].enabled, true, "other skills have room")
    contains(state.config.count.text, "Weapons 6 of 6, other skills 0 of 6")
end)
test("lock checkbox in the setup panel locks the box", function()
    local state = fixture()
    state.wsk.HandleCommand("config")
    state.config.lock:SetChecked(true)
    state.fire(state.config.lock, "OnClick")
    equal(state.wsk.db.locked, true)
end)
test("setup panel pages when there are more rows than fit", function()
    local skills = {header(1, "Professions")}
    for id = 1, 15 do skills[#skills + 1] = line(1000 + id, "Skill " .. id, 1, 75) end
    local state = fixture({skills = skills})
    state.wsk.HandleCommand("config")
    equal(state.config.pageText.text, "1 / 2")
    equal(state.config.previous.enabled, false)
    state.fire(state.config.next, "OnClick")
    equal(state.config.pageText.text, "2 / 2")
    equal(state.config.next.enabled, false)
end)
test("setup panel closes with Escape and its close button", function()
    local state = fixture()
    same(state.env.UISpecialFrames, {"WeaponSkillsForeverConfig"})
    state.wsk.HandleCommand("config")
    state.wsk.ToggleConfig()
    equal(state.config:IsShown(), false)
end)

-- Diagnostics ----------------------------------------------------------------

test("debug_skills reports line counts, collapsed headers, and each line", function()
    local skills = defaultSkills()
    skills[3].isCollapsed = true
    local state = fixture({skills = skills, db = {tracked = {43}}})
    state.wsk.HandleCommand("debug_skills")
    equal(state.messages[1], "WSK: debug_skills lines=13 headers=6 collapsed=1 children=1 trackable=3 tracked=1")
    equal(state.messages[2], "WSK: debug_skills header id=7 name=Class Skills collapsed=false")
    equal(state.messages[3], "WSK: debug_skills id=633 name=Lockpicking category=7 parent=0 rank=50 max=100 trackable=false tracked=false")
    equal(state.messages[4], "WSK: debug_skills header id=6 name=Weapon Skills collapsed=true")
    equal(state.messages[8], "WSK: debug_skills id=98 name=Language: Common category=10 parent=0 rank=300 max=300 trackable=false tracked=false")
    equal(state.messages[11], "WSK: debug_skills id=2486 name=Enchanting category=11 parent=333 rank=72 max=75 trackable=false tracked=false")
    equal(#state.messages, 14, "summary plus every visible header and line")
end)

-- Collapsed groups ---------------------------------------------------------------

local function headerButtons(state)
    local headers = {}
    for _, child in ipairs(state.config.children) do
        if child.kind == "Button" and child.stateIcon and child.shown then
            headers[#headers + 1] = child
        end
    end
    return headers
end
local function configLabels(state)
    local labels = {}
    for _, child in ipairs(state.config.children) do
        if child.kind == "FontString" and child.shown and child.text ~= "" and child.layer == "OVERLAY" then
            labels[#labels + 1] = child.text
        elseif child.kind == "Button" and child.stateIcon and child.shown then
            labels[#labels + 1] = "[" .. child.name.text .. (child.collapsed and "+" or "-") .. "]"
        end
    end
    return table.concat(labels, "|")
end

test("setup entries skip hidden categories and groups with nothing to track", function()
    local entries = fixture().wsk.ListSetupEntries()
    local names = {}
    for _, entry in ipairs(entries) do
        names[#names + 1] = entry.kind == "header" and ("[" .. entry.name .. "]") or entry.skill.name
    end
    equal(table.concat(names, ","),
        "[Weapon Skills],Swords,Axes,Daggers,Defense,Maces,Staves,Unarmed,[Professions],Enchanting,"
        .. "[Secondary Skills],Fishing,Cooking")
end)
test("group headers mirror the Skills tab: list background, highlight, and +/- icon", function()
    local skills = defaultSkills()
    skills[3].isCollapsed = true
    local state = fixture({skills = skills})
    state.wsk.HandleCommand("config")
    local headers = headerButtons(state)
    equal(#headers, 3)
    local weapon, professions = headers[1], headers[2]
    equal(weapon.name.text, "Weapon Skills")
    equal(weapon.stateIcon.atlas, "common-button-list-plus")
    equal(weapon.stateIcon.atlasSize, true)
    equal(professions.stateIcon.atlas, "common-button-list-minus")
    local layers = {}
    for _, child in ipairs(weapon.children) do
        if child.kind == "Texture" then layers[child.layer] = child end
    end
    equal(layers.BACKGROUND.atlas, "common-button-list-collapseExpand")
    equal(layers.HIGHLIGHT.atlas, "common-button-list-collapseExpand")
    equal(layers.HIGHLIGHT.blend, "ADD")
    equal(layers.HIGHLIGHT.alpha, 0.3)
end)
test("a collapsed group hides all its skills, tracked or not, like the Skills tab", function()
    local skills = defaultSkills()
    skills[3].isCollapsed = true
    local state = fixture({skills = skills, db = {tracked = {43, 95, 356}}})
    state.wsk.HandleCommand("config")
    local labels = configLabels(state)
    contains(labels, "[Weapon Skills+]|[Professions-]|Enchanting  (72 / 75)")
    for _, name in ipairs({"Swords", "Defense", "Axes"}) do
        equal(labels:find(name, 1, true), nil, name .. " hidden under the collapsed group")
    end
    same(state.wsk.GetTracked(), {43, 95, 356}, "still tracked")
    equal(#trackedRows(state), 2, "tracked weapon skills stay in the box")
    contains(state.config.count.text, "Weapons 2 of 6, other skills 1 of 6")
    same(state.expanded, {}, "WSK never expands or collapses a header on its own")
end)
test("clicking + expands and - collapses that group, as on the Skills tab", function()
    local skills = defaultSkills()
    skills[3].isCollapsed = true
    local state = fixture({skills = skills})
    state.wsk.HandleCommand("config")
    state.fire(headerButtons(state)[1], "OnClick")
    same(state.expanded, {"+Weapon Skills"})
    contains(configLabels(state), "[Weapon Skills-]|Swords  (297 / 300)|Axes  (120 / 300)")
    state.fire(headerButtons(state)[1], "OnEnter")
    equal(state.env.GameTooltip.text, "WSK: Collapse group")
    state.fire(headerButtons(state)[1], "OnClick")
    same(state.expanded, {"+Weapon Skills", "-Weapon Skills"})
    contains(configLabels(state), "[Weapon Skills+]|[Professions-]")
    state.fire(headerButtons(state)[1], "OnEnter")
    equal(state.env.GameTooltip.text, "WSK: Expand group")
end)
test("without the toggle APIs headers show without an icon and do nothing", function()
    local skills = defaultSkills()
    skills[3].isCollapsed = true
    local state = fixture({skills = skills})
    state.env.C_SkillInfo.CollapseSkillHeader = nil
    state.wsk.HandleCommand("config")
    local weapon = headerButtons(state)[1]
    equal(weapon.stateIcon.shown, false)
    equal(weapon.enabled, false)
    state.fire(weapon, "OnClick")
    same(state.expanded, {})
end)
test("collapsing a group on the Skills tab keeps its tracked skills in the box", function()
    local state = fixture({db = {tracked = {43, 333}}})
    state.skills[3].isCollapsed = true
    state.emit("SKILL_LINES_CHANGED")
    same(state.wsk.GetTracked(), {43, 333}, "not pruned while collapsed")
    equal(#trackedRows(state), 1, "Swords still shows in the weapons view")
end)

-- AddOn settings page -----------------------------------------------------------

local function settingsChecks(state)
    local checks = {}
    for _, child in ipairs(state.settings.children) do
        if child.kind == "CheckButton" and child.text and child.text.text then
            checks[child.text.text] = child
        end
    end
    return checks
end

test("settings page registers as an AddOn canvas category", function()
    local state = fixture()
    equal(state.settingsCategory.name, "Weapon Skills Forever")
    equal(state.settingsCategory.frame, state.settings)
    equal(state.settingsRegistered, state.settingsCategory)
    equal(state.settings.OnRefresh ~= nil, true, "refreshed when the Settings panel shows it")
end)
test("/wsk options opens the settings page", function()
    local state = fixture()
    state.wsk.HandleCommand("options")
    same(state.settingsOpened, {77})
end)
test("without the Settings API there is no page and /wsk options explains", function()
    local state = fixture({settings = false})
    equal(state.settings, nil)
    equal(state.wsk.available, true, "the AddOn still works")
    state.wsk.HandleCommand("options")
    contains(state.messages[1], "settings page is unavailable")
end)
test("settings show checkbox hides and shows the box quietly", function()
    local state = fixture()
    local shown = settingsChecks(state)["Show the skill box"]
    state.settings.OnRefresh()
    equal(shown.checked, true)
    shown:SetChecked(false)
    state.fire(shown, "OnClick")
    equal(state.tracker:IsShown(), false)
    equal(state.wsk.db.shown, false)
    equal(#state.messages, 0, "no chat hint from the settings page")
    shown:SetChecked(true)
    state.fire(shown, "OnClick")
    equal(state.tracker:IsShown(), true)
end)
test("settings checkboxes follow changes made elsewhere", function()
    local state = fixture()
    local checks = settingsChecks(state)
    state.wsk.HandleCommand("hide")
    equal(checks["Show the skill box"].checked, false)
    state.wsk.HandleCommand("lock")
    equal(checks["Lock the skill box position"].checked, true)
end)
test("settings lock checkbox and reset button work", function()
    local state = fixture({db = {position = {point = "TOP", relativePoint = "TOP", x = 1, y = 2}}})
    local lock = settingsChecks(state)["Lock the skill box position"]
    lock:SetChecked(true)
    state.fire(lock, "OnClick")
    equal(state.wsk.db.locked, true)
    state.fire(state.settings.reset, "OnClick")
    equal(state.wsk.db.position, nil)
end)
test("settings page embeds the same skill selector", function()
    local state = fixture({db = {tracked = {43}}})
    state.settings.OnRefresh()
    contains(state.settings.selector.count.text, "Weapons 1 of 6, other skills 0 of 6")
    local checks = {}
    for _, row in ipairs(state.settings.selector.rows) do
        if row.check.shown then checks[#checks + 1] = row end
    end
    equal(checks[1].check.checked, true, "Swords tracked")
    checks[2].check:SetChecked(true)
    state.fire(checks[2].check, "OnClick")
    same(state.wsk.GetTracked(), {43, 44})
    equal(#trackedRows(state), 2, "the box updates too")
end)
test("the settings skill list has a thin rounded gold border around it", function()
    local state = fixture()
    local border = state.settings.skillsBorder
    equal(border.template, "BackdropTemplate")
    contains(border.backdrop.edgeFile, "UI-Tooltip-Border")
    equal(border.backdrop.edgeSize, 8)
    equal(border.backdrop.bgFile, nil, "no fill over the list")
    same(border.borderColor, {1, 0.82, 0, 1})
    local selector = state.settings.selector
    local x, y = border.points[1][2], border.points[1][3]
    equal(x < selector.left and y > selector.top, true, "border starts above and left of the list")
    equal(border.width > selector.width, true)
    equal(border.height > state.settings.selector.rowCount * 24 + 22, true, "border reaches past the pager")
end)
test("layout and theme choices are shown but disabled", function()
    local state = fixture()
    local checks = settingsChecks(state)
    for _, name in ipairs({"Vertical", "Horizontal", "Classic gold"}) do
        equal(checks[name].enabled, false, name .. " disabled")
    end
    equal(checks["Vertical"].checked, true)
    equal(checks["Horizontal"].checked, false)
    equal(checks["Classic gold"].checked, true)
    same(state.wsk.db, {tracked = {}, shown = true, locked = false, view = "weapons",
        backgroundAlpha = 0.5, contentAlpha = 0.9}, "nothing saved for layout or theme")
end)

-- Opacity settings -----------------------------------------------------------

local function near(actual, expected, context)
    if type(actual) ~= "number" or math.abs(actual - expected) > 1e-9 then
        error((context or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

test("saved opacities are clamped to their ranges and rounded to the slider step", function()
    local state = fixture({db = {backgroundAlpha = 2, contentAlpha = 0}})
    near(state.wsk.db.backgroundAlpha, 1)
    near(state.wsk.db.contentAlpha, 0.2, "rows never fully invisible")
    local odd = fixture({db = {backgroundAlpha = 0.33, contentAlpha = "loud"}})
    near(odd.wsk.db.backgroundAlpha, 0.35)
    near(odd.wsk.db.contentAlpha, 0.9, "invalid values become the default")
end)
test("saved opacities are applied to the box at login", function()
    local state = fixture({db = {tracked = {43}, backgroundAlpha = 0.8, contentAlpha = 0.6}})
    near(state.tracker.backdropColor[4], 0.8)
    near(trackedRows(state)[1].alpha, 0.6)
    near(state.tracker.empty.alpha, 0.6)
end)
test("settings sliders show and change the opacities", function()
    local state = fixture({db = {tracked = {43}}})
    local background, rows = state.settings.opacity[1], state.settings.opacity[2]
    equal(background.template, "MinimalSliderTemplate")
    equal(background.label.text, "Background opacity: 50%")
    equal(rows.label.text, "Skill rows opacity: 90%")
    equal(background.min, 0)
    equal(rows.min, 0.2)
    near(background.step, 0.05)
    equal(background.obeyStep, true)
    state.fire(background, "OnValueChanged", 0.25)
    near(state.wsk.db.backgroundAlpha, 0.25)
    near(state.tracker.backdropColor[4], 0.25, "the box updates at once")
    equal(background.label.text, "Background opacity: 25%")
    state.fire(rows, "OnValueChanged", 0.7)
    near(trackedRows(state)[1].alpha, 0.7)
    equal(rows.label.text, "Skill rows opacity: 70%")
end)
test("refreshing the settings page does not count as a user change", function()
    local state = fixture({db = {backgroundAlpha = 0.4}})
    local before = state.wsk.SetOpacity
    local calls = 0
    state.wsk.SetOpacity = function(...) calls = calls + 1 return before(...) end
    state.settings.OnRefresh()
    equal(calls, 0)
    near(state.settings.opacity[1].value, 0.4)
end)
test("the Settings Defaults button resets opacities only", function()
    local state = fixture({db = {tracked = {43}, locked = true, backgroundAlpha = 0.1, contentAlpha = 0.3,
        position = {point = "TOP", relativePoint = "TOP", x = 1, y = 2}}})
    state.settings.OnDefault()
    near(state.wsk.db.backgroundAlpha, 0.5)
    near(state.wsk.db.contentAlpha, 0.9)
    equal(state.settings.opacity[1].label.text, "Background opacity: 50%")
    same(state.wsk.GetTracked(), {43}, "tracked skills kept")
    equal(state.wsk.db.locked, true)
    equal(state.wsk.db.position.point, "TOP")
end)

-- Slash commands -----------------------------------------------------------------

test("/wsk and /weaponskills are WSK's commands, and /wsf is never touched", function()
    local state = fixture()
    equal(state.env.SLASH_WEAPONSKILLSFOREVER1, "/wsk")
    equal(state.env.SLASH_WEAPONSKILLSFOREVER2, "/weaponskills")
    equal(state.env.SLASH_WEAPONSKILLSFOREVER3, nil)
    for key, value in pairs(state.env) do
        if type(key) == "string" and key:find("^SLASH_") then
            equal(value == "/wsf", false, key .. " must not be /wsf")
        end
    end
end)
for _, input in ipairs({"", "  ", "options"}) do
    local message = input
    test("'" .. message .. "' opens the settings page through the slash command", function()
        local state = fixture()
        state.env.SlashCmdList.WEAPONSKILLSFOREVER(message)
        same(state.settingsOpened, {77})
        equal(state.tracker:IsShown(), true, "no longer toggles the box")
        equal(#state.messages, 0)
    end)
end
test("/wsk opens the page under Dyre's AddOns with the toolkit", function()
    local state = fixture({toolkit = true})
    state.env.SlashCmdList.WEAPONSKILLSFOREVER("")
    same(state.toolkit.opened, {state.settingsCategory})
end)
test("/wsk does not open the settings in combat, and says so once", function()
    for _, toolkit in ipairs({false, true}) do
        local state = fixture({toolkit = toolkit})
        state.combat = true
        state.env.SlashCmdList.WEAPONSKILLSFOREVER("")
        same(state.settingsOpened, {})
        if toolkit then same(state.toolkit.opened, {}) end
        equal(#state.messages, 1)
        contains(state.messages[1], "WSK: The settings open out of combat.")
    end
end)
test("/wsk help lists the commands, also when WSK is unavailable", function()
    local state = fixture()
    state.wsk.HandleCommand("help")
    equal(#state.messages, 1)
    contains(state.messages[1], "/wsk (settings)")
    contains(state.messages[1], "/weaponskills works the same")
    state.wsk.available = false
    state.wsk.HandleCommand("help")
    contains(state.messages[2], "Use /wsk")
end)
test("another AddOn's /wsk is reported once at login, pointing to /weaponskills", function()
    local state = fixture({login = false, otherSlash = {OTHERADDON = {"/other", "/WSK"}}})
    state.emit("ADDON_LOADED", "WeaponSkillsForever")
    state.emit("PLAYER_LOGIN")
    local found = 0
    for _, message in ipairs(state.messages) do
        if message:find("also uses", 1, true) then
            found = found + 1
            equal(message, "WSK: Another AddOn (OTHERADDON) also uses /wsk. Use /weaponskills instead.")
        end
    end
    equal(found, 1)
    state.emit("SKILL_LINES_CHANGED")
    equal(#state.messages, 3 + found, "banner, ready, install line, and the conflict, once")
end)
test("another AddOn's /weaponskills points to /wsk; both taken gives no advice", function()
    local one = fixture({login = false, otherSlash = {OTHER = {"/weaponskills"}}})
    one.emit("ADDON_LOADED", "WeaponSkillsForever")
    one.emit("PLAYER_LOGIN")
    contains(one.messages[3], "WSK: Another AddOn (OTHER) also uses /weaponskills. Use /wsk instead.")
    local both = fixture({login = false, otherSlash = {OTHER = {"/wsk", "/weaponskills"}}})
    both.emit("ADDON_LOADED", "WeaponSkillsForever")
    both.emit("PLAYER_LOGIN")
    equal(both.messages[3], "WSK: Another AddOn (OTHER) also uses /wsk.")
    equal(both.messages[4], "WSK: Another AddOn (OTHER) also uses /weaponskills.")
end)
test("no conflict line when only WSK uses its commands", function()
    local state = fixture({login = false, otherSlash = {WEAPONSETSFOREVER = {"/wsf"}}})
    state.emit("ADDON_LOADED", "WeaponSkillsForever")
    state.emit("PLAYER_LOGIN")
    for _, message in ipairs(state.messages) do
        equal(message:find("also uses", 1, true), nil, message)
    end
end)

-- Secret values ----------------------------------------------------------------

local ALL_SECRET = {skillID = true, name = true, isHeader = true, isCollapsed = true, rank = true,
    maxRank = true, modifier = true, skillLineCategoryID = true, parentSkillLineID = true}

test("a secret modifier keeps the last known bonus (BugGrabber UI.lua:150)", function()
    local state = fixture({db = {tracked = {43}}})
    contains(rowsFor(state)[1].text, "(+5)")
    state.secret = {modifier = true}
    state.emit("SKILL_LINES_CHANGED")
    local row = rowsFor(state)[1]
    contains(row.text, "297 ")
    contains(row.text, "(+5)")
    same(state.wsk.GetTracked(), {43})
end)
test("a secret Defense bonus keeps the last known bonus", function()
    local state = fixture({db = {tracked = {95}}})
    state.defense = {280, 4}
    state.emit("SKILL_LINES_CHANGED")
    contains(rowsFor(state)[1].text, "(+4)")
    state.secretDefense = true
    state.emit("SKILL_LINES_CHANGED")
    contains(rowsFor(state)[1].text, "(+4)")
end)
test("secret ranks and caps show the last known values and are not pruned", function()
    local state = fixture({db = {tracked = {43, 44}}})
    state.secret = ALL_SECRET
    state.emit("SKILL_LINES_CHANGED")
    same(state.wsk.GetTracked(), {43, 44})
    local rows = rowsFor(state)
    equal(#rows, 2)
    equal(rows[1].value, 297)
    equal(rows[1].max, 300)
    same(rows[1].color, YELLOW)
    equal(rows[2].text, "120 / 300")
    state.wsk.HandleCommand("debug_skills")
    contains(state.messages[2], "<secret>")
end)
test("skills never seen plain stay tracked, and the box says the game hides them", function()
    local state = fixture({login = false, db = {tracked = {43}}})
    state.secret = ALL_SECRET
    state.emit("ADDON_LOADED", "WeaponSkillsForever")
    state.emit("PLAYER_LOGIN")
    equal(state.wsk.available, true)
    state.emit("SKILL_LINES_CHANGED")
    same(state.wsk.GetTracked(), {43}, "not pruned")
    state.tracker = state.env.WeaponSkillsForeverTracker
    equal(#trackedRows(state), 0)
    contains(state.tracker.empty.text, "hides skill values")
    state.secret = nil
    state.emit("SKILL_LINES_CHANGED")
    equal(#trackedRows(state), 1, "back when the values are plain")
    equal(state.tracker.empty.shown, false)
end)
test("an empty view still says to choose skills when nothing is hidden", function()
    local state = fixture({db = {tracked = {43}}})
    state.wsk.SetView("other")
    contains(state.tracker.empty.text, "Click the gear")
end)
test("a secret line count prunes nothing and lists nothing", function()
    local state = fixture({db = {tracked = {43}}})
    state.secretCount = true
    state.emit("SKILL_LINES_CHANGED")
    same(state.wsk.GetTracked(), {43})
    state.wsk.HandleCommand("debug_skills")
    contains(state.messages[1], "debug_skills lines=0")
end)
test("the setup panel and settings page open while values are secret", function()
    local state = fixture({db = {tracked = {43}}})
    state.secret = ALL_SECRET
    state.wsk.ToggleConfig()
    state.settings.OnRefresh()
    contains(state.config.count.text, "Weapons 1 of 6")
end)

-- Dyre's Toolkit -------------------------------------------------------------

local LOCK = "Lock the skill box position"

test("without Dyre's Toolkit the box keeps its own lock, drag, and page", function()
    local state = fixture()
    equal(state.wsk.toolkit, nil)
    equal(state.settingsCategory.parent, nil, "top-level page")
    equal(state.settingsRegistered, state.settingsCategory)
    equal(settingsChecks(state)[LOCK], state.settings.locked, "the settings page has the lock")
    same(state.settings.reset.points[1], {"TOPLEFT", 20, -140}, "reset below the lock")
    equal(state.config.lock ~= nil, true, "the gear panel has the lock")
    local label
    for _, child in ipairs(state.config.children) do
        if child.kind == "FontString" and child.text == LOCK then label = child end
    end
    equal(label ~= nil, true, "the gear panel's lock has its label")
    state.wsk.HandleCommand("lock")
    same(state.messages, {"WSK: Skill box locked."})
    state.wsk.HandleCommand("unlock")
    equal(state.messages[2], "WSK: Skill box unlocked. Drag it to move it.")
end)
test("a Dyre's Toolkit too old for contract 1 counts as missing", function()
    local state = fixture({toolkit = true, toolkitContract = 0})
    equal(state.wsk.toolkit, nil, "login asked for the install line (fixture)")
    equal(next(state.toolkit.movables), nil, "the box is not registered")
    equal(#state.toolkit.addons, 0)
    state.wsk.HandleCommand("unlock")
    equal(#state.toolkit.calls, 0)
end)
test("with Dyre's Toolkit, login registers WSK and says no install line", function()
    local state = fixture({toolkit = true})
    equal(state.wsk.toolkit, state.env.DyresToolkit)
    equal(#state.toolkit.addons, 1)
    local info = state.toolkit.addons[1]
    equal(info.addon, "WeaponSkillsForever")
    equal(info.title, "Weapon Skills Forever")
    equal(info.setLocked, state.wsk.ApplyLocked)
    equal(info.openSettings, state.wsk.OpenSettings)
    equal(type(state.toolkit.movables[state.tracker]), "function", "the box is registered to move")
end)
test("with Dyre's Toolkit, the box starts with the toolkit's lock", function()
    local locked = fixture({toolkit = true, db = {locked = false}})
    equal(locked.wsk.db.locked, true, "the toolkit starts locked")
    local unlocked = fixture({toolkit = true, toolkitUnlocked = true, db = {locked = true}})
    equal(unlocked.wsk.db.locked, false)
end)
test("with Dyre's Toolkit, the toolkit drags, snaps, and saves the box", function()
    local state = fixture({toolkit = true})
    state.fire(state.tracker, "OnDragStart")
    equal(state.tracker.moving, nil, "locked: the toolkit does not start a drag")
    state.fire(state.tracker, "OnDragStop")
    equal(state.wsk.db.position, nil, "nothing saved without a drag")
    state.wsk.HandleCommand("unlock")
    state.fire(state.tracker, "OnDragStart")
    equal(state.tracker.moving, true)
    state.fire(state.tracker, "OnDragStop")
    equal(state.tracker.moving, false)
    same(state.wsk.db.position, {point = "CENTER", relativePoint = "BOTTOMLEFT", x = 320, y = 256})
    same(state.toolkit.calls, {"BeginDrag", "EndDrag", "Unlock", "SetLocked", "BeginDrag", "EndDrag"})
end)
test("a position the toolkit saved is applied at login", function()
    local state = fixture({toolkit = true,
        db = {position = {point = "CENTER", relativePoint = "BOTTOMLEFT", x = 320, y = 256}}})
    same(state.tracker.points[#state.tracker.points], {"CENTER", state.env.UIParent, "BOTTOMLEFT", 320, 256})
end)
test("with Dyre's Toolkit, /wsk lock and unlock lock every Dyre's AddOn quietly", function()
    local state = fixture({toolkit = true})
    state.wsk.ToggleConfig()
    state.wsk.HandleCommand("unlock")
    equal(state.toolkit.locked, false)
    equal(state.wsk.db.locked, false)
    state.settings.OnRefresh()
    state.wsk.HandleCommand("lock")
    equal(state.toolkit.locked, true)
    equal(state.wsk.db.locked, true)
    same(state.messages, {}, "the toolkit says one line for all")
    same(state.toolkit.calls, {"Unlock", "SetLocked", "Lock", "SetLocked"})
end)
test("with Dyre's Toolkit, the settings page and gear panel have no lock checkbox", function()
    local state = fixture({toolkit = true})
    equal(state.settings.locked, nil)
    equal(state.config.lock, nil)
    for _, child in ipairs(state.settings.children) do
        equal(child.text == LOCK, false, "no lock label on the settings page")
    end
    for _, child in ipairs(state.config.children) do
        equal(child.kind == "CheckButton" and child.text == LOCK, false, "no lock in the gear panel")
        equal(child.text == LOCK, false, "no lock label in the gear panel")
    end
    equal(settingsChecks(state)["Show the skill box"] ~= nil, true, "show stays")
    same(state.settings.reset.points[1], {"TOPLEFT", 20, -112}, "reset moves up into the lock's place")
    state.fire(state.settings.reset, "OnClick")
    contains(state.messages[1], "default position")
end)
test("with Dyre's Toolkit, the gear panel drops the lock row", function()
    local plain, kit = fixture(), fixture({toolkit = true})
    equal(plain.config.height - kit.config.height, 28, "one row shorter")
    equal(kit.config.next.points[1][3] - plain.config.next.points[1][3], 28, "the pager moves up")
end)
test("another AddOn's unlock through the toolkit unlocks the box", function()
    local state = fixture({toolkit = true})
    state.wsk.ToggleConfig()
    state.env.DyresToolkit.Unlock()
    equal(state.wsk.db.locked, false)
    equal(#state.messages, 0)
end)
test("with Dyre's Toolkit, the settings page sits under Dyre's AddOns", function()
    local state = fixture({toolkit = true})
    equal(state.settingsCategory.parent, state.toolkit.home)
    equal(state.settingsCategory.name, "Weapon Skills Forever")
    equal(state.settingsCategory.frame, state.settings)
    equal(state.settingsRegistered, nil, "not a second top-level entry")
    state.wsk.HandleCommand("options")
    same(state.toolkit.opened, {state.settingsCategory}, "the toolkit opens it, never in combat")
    same(state.settingsOpened, {})
end)
test("with Dyre's Toolkit but no Settings API, /wsk options explains", function()
    local state = fixture({toolkit = true, settings = false})
    equal(state.settings, nil)
    state.wsk.HandleCommand("options")
    contains(state.messages[1], "settings page is unavailable")
    same(state.toolkit.opened, {})
end)
test("login reports a mixed install missing the toolkit lock functions", function()
    local state = fixture({login = false, toolkit = true})
    state.wsk.ApplyLocked = nil
    state.emit("ADDON_LOADED", "WeaponSkillsForever")
    state.emit("PLAYER_LOGIN")
    equal(state.wsk.available, false)
    contains(state.messages[2], "missing ApplyLocked")
    equal(#state.toolkit.addons, 0, "not registered with the toolkit")
end)

local failed = 0
for index, entry in ipairs(tests) do
    local ok, message = xpcall(entry.body, debug.traceback)
    if ok then
        io.write("ok ", index, " - ", entry.name, "\n")
    else
        failed = failed + 1
        io.write("not ok ", index, " - ", entry.name, "\n", tostring(message), "\n")
    end
end
io.write(string.format("\n%d tests: %d passed, %d failed\n", #tests, #tests - failed, failed))
io.write("Mock results do not establish in-client compatibility.\n")
os.exit(failed == 0 and 0 or 1)
