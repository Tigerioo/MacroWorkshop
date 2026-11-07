local _, addon = ...

local MAX_BODY_BYTES = 255
local MAX_NAME_CHARACTERS = 16
local QUESTION_MARK_ICON = 134400

local function trim(value)
    if type(value) ~= "string" then
        return ""
    end
    return value:match("^%s*(.-)%s*$")
end

local function characterCount(value)
    local _, count = value:gsub("[^\128-\191]", "")
    return count
end

function addon.BuildMacro(spellName, mode, fallback)
    spellName = trim(spellName)
    if spellName == "" then
        return nil, "请先拖入技能或输入技能名称。"
    end
    if spellName:match("^%d+$") then
        return nil, "请按回车确认技能 ID，或输入技能名称。"
    end
    if spellName:find("[\001-\031\127]") or spellName:find("[%[%];]") then
        return nil, "技能名称包含不能用于宏的字符，请检查后重试。"
    end

    local cast
    if mode == "normal" or mode == "attack" then
        cast = "/cast " .. spellName
    elseif mode == "self" then
        cast = "/cast [@player] " .. spellName
    elseif mode == "focus" or mode == "mouseover" then
        local target = mode == "focus" and "focus" or "mouseover"
        cast = "/cast [@" .. target .. ",exists,nodead]" .. (fallback and "[]" or "") .. " " .. spellName
    else
        return nil, "请选择宏模板。"
    end

    local body = "#showtooltip\n"
    if mode == "attack" then
        body = body .. "/startattack\n"
    end
    body = body .. cast
    if #body > MAX_BODY_BYTES then
        return nil, "宏内容超过 255 字节，请缩短技能名称。"
    end
    return body
end

local function macroLimits()
    local constants = type(Constants) == "table" and Constants.MacroConsts or nil
    if type(constants) ~= "table" then
        constants = type(MacroConsts) == "table" and MacroConsts or {}
    end
    local accountMax = MAX_ACCOUNT_MACROS or constants.MAX_ACCOUNT_MACROS
    local characterMax = MAX_CHARACTER_MACROS or constants.MAX_CHARACTER_MACROS
    if type(accountMax) ~= "number" or type(characterMax) ~= "number" then
        return nil, nil
    end
    return accountMax, characterMax
end

function addon.CreateMacroSafe(spellName, mode, fallback, macroName, perCharacter)
    local body, bodyError = addon.BuildMacro(spellName, mode, fallback)
    if not body then
        return nil, bodyError
    end

    macroName = trim(macroName)
    if macroName == "" then
        return nil, "请输入宏名称。"
    end
    if macroName:find("[\001-\031\127]") or characterCount(macroName) > MAX_NAME_CHARACTERS then
        return nil, "宏名称不能包含换行，且不能超过 16 个字符。"
    end
    if type(InCombatLockdown) ~= "function" then
        return nil, "无法确认战斗状态，请复制预览到游戏的宏界面。"
    end
    if InCombatLockdown() then
        return nil, "战斗中无法创建宏，请脱战后重试。"
    end
    if type(GetNumMacros) ~= "function" or type(GetMacroInfo) ~= "function" or type(CreateMacro) ~= "function" then
        return nil, "当前客户端无法调用宏接口，请复制预览到游戏的宏界面。"
    end

    local accountMax, characterMax = macroLimits()
    if not accountMax then
        return nil, "无法确认宏栏容量，请复制预览到游戏的宏界面。"
    end
    local accountCount, characterCount = GetNumMacros()
    if type(accountCount) ~= "number" or type(characterCount) ~= "number" then
        return nil, "无法读取宏栏，请稍后重试。"
    end

    for index = 1, accountMax + characterMax do
        local name, _, existingBody = GetMacroInfo(index)
        if name and name:lower() == macroName:lower() then
            local sameScope = (index > accountMax) == (perCharacter == true)
            if sameScope and existingBody == body then
                return index, "已有相同的宏，可直接拾取。"
            end
            return nil, "已有同名宏；为保护原有内容，请换一个名称。"
        end
    end

    if (perCharacter and characterCount >= characterMax) or (not perCharacter and accountCount >= accountMax) then
        return nil, "所选宏栏已满，请先在游戏宏界面腾出位置。"
    end

    local ok, index = pcall(CreateMacro, macroName, QUESTION_MARK_ICON, body, perCharacter == true)
    if not ok or type(index) ~= "number" or index <= 0 then
        return nil, "创建未成功，请复制预览到游戏的宏界面。"
    end
    local createdName, _, createdBody = GetMacroInfo(index)
    if not createdName or createdBody ~= body then
        return nil, "客户端未确认宏内容，请打开游戏宏界面检查。"
    end
    return index, "宏已创建，可拾取后放到动作条。"
end
