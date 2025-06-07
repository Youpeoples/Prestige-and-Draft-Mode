-- Create a hidden tooltip for reading spell descriptions
local tooltip = CreateFrame("GameTooltip", "DummyTooltip", UIParent, "GameTooltipTemplate")
local totalDrafts = 0
local rarityTextures = {
  "COMM.tga",  -- Common
  "UNCO.tga",  -- Uncommon
  "RARE.tga",  -- Rare
  "EPIC.tga",  -- Epic
  "LEGE.tga",  -- Legendary
  "BROK.tga",  -- Broken (joke/trap cards?)
}
local lastSpellIDs = {}
local dismissToggled = false
local currentSpellRarities = {}
tooltip:SetOwner(UIParent, "ANCHOR_NONE")
GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
GameTooltip:SetFrameStrata("TOOLTIP")
GameTooltip:SetFrameLevel(100)
GameTooltip:SetClampedToScreen(true)
-- Filter out SC:123 whispers from showing in chat
local function SpellChoiceWhisperFilter(_, _, msg)
  if msg:match("^SC:%d+$") then return true end
end
local rerollsLeft = 0
ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", SpellChoiceWhisperFilter)         -- incoming
ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", SpellChoiceWhisperFilter) -- outgoing

local unlocked = false -- ← Controlled by server response
local frame = SpellChoiceFrame
SpellChoiceFrame:EnableMouse(true)
SpellChoiceFrame:SetFrameStrata("TOOLTIP")
GameTooltip:SetClampedToScreen(true)
local buttons = {SpellChoiceButton1, SpellChoiceButton2, SpellChoiceButton3}

-- Delay function for 3.3.5
local function Delay(seconds, func)
    local waitFrame = CreateFrame("Frame")
    local total = 0
    waitFrame:SetScript("OnUpdate", function(self, elapsed)
        total = total + elapsed
        if total >= seconds then
            self:SetScript("OnUpdate", nil)
            func()
            self = nil
        end
    end)
end
local function UpdateRerollButton()
  if not SpellChoiceRerollButton then return end
  SpellChoiceRerollButton:SetText("Reroll (" .. rerollsLeft .. ")")

  if rerollsLeft > 0 then
    SpellChoiceRerollButton:Enable()
  else
    SpellChoiceRerollButton:Disable()
  end
end
-- Debug helper
local function Debug(msg)
  --DEFAULT_CHAT_FRAME:AddMessage("|cff9999ff[DEBUG]|r " .. tostring(msg))
end

-- Request prestige status on login/reload
local function RequestPrestigeStatus()
  local target = UnitName("player")
  if target then
    SendChatMessage("SC_CHECK", "WHISPER", nil, UnitName("player"))
    --Debug("Sent SC_CHECK to server")
  else
    print("SpellChoice: Failed to send SC message — player name is nil.")
  end
end

