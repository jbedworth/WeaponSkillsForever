local _, WSK = ...

-- The limit applies to each type separately: weapons and other skills.
WSK.MAX_TRACKED = 6
WSK.WEAPONS = "weapons"
WSK.OTHER = "other"
-- The client groups weapon skills (with Defense and Unarmed) under the Weapon
-- Skills header, category 6; a header's skillID is its skills' category.
local WEAPON_CATEGORY = 6
-- A skill within this many ranks of its cap shows as nearly capped.
WSK.NEAR_CAP_RANKS = 5

-- Skill categories never offered for tracking:
--   7  Class Skills: hidden by Blizzard's Skills panel too.
--   10 Languages: known languages are always at their cap, so there is
--      nothing to track. The ID comes from Classic skill data; confirm it in
--      client with /wsk debug_skills (category=).
local HIDDEN_CATEGORIES = {[7] = true, [10] = true}
-- Defense reports its bonus through UnitDefenseSkill, as in Blizzard's panel.
local DEFENSE_SKILL_ID = 95
local REQUIRED_APIS = {"GetNumSkillLines", "GetSkillLineInfo", "GetSkillLineInfoByID"}

function WSK.CheckCapabilities()
    if type(C_SkillInfo) ~= "table" then
        return false, "The skill API is unavailable on this client."
    end
    for _, name in ipairs(REQUIRED_APIS) do
        if type(C_SkillInfo[name]) ~= "function" then
            return false, "Required skill API is missing: " .. name
        end
    end
    return true
end

-- Secret values (the client's Midnight restrictions, seen in client on a
-- skill's modifier): never compare, do arithmetic on, concatenate, or print one.
function WSK.IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value) == true
end

-- For chat: a secret value is never printed.
function WSK.Describe(value)
    if WSK.IsSecret(value) then
        return "<secret>"
    end
    return tostring(value)
end

local LINE_FIELDS = {"skillID", "name", "isHeader", "isCollapsed", "rank", "maxRank", "modifier",
    "skillLineCategoryID", "parentSkillLineID"}
-- Each line's last plain values by skill ID, for the session: a secret field
-- takes its last known value, so the box keeps showing it.
local lastKnown = {}
local lastDefenseModifier

-- The number of skill lines, or 0 while the count is secret.
function WSK.CountSkillLines()
    local count = C_SkillInfo.GetNumSkillLines()
    if WSK.IsSecret(count) or type(count) ~= "number" then
        return 0
    end
    return count
end

