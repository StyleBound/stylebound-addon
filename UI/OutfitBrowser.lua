-- UI/OutfitBrowser.lua — Browse, manage, and promote saved outfits
-- Two-pane layout: folder list + outfit list with action buttons.

local _, StyleBound = ...

local OutfitBrowser = StyleBound:NewModule("OutfitBrowser")

local AceGUI = LibStub("AceGUI-3.0")

local frame = nil  -- singleton

-- Slot display names for the detail view
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

local SOURCE_BADGES = {
    export = "|cFF00CC00Export|r",
    import = "|cFF3399FFImport|r",
    copy   = "|cFFFF9900Copy|r",
    manual = "|cFFCCCCCCManual|r",
}

local activeFolder = nil  -- nil = All

-------------------------------------------------------------------------------
-- Frame helpers: position persistence + full-border dragging
-------------------------------------------------------------------------------

local function ConfigureFrame(aceFrame, positionKey)
    if StyleBound.db and StyleBound.db.global.framePositions then
        if not StyleBound.db.global.framePositions[positionKey] then
            StyleBound.db.global.framePositions[positionKey] = {}
        end
        aceFrame:SetStatusTable(StyleBound.db.global.framePositions[positionKey])
    end

    local rawFrame = aceFrame.frame
    rawFrame:SetMovable(true)
    rawFrame:EnableMouse(true)
    rawFrame:RegisterForDrag("LeftButton")
    rawFrame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    rawFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local status = aceFrame.status or aceFrame.localstatus
        if status then
            status.top = self:GetTop()
            status.left = self:GetLeft()
        end
    end)
end

-------------------------------------------------------------------------------
-- Save as Custom Set
-------------------------------------------------------------------------------

local function SaveAsCustomSet(outfit)
    -- Check cap
    local currentSets = C_TransmogCollection.GetCustomSets()
    local maxSets = C_TransmogCollection.GetNumMaxCustomSets()
    if #currentSets >= maxSets then
        StyleBound:Print("|cFFFF0000You've reached the Custom Set cap (" .. maxSets .. "). Delete one in Collections → Sets → Custom Sets first.|r")
        return
    end

    -- Validate name
    local name = outfit.name or "StyleBound Outfit"
    if not C_TransmogCollection.IsValidCustomSetName(name) then
        -- Try appending a number to make it unique
        for i = 2, 99 do
            local tryName = name .. " " .. i
            if C_TransmogCollection.IsValidCustomSetName(tryName) then
                name = tryName
                break
            end
            if i == 99 then
                StyleBound:Print("|cFFFF0000Could not find a valid name for the Custom Set. Try renaming the outfit first.|r")
                return
            end
        end
    end

    -- Build the ItemTransmogInfoList
    local list = TransmogUtil.GetEmptyItemTransmogInfoList()

    local mhData = outfit.slots["MAINHAND"]
    local ohData = outfit.slots["OFFHAND"]

    for slotKey, slotData in pairs(outfit.slots) do
        local invSlot = StyleBound.SLOT_TO_INVSLOT[slotKey]
        if invSlot then
            local listIndex = StyleBound.SLOT_LIST_INDEX[invSlot]
            if listIndex then
                -- The list uses sourceIDs, not visualIDs
                local appID = slotData.s or 0
                local secID = slotData.sa or 0
                local illID = slotData.il or 0

                -- Paired weapons: if MH and OH have the same appearance,
                -- store OH as the MH's secondaryAppearanceID instead
                if slotKey == "MAINHAND" and ohData and ohData.s == appID then
                    secID = appID
                    list[listIndex]:Init(appID, secID, illID)
                elseif slotKey == "OFFHAND" and mhData and mhData.s == appID then
                    -- Skip — already handled as MH secondary
                else
                    list[listIndex]:Init(appID, secID, illID)
                end
            end
        end
    end

    -- Create
    local newSetID = C_TransmogCollection.NewCustomSet(name, 0, list)
    if newSetID then
        StyleBound:Print("|cFF00FF00Custom Set '" .. name .. "' created!|r Open Collections → Sets → Custom Sets to load it into an Outfit Slot.")
    else
        StyleBound:Print("|cFFFF0000Failed to create Custom Set. The name may be invalid or a set with that name may already exist.|r")
    end
