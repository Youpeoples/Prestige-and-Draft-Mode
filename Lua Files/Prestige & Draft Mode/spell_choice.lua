dofile("lua_scripts/prestige_and_spell_choice_config.lua")
local DRAFT_MODE_SPELLS = CONFIG.DRAFT_MODE_SPELLS
local DRAFT_REROLLS_GAINED_PER_PRESTIGE_LEVEL = CONFIG.DRAFT_REROLLS_GAINED_PER_PRESTIGE_LEVEL
local INCLUDE_RARITY_5 = CONFIG.INCLUDE_RARITY_5
local REROLLS_PER_LEVELUP = CONFIG.REROLLS_PER_LEVELUP
local POOL_AMOUNT = CONFIG.POOL_AMOUNT
local RARITY_DISTRIBUTION = CONFIG.RARITY_DISTRIBUTION
-- Tracks which players are actively “drafting” a spell (so we don’t block those)
local draftingPlayers = {}

-- Tracks which spells were just blocked from a trainer, so UpgradeKnownSpells will skip exactly those
-- indexed like: justBlockedSpells[guid][spellId] = true
local justBlockedSpells = {}
local lastSpellChoiceSent = {}

-- Holds the full valid pool per player
local fullSpellPools = {}
-- Holds the current 3 choices shown to player

