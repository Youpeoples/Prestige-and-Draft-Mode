local REROLLS_PER_LEVELUP = 2
-- Tracks which players are actively “drafting” a spell (so we don’t block those)
local draftingPlayers = {}

-- Tracks which spells were just blocked from a trainer, so UpgradeKnownSpells will skip exactly those
-- indexed like: justBlockedSpells[guid][spellId] = true
local justBlockedSpells = {}

local spellChoicesPerPlayer = {}

local spellChoices = {}
-- List of exact spell IDs to exclude
local blacklistedSpellIds = {
}
local POOL_AMOUNT = 150

local function LoadSpellsFromDB(guid)
    local res = CharDBQuery("SELECT offered_spell_1, offered_spell_2, offered_spell_3 FROM prestige_stats WHERE player_id = " .. guid)
    if res then
        local spells = {
            res:GetUInt32(0),
            res:GetUInt32(1),
            res:GetUInt32(2)
        }
        spellChoicesPerPlayer[guid] = spells
        return spells
    end
    return nil
end

local function SaveSpellsToDB(guid, spells)
    CharDBExecute(string.format([[
        UPDATE prestige_stats
        SET offered_spell_1 = %d, offered_spell_2 = %d, offered_spell_3 = %d
        WHERE player_id = %d
    ]], spells[1], spells[2], spells[3], guid))
end

local function isLocationEffect(spell)
    return locationEffectTypes[spell.effect1]
        or locationEffectTypes[spell.effect2]
        or locationEffectTypes[spell.effect3]
end
-- Utility: check if spell ID is blacklisted
local function isBlacklistedSpellId(spellId)
    return blacklistedSpellIds[spellId] == true
end

-- Main loader function with randomization and filtering
local function LoadValidSpellChoices(player, maxLevel)
    spellChoices = {}

    -- Seed RNG for proper shuffling
    math.randomseed(os.time())

    -- Step 1: Load all known spells for this player from acore_characters.character_spell
    local knownSpellIds = {}
    local knownQuery = CharDBQuery("SELECT spell FROM character_spell WHERE guid = " .. player:GetGUIDLow())
    if knownQuery then
        repeat
            knownSpellIds[knownQuery:GetUInt32(0)] = true
        until not knownQuery:NextRow()
    end

    -- Step 2: Query valid spells from DBC
    local query = WorldDBQuery([[
    SELECT s.Id, s.Effect_1, s.Effect_2, s.Effect_3,
               s.Description_Lang_enUS, s.SpellLevel, s.MaxLevel, 
               s.DurationIndex, s.Category, s.Name_Lang_enUS, s.SpellIconID
          FROM dbc_spells s
          JOIN dbc_skilllineability sla ON s.Id = sla.Spell
          JOIN dbc_skillline sl ON sla.SkillLine = sl.ID
            AND sl.CategoryID IN (6, 7, 8, 9, 11)
         WHERE s.SpellLevel <= ]] .. maxLevel .. [[
           AND s.Id NOT IN (
               SELECT spell_id FROM spell_ranks WHERE spell_id != first_spell_id
           )
    ]])
    if not query then
        print("[SpellChoice] No valid spells found in WorldDB.")
        return
    end

    -- Step 3: Build full spell list
    local allSpells = {}

    repeat
        local spellId = query:GetUInt32(0)

        -- Skip if player already knows this spell
        if not knownSpellIds[spellId] then
            local spellData = {
                spellId       = spellId,
                effect1       = query:GetUInt32(1),
                effect2       = query:GetUInt32(2),
                effect3       = query:GetUInt32(3),
                desc          = query:GetString(4),
                baseLevel     = query:GetUInt32(5),
                maxLevelSpell = query:GetUInt32(6),
                durationIndex = query:GetUInt32(7),
                category      = query:GetUInt32(8),
                name          = query:GetString(9),
                iconId        = query:GetUInt32(10)
            }
            table.insert(allSpells, spellData)
        end
    until not query:NextRow()

    -- Shuffle using Fisher-Yates
    for i = #allSpells, 2, -1 do
        local j = math.random(i)
        allSpells[i], allSpells[j] = allSpells[j], allSpells[i]
    end

    -- Step 4: Filter
    local totalChecked = 0
    local totalAccepted = 0
    for _, spell in ipairs(allSpells) do
        totalChecked = totalChecked + 1
        local rejectedReasons = {}

        if isBlacklistedSpellId(spell.spellId) then
            table.insert(rejectedReasons, "Blacklisted ID")
        end

        if spell.desc == '' then
            table.insert(rejectedReasons, "Empty desc")
        end

        if spell.name == '' then
            table.insert(rejectedReasons, "Empty name")
        end

        if spell.iconId <= 1 then
            table.insert(rejectedReasons, "Missing icon")
        end

        if #rejectedReasons == 0 then
            table.insert(spellChoices, spell.spellId)
            totalAccepted = totalAccepted + 1
        else
            print("[SpellChoice] Rejected Spell: " .. spell.spellId .. " - " .. (spell.name or "nil") ..
                  " | Reason(s): " .. table.concat(rejectedReasons, ", "))
        end

        if totalAccepted >= POOL_AMOUNT then
            break
        end
    end

    print("[SpellChoice] Randomized check: scanned " .. totalChecked .. ", accepted " .. totalAccepted .. " for level " .. maxLevel)