end

-------------------------------------------------------------------------------
-- Preview in Dressing Room
-------------------------------------------------------------------------------

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

local function PreviewOutfit(outfit)
    DressUpFrame_Show(DressUpFrame)

    if DressUpFrame.ModelScene then
        local actor = DressUpFrame.ModelScene:GetPlayerActor()
        if actor then
            actor:Undress()
        end
    end

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
-- Share (export string without char metadata)
-------------------------------------------------------------------------------

local function ShareOutfit(outfit)
    -- Build a stripped copy without character data
    local shareOutfit = {
        v     = outfit.v or 1,
        kind  = "outfit",
        slots = outfit.slots,
        t     = outfit.t or time(),
    }
    if outfit.hidden then
        shareOutfit.hidden = outfit.hidden
    end

    local Export = StyleBound:GetModule("Export")
    local encoded = Export:EncodeOutfit(shareOutfit)

    -- Show in a small dialog
    local shareFrame = AceGUI:Create("Frame")
    shareFrame:SetTitle("Share Outfit: " .. (outfit.name or "Untitled"))
    shareFrame:SetWidth(420)
    shareFrame:SetHeight(150)
    shareFrame:SetLayout("List")
    ConfigureFrame(shareFrame, "shareDialog")
    shareFrame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
    end)

    local editBox = AceGUI:Create("EditBox")
    editBox:SetLabel("Copy this string (Ctrl+A, Ctrl+C):")
    editBox:SetFullWidth(true)
    editBox:SetText(encoded)
    editBox:DisableButton(true)
    shareFrame:AddChild(editBox)

    C_Timer.After(0.05, function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)
end

-------------------------------------------------------------------------------
-- Rename dialog
-------------------------------------------------------------------------------

local function PromptRename(outfit, refreshCallback)
    local renameFrame = AceGUI:Create("Frame")
    renameFrame:SetTitle("Rename Outfit")
    renameFrame:SetWidth(350)
    renameFrame:SetHeight(150)
    renameFrame:SetLayout("List")
    renameFrame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
    end)

    local nameBox = AceGUI:Create("EditBox")
    nameBox:SetLabel("New Name:")
    nameBox:SetFullWidth(true)
    nameBox:SetText(outfit.name or "")
    renameFrame:AddChild(nameBox)

    local saveBtn = AceGUI:Create("Button")
    saveBtn:SetText("Save")
    saveBtn:SetFullWidth(true)
    saveBtn:SetCallback("OnClick", function()
        local newName = nameBox:GetText()
        if newName and newName ~= "" then
            if #newName > 64 then newName = newName:sub(1, 64) end
            StyleBound:GetModule("OutfitLibrary"):Rename(outfit.id, newName)
            StyleBound:Print("Renamed to '" .. newName .. "'")
            AceGUI:Release(renameFrame)
            if refreshCallback then refreshCallback() end
        end
    end)
    renameFrame:AddChild(saveBtn)

    C_Timer.After(0.05, function()
        nameBox:SetFocus()
        nameBox:HighlightText()
    end)
end

-------------------------------------------------------------------------------
-- Delete confirmation
-------------------------------------------------------------------------------

