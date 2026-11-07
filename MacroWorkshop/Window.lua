local _, addon = ...
local frame
local modes = {
    { key = "normal", text = "普通施法" },
    { key = "attack", text = "自动攻击" },
    { key = "focus", text = "焦点施法" },
    { key = "mouseover", text = "鼠标指向" },
    { key = "self", text = "对自己施法" },
}

local function label(parent, text, x, y, style)
    local value = parent:CreateFontString(nil, "OVERLAY", style or "GameFontHighlight")
    value:SetPoint("TOPLEFT", x, -y)
    value:SetText(text)
    return value
end

local function button(parent, text, x, y, width, onClick)
    local value = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    value:SetPoint("TOPLEFT", x, -y)
    value:SetSize(width, 24)
    value:SetText(text)
    value:SetScript("OnClick", onClick)
    return value
end

local function field(parent, x, y, width)
    local value = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    value:SetPoint("TOPLEFT", x, -y)
    value:SetSize(width, 24)
    value:SetAutoFocus(false)
    value:SetScript("OnEscapePressed", value.ClearFocus)
    return value
end

local function getSpellInfo(value)
    if not C_Spell or not C_Spell.GetSpellInfo then return nil end
    local ok, info = pcall(C_Spell.GetSpellInfo, tonumber(value) or value)
    if ok and type(info) == "table" and info.name then return info end
end

local function refresh()
    frame.createdIndex = nil
    local body, err = addon.BuildMacro(frame.spell:GetText(), frame.mode, frame.fallback:GetChecked())
    frame.preview:SetText(body or "")
    frame.preview:ClearFocus()
    if err then frame.status:SetText(err) else frame.status:SetText("") end
    for _, item in ipairs(modes) do
        frame.modeButtons[item.key]:SetText((frame.mode == item.key and "● " or "") .. item.text)
    end
    local conditional = frame.mode == "focus" or frame.mode == "mouseover"
    frame.fallback:SetEnabled(conditional)
    frame.fallbackLabel:SetTextColor(conditional and 1 or 0.5, conditional and 1 or 0.5, conditional and 1 or 0.5)
end

local function setSpell(info)
    frame.spell:SetText(info.name)
    frame.name:SetText(info.name)
    frame.icon:SetTexture(info.iconID or 134400)
    frame.spell:ClearFocus()
    refresh()
    frame.status:SetText("已选择技能：" .. info.name)
end

local function receiveSpell()
    if InCombatLockdown() then frame.status:SetText("战斗中无法编辑，请脱战后重试。"); return end
    local kind, _, _, spellID = GetCursorInfo()
    if not kind then return end
    if kind ~= "spell" or type(spellID) ~= "number" then
        frame.status:SetText("请从技能书拖入技能，或手动填写技能名称。")
        return
    end
    local info = getSpellInfo(spellID)
    if not info then frame.status:SetText("无法识别该技能，请手动填写技能名称。"); return end
    ClearCursor()
    setSpell(info)
end