-- Show spell choices to the player
local function ShowSpellChoices(spellIDs)
  if dismissToggled then
    -- Full suppression: disable everything interactable
    for _, btn in ipairs(buttons) do
      btn:Hide()
      btn:EnableMouse(false)
      btn:SetScript("OnEnter", nil)
      btn:SetScript("OnLeave", nil)
      btn:SetScript("OnClick", nil)
    end

    GameTooltip:Hide()
    GameTooltip:ClearAllPoints()
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")

    SpellChoiceFrame:Hide()
    SpellChoiceFrame:EnableMouse(false)
    SpellChoiceFrame:SetAlpha(0)
    return
  end

  --print("SpellChoiceTitle is", SpellChoiceTitle and "found" or "MISSING")
  if not unlocked then
    --Debug("Blocked: Player is not prestiged.")
    return
  end

  -- if UnitLevel("player") == 1 then
  --   Debug("Blocked: Player is level 1. Spell choices disabled.")
  --   return
  -- end

  --Debug("Showing spell choices...")

  for i = 1, #buttons do
    local spellID = tonumber(spellIDs[i])
    local btn = buttons[i]

    if spellID and btn then
      local name, _, icon = GetSpellInfo(spellID)

      btn.icon        = _G[btn:GetName() .. "Icon"]
      btn.name        = _G[btn:GetName() .. "Name"]
      --btn.mana        = _G[btn:GetName() .. "Mana"]
      --btn.castTime    = _G[btn:GetName() .. "CastTime"]
      --btn.description = _G[btn:GetName() .. "Description"]
      btn.levelReq    = _G[btn:GetName() .. "LevelReq"]

      if name and icon then
        Debug("Spell " .. i .. ": " .. name .. " (ID: " .. spellID .. ")")
        -- Force spell to load into cache
        local cacheTooltip = CreateFrame("GameTooltip", "CacheTooltip", UIParent, "GameTooltipTemplate")
        cacheTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        cacheTooltip:SetHyperlink("spell:" .. spellID)
        btn:SetID(spellID)
        btn.icon:SetTexture(icon)
        btn.name:SetText(name)
        local rarityFrame = _G[btn:GetName() .. "Rarity"]
        local rarityIndex = currentSpellRarities[i] or -1
        if rarityFrame and rarityIndex >= 0 then
          local rarityTex = rarityTextures[rarityIndex + 1]
          if rarityTex then
            rarityFrame:SetTexture("Interface\\AddOns\\PrestigeSystem\\Textures\\" .. rarityTex)
            rarityFrame:Show()
          else
            rarityFrame:Hide()
          end
        elseif rarityFrame then
          rarityFrame:Hide()
        end
        tooltip:ClearLines()
        tooltip:SetHyperlink("spell:" .. spellID)

        local descriptionLines = {}
        for i = 2, tooltip:NumLines() do
          local line = _G["DummyTooltipTextLeft" .. i]
          local text = line and line:GetText()
          if text and text:find("%S") then
            table.insert(descriptionLines, text)
          end
        end

        --btn.description:SetText(table.concat(descriptionLines, "\n"))
        --btn.levelReq:SetText("Required level: 1")
        btn:Show()
      else
        Debug("Missing data for spell ID: " .. tostring(spellID))
        btn:SetID(0)
        btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        btn.name:SetText("Unknown Spell")
        btn.description:SetText("Spell data not cached.")
        btn.levelReq:SetText("")
        btn:Show()
        local rarityFrame = _G[btn:GetName() .. "Rarity"]
        if rarityFrame then
          rarityFrame:Hide()
        end
      end
    else
      Debug("Invalid spell or button at index " .. tostring(i))
      if btn then btn:Hide() end
    end
  end

  frame:Show()
end


-- Event listening for addon messages
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("PLAYER_LOGIN")

local statusReceived = false -- Prevent duplicate prestige status handling

eventFrame:SetScript("OnEvent", function(self, event, prefix, message, channel, sender)
  if event == "PLAYER_LOGIN" then
    RequestPrestigeStatus()

  elseif event == "CHAT_MSG_ADDON" then
    if prefix == "SpellChoiceStatus" then
      if statusReceived then return end
      statusReceived = true

      if message == "prestiged" then
        unlocked = true
        Debug("SpellChoice unlocked (prestiged).")
      else
        unlocked = false
        Debug("SpellChoice locked (not prestiged).")
      end

    elseif prefix == "SpellChoice" then
      Debug("Received SpellChoice message: " .. message)
      local spellIDs = {}
      for id in string.gmatch(message, "%d+") do
        table.insert(spellIDs, tonumber(id))
      end
      Delay(0.5, function()
        lastSpellIDs = spellIDs 
        ShowSpellChoices(spellIDs)
      end)

    elseif prefix == "SpellChoiceClose" then
      frame:Hide()

    elseif prefix == "SpellChoiceRerollDenied" then
      UIErrorsFrame:AddMessage("You have no rerolls remaining.", 1, 0, 0, 1)

    elseif prefix == "SpellChoiceRerolls" then
      rerollsLeft = tonumber(message) or 0
      UpdateRerollButton()

    elseif prefix == "SpellChoiceDrafts" then
      local totalDrafts = tonumber(message) or 0
      if SpellChoiceTitle then
        SpellChoiceTitle:SetText("" .. totalDrafts .. " Drafts Remaining")
      end
      if dismissToggled and SpellChoiceDismissButton then
        SpellChoiceDismissButton:SetText(totalDrafts .. " Draft(s) Left")
      end
    elseif prefix == "SpellChoiceRarities" then
      currentSpellRarities = {}
      for r in string.gmatch(message, "-?%d+") do
        table.insert(currentSpellRarities, tonumber(r))
      end
      local rarities = {}
      for r in string.gmatch(message, "-?%d+") do
        table.insert(rarities, tonumber(r))
      end

      for i, rarity in ipairs(rarities) do
        local btn = buttons[i]
        local rarityFrame = _G[btn:GetName() .. "Rarity"]

        if rarity and rarity >= 0 then
          local rarityTex = rarityTextures[rarity + 1]
          if rarityTex and rarityFrame then
            rarityFrame:SetTexture("Interface\\AddOns\\PrestigeSystem\\Textures\\" .. rarityTex)
            rarityFrame:Show()
          elseif rarityFrame then
            rarityFrame:Hide()
          end
        elseif rarityFrame then
          -- Rarity is -1 or invalid (NULL or missing)
          rarityFrame:Hide()
        end
      end
    end
  end
end)

