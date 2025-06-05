local prestigeTitles = {
    [1] = 523, [2] = 524, [3] = 525, [4] = 526,
    [5] = 527, [6] = 528, [7] = 529, [8] = 530,
    [9] = 531, [10] = 532, [11] = 537
}

-- Check if the player is in draft state
local function IsPlayerInDraft(player)
    local guid = player:GetGUIDLow()
    local query = CharDBQuery("SELECT draft_state FROM prestige_stats WHERE player_id = " .. guid)
    return query and query:GetUInt32(0) == 1
end

-- Apply custom power values
local function ApplyDraftPowerTypes(player)
    if not player or not player:IsInWorld() then return end

    player:SetMaxPower(1, 100)  -- Rage
    player:SetPower(100, 1)
    player:SetMaxPower(3, 100)  -- Energy
    player:SetPower(100, 3)
    player:SetPowerType(1)  -- Force Rage display
    player:SetPower(player:GetMaxPower(0), 0)  -- Fill mana

    -- print("[Prestige] Draft power types reapplied for:", player:GetName())
end

-- Track ticking players
local draftTickerGUIDs = {}

local function StartDraftPowerTicker(player)
    local guid = player:GetGUIDLow()
    if draftTickerGUIDs[guid] then return end  -- Already ticking

    local eventId = CreateLuaEvent(function()
        local p = GetPlayerByGUID(guid)
        if not p or not p:IsInWorld() then
            RemoveEventById(draftTickerGUIDs[guid])
            draftTickerGUIDs[guid] = nil
            return
        end

        p:SetPowerType(1)  -- Force Rage display
    end, 2000, 0)

    draftTickerGUIDs[guid] = eventId
end

-- Give title for prestige level
local function GivePrestigeTitle(guid, prestigeLevel)
    local player = GetPlayerByGUID(guid)
    if player then
        local titleId = prestigeTitles[prestigeLevel]
        if titleId and not player:HasTitle(titleId) then
            player:SetKnownTitle(titleId)
        end
    end
end

-- On login: ensure DB row, give title, maybe start ticker
local function EnsurePrestigeEntry(_, player)
    local guid = player:GetGUIDLow()
    local query = CharDBQuery("SELECT prestige_level, draft_state FROM prestige_stats WHERE player_id = " .. guid)

    if query then
        local prestigeLevel = query:GetUInt32(0)
        local draftState = query:GetUInt32(1)

        CreateLuaEvent(function()
            local p = GetPlayerByGUID(guid)
            if not p then return end

            GivePrestigeTitle(guid, prestigeLevel)

            if draftState == 1 then
                ApplyDraftPowerTypes(p)
                StartDraftPowerTicker(p)
            end
        end, 3000, 1)
    else
        local class = player:GetClass()
        CharDBExecute("INSERT INTO prestige_stats (player_id, prestige_level, draft_state, stored_class) VALUES (" .. guid .. ", 0, 0, " .. class .. ")")
    end
end

-- Apply draft state if needed
local function OnRebuildEvent(_, player)
    if IsPlayerInDraft(player) then
        ApplyDraftPowerTypes(player)
        StartDraftPowerTicker(player)
    end
end
local function OnPlayerLogout(_, player)
    local guid = player:GetGUIDLow()
    if draftTickerGUIDs[guid] then
        RemoveEventById(draftTickerGUIDs[guid])
        draftTickerGUIDs[guid] = nil
    end
end

-- Register only valid events
RegisterPlayerEvent(4, OnPlayerLogout)
RegisterPlayerEvent(3, EnsurePrestigeEntry)   -- On login
RegisterPlayerEvent(13, OnRebuildEvent)       -- On level change
RegisterPlayerEvent(28, OnRebuildEvent)       -- On map change
RegisterPlayerEvent(35, OnRebuildEvent)       -- On repop
RegisterPlayerEvent(36, OnRebuildEvent)       -- On resurrect
RegisterPlayerEvent(5, OnRebuildEvent)        -- On spell cast (catches form/stealth)
RegisterPlayerEvent(33, OnRebuildEvent)       -- On enter combat
RegisterPlayerEvent(34, OnRebuildEvent)       -- On leave combat