local function createWindow()
    local f = CreateFrame("Frame", "MacroWorkshopFrame", UIParent, "BackdropTemplate")
    frame = f
    f:SetSize(510, 440)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(0.065, 0.06, 0.06, 0.98)
    f:SetBackdropBorderColor(0.44, 0.38, 0.27)
    f:Hide()
    f.mode = "normal"
    f.modeButtons = {}
    label(f, "宏工坊", 18, 16, "GameFontNormalLarge")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT")
    close:SetScript("OnClick", function() f:Hide() end)

    label(f, "技能", 18, 55, "GameFontNormal")
    local slot = CreateFrame("Button", nil, f)
    slot:SetPoint("TOPLEFT", 20, -78)
    slot:SetSize(40, 40)
    local background = slot:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.2, 0.18, 0.15, 1)
    f.icon = slot:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexture(134400)
    slot:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    slot:SetScript("OnReceiveDrag", receiveSpell)
    slot:SetScript("OnClick", receiveSpell)
    label(f, "拖入技能，或输入技能名称 / ID 后按回车", 76, 62, "GameFontHighlightSmall")
    f.spell = field(f, 80, 84, 245)
    f.spell:SetScript("OnTextChanged", function(_, userInput)
        if userInput then f.icon:SetTexture(134400); refresh() end
    end)
    f.spell:SetScript("OnEnterPressed", function(self)
        local info = getSpellInfo(self:GetText())
        if info then setSpell(info) else
            self:ClearFocus()
            refresh()
            f.status:SetText("未识别技能；可填写游戏中的准确技能名称。")
        end
    end)

    label(f, "宏类型", 18, 132, "GameFontNormal")
    for i, item in ipairs(modes) do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        f.modeButtons[item.key] = button(f, item.text, 18 + col * 155, 155 + row * 29, 145, function()
            f.mode = item.key
            refresh()
        end)
    end
    f.fallback = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    f.fallback:SetPoint("TOPLEFT", 16, -215)
    f.fallback:SetSize(24, 24)
    f.fallback:SetScript("OnClick", refresh)
    f.fallbackLabel = label(f, "目标无效时按默认方式施法", 42, 221, "GameFontHighlightSmall")

    label(f, "宏预览（点击后可选中复制）", 18, 249, "GameFontNormal")
    local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 18, -271)
    box:SetSize(474, 64)
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    box:SetBackdropColor(0.02, 0.02, 0.02, 1)
    box:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    f.preview = CreateFrame("EditBox", nil, box)
    f.preview:SetPoint("TOPLEFT", 8, -6)
    f.preview:SetSize(458, 52)
    f.preview:SetFontObject(ChatFontNormal)
    f.preview:SetMultiLine(true)
    f.preview:SetAutoFocus(false)
    f.preview:SetScript("OnEscapePressed", f.preview.ClearFocus)
    f.preview:SetScript("OnTextChanged", function(_, userInput)
        if userInput then refresh() end
    end)

    label(f, "宏名称", 18, 351, "GameFontNormal")
    f.name = field(f, 79, 347, 140)
    f.name:SetScript("OnTextChanged", function(_, userInput)
        if userInput then f.createdIndex = nil end
    end)
    f.character = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    f.character:SetPoint("TOPLEFT", 231, -347)
    f.character:SetSize(24, 24)
    f.character:SetChecked(true)
    f.character:SetScript("OnClick", function() f.createdIndex = nil end)
    label(f, "仅当前角色", 257, 353, "GameFontHighlightSmall")

    f.status = label(f, "", 18, 384, "GameFontHighlightSmall")
    f.status:SetWidth(290)
    f.status:SetJustifyH("LEFT")
    button(f, "创建宏", 314, 378, 80, function()
        f.createdIndex = nil
        local index, message = addon.CreateMacroSafe(f.spell:GetText(), f.mode, not not f.fallback:GetChecked(), f.name:GetText(), not not f.character:GetChecked())
        if index then
            f.createdIndex = index
            f.createdName, _, f.createdBody = GetMacroInfo(index)
        end
        f.status:SetText(message or (index and "宏已创建。" or "创建失败。"))
    end)
    button(f, "拾取宏", 404, 378, 80, function()
        if InCombatLockdown() then f.status:SetText("请脱战后拾取宏。"); return end
        if not f.createdIndex then f.status:SetText("请先创建宏。"); return end
        local name, _, body = GetMacroInfo(f.createdIndex)
        if name ~= f.createdName or body ~= f.createdBody then
            f.status:SetText("宏列表已变化，请从 /macro 中拾取。")
            f.createdIndex = nil
            return
        end
        PickupMacro(f.createdIndex)
        f.status:SetText("已拾取宏，请点击动作条放置。")
    end)
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:SetScript("OnEvent", function(self) self:Hide() end)
    refresh()
end

SLASH_MACROWORKSHOP1 = "/mw"
SLASH_MACROWORKSHOP2 = "/macroworkshop"
SlashCmdList.MACROWORKSHOP = function()
    if InCombatLockdown() then
        print("宏工坊：请脱战后打开。")
        return
    end
    if not frame then createWindow() end
    if frame:IsShown() then frame:Hide() else frame:Show(); refresh() end
end
