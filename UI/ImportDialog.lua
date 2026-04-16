-- UI/ImportDialog.lua — Paste-to-import modal (AceGUI-3.0)
-- Presentation only. Business logic lives in Import.lua and OutfitLibrary.lua.

local _, StyleBound = ...

local ImportDialog = StyleBound:NewModule("ImportDialog")

local AceGUI = LibStub("AceGUI-3.0")

local frame = nil  -- singleton

-------------------------------------------------------------------------------
-- Frame helpers: position persistence + full-border dragging
-------------------------------------------------------------------------------

local function ConfigureFrame(aceFrame, positionKey)
    -- Position persistence via AceGUI SetStatusTable
    if StyleBound.db and StyleBound.db.global.framePositions then
        aceFrame:SetStatusTable(StyleBound.db.global.framePositions[positionKey])
    end

    -- Enable dragging from anywhere on the frame (not just title bar)
    local rawFrame = aceFrame.frame
    rawFrame:SetMovable(true)
    rawFrame:EnableMouse(true)
    rawFrame:RegisterForDrag("LeftButton")
    rawFrame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    rawFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Trigger AceGUI's status save by firing a fake "OnDragStop" on the status table
        local status = aceFrame.status or aceFrame.localstatus
        if status then
            status.top = self:GetTop()
            status.left = self:GetLeft()
        end
    end)
end

-- Human-readable slot names for the grid
local SLOT_DISPLAY_NAMES = {
    HEAD      = "Head",
    SHOULDER  = "Shoulders",
    BACK      = "Back",
    CHEST     = "Chest",
    SHIRT     = "Shirt",
    TABARD    = "Tabard",
    WRIST     = "Wrists",
    HANDS     = "Hands",
    WAIST     = "Waist",
    LEGS      = "Legs",
    FEET      = "Feet",
    MAINHAND  = "Main Hand",
    OFFHAND   = "Off Hand",
}

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function GetItemIcon(itemID)
    if not itemID then return 134400 end -- INV_Misc_QuestionMark
    local icon = C_Item.GetItemIconByID(itemID)
    return icon or 134400
end

local function GetItemNameAsync(itemID, callback)
    if not itemID then
        callback("Unknown Item")
        return
    end
    local item = Item:CreateFromItemID(itemID)
    item:ContinueOnItemLoad(function()
        callback(item:GetItemName() or ("Item " .. itemID))
    end)
end

-------------------------------------------------------------------------------
-- Slot grid view (shown after successful decode)
-------------------------------------------------------------------------------

