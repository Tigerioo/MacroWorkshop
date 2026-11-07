local _, addon = ...
local manager
local PAGE_SIZE = 8

local function label(parent, text, x, y, style)
    local value = parent:CreateFontString(nil, "OVERLAY", style or "GameFontHighlight")
    value:SetPoint("TOPLEFT", x, -y)
    value:SetText(text)
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

local function edit(parent, x, y, width)
    local value = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    value:SetPoint("TOPLEFT", x, -y)
    value:SetSize(width, 24)
    value:SetAutoFocus(false)
    value:SetScript("OnEscapePressed", value.ClearFocus)
    return value
end

StaticPopupDialogs.MACROWORKSHOP_DISCARD = {
    text = "当前宏有未保存的修改，放弃修改并继续？",
    button1 = "放弃修改",
    button2 = "取消",
    OnAccept = function(_, data) if data and data.action then data.action() end end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
StaticPopupDialogs.MACROWORKSHOP_DELETE = {
    text = "删除宏“%s”？动作条中使用此宏的按钮可能失效，删除后无法在此恢复。",
    button1 = "删除",
    button2 = "取消",
    OnAccept = function(_, data) if data and data.action then data.action() end end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local function confirmDiscard(action)
    if manager.dirty then
        StaticPopup_Show("MACROWORKSHOP_DISCARD", nil, nil, { action = function()
            if manager.selected then
                manager.name:SetText(manager.selected.name)
                manager.body:SetText(manager.selected.body)
            end
            manager.dirty = false
            action()
        end })
    else
        action()
    end
end

local function setStatus(text)
    manager.status:SetText(text or "")
end

local function updateRows()
    local f = manager
    local total = #f.entries
    local pages = math.max(1, math.ceil(total / PAGE_SIZE))
    f.page = math.min(math.max(f.page, 1), pages)
    for i, row in ipairs(f.rows) do
        local item = f.entries[(f.page - 1) * PAGE_SIZE + i]
        row.item = item
        if item then
            local mark = f.selected == item and "● " or ""
            row:SetText(mark .. (item.perCharacter and "[角色] " or "[通用] ") .. item.name)
            row:Show()
        else
            row:Hide()
        end
    end
    f.pageLabel:SetText(f.page .. " / " .. pages)
    f.previous:SetEnabled(f.page > 1)
    f.next:SetEnabled(f.page < pages)
    f.empty:SetShown(total == 0)
end

local function clearSelection()
    local f = manager
    f.selected = nil
    f.name:SetText("")
    f.body:SetText("")
    f.scope:SetText("选择左侧的宏")
    f.dirty = false
end

local function refreshList()
    local f = manager
    local entries, counts, err = addon.ListMacros()
    if not entries then
        f.entries = {}
        clearSelection()
        f.capacity:SetText("无法读取宏列表")
        setStatus(err or "无法读取宏，请稍后重试。")
        updateRows()
        return
    end
    f.entries = entries
    f.listGeneration = f.generation
    clearSelection()
    f.capacity:SetText(("通用 %d/%d   当前角色 %d/%d"):format(
        counts.account, counts.accountMax, counts.character, counts.characterMax))
    setStatus("选择一个宏查看、编辑或拾取。")
    updateRows()
end

local function selectItem(item)
    if not item then return end
    local f = manager
    if f.listGeneration ~= f.generation then
        setStatus("宏列表已变化，请刷新后重新选择。")
        return
    end
    local index, err = addon.ResolveMacro(item)
    if not index then setStatus(err); return end
    f.selected = item
    f.name:SetText(item.name)
    f.body:SetText(item.body or "")
    f.scope:SetText(item.perCharacter and "当前角色专用宏" or "账号通用宏")
    f.dirty = false
    setStatus(f.pendingBody and "可点击“使用新建预览”，确认内容后保存。" or "修改后点击保存；切换宏前请保存。")
    updateRows()
end

local function selectedForAction()
    local f = manager
    if not f.selected then setStatus("请先选择一个宏。"); return nil end
    if f.listGeneration ~= f.generation then
        setStatus("宏列表已变化。请先复制未保存内容，再刷新并重新选择。")
        return nil
    end
    return f.selected
end

local function showManager()
    local f = CreateFrame("Frame", "MacroWorkshopManagerFrame", UIParent, "BackdropTemplate")
    manager = f
    f:SetSize(740, 490)
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
    f.entries, f.rows, f.page, f.generation = {}, {}, 1, 0
    label(f, "宏工坊 · 管理已有宏", 18, 16, "GameFontNormalLarge")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT")
    close:SetScript("OnClick", function() confirmDiscard(function() f:Hide() end) end)

    f.capacity = label(f, "", 18, 52, "GameFontHighlightSmall")
    button(f, "刷新列表", 160, 71, 93, function()
        confirmDiscard(function() f.page = 1; refreshList() end)
    end)
    label(f, "游戏已有宏", 18, 78, "GameFontNormal")
    f.empty = label(f, "当前没有可用的宏", 26, 126, "GameFontDisable")
    for i = 1, PAGE_SIZE do
        local row = button(f, "", 18, 101 + (i - 1) * 31, 235, function(self)
            if self.item ~= f.selected then
                local item = self.item
                confirmDiscard(function() selectItem(item) end)
            end
        end)
        f.rows[i] = row
    end
    f.previous = button(f, "上一页", 18, 361, 70, function() f.page = f.page - 1; updateRows() end)
    f.pageLabel = label(f, "1 / 1", 112, 368, "GameFontHighlightSmall")
    f.next = button(f, "下一页", 183, 361, 70, function() f.page = f.page + 1; updateRows() end)

    f.scope = label(f, "选择左侧的宏", 282, 55, "GameFontNormal")
    button(f, "返回新建", 604, 51, 112, function()
        confirmDiscard(function()
            f:Hide()
            addon.OpenMacroBuilder()
        end)
    end)
    label(f, "名称", 282, 87, "GameFontHighlightSmall")
    f.name = edit(f, 326, 81, 210)
    button(f, "使用新建预览", 570, 81, 146, function()
        if not selectedForAction() then return end
        if not f.pendingBody then setStatus("请先在新建页面生成预览。"); return end
        confirmDiscard(function()
            f.body:SetText(f.pendingBody)
            f.dirty = true
            setStatus("预览已放入编辑框；确认后点击保存修改。")
        end)
    end)
    label(f, "宏内容", 282, 121, "GameFontHighlightSmall")
    local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 282, -143)
    box:SetSize(435, 195)
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    box:SetBackdropColor(0.02, 0.02, 0.02, 1)
    box:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -30, 8)
    f.body = CreateFrame("EditBox", nil, scroll)
    f.body:SetSize(395, 180)
    f.body:SetFontObject(ChatFontNormal)
    f.body:SetMultiLine(true)
    f.body:SetAutoFocus(false)
    f.body:SetScript("OnEscapePressed", f.body.ClearFocus)
    scroll:SetScrollChild(f.body)
    f.name:SetScript("OnTextChanged", function(_, userInput)
        if userInput and f.selected then f.dirty = true end
    end)
    f.body:SetScript("OnTextChanged", function(_, userInput)
        if userInput and f.selected then f.dirty = true end
    end)

    button(f, "保存修改", 282, 355, 100, function()
        local item = selectedForAction()
        if not item then return end
        local updated, message = addon.UpdateExistingMacro(item, f.name:GetText(), f.body:GetText())
        if updated then
            f.dirty = false
            refreshList()
        end
        setStatus(message)
    end)
    button(f, "拾取宏", 392, 355, 94, function()
        local item = selectedForAction()
        if not item then return end
        if f.dirty then setStatus("请先保存或放弃修改，再拾取宏。"); return end
        local ok, message = addon.PickupExistingMacro(item)
        setStatus(message or (ok and "已拾取宏，请放到动作条。" or "拾取失败。"))
    end)
    button(f, "删除宏", 496, 355, 94, function()
        local item = selectedForAction()
        if not item then return end
        if f.dirty then setStatus("请先保存或放弃修改，再删除宏。"); return end
        local generation = f.generation
        StaticPopup_Show("MACROWORKSHOP_DELETE", item.name, nil, { action = function()
            if f.generation ~= generation or f.selected ~= item then
                setStatus("宏列表已变化，请刷新后重新选择。")
                return
            end
            local deleted, message = addon.DeleteExistingMacro(item)
            if deleted then refreshList() end
            setStatus(message)
        end })
    end)
    f.status = label(f, "", 18, 411, "GameFontHighlightSmall")
    f.status:SetWidth(700)
    f.status:SetJustifyH("LEFT")
    f:RegisterEvent("UPDATE_MACROS")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:SetScript("OnEvent", function(self, event)
        if event == "UPDATE_MACROS" then
            self.generation = self.generation + 1
            if self:IsShown() then setStatus("宏列表已变化；未保存内容可先复制，再刷新。") end
        elseif event == "PLAYER_REGEN_DISABLED" and self:IsShown() then
            setStatus("战斗中不能修改或拾取宏；脱战后操作。")
        end
    end)
end

function addon.OpenMacroManager(draftBody)
    if not manager then showManager() end
    if InCombatLockdown() then
        print("宏工坊：请脱战后管理宏。")
        return
    end
    manager:Show()
    local function open()
        manager.pendingBody = draftBody
        if #manager.entries == 0 or manager.listGeneration ~= manager.generation then
            refreshList()
        elseif draftBody then
            setStatus("选择目标宏，点击“使用新建预览”，确认后保存。")
        end
    end
    if manager.dirty and (draftBody or manager.listGeneration ~= manager.generation) then
        confirmDiscard(open)
    else
        open()
    end
end