local currentDraftChoices = {}-- List of exact spell IDs to exclude
local blacklistedSpellIds = {}
-- Utility: shuffle and select N random spells
local function GetRandomSpells(num, guid, excludeSet)
    local copy = {}
    for _, id in ipairs(fullSpellPools[guid] or {}) do
        -- Skip if this spell is banned for this player
        local banned = CharDBQuery("SELECT 1 FROM draft_bans WHERE player_id = " .. guid .. " AND spell_id = " .. id)
        if not banned and not (excludeSet and excludeSet[id]) then
            table.insert(copy, id)
        end
    end

    -- Shuffle and return
    for i = #copy, 2, -1 do
        local j = math.random(i)
        copy[i], copy[j] = copy[j], copy[i]
    end

    local result = {}
    local seen = {}
    for i = 1, #copy do
        local id = copy[i]
        if not seen[id] then
            table.insert(result, id)
            seen[id] = true
        end
        if #result >= num then break end
    end

    if #result < num then
        --print(string.format("[SpellChoice] Warning: Only %d/%d unique spells found for player %d", #result, num, guid))
    end
    return result
end
local function LoadSpellsFromDB(guid)
    local banned = {}
    local banQ = CharDBQuery("SELECT spell_id FROM draft_bans WHERE player_id = " .. guid)
    if banQ then
        repeat
            banned[banQ:GetUInt32(0)] = true
        until not banQ:NextRow()
    end

    local res = CharDBQuery("SELECT offered_spell_1, offered_spell_2, offered_spell_3 FROM prestige_stats WHERE player_id = " .. guid)
    if not res then return nil end

    local spells = {}
    for i = 0, 2 do
        local id = res:GetUInt32(i)
        if id and id > 0 and not banned[id] then
            table.insert(spells, id)
        end
    end

    -- Replace banned slots with new picks from pool
    if #spells < 3 then
        local needed = 3 - #spells
        local fill = GetRandomSpells(needed, guid)
        for _, id in ipairs(fill) do
            table.insert(spells, id)
        end

        -- Update DB with cleaned set
        CharDBExecute(string.format("UPDATE prestige_stats SET offered_spell_1 = %d, offered_spell_2 = %d, offered_spell_3 = %d WHERE player_id = %d",
            spells[1] or 0, spells[2] or 0, spells[3] or 0, guid))

        --print(string.format("[SpellChoice] Replaced banned spells on load for player %d → %d,%d,%d", guid, spells[1] or 0, spells[2] or 0, spells[3] or 0))
    end

    currentDraftChoices[guid] = spells
    return spells
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
    local guid = player:GetGUIDLow()
    local pool = {}
    -- Fetch all banned spell *names* to exclude all ranks
    local bannedNames = {}
    local banQ = CharDBQuery("SELECT spell_id FROM draft_bans WHERE player_id = " .. guid)
    if banQ then
        repeat
            local bannedId = banQ:GetUInt32(0)
            local nameQ = WorldDBQuery("SELECT Name_Lang_enUS FROM dbc_spells WHERE Id = " .. bannedId)
            if nameQ and not nameQ:IsNull(0) then
                local name = nameQ:GetString(0)
                bannedNames[name] = true
                --print(string.format("[SpellChoice] Banned name: \"%s\" from spell ID %d", name, bannedId))
            end
        until not banQ:NextRow()
    end
    fullSpellPools[guid] = pool
    math.randomseed(os.time())

    -- Step 1: Load known spells
    local knownSpellIds = {}
    local knownQuery = CharDBQuery("SELECT spell FROM character_spell WHERE guid = " .. player:GetGUIDLow())
    if knownQuery then
        repeat
            knownSpellIds[knownQuery:GetUInt32(0)] = true
        until not knownQuery:NextRow()
    end
    -- Step 1b: Load drafted spells
    local draftedSpellIds = {}
    local draftedQuery = CharDBQuery("SELECT spell_id FROM drafted_spells WHERE player_guid = " .. player:GetGUIDLow())
    if draftedQuery then
        repeat
            draftedSpellIds[draftedQuery:GetUInt32(0)] = true
        until not draftedQuery:NextRow()
    end
    -- Step 2: Query spells from DBC
    local query = WorldDBQuery([[
        SELECT s.Id, s.Effect_1, s.Effect_2, s.Effect_3,
               s.Description_Lang_enUS, s.SpellLevel, s.MaxLevel,
               s.DurationIndex, s.Category, s.Name_Lang_enUS, s.SpellIconID,
               s.Rarity
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
        --print("[SpellChoice] No valid spells found.")
        return
    end

    -- Step 3: Filter & bucket by rarity
    local categorized = { [0]={}, [1]={}, [2]={}, [3]={}, [4]={}, [5]={} }
    local totalChecked, totalAccepted = 0, 0

    repeat
        totalChecked = totalChecked + 1

        local spellId = query:GetUInt32(0)
        if not knownSpellIds[spellId] and not draftedSpellIds[spellId] then
            local rarity = query:GetUInt8(11)
            if (rarity ~= 5 or INCLUDE_RARITY_5) and (rarity >= 0 and rarity <= 5) then
                local spell = {
                    spellId = spellId,
                    effect1 = query:GetUInt32(1),
                    effect2 = query:GetUInt32(2),
                    effect3 = query:GetUInt32(3),
                    desc    = query:GetString(4),
                    name    = query:GetString(9),
                    iconId  = query:GetUInt32(10)
                }

                if not isBlacklistedSpellId(spellId)
                   and spell.desc ~= ''
                   and spell.name ~= ''
                   and spell.iconId > 1
                   and not bannedNames[spell.name]
                then
                    if bannedNames[spell.name] then
                        --print(string.format("[SpellChoice] Excluded spell ID %d (%s) due to banned name match", spellId, spell.name))
                    else
                        table.insert(categorized[rarity], spellId)
                        totalAccepted = totalAccepted + 1
                    end
                end
            end
        end
    until not query:NextRow()


    -- Step 4: Shuffle buckets and pick N from each
    for rarity = 0, 4 do
        local bucket = categorized[rarity]
        for i = #bucket, 2, -1 do
            local j = math.random(i)
            bucket[i], bucket[j] = bucket[j], bucket[i]
        end
        local target = math.floor((RARITY_DISTRIBUTION[rarity] or 0) * POOL_AMOUNT)
        local added = 0
        for i = 1, #bucket do
            local id = bucket[i]
            if not knownSpellIds[id] then
                table.insert(pool, id)
                added = added + 1
                if added >= target then break end
            end
        end
    end

    -- Optionally add Broken (5) spells last if allowed
    if INCLUDE_RARITY_5 then
        local bucket = categorized[5]
        for i = #bucket, 2, -1 do
            local j = math.random(i)
            bucket[i], bucket[j] = bucket[j], bucket[i]
        end
        for _, id in ipairs(bucket) do
            if #pool >= POOL_AMOUNT then break end
            table.insert(pool, id)
        end
    end

    local draftedRarityCount = { [0]=0, [1]=0, [2]=0, [3]=0, [4]=0, [5]=0 }

    for _, spellId in ipairs(pool) do
        local q = WorldDBQuery("SELECT Rarity FROM dbc_spells WHERE Id = " .. spellId)
        local rarity = (q and not q:IsNull(0)) and q:GetUInt8(0) or 0
        draftedRarityCount[rarity] = (draftedRarityCount[rarity] or 0) + 1
    end

    -- print(string.format(
    --     "[SpellChoice] Built pool: %d scanned, %d accepted, %d selected. Rarities: C=%d, U=%d, R=%d, E=%d, L=%d, B=%d",
    --     totalChecked,
    --     totalAccepted,
    --     #spellChoices,
    --     draftedRarityCount[0],
    --     draftedRarityCount[1],
    --     draftedRarityCount[2],
    --     draftedRarityCount[3],
    --     draftedRarityCount[4],
    --     draftedRarityCount[5]
    -- ))

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
                            player:CastSpell(player,24312,true)
                            player:RemoveAura(24312)
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
        --print("[SpellChoice] Taught " .. upgraded .. " spells to " .. player:GetName())
    end  
end





-- Event: Player level-up
local function OnLevelUp(event, player, oldLevel)
    --print("[DEBUG] Player leveled up: " .. player:GetName())

    local guid = player:GetGUIDLow()

    -- Block if player has not unlocked spell draft (draft_state < 1)
    local result = CharDBQuery("SELECT draft_state FROM prestige_stats WHERE player_id = " .. guid)
    if not result or result:GetUInt32(0) < 1 then
        return
    end
    do
    local level = player:GetLevel()
    local expectedTarget = DRAFT_MODE_SPELLS + (level - 2)
    local check = CharDBQuery("SELECT total_expected_drafts FROM prestige_stats WHERE player_id = " .. guid)
    if check then
        local currentExpected = check:GetUInt32(0)
        if currentExpected < expectedTarget then
            CharDBExecute(string.format("UPDATE prestige_stats SET total_expected_drafts = %d WHERE player_id = %d", expectedTarget, guid))
            --print(string.format("[SpellChoice] Adjusted total_expected_drafts to %d for player %s (level %d)", expectedTarget, player:GetName(), level))
        end
    end
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
        --print("[DEBUG] Player has no pending draft: " .. player:GetName())
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

        local spells = GetRandomSpells(3, guid)
        currentDraftChoices[guid] = spells
        SaveSpellsToDB(guid, spells)

        local data = table.concat(spells, ",")
        --print("[DEBUG] New spells for " .. player:GetName() .. ": " .. data)
        --player:SendBroadcastMessage("[DEBUG] Sending spell choices: " .. data)
        player:SendAddonMessage("SpellChoice", data, 0, player)
        local rarityParts = {}
        for _, id in ipairs(spells) do
            local q = WorldDBQuery("SELECT Rarity FROM dbc_spells WHERE Id = " .. id)
            table.insert(rarityParts, q and (q:IsNull(0) and "-1" or tostring(q:GetUInt8(0))) or "-1")
        end
        player:SendAddonMessage("SpellChoiceRarities", table.concat(rarityParts, ","), 0, player)
    else
        --print("[DEBUG] Player already has pending draft. Resending existing spells.")

        currentDraftChoices[guid] = existing
        local data = table.concat(existing, ",")
        --player:SendBroadcastMessage("[DEBUG] Resending existing spell choices: " .. data)
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
            local bansQ = CharDBQuery("SELECT bans FROM prestige_stats WHERE player_id = " .. guid)
            if bansQ then
              local bansRemaining = bansQ:GetUInt32(0)
              player:SendAddonMessage("SpellChoiceBansLeft", tostring(bansRemaining), 0, player)
            end
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
    if msg == "SC_REPLACE_BANNED" then
        local guid = player:GetGUIDLow()
        local current = LoadSpellsFromDB(guid)
        local replaced = false
        local bansQ = CharDBQuery("SELECT bans FROM prestige_stats WHERE player_id = " .. guid)
        if bansQ then
          local bansRemaining = bansQ:GetUInt32(0)
          player:SendAddonMessage("SpellChoiceBansLeft", tostring(bansRemaining), 0, player)
        end
        if current then
        LoadValidSpellChoices(player, player:GetLevel())

        local newChoices = {}
        local excludeSet = {}
        local bannedIDs = {}

        -- Phase 1: Collect all unbanned spells first
        for _, id in ipairs(current) do
            local isBanned = CharDBQuery("SELECT 1 FROM draft_bans WHERE player_id = " .. guid .. " AND spell_id = " .. id)
            if isBanned then
                table.insert(bannedIDs, id)
            else
                table.insert(newChoices, id)
                excludeSet[id] = true
            end
        end

        -- Optional: fetch all banned spells into a set for safety check
        local bannedSet = {}
        local banQ = CharDBQuery("SELECT spell_id FROM draft_bans WHERE player_id = " .. guid)
        if banQ then
            repeat
                bannedSet[banQ:GetUInt32(0)] = true
            until not banQ:NextRow()
        end

        local replaced = false

        -- Phase 2: Replace each banned spell
        for _, _ in ipairs(bannedIDs) do
            local newList = GetRandomSpells(1, guid, excludeSet)
            local new = newList and newList[1]
            if new and not bannedSet[new] then
                table.insert(newChoices, new)
                excludeSet[new] = true
                replaced = true
            else
                --print("[SpellChoice] Failed to find replacement spell for banned ID (duplicate or banned)")
            end
        end


            currentDraftChoices[guid] = newChoices
            SaveSpellsToDB(guid, newChoices)

            local data = table.concat(newChoices, ",")
            player:SendAddonMessage("SpellChoice", data, 0, player)

            local rarityParts = {}
            for _, id in ipairs(newChoices) do
                local q = WorldDBQuery("SELECT Rarity FROM dbc_spells WHERE Id = " .. id)
                table.insert(rarityParts, q and (q:IsNull(0) and "-1" or tostring(q:GetUInt8(0))) or "-1")
            end
            player:SendAddonMessage("SpellChoiceRarities", table.concat(rarityParts, ","), 0, player)

            if replaced then
                --print("[SpellChoice] Replaced banned spells for player " .. player:GetName() .. ": " .. data)
            else
                --print("[SpellChoice] SC_REPLACE_BANNED called but no changes needed.")
            end

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

        local spells = GetRandomSpells(3, guid)
        currentDraftChoices[guid] = spells
        SaveSpellsToDB(guid, spells)
        local data = table.concat(spells, ",")
        --print("[SpellChoice] Rerolled spell choices for " .. player:GetName() .. ": " .. data)
        --player:SendBroadcastMessage("[DEBUG] Sending spell choices: " .. data)
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
    -- Handle SC:<spellId>-- Handle SC_BAN:<spellId>
    local banSpellId = tonumber(msg:match("^SC_BAN:(%d+)$"))
    if banSpellId then
        local bansQ = CharDBQuery("SELECT bans FROM prestige_stats WHERE player_id = " .. guid)
        if not bansQ then return false end

        local bansLeft = bansQ:GetUInt32(0)

        if bansLeft <= 0 then
            player:SendAddonMessage("SpellChoiceBanDenied", "0", 0, player)
            --print("[SpellChoice] Ban denied — no bans left for player " .. player:GetName())
            return false
        end

        -- Subtract ban, insert ban into DB
        CharDBExecute("UPDATE prestige_stats SET bans = bans - 1 WHERE player_id = " .. guid)
        CharDBExecute("INSERT IGNORE INTO draft_bans (player_id, spell_id) VALUES (" .. guid .. ", " .. banSpellId .. ")")

        -- Remove from global pool
        local removed = false
        for i = #(fullSpellPools[guid] or {}), 1, -1 do
            if fullSpellPools[guid][i] == banSpellId then
                table.remove(fullSpellPools[guid], i)
                removed = true
                break
            end
        end

        -- Also remove from player's 3 draft picks (if they match)
        if currentDraftChoices[guid] then
            for i = #currentDraftChoices[guid], 1, -1 do
                if currentDraftChoices[guid][i] == banSpellId then
                    table.remove(currentDraftChoices[guid], i)
                    --print("[SpellChoice] [Ban] Removed banned spell from player's active draft list")
                    break
                end
            end
        end

        player:SendAddonMessage("SpellChoiceBanAccepted", tostring(banSpellId), 0, player)
        local updated = CharDBQuery("SELECT bans FROM prestige_stats WHERE player_id = " .. guid)
        if updated then
          local left = updated:GetUInt32(0)
          player:SendAddonMessage("SpellChoiceBansLeft", tostring(left), 0, player)
        end
        print(string.format("[SpellChoice] Player %s banned spell ID %d (bans left: %d) %s",
            player:GetName(),
            banSpellId,
            bansLeft - 1,
            removed and "[REMOVED FROM POOL]" or "[NOT IN POOL]"
        ))

        return false
    end


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

        local spells = GetRandomSpells(3, guid)
        currentDraftChoices[guid] = spells
        local data = table.concat(spells, ",")
        --print("[SpellChoice] Auto-reroll (duplicate spell) for " .. player:GetName() .. ": " .. data)
        player:SendAddonMessage("SpellChoice", data, 0, player)
        local rarityParts = {}
        for _, id in ipairs(spells) do
            local q = WorldDBQuery("SELECT Rarity FROM dbc_spells WHERE Id = " .. id)
            table.insert(rarityParts, q and (q:IsNull(0) and "-1" or tostring(q:GetUInt8(0))) or "-1")
        end
        player:SendAddonMessage("SpellChoiceRarities", table.concat(rarityParts, ","), 0, player)
        return false
    end

    local validChoices = currentDraftChoices[guid]
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
    player:CastSpell(player,24312,true)
    player:RemoveAura(24312)
    -- Additional spell groups
    if spellId == 1515 then
        local extraSpells = {883, 2641, 6991, 982, 136}
        for _, sid in ipairs(extraSpells) do
            player:LearnSpell(sid)
    player:CastSpell(player,24312,true)
    player:RemoveAura(24312)
        end
    elseif spellId == 47241 then
        local extraSpells = {50581, 59671, 54785, 50589}
        for _, sid in ipairs(extraSpells) do
            player:LearnSpell(sid)
    player:CastSpell(player,24312,true)
    player:RemoveAura(24312)
        end
    end
    draftingPlayers[guid] = nil
    for i = #(fullSpellPools[guid] or {}), 1, -1 do
        if fullSpellPools[guid][i] == spellId then
            table.remove(fullSpellPools[guid], i)
            break
        end
    end
    CharDBExecute(string.format([[
        UPDATE prestige_stats
        SET offered_spell_1 = 0, offered_spell_2 = 0, offered_spell_3 = 0
        WHERE player_id = %d
    ]], guid))
    CharDBExecute("INSERT IGNORE INTO drafted_spells (player_guid, spell_id) VALUES (" .. guid .. ", " .. spellId .. ")")
    UpgradeKnownSpells(player)

    currentDraftChoices[guid] = nil
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
            LoadValidSpellChoices(player, player:GetLevel())
            local spells = GetRandomSpells(3, guid)
            currentDraftChoices[guid] = spells
            SaveSpellsToDB(guid, spells) 
            local data = table.concat(spells, ",")
            --print("[SpellChoice] Follow-up draft for " .. player:GetName() .. ": " .. data)
            --player:SendBroadcastMessage("[DEBUG] Sending follow-up spell choices: " .. data)
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
    currentDraftChoices[guid] = spells
    SaveSpellsToDB(guid, spells) 
    local data = table.concat(spells, ",")
    --print("[DEBUG] (Login) Pending draft for " .. player:GetName() .. ": " .. data)
    --player:SendBroadcastMessage("[DEBUG] Sending spell choices: " .. data)
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
    --print("[DEBUG] Player GUID:", playerGuid)

    local query = CharDBQuery("SELECT total_expected_drafts, successful_drafts FROM prestige_stats WHERE player_id = " .. playerGuid)
    if query then
        local totalExpected = query:GetUInt32(0)
        local successful = query:GetUInt32(1)
        --print("[DEBUG] total_expected_drafts:", totalExpected)
        --print("[DEBUG] successful_drafts:", successful)
        local totalDrafts = totalExpected - successful
        if totalDrafts < 0 then totalDrafts = 0 end
        --print("[DEBUG] totalDrafts remaining:", totalDrafts)
        player:SendAddonMessage("SpellChoiceDrafts", tostring(totalDrafts), 0, player)
    else
        --print("This player is not setup for drafting", playerGuid)
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
        if not fullSpellPools[guid] or #fullSpellPools[guid] == 0 then
            LoadValidSpellChoices(player, player:GetLevel())-- or 80 if you want full list
        end

        -- Start draft loop
        BeginDraftLoop(player, guid, rerolls, successful, expected)
    else
    -- Send current bans
    local bansQ = CharDBQuery("SELECT spell_id FROM draft_bans WHERE player_id = " .. guid)
    if bansQ then
        local banned = {}
        repeat
            table.insert(banned, bansQ:GetUInt32(0))
        until not bansQ:NextRow()

        if #banned > 0 then
            local data = table.concat(banned, ",")
            player:SendAddonMessage("SpellChoiceBans", data, 0, player)
            --print("[SpellChoice] Sent banned spells to " .. player:GetName() .. ": " .. data)
        end
    end
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
    if currentDraftChoices[guid] and #currentDraftChoices[guid] == 3 then
      return
    end
    local now = os.time()
    if lastSpellChoiceSent[guid] and now - lastSpellChoiceSent[guid] < 10 then
        return
    end
    lastSpellChoiceSent[guid] = now

    local result = CharDBQuery("SELECT draft_state, successful_drafts, total_expected_drafts FROM prestige_stats WHERE player_id = " .. guid)
    if not result then return end

    local draftState = result:GetUInt8(0)
    if draftState ~= 1 then return end --not in draft mode, bail out

    local successful = result:GetUInt32(1)
    local expected = result:GetUInt32(2)

    if successful < expected then
        local now = os.time()
        if lastZoneDraft[guid] and now - lastZoneDraft[guid] < 5 then
            return
        end
        lastZoneDraft[guid] = now

        CreateLuaEvent(function()
            local p = GetPlayerByGUID(guid)
            if not p or not p:IsInWorld() then return end

            if not spellChoices or not currentDraftChoices[guid] then
                LoadValidSpellChoices(p, p:GetLevel())
            end

            local spells = currentDraftChoices[guid]
            if not spells or #spells ~= 3 then
                spells = LoadSpellsFromDB(guid)
                if not spells or spells[1] == 0 then
                    spells = GetRandomSpells(3)
                    SaveSpellsToDB(guid, spells)
                end
                currentDraftChoices[guid] = spells
                SaveSpellsToDB(guid, spells)
            end

            local data = table.concat(spells, ",")
            --print("[SpellChoice] Zone-triggered draft for " .. p:GetName() .. ": " .. data)
            --p:SendBroadcastMessage("[DEBUG] Sending zone-triggered spell choices: " .. data)
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