end






-- Utility: check if table contains value
local function tableContains(tbl, val)
    for _, v in ipairs(tbl) do
        if v == val then return true end
    end
    return false
end
-- Prevent players in Draft Mode from learning new spells (via trainer or other means)
local function OnLearnSpell(event, player, spellId)
    local guid = player:GetGUIDLow()

    -- 1) If this LearnSpell was triggered by our draft system, allow it immediately:
    if draftingPlayers[guid] then
        return
    end

    -- 2) Otherwise, check if the player is flagged draft_state = 1:
    local res = CharDBQuery(
        "SELECT draft_state FROM prestige_stats WHERE player_id = " .. guid
    )
    if res and res:GetUInt32(0) == 1 then
        -- a) Tell the player it’s blocked:
        player:SendBroadcastMessage("You cannot learn new spells while in Draft Mode.")

        -- b) Instead of removing immediately, schedule it 0.5s later:
        CreateLuaEvent(function()
            -- Re‐grab the player object (they might have logged off)
            local p = GetPlayerByGUID(guid)
            if not p then
                return
            end

            -- Remove from their in‐memory spellbook:
            p:RemoveSpell(spellId)

            -- Permanently delete from the database so the trainer UI never shows it:
            CharDBExecute(
                "DELETE FROM character_spell WHERE guid = " .. guid .. " AND spell = " .. spellId
            )

            print("[SpellBlock] (delayed) Removed spell " .. spellId .. " from " .. p:GetName())
        end, 250, 1)  -- 500 ms delay, fire once

        -- c) Mark it “just blocked,” in case your rank‐up logic needs to know:
        justBlockedSpells[guid] = justBlockedSpells[guid] or {}
        justBlockedSpells[guid][spellId] = true

        print("[SpellBlock] Scheduled removal of spell " .. spellId .. " for " .. player:GetName())
    end

end

local function UpgradeKnownSpells(player)
    local level = player:GetLevel()
    local upgraded = 0

    local visitedRoot = {}
    local knownSpells = player:GetSpells()  -- Returns an array of { spellId, … }

    for _, spellId in ipairs(knownSpells) do
        local rootQ = WorldDBQuery(
            "SELECT first_spell_id FROM spell_ranks WHERE spell_id = " .. spellId .. " LIMIT 1"
        )
        local firstSpellId = (rootQ and rootQ:GetUInt32(0)) or spellId

        if not visitedRoot[firstSpellId] then
            visitedRoot[firstSpellId] = true

            local rankQuery = WorldDBQuery([[
                SELECT sr.spell_id, ds.SpellLevel
                  FROM spell_ranks sr
                  JOIN dbc_spells ds ON sr.spell_id = ds.Id
                 WHERE sr.first_spell_id = ]] .. firstSpellId .. [[
                   ORDER BY ds.SpellLevel ASC
            ]])

            if rankQuery then
                repeat
                    local candidateId = rankQuery:GetUInt32(0)
                    local candidateLvl = rankQuery:GetUInt32(1)

                    if candidateLvl <= level and not player:HasSpell(candidateId) then
                        local guid = player:GetGUIDLow()

                        if not (justBlockedSpells[guid] and justBlockedSpells[guid][candidateId]) then
                            CharDBExecute(
                                "INSERT IGNORE INTO drafted_spells (player_guid, spell_id) VALUES (" .. guid .. ", " .. candidateId .. ")"
                            )

                            draftingPlayers[guid] = true
                            player:LearnSpell(candidateId)
                            draftingPlayers[guid] = nil

                            upgraded = upgraded + 1
                        else
                            justBlockedSpells[guid][candidateId] = nil
                        end
                    end
                until not rankQuery:NextRow()
            end
        end
    end

    if upgraded > 0 then
        print("[SpellChoice] Taught " .. upgraded .. " spells to " .. player:GetName())
    end  
