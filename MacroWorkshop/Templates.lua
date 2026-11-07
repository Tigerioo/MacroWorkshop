local _, addon = ...

-- Example skills are editable and must be checked against the player's client.
local templates = {
    { id = "normal", title = "普通施法", purpose = "攻击", spell = "背刺", mode = "normal" },
    { id = "attack", title = "自动攻击 + 技能", purpose = "攻击", spell = "背刺", mode = "attack" },
    { id = "focus", title = "焦点施法", purpose = "打断", spell = "脚踢", mode = "focus" },
    { id = "mouseover", title = "鼠标指向施法", purpose = "治疗", spell = "治疗术", mode = "mouseover", fallback = true },
    { id = "self", title = "对自己施法", purpose = "治疗", spell = "治疗术", mode = "self" },
    { id = "rogue-kick", title = "焦点打断", class = "ROGUE", purpose = "打断", spell = "脚踢", mode = "focus" },
    { id = "rogue-stealth", title = "潜行", class = "ROGUE", purpose = "潜行", spell = "潜行", mode = "normal" },
    { id = "warrior", title = "冲锋与自动攻击", class = "WARRIOR", purpose = "攻击", spell = "冲锋", mode = "attack" },
    { id = "paladin", title = "鼠标指向圣光术", class = "PALADIN", purpose = "治疗", spell = "圣光术", mode = "mouseover", fallback = true },
    { id = "hunter", title = "焦点奥术射击", class = "HUNTER", purpose = "攻击", spell = "奥术射击", mode = "focus" },
    { id = "priest", title = "鼠标指向真言术：盾", class = "PRIEST", purpose = "治疗", spell = "真言术：盾", mode = "mouseover", fallback = true },
    { id = "shaman", title = "鼠标指向治疗波", class = "SHAMAN", purpose = "治疗", spell = "治疗波", mode = "mouseover", fallback = true },
    { id = "mage", title = "焦点寒冰箭", class = "MAGE", purpose = "攻击", spell = "寒冰箭", mode = "focus" },
    { id = "warlock", title = "焦点暗影箭", class = "WARLOCK", purpose = "攻击", spell = "暗影箭", mode = "focus" },
    { id = "druid", title = "鼠标指向愈合", class = "DRUID", purpose = "治疗", spell = "愈合", mode = "mouseover", fallback = true },
}

function addon.GetTemplates(class, purpose)
    local result = {}
    for _, template in ipairs(templates) do
        if (not class or not template.class or template.class == class)
            and (not purpose or template.purpose == purpose) then
            local copy = {}
            for key, value in pairs(template) do copy[key] = value end
            result[#result + 1] = copy
        end
    end
    return result
end

addon.MacroTagOptions = {
    "通用", "战士", "圣骑士", "猎人", "盗贼", "牧师", "萨满", "法师", "术士", "德鲁伊",
    "战斗", "控制", "治疗", "辅助",
}
local validTags = {}
for _, tag in ipairs(addon.MacroTagOptions) do validTags[tag] = true end

-- No stable macro ID is exposed by the client. Tags intentionally exist only
-- during this session and are discarded as soon as the macro list changes.
local tagEntries = {}
local baseline

local function sameMacro(a, b, ignoreIndex)
    return a and b and (ignoreIndex or a.index == b.index)
        and a.name == b.name and a.icon == b.icon and a.body == b.body
        and a.perCharacter == b.perCharacter
end

function addon.InvalidateMacroTags()
    tagEntries, baseline = {}, nil
end

local function currentList()
    local entries, _, err = addon.ListMacros()
    if not entries then
        addon.InvalidateMacroTags()
        return nil, err
    end
    if baseline then
        local same = #baseline == #entries
        if same then
            for i, entry in ipairs(entries) do
                if not sameMacro(entry, baseline[i]) then same = false; break end
            end
        end
        if not same then addon.InvalidateMacroTags() end
    end
    return entries
end

local function uniqueSnapshot(entries, snapshot)
    local matches, exact = 0, false
    for _, entry in ipairs(entries) do
        if sameMacro(entry, snapshot, true) then
            matches = matches + 1
            if sameMacro(entry, snapshot) then exact = true end
        end
    end
    return matches == 1 and exact
end

local function copyTags(tags)
    local result = {}
    for _, tag in ipairs(tags) do result[#result + 1] = tag end
    return result
end

function addon.GetMacroTags(snapshot)
    local entries, err = currentList()
    if not entries then return nil, err end
    if not uniqueSnapshot(entries, snapshot) then
        return nil, "无法确认宏身份，请重新选择。"
    end
    return copyTags(tagEntries[snapshot.index] or {})
end

function addon.SetMacroTags(snapshot, tags)
    if type(tags) ~= "table" then return nil, "请选择有效的标签。" end
    local selected, seen = {}, {}
    for _, tag in ipairs(tags) do
        if not validTags[tag] then return nil, "请选择有效的标签。" end
        if not seen[tag] then selected[#selected + 1] = tag; seen[tag] = true end
    end
    local entries, err = currentList()
    if not entries then return nil, err end
    if not uniqueSnapshot(entries, snapshot) then
        return nil, "无法确认宏身份，请重新选择。"
    end
    baseline = entries
    tagEntries[snapshot.index] = selected
    return true
end