local function ConfirmDelete(outfit, refreshCallback)
    local deleteFrame = AceGUI:Create("Frame")
    deleteFrame:SetTitle("Delete Outfit")
    deleteFrame:SetWidth(350)
    deleteFrame:SetHeight(130)
    deleteFrame:SetLayout("List")
    deleteFrame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
    end)

    local label = AceGUI:Create("Label")
    label:SetText("Delete |cFFFFD100" .. (outfit.name or "Untitled") .. "|r? This cannot be undone.")
    label:SetFullWidth(true)
    deleteFrame:AddChild(label)

    local btnGroup = AceGUI:Create("SimpleGroup")
    btnGroup:SetFullWidth(true)
    btnGroup:SetLayout("Flow")
    deleteFrame:AddChild(btnGroup)

    local delBtn = AceGUI:Create("Button")
    delBtn:SetText("Delete")
    delBtn:SetWidth(120)
    delBtn:SetCallback("OnClick", function()
        StyleBound:GetModule("OutfitLibrary"):Delete(outfit.id)
        StyleBound:Print("Deleted '" .. (outfit.name or "Untitled") .. "'")
        AceGUI:Release(deleteFrame)
        if refreshCallback then refreshCallback() end
    end)
    btnGroup:AddChild(delBtn)

    local cancelBtn = AceGUI:Create("Button")
    cancelBtn:SetText("Cancel")
    cancelBtn:SetWidth(120)
    cancelBtn:SetCallback("OnClick", function()
        AceGUI:Release(deleteFrame)
    end)
    btnGroup:AddChild(cancelBtn)
end

-------------------------------------------------------------------------------
-- Move to folder dialog
-------------------------------------------------------------------------------

local function PromptMoveToFolder(outfit, refreshCallback)
    local moveFrame = AceGUI:Create("Frame")
    moveFrame:SetTitle("Move to Folder")
    moveFrame:SetWidth(300)
    moveFrame:SetHeight(200)
    moveFrame:SetLayout("List")
    moveFrame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
    end)

    local label = AceGUI:Create("Label")
    label:SetText("Move |cFFFFD100" .. (outfit.name or "Untitled") .. "|r to:")
    label:SetFullWidth(true)
    moveFrame:AddChild(label)

    local spacer = AceGUI:Create("Label")
    spacer:SetText(" ")
    spacer:SetFullWidth(true)
    moveFrame:AddChild(spacer)

    -- "No Folder" option
    local noneBtn = AceGUI:Create("Button")
    noneBtn:SetText("No Folder")
    noneBtn:SetFullWidth(true)
    noneBtn:SetCallback("OnClick", function()
        StyleBound:GetModule("OutfitLibrary"):SetFolder(outfit.id, nil)
        StyleBound:Print("Removed '" .. (outfit.name or "Untitled") .. "' from folder.")
        AceGUI:Release(moveFrame)
        if refreshCallback then refreshCallback() end
    end)
    moveFrame:AddChild(noneBtn)

    -- One button per folder
    local folders = StyleBound.db.global.folders or {}
    for _, folderName in ipairs(folders) do
        local folderBtn = AceGUI:Create("Button")
        local btnText = folderName
        if outfit.folder == folderName then
            btnText = "► " .. folderName .. " (current)"
        end
        folderBtn:SetText(btnText)
        folderBtn:SetFullWidth(true)
        folderBtn:SetCallback("OnClick", function()
            StyleBound:GetModule("OutfitLibrary"):SetFolder(outfit.id, folderName)
            StyleBound:Print("Moved '" .. (outfit.name or "Untitled") .. "' to '" .. folderName .. "'.")
            AceGUI:Release(moveFrame)
            if refreshCallback then refreshCallback() end
        end)
        moveFrame:AddChild(folderBtn)
    end

    if #folders == 0 then
        local hint = AceGUI:Create("Label")
        hint:SetText("|cFF888888No folders yet. Create one from the left panel.|r")
        hint:SetFullWidth(true)
        moveFrame:AddChild(hint)
    end
end

-------------------------------------------------------------------------------
-- Collection status check for an outfit
-------------------------------------------------------------------------------