local function BuildSlotGrid(container, outfit, collected)
    local scrollFrame = AceGUI:Create("ScrollFrame")
    scrollFrame:SetLayout("List")
    scrollFrame:SetFullWidth(true)
    scrollFrame:SetFullHeight(true)
    container:AddChild(scrollFrame)

    for _, slotKey in ipairs(StyleBound.SLOTS) do
        local slotData = outfit.slots[slotKey]
        if slotData then
            local row = AceGUI:Create("SimpleGroup")
            row:SetFullWidth(true)
            row:SetLayout("Flow")
            scrollFrame:AddChild(row)

            -- Icon
            local icon = AceGUI:Create("Icon")
            icon:SetImage(GetItemIcon(slotData.i))
            icon:SetImageSize(24, 24)
            icon:SetWidth(32)
            icon:SetHeight(32)
            row:AddChild(icon)

            -- Slot name + item name label
            local label = AceGUI:Create("Label")
            local displayName = SLOT_DISPLAY_NAMES[slotKey] or slotKey
            local collectedStatus = collected[slotKey]

            if collectedStatus == false then
                label:SetText(displayName .. ": |cFFFF6600Loading...|r  |cFFFF0000(Not Collected)|r")
            else
                label:SetText(displayName .. ": Loading...")
            end
            label:SetWidth(350)
            row:AddChild(label)

            -- Async item name resolution
            if slotData.i then
                GetItemNameAsync(slotData.i, function(name)
                    if collectedStatus == false then
                        label:SetText(displayName .. ": |cFFFF6600" .. name .. "|r  |cFFFF0000(Not Collected)|r")
                    else
                        label:SetText(displayName .. ": " .. name)
                    end
                end)
            else
                local fallback = "Appearance " .. slotData.a
                if collectedStatus == false then
                    label:SetText(displayName .. ": |cFFFF6600" .. fallback .. "|r  |cFFFF0000(Not Collected)|r")
                else
                    label:SetText(displayName .. ": " .. fallback)
                end
            end

            -- Update icon once item loads
            if slotData.i then
                local item = Item:CreateFromItemID(slotData.i)
                item:ContinueOnItemLoad(function()
                    icon:SetImage(C_Item.GetItemIconByID(slotData.i) or 134400)
                end)
            end
        end
    end

    -- Hidden slots note
    if outfit.hidden and #outfit.hidden > 0 then
        local hiddenLabel = AceGUI:Create("Label")
        local names = {}
        for _, key in ipairs(outfit.hidden) do
            names[#names + 1] = SLOT_DISPLAY_NAMES[key] or key
        end
        hiddenLabel:SetText("\n|cFF888888Hidden: " .. table.concat(names, ", ") .. "|r")
        hiddenLabel:SetFullWidth(true)
        scrollFrame:AddChild(hiddenLabel)
    end
end

-------------------------------------------------------------------------------
-- Preview in Dressing Room
-------------------------------------------------------------------------------

--- Resolve a transmog source ID for DressUpVisual: prefer explicit `s`, else derive from item `i`.
local function GetDressUpSourceID(slotData)
    if slotData.s and slotData.s > 0 then
        return slotData.s
    end
    if slotData.i and slotData.i > 0 then
        local itemLink = select(2, GetItemInfo(slotData.i))
        if itemLink then
            local ok, _, sourceID = pcall(C_TransmogCollection.GetItemInfo, itemLink)
            if ok and sourceID and sourceID > 0 then
                return sourceID
            end
        end
    end
    return nil
end

local function PreviewInDressingRoom(outfit)
    DressUpFrame_Show(DressUpFrame)

    -- Reset the model
    if DressUpFrame.ModelScene then
        local actor = DressUpFrame.ModelScene:GetPlayerActor()
        if actor then
            actor:Undress()
        end
    end

    -- Dress each slot
    for _, slotKey in ipairs(StyleBound.SLOTS) do
        local slotData = outfit.slots[slotKey]
        if slotData then
            local sourceID = GetDressUpSourceID(slotData)
            if sourceID then
                DressUpVisual(sourceID)
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Save to Library (with name prompt)
-------------------------------------------------------------------------------

local function PromptSaveToLibrary(outfit)
    local defaultName = "Imported outfit"
    if outfit.char and outfit.char.name then
        defaultName = outfit.char.name .. " outfit"
    end

    local saveFrame = AceGUI:Create("Frame")
    saveFrame:SetTitle("Save to Library")
    saveFrame:SetWidth(350)
    saveFrame:SetHeight(150)
    saveFrame:SetLayout("List")
    ConfigureFrame(saveFrame, "savePrompt")
    saveFrame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
    end)

    local nameBox = AceGUI:Create("EditBox")
    nameBox:SetLabel("Outfit Name:")
    nameBox:SetFullWidth(true)
    nameBox:SetText(defaultName)
    saveFrame:AddChild(nameBox)

    local saveBtn = AceGUI:Create("Button")
    saveBtn:SetText("Save")
    saveBtn:SetFullWidth(true)
    saveBtn:SetCallback("OnClick", function()
        local name = nameBox:GetText()
        if name == "" then name = defaultName end
        if #name > 64 then name = name:sub(1, 64) end

        outfit.source = "import"
        local OutfitLibrary = StyleBound:GetModule("OutfitLibrary")
        OutfitLibrary:Save(outfit, name)

        StyleBound:Print("Outfit saved: " .. name)
        AceGUI:Release(saveFrame)
    end)
    saveFrame:AddChild(saveBtn)

    C_Timer.After(0.05, function()
        nameBox:SetFocus()
        nameBox:HighlightText()
    end)
end

-------------------------------------------------------------------------------
-- Main dialog states
-------------------------------------------------------------------------------

local function ShowInputState(container)
    container:ReleaseChildren()
    container:SetLayout("List")

    local desc = AceGUI:Create("Label")
    desc:SetText("Paste a StyleBound export string below to preview and import a transmog outfit.")
    desc:SetFullWidth(true)
    container:AddChild(desc)

    local spacer = AceGUI:Create("Label")
    spacer:SetText(" ")
    spacer:SetFullWidth(true)
    container:AddChild(spacer)

    local editBox = AceGUI:Create("MultiLineEditBox")
    editBox:SetLabel("Export String:")
    editBox:SetFullWidth(true)
    editBox:SetNumLines(6)
    editBox:DisableButton(true)
    container:AddChild(editBox)

    local errorLabel = AceGUI:Create("Label")
    errorLabel:SetText("")
    errorLabel:SetFullWidth(true)
    container:AddChild(errorLabel)

    local decodeBtn = AceGUI:Create("Button")
    decodeBtn:SetText("Decode")
    decodeBtn:SetWidth(150)
    decodeBtn:SetCallback("OnClick", function()
        local encoded = editBox:GetText()
        if not encoded or encoded:match("^%s*$") then
            errorLabel:SetText("|cFFFF0000Please paste an export string.|r")
            return
        end

        -- Strip whitespace
        encoded = encoded:gsub("%s+", "")

        local Import = StyleBound:GetModule("Import")

        -- Decode
        local outfit, decodeErr = Import:DecodeString(encoded)
        if not outfit then
            errorLabel:SetText("|cFFFF0000" .. decodeErr .. "|r")
            return
        end

        -- Validate
        local valid, validateErr = Import:ValidateSchema(outfit)
        if not valid then
            errorLabel:SetText("|cFFFF0000" .. validateErr .. "|r")
            return
        end

        -- Resolve collection
        local collected = Import:ResolveCollection(outfit)

        -- Show result state
        ShowResultState(container, outfit, collected)
    end)
    container:AddChild(decodeBtn)

    C_Timer.After(0.05, function()
        editBox:SetFocus()
    end)
