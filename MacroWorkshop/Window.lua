local _, addon = ...
local frame, entry
local modes = {
    { key = "normal", text = "普通施法" }, { key = "attack", text = "自动攻击" },
    { key = "focus", text = "焦点施法" }, { key = "mouseover", text = "鼠标指向" },
    { key = "self", text = "对自己施法" },
}
local classes = {
    { nil, "全部" }, { "GENERAL", "通用" }, { "WARRIOR", "战士" }, { "PALADIN", "圣骑士" },
    { "HUNTER", "猎人" }, { "ROGUE", "盗贼" }, { "PRIEST", "牧师" }, { "SHAMAN", "萨满" },
    { "MAGE", "法师" }, { "WARLOCK", "术士" }, { "DRUID", "德鲁伊" },
}
local purposes = { { nil, "全部用途" }, { "攻击", "攻击" }, { "打断", "打断" },
    { "治疗", "治疗" }, { "辅助", "辅助" }, { "潜行", "潜行" } }
local generation = 0

local function label(parent, text, x, y, style)
    local value = parent:CreateFontString(nil, "OVERLAY", style or "GameFontHighlightSmall")
    value:SetPoint("TOPLEFT", x, -y)
    value:SetText(text)
    value:SetJustifyH("LEFT")
    return value
end

local function button(parent, text, x, y, width, action)
    local value = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    value:SetPoint("TOPLEFT", x, -y)
    value:SetSize(width, 24)
    value:SetText(text)
    value:SetScript("OnClick", action)
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

local function textBox(parent, x, y, width, height)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetPoint("TOPLEFT", x, -y)
    box:SetSize(width, height)
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    box:SetBackdropColor(0.02, 0.02, 0.02, 1)
    box:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -27, 6)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetSize(width - 36, height - 12)
    edit:SetFontObject(ChatFontNormal)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    scroll:SetScrollChild(edit)
    return edit
end

-- Only use indices provided by the active Blizzard UI, never guess across tabs.
local function selectedMacro()
    if not MacroFrame or not MacroFrame.IsShown or not MacroFrame:IsShown()
        or type(MacroFrame.GetSelectedIndex) ~= "function"
        or type(MacroFrame.GetMacroDataIndex) ~= "function"
        or not MacroFrameText or type(GetMacroInfo) ~= "function" then
        return nil, "请选择系统宏窗口中的宏。"
    end
    local ok, index = pcall(MacroFrame.GetSelectedIndex, MacroFrame)
    if not ok or type(index) ~= "number" then return nil, "请选择系统宏窗口中的宏。" end
    ok, index = pcall(MacroFrame.GetMacroDataIndex, MacroFrame, index)
    if not ok or type(index) ~= "number" then return nil, "无法确认当前宏，请使用系统宏窗口。" end
    local entries, _, err = addon.ListMacros()
    if not entries then return nil, err end
    local selected
    for _, item in ipairs(entries) do if item.index == index then selected = item; break end end
    if selected then
        local matches = 0
        for _, item in ipairs(entries) do
            if item.name == selected.name and item.icon == selected.icon and item.body == selected.body
                and item.perCharacter == selected.perCharacter then matches = matches + 1 end
        end
        if matches ~= 1 then return nil, "存在无法区分的相同宏，请先在系统窗口处理。" end
        return selected
    end
    return nil, "请选择系统宏窗口中的宏。"
end

local function sameMacro(a, b)
    return a and b and a.index == b.index and a.name == b.name and a.icon == b.icon
        and a.body == b.body and a.perCharacter == b.perCharacter
end

local function canEdit()
    if type(InCombatLockdown) ~= "function" or InCombatLockdown() then
        return nil, "战斗中无法修改宏，请脱战后重试。"
    end
    if MacroPopupFrame and MacroPopupFrame:IsShown() then return nil, "请先关闭系统图标选择器。" end
    return true
end

local function spellInfo(value)
    if not C_Spell or not C_Spell.GetSpellInfo then return nil end
    local ok, info = pcall(C_Spell.GetSpellInfo, tonumber(value) or value)
    if ok and type(info) == "table" and type(info.name) == "string" then return info end
end