Debug("SpellChoice addon loaded.")

for _, btn in ipairs(buttons) do
  btn:SetScript("OnEnter", function(self)
    local spellID = self:GetID()
    if spellID and spellID > 0 then
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
      GameTooltip:SetHyperlink("spell:" .. spellID)
      GameTooltip:Show()
    end
  end)

  btn:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
  end)
btn:SetScript("OnClick", function(self)
    local spellID = self:GetID()
    if spellID and spellID > 0 then
      local target = UnitName("player")
      if target then
        SendChatMessage("SC:" .. spellID, "WHISPER", nil, target)
      else
        print("SpellChoice: Failed to send SC message — player name is nil.")
      end
    end
  end)


end



local rerollCooldown = false

SpellChoiceRerollButton:SetScript("OnClick", function()
  if rerollCooldown or not unlocked or rerollsLeft <= 0 then
    UIErrorsFrame:AddMessage("Cannot reroll at this time.", 1, 0, 0, 1)
    return
  end

  rerollCooldown = true
  SpellChoiceRerollButton:Disable()

  Delay(0.5, function()
    rerollCooldown = false
    UpdateRerollButton() -- Re-enables if rerollsLeft > 0
  end)

  local target = UnitName("player")
  if target then
    SendChatMessage("SC_REROLL", "WHISPER", nil, target)
  else
    print("SpellChoice: Failed to send SC_REROLL — player name is nil.")
  end
end)

SpellChoiceDismissButton:SetScript("OnClick", function(self)
    dismissToggled = not dismissToggled
    if dismissToggled then
        -- Hide all UI, show small dismiss button at center
        local label = SpellChoiceTitle:GetText() or ""
        local count = label:match("(%d+)") or "0"
        self:SetText(count .. " Draft(s) Left")
        for _, btn in ipairs(buttons) do
            btn:Hide()
            btn:EnableMouse(false)
            btn:SetScript("OnEnter", nil)
            btn:SetScript("OnLeave", nil)
            btn:SetScript("OnClick", nil)
        end
        SpellChoiceTitle:Hide()
        SpellChoiceRerollButton:Hide()
        SpellChoiceFrame:EnableMouse(false)
        SpellChoiceFrame:SetAlpha(0.01)
        -- Reparent dismiss to UIParent for central display
        self:SetParent(UIParent)
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "CENTER", 0, -300)
        self:SetFrameStrata("FULLSCREEN_DIALOG")
        self:EnableMouse(true)
        self:Show()
    else
        -- Toggle back on: fully restore UI
        self:SetText("Dismiss")
        if lastSpellIDs and #lastSpellIDs > 0 then
            ShowSpellChoices(lastSpellIDs)
        end
        -- Ensure frame and buttons are visible and interactive again
        SpellChoiceFrame:EnableMouse(true)
        SpellChoiceFrame:SetAlpha(1)
        SpellChoiceFrame:Show()
        for _, btn in ipairs(buttons) do
            btn:Show()
            btn:EnableMouse(true)
            -- Reattach hover (tooltip) handler
            btn:SetScript("OnEnter", function(self)
                local spellID = self:GetID()
                if spellID and spellID > 0 then
                    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                    GameTooltip:SetHyperlink("spell:" .. spellID)
                    GameTooltip:Show()
                end
            end)
            -- Reattach mouse-leave handler
            btn:SetScript("OnLeave", function(self)
                GameTooltip:Hide()
            end)
            -- Reattach click handler to send the SC:<spellID> whisper
            btn:SetScript("OnClick", function(self)
                local spellID = self:GetID()
                if spellID and spellID > 0 then
                    local target = UnitName("player")
                    if target then
                        SendChatMessage("SC:" .. spellID, "WHISPER", nil, target)
                    else
                        print("SpellChoice: Failed to send SC message — player name is nil.")
                    end
                end
            end)
        end
        SpellChoiceTitle:Show()
        SpellChoiceRerollButton:Show()
        -- Restore dismiss button to original parent/position
        self:SetParent(SpellChoiceFrame)
        self:ClearAllPoints()
        self:SetPoint("BOTTOM", SpellChoiceTitle, "TOP", 0, -290)
    end
end)