end

function ShowResultState(container, outfit, collected)
    container:ReleaseChildren()
    container:SetLayout("List")

    -- Character info header
    if outfit.char then
        local c = outfit.char
        local charText = (c.name or "Unknown") .. "-" .. (c.realm or "Unknown")
        if c.race and c.class then
            charText = charText .. "  (" .. c.race .. " " .. c.class .. ")"
        end
        local charLabel = AceGUI:Create("Label")
        charLabel:SetText("|cFFFFD100" .. charText .. "|r")
        charLabel:SetFullWidth(true)
        container:AddChild(charLabel)
    end

    -- Slot count + collection summary
    local slotCount = 0
    local missingCount = 0
    for slotKey in pairs(outfit.slots) do
        slotCount = slotCount + 1
        if collected[slotKey] == false then
            missingCount = missingCount + 1
        end
    end

    local summaryText = slotCount .. " slots"
    if missingCount > 0 then
        summaryText = summaryText .. "  |cFFFF6600(" .. missingCount .. " not collected)|r"
    end
    local summaryLabel = AceGUI:Create("Label")
    summaryLabel:SetText(summaryText)
    summaryLabel:SetFullWidth(true)
    container:AddChild(summaryLabel)

    -- Spacer
    local spacer = AceGUI:Create("Label")
    spacer:SetText(" ")
    spacer:SetFullWidth(true)
    container:AddChild(spacer)

    -- Slot grid (scrollable)
    local gridGroup = AceGUI:Create("SimpleGroup")
    gridGroup:SetFullWidth(true)
    gridGroup:SetHeight(220)
    gridGroup:SetLayout("Fill")
    container:AddChild(gridGroup)

    BuildSlotGrid(gridGroup, outfit, collected)

    -- Action buttons
    local btnGroup = AceGUI:Create("SimpleGroup")
    btnGroup:SetFullWidth(true)
    btnGroup:SetLayout("Flow")
    container:AddChild(btnGroup)

    local previewBtn = AceGUI:Create("Button")
    previewBtn:SetText("Preview in Dressing Room")
    previewBtn:SetWidth(200)
    previewBtn:SetCallback("OnClick", function()
        PreviewInDressingRoom(outfit)
    end)
    btnGroup:AddChild(previewBtn)

    local saveBtn = AceGUI:Create("Button")
    saveBtn:SetText("Save to Library")
    saveBtn:SetWidth(150)
    saveBtn:SetCallback("OnClick", function()
        PromptSaveToLibrary(outfit)
    end)
    btnGroup:AddChild(saveBtn)

    -- Back button
    local backBtn = AceGUI:Create("Button")
    backBtn:SetText("Back")
    backBtn:SetWidth(80)
    backBtn:SetCallback("OnClick", function()
        ShowInputState(container)
    end)
    btnGroup:AddChild(backBtn)
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

function ImportDialog:Show()
    if frame then return end

    frame = AceGUI:Create("Frame")
    frame:SetTitle("StyleBound — Import Outfit")
    frame:SetWidth(480)
    frame:SetHeight(500)
    frame:SetLayout("Fill")
    ConfigureFrame(frame, "importDialog")
    frame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        frame = nil
    end)

    local content = AceGUI:Create("SimpleGroup")
    content:SetFullWidth(true)
    content:SetFullHeight(true)
    content:SetLayout("List")
    frame:AddChild(content)

    ShowInputState(content)
end

function ImportDialog:ShowResult(outfit, collected)
    if frame then
        frame:Hide()
    end

    frame = AceGUI:Create("Frame")
    frame:SetTitle("StyleBound — Import Preview")
    frame:SetWidth(480)
    frame:SetHeight(500)
    frame:SetLayout("Fill")
    ConfigureFrame(frame, "importDialog")
    frame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        frame = nil
    end)

    local content = AceGUI:Create("SimpleGroup")
    content:SetFullWidth(true)
    content:SetFullHeight(true)
    content:SetLayout("List")
    frame:AddChild(content)

    ShowResultState(content, outfit, collected)
end

function ImportDialog:Hide()
    if not frame then return end
    frame:Hide()
end

function ImportDialog:IsShown()
    return frame ~= nil
end