local function GetMissingSlots(outfit)
    local missing = {}
    for slotKey, slotData in pairs(outfit.slots) do
        if slotData.s and slotData.s > 0 then
            if not C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(slotData.s) then
                missing[#missing + 1] = slotKey
            end
        end
    end
    return missing
end

-------------------------------------------------------------------------------
-- Build outfit list pane
-------------------------------------------------------------------------------

local function BuildOutfitList(container, refreshCallback)
    container:ReleaseChildren()

    local OutfitLibrary = StyleBound:GetModule("OutfitLibrary")
    local outfits = OutfitLibrary:List(activeFolder)

    if #outfits == 0 then
        local emptyLabel = AceGUI:Create("Label")
        if activeFolder then
            emptyLabel:SetText("\nNo outfits in folder '" .. activeFolder .. "'.\n\nSave outfits via /sb save or the Import screen.")
        else
            emptyLabel:SetText("\nNo saved outfits yet.\n\nSave outfits via /sb save, the Import screen, or /sb copy.")
        end
        emptyLabel:SetFullWidth(true)
        container:AddChild(emptyLabel)
        return
    end

    local scrollFrame = AceGUI:Create("ScrollFrame")
    scrollFrame:SetLayout("List")
    scrollFrame:SetFullWidth(true)
    scrollFrame:SetFullHeight(true)
    container:AddChild(scrollFrame)

    for _, outfit in ipairs(outfits) do
        local row = AceGUI:Create("SimpleGroup")
        row:SetFullWidth(true)
        row:SetLayout("Flow")
        scrollFrame:AddChild(row)

        -- Name + source badge + missing warning
        local missing = GetMissingSlots(outfit)
        local slotCount = 0
        for _ in pairs(outfit.slots) do slotCount = slotCount + 1 end

        local badge = SOURCE_BADGES[outfit.source] or ""
        local nameText = "|cFFFFD100" .. (outfit.name or "Untitled") .. "|r"
        if badge ~= "" then
            nameText = nameText .. "  " .. badge
        end
        nameText = nameText .. "  |cFF888888(" .. slotCount .. " slots)|r"
        if #missing > 0 then
            nameText = nameText .. "  |cFFFF6600⚠ " .. #missing .. " not collected|r"
        end

        local nameLabel = AceGUI:Create("InteractiveLabel")
        nameLabel:SetText(nameText)
        nameLabel:SetWidth(320)
        nameLabel:SetCallback("OnClick", function()
            PreviewOutfit(outfit)
        end)
        row:AddChild(nameLabel)

        -- Action buttons row
        local btnRow = AceGUI:Create("SimpleGroup")
        btnRow:SetFullWidth(true)
        btnRow:SetLayout("Flow")
        scrollFrame:AddChild(btnRow)

        local previewBtn = AceGUI:Create("Button")
        previewBtn:SetText("Preview")
        previewBtn:SetWidth(80)
        previewBtn:SetCallback("OnClick", function()
            PreviewOutfit(outfit)
        end)
        btnRow:AddChild(previewBtn)

        local customSetBtn = AceGUI:Create("Button")
        customSetBtn:SetText("Save as Set")
        customSetBtn:SetWidth(100)
        customSetBtn:SetCallback("OnClick", function()
            SaveAsCustomSet(outfit)
        end)
        btnRow:AddChild(customSetBtn)

        local shareBtn = AceGUI:Create("Button")
        shareBtn:SetText("Share")
        shareBtn:SetWidth(65)
        shareBtn:SetCallback("OnClick", function()
            ShareOutfit(outfit)
        end)
        btnRow:AddChild(shareBtn)

        local folderBtn = AceGUI:Create("Button")
        folderBtn:SetText("Folder")
        folderBtn:SetWidth(65)
        folderBtn:SetCallback("OnClick", function()
            PromptMoveToFolder(outfit, refreshCallback)
        end)
        btnRow:AddChild(folderBtn)

        local renameBtn = AceGUI:Create("Button")
        renameBtn:SetText("Rename")
        renameBtn:SetWidth(75)
        renameBtn:SetCallback("OnClick", function()
            PromptRename(outfit, refreshCallback)
        end)
        btnRow:AddChild(renameBtn)

        local deleteBtn = AceGUI:Create("Button")
        deleteBtn:SetText("Delete")
        deleteBtn:SetWidth(70)
        deleteBtn:SetCallback("OnClick", function()
            ConfirmDelete(outfit, refreshCallback)
        end)
        btnRow:AddChild(deleteBtn)

        -- Separator
        local sep = AceGUI:Create("Label")
        sep:SetText(" ")
        sep:SetFullWidth(true)
        scrollFrame:AddChild(sep)
    end
end

-------------------------------------------------------------------------------
-- Build folder pane
-------------------------------------------------------------------------------

local function BuildFolderPane(container, outfitContainer)
    container:ReleaseChildren()

    local refreshCallback = function()
        BuildOutfitList(outfitContainer, nil)
        BuildFolderPane(container, outfitContainer)
    end

    -- Inject refreshCallback into outfit list too
    local refreshAll = function()
        BuildFolderPane(container, outfitContainer)
        BuildOutfitList(outfitContainer, refreshAll)
    end

    -- "All" button
    local allBtn = AceGUI:Create("InteractiveLabel")
    local allText = "All Outfits"
    if activeFolder == nil then
        allText = "|cFF00FF00► |r" .. allText
    end
    allBtn:SetText(allText)
    allBtn:SetFullWidth(true)
    allBtn:SetCallback("OnClick", function()
        activeFolder = nil
        refreshAll()
    end)
    container:AddChild(allBtn)

    -- Folder list
    local folders = StyleBound.db.global.folders or {}
    for _, folderName in ipairs(folders) do
        local folderBtn = AceGUI:Create("InteractiveLabel")
        local text = folderName
        if activeFolder == folderName then
            text = "|cFF00FF00► |r" .. text
        end
        -- Count outfits in folder
        local count = 0
        for _, o in ipairs(StyleBound.db.global.outfits) do
            if o.folder == folderName then count = count + 1 end
        end
        text = text .. " |cFF888888(" .. count .. ")|r"
        folderBtn:SetText(text)
        folderBtn:SetFullWidth(true)
        folderBtn:SetCallback("OnClick", function()
            activeFolder = folderName
            refreshAll()
        end)
        container:AddChild(folderBtn)
    end

    -- Spacer
    local spacer = AceGUI:Create("Label")
    spacer:SetText(" ")
    spacer:SetFullWidth(true)
    container:AddChild(spacer)

    -- New Folder button
    local newFolderBtn = AceGUI:Create("Button")
    newFolderBtn:SetText("+ New Folder")
    newFolderBtn:SetFullWidth(true)
    newFolderBtn:SetCallback("OnClick", function()
        local promptFrame = AceGUI:Create("Frame")
        promptFrame:SetTitle("New Folder")
        promptFrame:SetWidth(300)
        promptFrame:SetHeight(130)
        promptFrame:SetLayout("List")
        promptFrame:SetCallback("OnClose", function(widget)
            AceGUI:Release(widget)
        end)

        local nameBox = AceGUI:Create("EditBox")
        nameBox:SetLabel("Folder Name:")
        nameBox:SetFullWidth(true)
        promptFrame:AddChild(nameBox)

        local createBtn = AceGUI:Create("Button")
        createBtn:SetText("Create")
        createBtn:SetFullWidth(true)
        createBtn:SetCallback("OnClick", function()
            local name = nameBox:GetText()
            if name and name ~= "" then
                if StyleBound:GetModule("OutfitLibrary"):CreateFolder(name) then
                    StyleBound:Print("Created folder '" .. name .. "'")
                    AceGUI:Release(promptFrame)
                    refreshAll()
                else
                    StyleBound:Print("Folder '" .. name .. "' already exists.")
                end
            end
        end)
        promptFrame:AddChild(createBtn)

        C_Timer.After(0.05, function()
            nameBox:SetFocus()
        end)
    end)
    container:AddChild(newFolderBtn)

    -- Build outfit list with the shared refresh
    BuildOutfitList(outfitContainer, refreshAll)
end

-------------------------------------------------------------------------------
-- Search
-------------------------------------------------------------------------------

local function BuildSearchResults(outfitContainer, query)
    outfitContainer:ReleaseChildren()

    local OutfitLibrary = StyleBound:GetModule("OutfitLibrary")
    local results = OutfitLibrary:Search(query)

    if #results == 0 then
        local label = AceGUI:Create("Label")
        label:SetText("\nNo outfits matching '" .. query .. "'.")
        label:SetFullWidth(true)
        outfitContainer:AddChild(label)
        return
    end

    local scrollFrame = AceGUI:Create("ScrollFrame")
    scrollFrame:SetLayout("List")
    scrollFrame:SetFullWidth(true)
    scrollFrame:SetFullHeight(true)
    outfitContainer:AddChild(scrollFrame)

    for _, outfit in ipairs(results) do
        local row = AceGUI:Create("SimpleGroup")
        row:SetFullWidth(true)
        row:SetLayout("Flow")
        scrollFrame:AddChild(row)

        local badge = SOURCE_BADGES[outfit.source] or ""
        local nameText = "|cFFFFD100" .. (outfit.name or "Untitled") .. "|r"
        if badge ~= "" then nameText = nameText .. "  " .. badge end
        if outfit.folder then nameText = nameText .. "  |cFF888888[" .. outfit.folder .. "]|r" end

        local nameLabel = AceGUI:Create("InteractiveLabel")
        nameLabel:SetText(nameText)
        nameLabel:SetWidth(350)
        nameLabel:SetCallback("OnClick", function()
            PreviewOutfit(outfit)
        end)
        row:AddChild(nameLabel)
    end
end

-------------------------------------------------------------------------------
-- Panel creation
-------------------------------------------------------------------------------

local function CreateBrowser()
    local f = AceGUI:Create("Frame")
    f:SetTitle("StyleBound — Outfit Library")
    f:SetWidth(650)
    f:SetHeight(500)
    f:SetLayout("Flow")
    ConfigureFrame(f, "outfitBrowser")
    f:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        frame = nil
    end)

    -- Search bar at top
    local searchGroup = AceGUI:Create("SimpleGroup")
    searchGroup:SetFullWidth(true)
    searchGroup:SetLayout("Flow")
    f:AddChild(searchGroup)

    local searchBox = AceGUI:Create("EditBox")
    searchBox:SetLabel("Search:")
    searchBox:SetWidth(300)
    searchGroup:AddChild(searchBox)

    -- Left pane: folders (narrow)
    local folderPane = AceGUI:Create("SimpleGroup")
    folderPane:SetWidth(150)
    folderPane:SetFullHeight(true)
    folderPane:SetLayout("List")
    f:AddChild(folderPane)

    -- Right pane: outfit list (fills remaining)
    local outfitPane = AceGUI:Create("SimpleGroup")
    outfitPane:SetWidth(470)
    outfitPane:SetFullHeight(true)
    outfitPane:SetLayout("Fill")
    f:AddChild(outfitPane)

    -- Wire up search
    searchBox:SetCallback("OnEnterPressed", function(_, _, text)
        if text and text ~= "" then
            BuildSearchResults(outfitPane, text)
        else
            BuildFolderPane(folderPane, outfitPane)
        end
    end)

    -- Initial render
    BuildFolderPane(folderPane, outfitPane)

    return f
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

function OutfitBrowser:Toggle()
    if frame then
        self:Hide()
    else
        self:Show()
    end
end

function OutfitBrowser:Show()
    if frame then return end
    activeFolder = nil
    frame = CreateBrowser()
end

function OutfitBrowser:Hide()
    if not frame then return end
    frame:Hide()
end

function OutfitBrowser:IsShown()
    return frame ~= nil
end