end



-- Utility: shuffle and select N random spells
local function GetRandomSpells(num)
    local shuffled = {}
    for _, spell in ipairs(spellChoices) do
        table.insert(shuffled, spell)
    end
    for i = #shuffled, 2, -1 do
        local j = math.random(i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end
    local selected = {}
    for i = 1, num do
        table.insert(selected, shuffled[i])
    end
    return selected
end

-- Store current choices per player
local spellChoicesPerPlayer = {}

-- Event: Player level-up
local function OnLevelUp(event, player, oldLevel)
    print("[DEBUG] Player leveled up: " .. player:GetName())

    local guid = player:GetGUIDLow()

    -- Block if player has not unlocked spell draft (draft_state < 1)
    local result = CharDBQuery("SELECT draft_state FROM prestige_stats WHERE player_id = " .. guid)
    if not result or result:GetUInt32(0) < 1 then
        return
    end

    -- Prevent spell choice at level 1
    -- if player:GetLevel() == 1 then
    --     return
    -- end

    -- Increment expected drafts AND rerolls
    CharDBQuery(string.format([[
        INSERT INTO prestige_stats (player_id, successful_drafts, total_expected_drafts, draft_state, rerolls)
        VALUES (%d, 0, 1, 1, %d)
        ON DUPLICATE KEY UPDATE
            total_expected_drafts = total_expected_drafts + 1,
            rerolls = rerolls + %d;
    ]], guid, REROLLS_PER_LEVELUP, REROLLS_PER_LEVELUP))
    -- Send updated rerolls to client
    local rerollQ = CharDBQuery("SELECT rerolls FROM prestige_stats WHERE player_id = " .. guid)
    if rerollQ then
      local rerolls = rerollQ:GetUInt32(0)
      player:SendAddonMessage("SpellChoiceRerolls", tostring(rerolls), 0, player)
    end
    -- Check if player is due for a draft
    local check = CharDBQuery("SELECT successful_drafts, total_expected_drafts FROM prestige_stats WHERE player_id = " .. guid)
    if not check then return end

    local successful = check:GetUInt32(0)
    local expected = check:GetUInt32(1)

    if successful >= expected then
        print("[DEBUG] Player has no pending draft: " .. player:GetName())
        return
    end
    local remaining = math.max(0, expected - successful)
    player:SendAddonMessage("SpellChoiceDrafts", tostring(remaining), 0, player)
    -- Reset and reload valid spell choices
    -- Check if player already has pending spells
    local existing = LoadSpellsFromDB(guid)
    if not existing or existing[1] == 0 then
        -- No pending spells, generate new ones
        ValidSpellChoices = {}
        LoadValidSpellChoices(player, player:GetLevel())

        local spells = GetRandomSpells(3)
        spellChoicesPerPlayer[guid] = spells
        SaveSpellsToDB(guid, spells)

        local data = table.concat(spells, ",")
        print("[DEBUG] New spells for " .. player:GetName() .. ": " .. data)
        player:SendBroadcastMessage("[DEBUG] Sending spell choices: " .. data)
        player:SendAddonMessage("SpellChoice", data, 0, player)
        local rarityParts = {}
        for _, id in ipairs(spells) do
            local q = WorldDBQuery("SELECT Rarity FROM dbc_spells WHERE Id = " .. id)
            table.insert(rarityParts, q and (q:IsNull(0) and "-1" or tostring(q:GetUInt8(0))) or "-1")
        end
        player:SendAddonMessage("SpellChoiceRarities", table.concat(rarityParts, ","), 0, player)
    else
        print("[DEBUG] Player already has pending draft. Resending existing spells.")

        spellChoicesPerPlayer[guid] = existing
        local data = table.concat(existing, ",")
        player:SendBroadcastMessage("[DEBUG] Resending existing spell choices: " .. data)
        player:SendAddonMessage("SpellChoice", data, 0, player)
        local rarityParts = {}
        for _, id in ipairs(existing) do
            local q = WorldDBQuery("SELECT Rarity FROM dbc_spells WHERE Id = " .. id)
            table.insert(rarityParts, q and (q:IsNull(0) and "-1" or tostring(q:GetUInt8(0))) or "-1")
        end
        player:SendAddonMessage("SpellChoiceRarities", table.concat(rarityParts, ","), 0, player)
    end

end


-- Event: Player sends whisper to addon
local function OnAddonWhisper(event, player, msg, msgType, lang, receiver)
    local guid = player:GetGUIDLow()

    -- Handle SC_CHECK (client re-checks prestige)    
    if msg == "SC_CHECK" then
        local result = CharDBQuery("SELECT draft_state, rerolls FROM prestige_stats WHERE player_id = " .. guid)
        if result then
            local draftState = result:GetUInt32(0)
            local rerolls = result:GetUInt32(1)

            local status = draftState >= 1 and "prestiged" or "not_prestiged"

            local drafts = CharDBQuery("SELECT total_expected_drafts FROM prestige_stats WHERE player_id = " .. player:GetGUIDLow())
            
            local playerGuid = player:GetGUIDLow()
            local query = CharDBQuery("SELECT total_expected_drafts, successful_drafts FROM prestige_stats WHERE player_id = " .. playerGuid)
            if query then
                local totalExpected = query:GetUInt32(0)
                local successful = query:GetUInt32(1)
                local totalDrafts = totalExpected - successful
                if totalDrafts < 0 then totalDrafts = 0 end -- safety clamp
                player:SendAddonMessage("SpellChoiceDrafts", tostring(totalDrafts), 0, player)
            end
            player:SendAddonMessage("SpellChoiceStatus", status, 0, player)

            -- NEW: Send reroll count too
            player:SendAddonMessage("SpellChoiceRerolls", tostring(rerolls), 0, player)
        end
        return false
    end

    -- Handle SC_REROLL
    if msg == "SC_REROLL" then
        local result = CharDBQuery("SELECT draft_state, rerolls FROM prestige_stats WHERE player_id = " .. guid)
        local updatedQ = CharDBQuery("SELECT total_expected_drafts, successful_drafts FROM prestige_stats WHERE player_id = " .. guid)
        if updatedQ then
            local totalExpected = updatedQ:GetUInt32(0)
            local successful = updatedQ:GetUInt32(1)
            local remaining = math.max(0, totalExpected - successful)
            player:SendAddonMessage("SpellChoiceDrafts", tostring(remaining), 0, player)
        end
        if not result or result:GetUInt32(0) < 1 then
            player:SendBroadcastMessage("You are not prestiged.")
            return false
        end

        local rerolls = result:GetUInt32(1)
        if rerolls <= 0 then
            player:SendBroadcastMessage("No rerolls remaining.")
            return false
        end

        -- Reduce reroll count and update
        CharDBExecute("UPDATE prestige_stats SET rerolls = rerolls - 1 WHERE player_id = " .. guid)

        local spells = GetRandomSpells(3)
        spellChoicesPerPlayer[guid] = spells
        SaveSpellsToDB(guid, spells)
        local data = table.concat(spells, ",")
        print("[SpellChoice] Rerolled spell choices for " .. player:GetName() .. ": " .. data)
        player:SendBroadcastMessage("[DEBUG] Sending spell choices: " .. data)
        player:SendAddonMessage("SpellChoice", data, 0, player)
        local rerolls = result:GetUInt32(1) - 1
        player:SendAddonMessage("SpellChoiceRerolls", tostring(rerolls), 0, player)
        local rarityParts = {}
        for _, id in ipairs(spells) do
            local q = WorldDBQuery("SELECT Rarity FROM dbc_spells WHERE Id = " .. id)
            table.insert(rarityParts, q and (q:IsNull(0) and "-1" or tostring(q:GetUInt8(0))) or "-1")
        end
        player:SendAddonMessage("SpellChoiceRarities", table.concat(rarityParts, ","), 0, player)
        return false
    end

    -- Handle SC:<spellId>
    local spellId = tonumber(msg:match("^SC:(%d+)$"))
    if not spellId then return end

    local level = player:GetLevel()
    local result = CharDBQuery("SELECT draft_state FROM prestige_stats WHERE player_id = " .. guid)
    local isPrestiged = result and result:GetUInt32(0) >= 1

    if not isPrestiged then
        player:SendBroadcastMessage("You are not prestiged.")
        return false
    end

    -- if level == 1 then
    --     player:SendBroadcastMessage("You cannot select a spell at level 1.")
    --     return false
    -- end

    if player:HasSpell(spellId) then
        player:SendBroadcastMessage("You already know that spell. Rerolling...")

        local spells = GetRandomSpells(3)
        spellChoicesPerPlayer[guid] = spells
        local data = table.concat(spells, ",")
        print("[SpellChoice] Auto-reroll (duplicate spell) for " .. player:GetName() .. ": " .. data)
        player:SendAddonMessage("SpellChoice", data, 0, player)
        local rarityParts = {}
        for _, id in ipairs(spells) do
            local q = WorldDBQuery("SELECT Rarity FROM dbc_spells WHERE Id = " .. id)
            table.insert(rarityParts, q and (q:IsNull(0) and "-1" or tostring(q:GetUInt8(0))) or "-1")
        end
        player:SendAddonMessage("SpellChoiceRarities", table.concat(rarityParts, ","), 0, player)
        return false
    end

    local validChoices = spellChoicesPerPlayer[guid]
    if not validChoices or not tableContains(validChoices, spellId) then
        player:SendBroadcastMessage("Invalid spell selection.")
        return false
    end

    -- Increment successful drafts
    CharDBExecute("UPDATE prestige_stats SET successful_drafts = successful_drafts + 1 WHERE player_id = " .. guid)
    local updatedQ = CharDBQuery("SELECT total_expected_drafts, successful_drafts FROM prestige_stats WHERE player_id = " .. guid)
    if updatedQ then
        local totalExpected = updatedQ:GetUInt32(0)
        local successful = updatedQ:GetUInt32(1)
        local remaining = math.max(0, totalExpected - successful)
        player:SendAddonMessage("SpellChoiceDrafts", tostring(remaining), 0, player)
    end
    draftingPlayers[guid] = true
    player:LearnSpell(spellId)
    draftingPlayers[guid] = nil
    CharDBExecute(string.format([[
        UPDATE prestige_stats
        SET offered_spell_1 = 0, offered_spell_2 = 0, offered_spell_3 = 0
        WHERE player_id = %d
    ]], guid))
    CharDBExecute("INSERT IGNORE INTO drafted_spells (player_guid, spell_id) VALUES (" .. guid .. ", " .. spellId .. ")")
    UpgradeKnownSpells(player)

    spellChoicesPerPlayer[guid] = nil
    player:SendAddonMessage("SpellChoiceClose", "", 0, player)
    -- Fresh query and send updated draft count again
    local check = CharDBQuery("SELECT total_expected_drafts, successful_drafts FROM prestige_stats WHERE player_id = " .. guid)
    if check then
        local totalExpected = check:GetUInt32(0)
        local successful = check:GetUInt32(1)
        local remaining = math.max(0, totalExpected - successful)
        player:SendAddonMessage("SpellChoiceDrafts", tostring(remaining), 0, player)

    end
    -- Check for additional pending drafts
    local check = CharDBQuery("SELECT successful_drafts, total_expected_drafts FROM prestige_stats WHERE player_id = " .. guid)
    if check then
        local successful = check:GetUInt32(0)
        local expected = check:GetUInt32(1)

        if successful < expected then
            local spells = GetRandomSpells(3)
            spellChoicesPerPlayer[guid] = spells
            SaveSpellsToDB(guid, spells) 
            local data = table.concat(spells, ",")
            print("[SpellChoice] Follow-up draft for " .. player:GetName() .. ": " .. data)
            player:SendBroadcastMessage("[DEBUG] Sending follow-up spell choices: " .. data)
            player:SendAddonMessage("SpellChoice", data, 0, player)
            local rarityParts = {}
            for _, id in ipairs(spells) do
                local q = WorldDBQuery("SELECT Rarity FROM dbc_spells WHERE Id = " .. id)
                table.insert(rarityParts, q and (q:IsNull(0) and "-1" or tostring(q:GetUInt8(0))) or "-1")
            end
            player:SendAddonMessage("SpellChoiceRarities", table.concat(rarityParts, ","), 0, player)
        end
    end

    return false
end


local function BeginDraftLoop(player, guid, rerolls, successful, expected)
    if not player or not player:IsInWorld() then return end
    if successful >= expected then return end

    -- Send status and rerolls again, just to be safe

    local playerGuid = player:GetGUIDLow()
    local query = CharDBQuery("SELECT total_expected_drafts, successful_drafts FROM prestige_stats WHERE player_id = " .. playerGuid)
    if query then
        local totalExpected = query:GetUInt32(0)
        local successful = query:GetUInt32(1)
        local totalDrafts = totalExpected - successful
        if totalDrafts < 0 then totalDrafts = 0 end -- safety clamp
        player:SendAddonMessage("SpellChoiceDrafts", tostring(totalDrafts), 0, player)
    end

    player:SendAddonMessage("SpellChoiceStatus", "prestiged", 0, player)
    player:SendAddonMessage("SpellChoiceRerolls", tostring(rerolls), 0, player)

    -- First spell roll
    -- Load from DB or generate if missing
    local spells = LoadSpellsFromDB(guid)
    if not spells or spells[1] == 0 then
        spells = GetRandomSpells(3)
        SaveSpellsToDB(guid, spells)
    end
    spellChoicesPerPlayer[guid] = spells
    SaveSpellsToDB(guid, spells) 
    local data = table.concat(spells, ",")
    print("[DEBUG] (Login) Pending draft for " .. player:GetName() .. ": " .. data)
    player:SendBroadcastMessage("[DEBUG] Sending spell choices: " .. data)
    player:SendAddonMessage("SpellChoice", data, 0, player)
    local rarityParts = {}
    for _, id in ipairs(spells) do
        local q = WorldDBQuery("SELECT Rarity FROM dbc_spells WHERE Id = " .. id)
        table.insert(rarityParts, q and (q:IsNull(0) and "-1" or tostring(q:GetUInt8(0))) or "-1")
    end
    player:SendAddonMessage("SpellChoiceRarities", table.concat(rarityParts, ","), 0, player)
end

-- Player login hook
local function OnLogin(event, player)
    local guid = player:GetGUIDLow()
        local playerGuid = player:GetGUIDLow()
    print("[DEBUG] Player GUID:", playerGuid)

    local query = CharDBQuery("SELECT total_expected_drafts, successful_drafts FROM prestige_stats WHERE player_id = " .. playerGuid)
    if query then
        local totalExpected = query:GetUInt32(0)
        local successful = query:GetUInt32(1)
        print("[DEBUG] total_expected_drafts:", totalExpected)
        print("[DEBUG] successful_drafts:", successful)
        local totalDrafts = totalExpected - successful
        if totalDrafts < 0 then totalDrafts = 0 end
        print("[DEBUG] totalDrafts remaining:", totalDrafts)
        player:SendAddonMessage("SpellChoiceDrafts", tostring(totalDrafts), 0, player)
    else
        print("This player is not setup for drafting", playerGuid)
    end

    local result = CharDBQuery("SELECT draft_state, rerolls, successful_drafts, total_expected_drafts FROM prestige_stats WHERE player_id = " .. guid)

    if not result then
    local playerGuid = player:GetGUIDLow()
    local query = CharDBQuery("SELECT total_expected_drafts, successful_drafts FROM prestige_stats WHERE player_id = " .. playerGuid)
    if query then
        local totalExpected = query:GetUInt32(0)
        local successful = query:GetUInt32(1)
        local totalDrafts = totalExpected - successful
        if totalDrafts < 0 then totalDrafts = 0 end -- safety clamp
        player:SendAddonMessage("SpellChoiceDrafts", tostring(totalDrafts), 0, player)
    end

        player:SendAddonMessage("SpellChoiceStatus", "not_prestiged", 0, player)
        player:SendAddonMessage("SpellChoiceRerolls", "0", 0, player)
        return
    end

    local draft = result:GetUInt32(0)
    local rerolls = result:GetUInt32(1)
    local successful = result:GetUInt32(2)
    local expected = result:GetUInt32(3)

    if draft >= 1 then

        --Ensure spell list is loaded
        if not spellChoices or #spellChoices == 0 then
            LoadValidSpellChoices(player, player:GetLevel())-- or 80 if you want full list
        end

        -- Start draft loop
        BeginDraftLoop(player, guid, rerolls, successful, expected)
    else

    local playerGuid = player:GetGUIDLow()
    local query = CharDBQuery("SELECT total_expected_drafts, successful_drafts FROM prestige_stats WHERE player_id = " .. playerGuid)
    if query then
        local totalExpected = query:GetUInt32(0)
        local successful = query:GetUInt32(1)
        local totalDrafts = totalExpected - successful
        if totalDrafts < 0 then totalDrafts = 0 end -- safety clamp
        player:SendAddonMessage("SpellChoiceDrafts", tostring(totalDrafts), 0, player)
    end

        player:SendAddonMessage("SpellChoiceStatus", "not_prestiged", 0, player)
        player:SendAddonMessage("SpellChoiceRerolls", "0", 0, player)
    end
end

local lastZoneDraft = {}

local function OnZoneChanged(event, player, newZone, newArea)
    local guid = player:GetGUIDLow()

    local result = CharDBQuery("SELECT successful_drafts, total_expected_drafts FROM prestige_stats WHERE player_id = " .. guid)
    if not result then return end

    local successful = result:GetUInt32(0)
    local expected = result:GetUInt32(1)

    if successful < expected then
        -- Prevent spammy triggers
        local now = os.time()
        if lastZoneDraft[guid] and now - lastZoneDraft[guid] < 5 then
            return
        end
        lastZoneDraft[guid] = now

        -- Delay zone-triggered draft
        CreateLuaEvent(function()
            local p = GetPlayerByGUID(guid)
            if not p or not p:IsInWorld() then return end

            if not spellChoices or not spellChoicesPerPlayer[guid] then
                LoadValidSpellChoices(p, p:GetLevel())
            end

            local spells = spellChoicesPerPlayer[guid]
            if not spells or #spells ~= 3 then
                spells = LoadSpellsFromDB(guid)
                if not spells or spells[1] == 0 then
                    spells = GetRandomSpells(3)
                    SaveSpellsToDB(guid, spells)
                end
                spellChoicesPerPlayer[guid] = spells
                SaveSpellsToDB(guid, spells)
            end

            local data = table.concat(spells, ",")
            print("[SpellChoice] Zone-triggered draft for " .. p:GetName() .. ": " .. data)
            p:SendBroadcastMessage("[DEBUG] Sending zone-triggered spell choices: " .. data)
            p:SendAddonMessage("SpellChoice", data, 0, p)
            local rarityParts = {}
            for _, id in ipairs(spells) do
                local q = WorldDBQuery("SELECT Rarity FROM dbc_spells WHERE Id = " .. id)
                table.insert(rarityParts, q and (q:IsNull(0) and "-1" or tostring(q:GetUInt8(0))) or "-1")
            end
            p:SendAddonMessage("SpellChoiceRarities", table.concat(rarityParts, ","), 0, p)
        end, 2000, 1)
    end
end







-- Register events
RegisterPlayerEvent(44, OnLearnSpell) -- EVENT_ON_LEARN_SPELL
RegisterPlayerEvent(13, OnLevelUp)       -- PLAYER_LEVEL_CHANGED
RegisterPlayerEvent(19, OnAddonWhisper) -- ON_WHISPER
RegisterPlayerEvent(3, OnLogin)
RegisterPlayerEvent(27, OnZoneChanged) -- EVENT_ON_UPDATE_ZONE


