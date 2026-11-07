local _, addon = ...

local function limits()
    local constants = type(Constants) == "table" and Constants.MacroConsts or nil
    if type(constants) ~= "table" then constants = type(MacroConsts) == "table" and MacroConsts or {} end
    local account = MAX_ACCOUNT_MACROS or constants.MAX_ACCOUNT_MACROS
    local character = MAX_CHARACTER_MACROS or constants.MAX_CHARACTER_MACROS
    if type(account) ~= "number" or type(character) ~= "number" then return nil end
    return account, character
end

local function isEditable()
    if type(InCombatLockdown) ~= "function" then
        return nil, "无法确认战斗状态，请稍后重试。"
    end
    if InCombatLockdown() then return nil, "战斗中无法管理宏，请脱战后重试。" end
    return true
end

local function readMacro(index, accountMax)
    local ok, name, icon, body = pcall(GetMacroInfo, index)
    if not ok then return nil, "无法读取宏，请稍后刷新。" end
    if not name then return nil end
    if type(name) ~= "string" or (body ~= nil and type(body) ~= "string") then
        return nil, "客户端返回了无法识别的宏内容。"
    end
    return { index = index, name = name, icon = icon, body = body or "", perCharacter = index > accountMax }
end

function addon.ListMacros()
    if type(GetMacroInfo) ~= "function" or type(GetNumMacros) ~= "function" then
        return nil, nil, "当前客户端无法读取游戏宏。"
    end
    local accountMax, characterMax = limits()
    if not accountMax then return nil, nil, "无法读取宏栏容量。" end
    local ok, account, character = pcall(GetNumMacros)
    if not ok or type(account) ~= "number" or type(character) ~= "number"
        or account < 0 or account > accountMax or character < 0 or character > characterMax then
        return nil, nil, "无法读取宏栏数量，请稍后重试。"
    end
    local entries = {}
    local function append(index)
        local entry, err = readMacro(index, accountMax)
        if err then return nil, err end
        if entry then entries[#entries + 1] = entry end
        return true
    end
    for index = 1, accountMax do
        local success, err = append(index)
        if not success then return nil, nil, err end
    end
    for index = accountMax + 1, accountMax + characterMax do
        local success, err = append(index)
        if not success then return nil, nil, err end
    end
    if #entries ~= account + character then
        return nil, nil, "宏列表正在变化或无法完整读取，请刷新后重试。"
    end
    return entries, { account = account, character = character, accountMax = accountMax, characterMax = characterMax }
end

function addon.ResolveMacro(snapshot)
    local accountMax, characterMax = limits()
    if not accountMax or type(GetMacroInfo) ~= "function" then return nil, "无法读取游戏宏，请刷新后重试。" end
    if type(snapshot) ~= "table" or type(snapshot.index) ~= "number" or snapshot.index % 1 ~= 0
        or snapshot.index < 1 or snapshot.index > accountMax + characterMax
        or type(snapshot.name) ~= "string" or type(snapshot.body) ~= "string"
        or type(snapshot.perCharacter) ~= "boolean"
        or (snapshot.index > accountMax) ~= snapshot.perCharacter then
        return nil, "没有可操作的宏，请重新选择。"
    end
    local current, err = readMacro(snapshot.index, accountMax)
    if err then return nil, err end
    if not current or current.name ~= snapshot.name or current.icon ~= snapshot.icon or current.body ~= snapshot.body then
        return nil, "宏列表或内容已变化，请刷新后重新选择。"
    end
    return snapshot.index
end

local function validateName(name)
    if type(name) ~= "string" then return nil, "请输入宏名称。" end
    name = name:match("^%s*(.-)%s*$")
    if name == "" then return nil, "请输入宏名称。" end
    local _, count = name:gsub("[^\128-\191]", "")
    if name:find("[\001-\031\127]") or count > 16 then
        return nil, "宏名称不能包含控制字符，且不能超过 16 个字符。"
    end
    return name
end

function addon.UpdateExistingMacro(snapshot, newName, newBody)
    local editable, err = isEditable()
    if not editable then return nil, err end
    local index
    index, err = addon.ResolveMacro(snapshot)
    if not index then return nil, err end
    if type(EditMacro) ~= "function" then return nil, "当前客户端无法编辑宏。" end
    local name
    name, err = validateName(newName)
    if not name then return nil, err end
    if type(newBody) ~= "string" or #newBody > 255 then
        return nil, "宏内容不能超过 255 字节。"
    end
    if name ~= snapshot.name then
        local entries, counts
        entries, counts, err = addon.ListMacros()
        if not entries then return nil, err end
        for _, entry in ipairs(entries) do
            if entry.index ~= index and entry.name:lower() == name:lower() then
                return nil, "已有同名宏，请换一个名称。"
            end
        end
    end
    if name == snapshot.name and newBody == snapshot.body then return snapshot, "宏内容没有变化。" end
    index, err = addon.ResolveMacro(snapshot)
    if not index then return nil, err end

    -- nil preserves the original icon, including the game's dynamic question-mark icon.
    local ok, newIndex = pcall(EditMacro, index, name ~= snapshot.name and name or nil, nil, newBody)
    if not ok then return nil, "保存未成功，请打开游戏宏界面检查。" end
    local accountMax = limits()
    if type(newIndex) ~= "number" or not accountMax then
        return nil, "客户端未确认保存结果，请刷新宏列表检查。"
    end
    local saved, readError = readMacro(newIndex, accountMax)
    if readError then return nil, readError end
    if not saved or saved.name ~= name or saved.body ~= newBody or saved.perCharacter ~= snapshot.perCharacter then
        return nil, "客户端未确认保存结果，请刷新宏列表检查。"
    end
    return saved, "宏已保存。"
end

function addon.DeleteExistingMacro(snapshot)
    local editable, err = isEditable()
    if not editable then return nil, err end
    local index
    index, err = addon.ResolveMacro(snapshot)
    if not index then return nil, err end
    if type(DeleteMacro) ~= "function" or type(GetNumMacros) ~= "function" then
        return nil, "当前客户端无法删除宏。"
    end
    local beforeOK, beforeAccount, beforeCharacter = pcall(GetNumMacros)
    if not beforeOK or type(beforeAccount) ~= "number" or type(beforeCharacter) ~= "number" then
        return nil, "无法读取宏栏数量，请刷新后重试。"
    end
    index, err = addon.ResolveMacro(snapshot)
    if not index then return nil, err end
    local ok = pcall(DeleteMacro, index)
    if not ok then return nil, "删除未成功，请打开游戏宏界面检查。" end
    local afterOK, afterAccount, afterCharacter = pcall(GetNumMacros)
    if not afterOK or type(afterAccount) ~= "number" or type(afterCharacter) ~= "number"
        or afterAccount ~= beforeAccount - (snapshot.perCharacter and 0 or 1)
        or afterCharacter ~= beforeCharacter - (snapshot.perCharacter and 1 or 0) then
        return nil, "客户端未确认删除结果，请刷新宏列表检查。"
    end
    return true, "宏已删除。"
end

function addon.PickupExistingMacro(snapshot)
    local editable, err = isEditable()
    if not editable then return nil, err end
    local index
    index, err = addon.ResolveMacro(snapshot)
    if not index then return nil, err end
    if type(PickupMacro) ~= "function" or type(GetCursorInfo) ~= "function" then
        return nil, "当前客户端无法拾取宏，请使用游戏宏界面。"
    end
    local cursorOK, kind = pcall(GetCursorInfo)
    if not cursorOK then return nil, "无法确认鼠标状态，请重试。" end
    if kind then return nil, "请先放下鼠标当前拾取的内容。" end
    local ok = pcall(PickupMacro, index)
    if not ok then return nil, "无法拾取宏，请使用游戏宏界面。" end
    local checked, cursorKind, cursorIndex = pcall(GetCursorInfo)
    if not checked or cursorKind ~= "macro" or cursorIndex ~= index then
        return nil, "客户端未确认拾取，请检查鼠标或游戏宏界面。"
    end
    return true, "已拾取宏，请点击动作条放置。"
end