-- A plain copy of a skill line: no secret values. line.unknown is set when a
-- secret field has no last known value; such a line is never trackable, but
-- is not proof that the skill is unlearned.
local function ReadLine(info, requestedID)
    if type(info) ~= "table" then
        return nil
    end
    local line, secret = {}, {}
    for _, field in ipairs(LINE_FIELDS) do
        local value = info[field]
        if WSK.IsSecret(value) then
            secret[#secret + 1] = field
        else
            line[field] = value
        end
    end
    local id = type(line.skillID) == "number" and line.skillID or requestedID
    local known = id and lastKnown[id]
    for _, field in ipairs(secret) do
        if known and known[field] ~= nil then
            line[field] = known[field]
        else
            line.unknown = true
        end
    end
    if id and not line.unknown then
        local copy = {}
        for _, field in ipairs(LINE_FIELDS) do
            copy[field] = line[field]
        end
        lastKnown[id] = copy
    end
    return line
end

function WSK.ReadSkillLine(index)
    return ReadLine(C_SkillInfo.GetSkillLineInfo(index))
end

-- Ranked skills only: single-rank lines (armor proficiencies, some languages)
-- have nothing to track. Child lines (parentSkillLineID ~= 0) repeat their
-- parent's name and rank; Blizzard's Skills panel lists only top-level lines.
local function IsTrackable(line)
    return type(line) == "table" and not line.unknown and not line.isHeader
        and (line.parentSkillLineID or 0) == 0
        and not HIDDEN_CATEGORIES[line.skillLineCategoryID]
        and type(line.skillID) == "number" and type(line.name) == "string"
        and type(line.rank) == "number" and type(line.maxRank) == "number"
        and line.maxRank > 1
end

local function Describe(line)
    local modifier = type(line.modifier) == "number" and line.modifier or 0
    if line.skillID == DEFENSE_SKILL_ID and type(UnitDefenseSkill) == "function" then
        local _, defenseModifier = UnitDefenseSkill("player")
        if WSK.IsSecret(defenseModifier) then
            defenseModifier = lastDefenseModifier
        elseif type(defenseModifier) == "number" then
            lastDefenseModifier = defenseModifier
        end
        if type(defenseModifier) == "number" then
            modifier = defenseModifier
        end
    end
    return {id = line.skillID, name = line.name, rank = line.rank,
        modifier = modifier, maxRank = line.maxRank, categoryID = line.skillLineCategoryID}
end

-- Returns {id, name, rank, modifier, maxRank} for a learned, ranked skill, or nil.
function WSK.GetSkill(id)
    local line = ReadLine(C_SkillInfo.GetSkillLineInfoByID(id), id)
    if not IsTrackable(line) then
        return nil
    end
    return Describe(line)
end

-- True only when the client says the character lacks the skill: a line with
-- secret values and no last known ones is kept.
function WSK.IsUnlearned(id)
    local line = ReadLine(C_SkillInfo.GetSkillLineInfoByID(id), id)
    return line == nil or (not line.unknown and not IsTrackable(line))
end

-- Learned ranked skills in client order, each with the header ("group") above it.
function WSK.ListTrackableSkills()
    local skills, group = {}, nil
    for index = 1, WSK.CountSkillLines() do
        local info = WSK.ReadSkillLine(index)
        if type(info) == "table" and info.isHeader then
            group = info.name
        elseif IsTrackable(info) then
            local skill = Describe(info)
            skill.group = group
            skills[#skills + 1] = skill
        end
    end
    return skills
end

function WSK.SkillType(skill)
    return skill.categoryID == WEAPON_CATEGORY and WSK.WEAPONS or WSK.OTHER
end

-- Each skill's position within its group, remembered for the session from the
-- last time the group was expanded, because a collapsed group's lines are not
-- listed by the client.
local groupOffsets = {}
-- Fraction of a line per remembered position; a group never has this many lines.
local OFFSET_SCALE = 1000
-- Each tracked skill's last order, for the session.
local lastOrder = {}

-- Returns the learned skills among ids in Skills tab order. A skill hidden
-- under a collapsed header takes its header's place, keeping its remembered
-- position in the group; one never seen expanded sorts by name after those.
function WSK.OrderSkills(ids)
    local position, headerPosition, header = {}, {}, nil
    for index = 1, WSK.CountSkillLines() do
        local info = WSK.ReadSkillLine(index)
        if type(info) ~= "table" or type(info.skillID) ~= "number" then
            -- Nothing to place: no line, or its ID is secret and not yet known.
        elseif info.isHeader then
            headerPosition[info.skillID] = index
            header = index
        else
            position[info.skillID] = index
            if header then
                groupOffsets[info.skillID] = index - header
            end
        end
    end
    local skills = {}
    for _, id in ipairs(ids) do
        local skill = WSK.GetSkill(id)
        if skill then
            local headerIndex = headerPosition[skill.categoryID]
            if position[id] then
                skill.order = position[id]
            elseif headerIndex then
                skill.order = headerIndex + (groupOffsets[id] or OFFSET_SCALE - 1) / OFFSET_SCALE
            else
                -- No line or header found (secret IDs): the last order seen.
                skill.order = lastOrder[id] or math.huge
            end
            lastOrder[id] = skill.order
            skills[#skills + 1] = skill
        end
    end
    table.sort(skills, function(left, right)
        if left.order ~= right.order then
            return left.order < right.order
        end
        return left.name < right.name
    end)
    return skills
end

-- Setup panel rows in client order: {kind = "header", name, index, collapsed}
-- and {kind = "skill", skill}. As on Blizzard's Skills tab, a collapsed group
-- shows only its header; the client does not list its skills until it is
-- expanded (tracked skills stay in the box, found by ID). Hidden categories,
-- and expanded groups with nothing to track, are left out.
function WSK.ListSetupEntries()
    local entries, group = {}, nil
    local function addGroup()
        if not group or (not group.collapsed and #group.skills == 0) then
            return
        end
        entries[#entries + 1] = {kind = "header", name = group.name, index = group.index,
            collapsed = group.collapsed}
        for _, skill in ipairs(group.skills) do
            entries[#entries + 1] = {kind = "skill", skill = skill}
        end
    end
    for index = 1, WSK.CountSkillLines() do
        local info = WSK.ReadSkillLine(index)
        if type(info) == "table" and info.isHeader then
            addGroup()
            group = nil
            if not HIDDEN_CATEGORIES[info.skillID] then
                group = {name = info.name, index = index, collapsed = info.isCollapsed == true,
                    skills = {}}
            end
        elseif group and IsTrackable(info) then
            group.skills[#group.skills + 1] = Describe(info)
        end
    end
    addGroup()
    return entries
end

-- Expanding or collapsing a header is the same action as clicking it on the
-- Skills tab; WSK does it only when the user clicks a header's +/- in the
-- setup panel.
function WSK.CanToggleHeaders()
    return type(C_SkillInfo.ExpandSkillHeader) == "function"
        and type(C_SkillInfo.CollapseSkillHeader) == "function"
end

function WSK.ExpandHeader(index)
    C_SkillInfo.ExpandSkillHeader(index)
end

function WSK.CollapseHeader(index)
    C_SkillInfo.CollapseSkillHeader(index)
end

-- "capped" at the cap, "near" within NEAR_CAP_RANKS of it, otherwise "low".
-- The base rank is compared, because bonuses do not count toward the cap.
function WSK.SkillStatus(rank, maxRank)
    if rank >= maxRank then
        return "capped"
    elseif rank >= maxRank - WSK.NEAR_CAP_RANKS then
        return "near"
    end
    return "low"
end