local function refreshPreview()
    if not frame then return end
    local body, err = addon.BuildMacro(frame.spell:GetText(), frame.mode, frame.fallback:GetChecked())
    frame.body = body
    frame.preview:SetText(body or "")
    frame.preview:ClearFocus()
    frame.hint:SetText(err or "")
    frame.modeButton:SetText("类型：" .. (frame.modeName or "普通施法"))
    frame.fallback:SetEnabled(frame.mode == "focus" or frame.mode == "mouseover")
end

local function getFiltered()
    local class, purpose = classes[frame.classIndex][1], purposes[frame.purposeIndex][1]
    local queryClass = class
    if class == "GENERAL" then queryClass = nil end
    local result = addon.GetTemplates(queryClass, purpose)
    if class ~= "GENERAL" then return result end
    local general = {}
    for _, item in ipairs(result) do if not item.class then general[#general + 1] = item end end
    return general
end

local function updateTemplates()
    local f = frame
    local items = getFiltered()
    local pages = math.max(1, math.ceil(#items / 4))
    f.templatePage = math.max(1, math.min(f.templatePage, pages))
    f.classButton:SetText("分类：" .. classes[f.classIndex][2])
    f.purposeButton:SetText(purposes[f.purposeIndex][2])
    f.pageText:SetText(f.templatePage .. " / " .. pages)
    for i, row in ipairs(f.templateRows) do
        local item = items[(f.templatePage - 1) * 4 + i]
        row.item = item
        if item then
            row:SetText((f.template == item.id and "● " or "") .. item.title)
            row:Show()
        else row:Hide() end
    end
    f.emptyTemplates:SetShown(#items == 0)
end

local function updateTags()
    local f = frame
    local selected = selectedMacro()
    local tags, err
    if selected then tags, err = addon.GetMacroTags(selected) end
    local lookup = {}
    for _, tag in ipairs(tags or {}) do lookup[tag] = true end
    f.tagTarget:SetText(selected and ("当前：" .. selected.name .. (selected.perCharacter and "（角色）" or "（通用）"))
        or "请在系统窗口选择宏")
    f.tagNote:SetText(err or "标签仅本次会话有效；宏变化或重载后需重新分类。")
    local options = addon.MacroTagOptions or {}
    local pages = math.max(1, math.ceil(#options / 8))
    f.tagPage = math.max(1, math.min(f.tagPage, pages))
    f.tagPageText:SetText(f.tagPage .. " / " .. pages)
    for i, row in ipairs(f.tagRows) do
        local tag = options[(f.tagPage - 1) * 8 + i]
        row.tag = tag
        if tag then row:SetText((lookup[tag] and "● " or "") .. tag); row:Show() else row:Hide() end
    end
end

local function updateTab()
    local f = frame
    f.templatePanel:SetShown(f.tab == "templates")
    f.skillPanel:SetShown(f.tab == "skill")
    f.tagPanel:SetShown(f.tab == "tags")
    f.templateTab:SetText((f.tab == "templates" and "● " or "") .. "预设模板")
    f.skillTab:SetText((f.tab == "skill" and "● " or "") .. "按技能生成")
    f.tagTab:SetText((f.tab == "tags" and "● " or "") .. "宏标签")
    if f.tab == "templates" then updateTemplates() elseif f.tab == "tags" then updateTags() end
end

local function setStatus(text)
    frame.status:SetText(text or "")
end

local function createConfirm(parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetAllPoints(parent)
    f:SetFrameLevel(parent:GetFrameLevel() + 10)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(0.055, 0.05, 0.045, 0.99)
    f:SetBackdropBorderColor(0.55, 0.43, 0.25, 1)
    f:EnableMouse(true)
    f:Hide()
    f.title = label(f, "", 16, 18, "GameFontNormal")
    local note = label(f, "确认后替换系统编辑框；系统可能在切换或关闭时自动保存。", 16, 45)
    note:SetWidth(405)
    label(f, "当前编辑内容", 16, 80, "GameFontNormal")
    f.before = textBox(f, 16, 101, 405, 130)
    label(f, "将填入的内容", 16, 244, "GameFontNormal")
    f.after = textBox(f, 16, 265, 405, 130)
    for _, edit in ipairs({ f.before, f.after }) do
        edit:SetScript("OnTextChanged", function(self, userInput)
            if userInput then self:SetText(self.original or "") end
        end)
    end
    f.warning = label(f, "", 16, 411)
    f.warning:SetWidth(405)
    button(f, "取消", 218, 464, 90, function() f:Hide() end)
    button(f, "确认填入", 320, 464, 100, function()
        local editable, err = canEdit()
        local current = selectedMacro()
        if not editable or generation ~= f.generation or not sameMacro(current, f.target)
            or not MacroFrameText or MacroFrameText:GetText() ~= f.originalText then
            f.warning:SetText(err or "宏或编辑内容已变化，请取消后重新确认。")
            return
        end
        MacroFrameText:SetText(f.generated)
        -- The system's OnTextChanged commonly marks only user input; mark the frame explicitly.
        MacroFrame.textChanged = true
        f:Hide()
        setStatus("已填入系统编辑框；系统可能自动保存。")
    end)
    return f
end

local function startCompare()
    local f = frame
    local editable, err = canEdit()
    if not editable then setStatus(err); return end
    if not f.body then setStatus("请先生成有效的宏预览。"); return end
    local target
    target, err = selectedMacro()
    if not target then setStatus(err); return end
    local current = MacroFrameText:GetText()
    local c = f.confirm
    c.target, c.originalText, c.generated, c.generation = target, current, f.body, generation
    c.title:SetText("替换：" .. target.name .. (target.perCharacter and "（当前角色）" or "（账号通用）"))
    c.before.original, c.after.original = current, f.body
    c.before:SetText(current)
    c.after:SetText(f.body)
    c.warning:SetText("请核对当前内容；取消不会修改系统编辑框。")
    c:Show()
end

local function createMacro()
    local f = frame
    local editable, err = canEdit()
    if not editable then setStatus(err); return end
    local target = selectedMacro()
    if MacroFrameText and MacroFrameText:IsShown() and not target then
        setStatus("无法确认系统当前宏，请先处理编辑框中的内容。")
        return
    end
    if target and MacroFrameText:GetText() ~= target.body then
        setStatus("系统宏编辑框有未处理内容，请先在系统窗口处理后再新建。")
        return
    end
    local index, message = addon.CreateMacroSafe(f.spell:GetText(), f.mode, not not f.fallback:GetChecked(),
        f.name:GetText(), not not f.character:GetChecked())
    setStatus(message or (index and "宏已创建，请在系统窗口中查看。" or "创建失败，请复制预览。"))
end

local function receiveSpell()
    local editable, err = canEdit()
    if not editable then setStatus(err); return end
    if type(GetCursorInfo) ~= "function" then setStatus("请手动输入技能名称。" ); return end
    local kind, _, _, spellID = GetCursorInfo()
    if not kind then return end
    if kind ~= "spell" or type(spellID) ~= "number" then setStatus("请拖入技能或输入技能名称。" ); return end
    local info = spellInfo(spellID)
    if not info then setStatus("无法识别技能，请输入技能名称。" ); return end
    ClearCursor()
    frame.spell:SetText(info.name)
    frame.name:SetText(info.name)
    frame.icon:SetTexture(info.iconID or 134400)
    refreshPreview()
    setStatus("已选择技能：" .. info.name)
end

local function filterTags()
    local f = frame
    local options = addon.MacroTagOptions or {}
    local tag = options[f.tagFilter]
    f.filterButton:SetText("筛选：" .. (tag or "全部"))
    local entries, _, err = addon.ListMacros()
    if not entries then f.filterResult:SetText(err or "无法读取宏。"); return end
    local names = {}
    for _, item in ipairs(entries) do
        local tags = addon.GetMacroTags(item)
        local matches = not tag
        for _, value in ipairs(tags or {}) do if value == tag then matches = true end end
        if matches then names[#names + 1] = item.name .. (item.perCharacter and "（角色）" or "（通用）") end
    end
    f.filterResult:SetText(#names > 0 and table.concat(names, "、") or "没有匹配的宏")
end

local function createWindow()
    local f = CreateFrame("Frame", "MacroWorkshopFrame", MacroFrame, "BackdropTemplate")
    frame = f
    f:SetSize(438, 555)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(0.065, 0.06, 0.06, 0.98)
    f:SetBackdropBorderColor(0.44, 0.38, 0.27)
    f:Hide()
    f.mode, f.modeName, f.modeIndex = "normal", "普通施法", 1
    f.tab, f.classIndex, f.purposeIndex = "templates", 1, 1
    f.templatePage, f.tagPage, f.tagFilter = 1, 1, 0
    label(f, "宏工坊", 16, 15, "GameFontNormalLarge")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT")
    close:SetScript("OnClick", function() f.wanted = false; f:Hide() end)
    f.templateTab = button(f, "预设模板", 16, 43, 126, function() f.tab = "templates"; updateTab() end)
    f.skillTab = button(f, "按技能生成", 149, 43, 126, function() f.tab = "skill"; updateTab() end)
    f.tagTab = button(f, "宏标签", 282, 43, 126, function() f.tab = "tags"; updateTab() end)

    local templatePanel = CreateFrame("Frame", nil, f)
    templatePanel:SetAllPoints()
    f.templatePanel = templatePanel
    f.classButton = button(templatePanel, "", 16, 75, 145, function()
        f.classIndex = f.classIndex % #classes + 1; f.templatePage = 1; updateTemplates()
    end)
    f.purposeButton = button(templatePanel, "", 169, 75, 122, function()
        f.purposeIndex = f.purposeIndex % #purposes + 1; f.templatePage = 1; updateTemplates()
    end)
    f.templateRows = {}
    for i = 1, 4 do
        f.templateRows[i] = button(templatePanel, "", 16 + ((i - 1) % 2) * 203,
            105 + math.floor((i - 1) / 2) * 27, 195, function(self)
                local item = self.item
                if not item then return end
                f.template = item.id
                f.mode = item.mode
                for n, mode in ipairs(modes) do
                    if mode.key == item.mode then f.modeIndex, f.modeName = n, mode.text; break end
                end
                f.spell:SetText(item.spell or "")
                f.name:SetText(item.spell or "")
                f.fallback:SetChecked(item.fallback or false)
                refreshPreview()
                updateTemplates()
                setStatus("示例技能可修改；实际效果请在无限服验证。")
            end)
    end
    f.emptyTemplates = label(templatePanel, "此分类暂无预设。", 16, 112)
    button(templatePanel, "上一页", 16, 163, 72, function() f.templatePage = f.templatePage - 1; updateTemplates() end)
    f.pageText = label(templatePanel, "", 107, 169)
    button(templatePanel, "下一页", 152, 163, 72, function() f.templatePage = f.templatePage + 1; updateTemplates() end)
    local templateHint = label(templatePanel, "选择模板后，可在下方修改示例技能。", 16, 194)
    templateHint:SetWidth(405)

    local skillPanel = CreateFrame("Frame", nil, f)
    skillPanel:SetAllPoints()
    f.skillPanel = skillPanel
    local skillHint = label(skillPanel, "拖入技能或输入技能名称，选择宏类型。", 16, 83)
    skillHint:SetWidth(405)
    label(skillPanel, "自动攻击、焦点、鼠标指向等选项可直接组合。", 16, 106)

    local tagPanel = CreateFrame("Frame", nil, f)
    tagPanel:SetAllPoints()
    f.tagPanel = tagPanel
    f.tagTarget = label(tagPanel, "", 16, 76, "GameFontNormal")
    f.tagTarget:SetWidth(395)
    f.tagRows = {}
    for i = 1, 8 do
        f.tagRows[i] = button(tagPanel, "", 16 + ((i - 1) % 4) * 103,
            99 + math.floor((i - 1) / 4) * 26, 97, function(self)
                local item, err = selectedMacro()
                if not item then setStatus(err); return end
                local tags
                tags, err = addon.GetMacroTags(item)
                if not tags then setStatus(err); return end
                local nextTags, exists = {}, false
                for _, tag in ipairs(tags) do
                    if tag == self.tag then exists = true else nextTags[#nextTags + 1] = tag end
                end
                if not exists then nextTags[#nextTags + 1] = self.tag end
                local ok
                ok, err = addon.SetMacroTags(item, nextTags)
                if not ok then setStatus(err); return end
                updateTags(); filterTags()
            end)
    end
    button(tagPanel, "上一页", 16, 155, 70, function() f.tagPage = f.tagPage - 1; updateTags() end)
    f.tagPageText = label(tagPanel, "", 93, 161)
    button(tagPanel, "下一页", 130, 155, 70, function() f.tagPage = f.tagPage + 1; updateTags() end)
    button(tagPanel, "清除标签", 209, 155, 92, function()
        local item, err = selectedMacro()
        if not item then setStatus(err); return end
        local ok
        ok, err = addon.SetMacroTags(item, {})
        if not ok then setStatus(err); return end
        updateTags(); filterTags()
    end)
    f.filterButton = button(tagPanel, "筛选：全部", 309, 155, 108, function()
        f.tagFilter = (f.tagFilter + 1) % (#(addon.MacroTagOptions or {}) + 1)
        filterTags()
    end)
    f.tagNote = label(tagPanel, "", 16, 185)
    f.tagNote:SetWidth(405)
    f.filterResult = label(tagPanel, "", 16, 205)
    f.filterResult:SetWidth(405)
    f.filterResult:SetHeight(28)

    label(f, "技能", 16, 240, "GameFontNormal")
    local slot = CreateFrame("Button", nil, f)
    slot:SetPoint("TOPLEFT", 16, -260)
    slot:SetSize(35, 35)
    f.icon = slot:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexture(134400)
    slot:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    slot:SetScript("OnReceiveDrag", receiveSpell)
    slot:SetScript("OnClick", receiveSpell)
    f.spell = field(f, 62, 263, 192)
    f.spell:SetScript("OnTextChanged", function(_, userInput)
        if userInput then f.icon:SetTexture(134400); refreshPreview() end
    end)
    f.spell:SetScript("OnEnterPressed", function(self)
        local info = spellInfo(self:GetText())
        if info then self:SetText(info.name); f.name:SetText(info.name); f.icon:SetTexture(info.iconID or 134400)
        else setStatus("未识别技能，请输入游戏中的准确技能名称。") end
        self:ClearFocus(); refreshPreview()
    end)
    f.modeButton = button(f, "", 262, 263, 155, function()
        f.modeIndex = f.modeIndex % #modes + 1
        f.mode, f.modeName = modes[f.modeIndex].key, modes[f.modeIndex].text
        f.template = nil
        refreshPreview()
    end)
    f.fallback = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    f.fallback:SetPoint("TOPLEFT", 14, -298)
    f.fallback:SetSize(23, 23)
    f.fallback:SetScript("OnClick", refreshPreview)
    label(f, "目标无效时按默认方式施法", 41, 304)
    f.hint = label(f, "", 16, 326)
    f.hint:SetWidth(405)
    label(f, "宏预览（可选中复制）", 16, 347, "GameFontNormal")
    f.preview = textBox(f, 16, 367, 405, 68)
    f.preview:SetScript("OnTextChanged", function(_, userInput) if userInput then refreshPreview() end end)
    label(f, "新宏名称", 16, 449)
    f.name = field(f, 82, 443, 144)
    f.character = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    f.character:SetPoint("TOPLEFT", 239, -443)
    f.character:SetSize(23, 23)
    f.character:SetChecked(true)
    label(f, "仅当前角色", 265, 449)
    button(f, "填入当前宏", 16, 480, 126, startCompare)
    button(f, "新建宏", 151, 480, 112, createMacro)
    f.status = label(f, "", 16, 513)
    f.status:SetWidth(405)
    f.status:SetHeight(30)
    f.confirm = createConfirm(f)
    updateTab()
    refreshPreview()
end

local function position()
    if not frame or not MacroFrame or not UIParent then return false end
    local scale = MacroFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local right, left, screen = MacroFrame:GetRight(), MacroFrame:GetLeft(), UIParent:GetRight()
    if not right or not left or not screen then return false end
    local needed = frame:GetWidth() * scale + 12
    frame:ClearAllPoints()
    if screen - right * scale >= needed then
        frame:SetPoint("TOPLEFT", MacroFrame, "TOPRIGHT", 8, 0)
    elseif left * scale >= needed then
        frame:SetPoint("TOPRIGHT", MacroFrame, "TOPLEFT", -8, 0)
    else
        setStatus("屏幕空间不足，请缩小界面后重新打开助手。")
        return false
    end
    return true
end

local function positionEntry()
    if not entry or not MacroFrame or not UIParent then return end
    local scale = MacroFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local right, left, screen = MacroFrame:GetRight(), MacroFrame:GetLeft(), UIParent:GetRight()
    entry:ClearAllPoints()
    if right and screen and screen - right * scale < 110 * scale then
        if left and left * scale >= 110 * scale then
            entry:SetPoint("TOPRIGHT", MacroFrame, "TOPLEFT", -8, -4)
        else
            entry:SetPoint("TOPRIGHT", MacroFrame, "TOPRIGHT", -32, -4)
        end
    else
        entry:SetPoint("TOPLEFT", MacroFrame, "TOPRIGHT", 8, -4)
    end
end

local function attach()
    if entry or not MacroFrame or type(MacroFrame.HookScript) ~= "function" then return end
    entry = button(MacroFrame, "宏工坊", 0, 0, 100, function()
        if not frame then createWindow() end
        if frame.wanted then frame.wanted = false; frame:Hide(); return end
        if MacroPopupFrame and MacroPopupFrame:IsShown() then return end
        if not position() then print("宏工坊：屏幕空间不足，请缩小界面后重试。" ); return end
        frame.wanted = true
        frame:Show()
        updateTab()
    end)
    positionEntry()
    MacroFrame:HookScript("OnShow", positionEntry)
    MacroFrame:HookScript("OnHide", function()
        if frame then frame.wanted = false; frame.confirm:Hide(); frame:Hide() end
    end)
    local elapsed, previous, previousPosition = 0, "", ""
    MacroFrame:HookScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < 0.3 then return end
        elapsed = 0
        local location = tostring(MacroFrame:GetLeft()) .. ":" .. tostring(MacroFrame:GetRight())
            .. ":" .. tostring(UIParent:GetRight()) .. ":" .. tostring(MacroFrame:GetEffectiveScale())
        if location ~= previousPosition then
            previousPosition = location
            positionEntry()
            if frame and frame:IsShown() and not position() then
                frame.wanted = false
                frame.confirm:Hide()
                frame:Hide()
                print("宏工坊：屏幕空间不足，请缩小界面后重新打开助手。")
            end
        end
        if not frame or not frame:IsShown() or frame.tab ~= "tags" then return end
        local selected = selectedMacro()
        local identity = selected and (selected.index .. "\001" .. selected.name .. "\001" .. selected.body) or ""
        if identity ~= previous then
            previous = identity
            updateTags()
            filterTags()
        end
    end)
    if MacroPopupFrame and MacroPopupFrame.HookScript then
        MacroPopupFrame:HookScript("OnShow", function()
            if frame then frame.confirm:Hide(); frame:Hide() end
            entry:Disable()
        end)
        MacroPopupFrame:HookScript("OnHide", function()
            entry:Enable()
            if frame and frame.wanted and MacroFrame:IsShown() and position() then frame:Show() end
        end)
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("UPDATE_MACROS")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == "Blizzard_MacroUI" or event == "PLAYER_LOGIN" then
        attach()
    elseif event == "UPDATE_MACROS" then
        generation = generation + 1
        addon.InvalidateMacroTags()
        if frame and frame:IsShown() then
            if frame.tab == "tags" then updateTags(); filterTags() end
            setStatus("宏列表已变化，标签已清除；请重新选择并分类。")
        end
    elseif event == "PLAYER_REGEN_DISABLED" and frame and frame:IsShown() then
        setStatus("战斗中无法修改宏，预览会保留至脱战。")
    end
end)

function addon.OpenMacroBuilder()
    if type(InCombatLockdown) ~= "function" or InCombatLockdown() then
        print("宏工坊：请脱战后打开系统宏窗口。")
        return
    end
    if not MacroFrame then
        local loader = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
        if loader then pcall(loader, "Blizzard_MacroUI") end
    end
    attach()
    if not MacroFrame or type(ShowUIPanel) ~= "function" then
        print("宏工坊：无法打开系统宏窗口，请使用 /macro。")
        return
    end
    ShowUIPanel(MacroFrame)
    if entry and MacroFrame:IsShown() and (not frame or not frame:IsShown()) then entry:Click() end
end
SLASH_MACROWORKSHOP1 = "/mw"
SLASH_MACROWORKSHOP2 = "/macroworkshop"
SlashCmdList.MACROWORKSHOP = addon.OpenMacroBuilder
