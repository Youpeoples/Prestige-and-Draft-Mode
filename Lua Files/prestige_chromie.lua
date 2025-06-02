local NPC_ID = 2069426

-- Configuration
local MAX_LEVEL = 70
local DRAFT_MODE_REROLLS = 99 
local DRAFT_MODE_SPELLS = 3  --starting amount drafts allowed on character creation/prestige
local prestigeDescription = "Potato\nPotato\nPotato\nPotato\nPotato"
local prestigeBlockedMessage = "French\nFrench\nFrench\nFrench\nFrench"
local prestigeLossList = {
    "- Earned Levels",
    "- Learned Spells",
    "- Quest History",
    "- Talent Points",
    "- Equipped Gear(Returned via Mail)"
}
LOGOUT_TIMER = 10 -- time in seconds to wait after sending back to start before logging out to finish process.
LOGOUT_AFTER_PRESTIGE_TIMER = LOGOUT_TIMER * 1000
local EQUIP_SLOT_START = 0
local EQUIP_SLOT_END = 18
local MAIL_SUBJECT = "Your Returned Gear [Prestige]"
local MAIL_BODY = "Your equipped gear has been returned to you after prestiging."
local RED = "|cffff0000"
local YELLOW = "|cffffff00"
local WHITE = "|cffffffff"

local startingGear = {
  -- ALLIANCE
  ["HUMAN_WARRIOR"] = {
    [16] = 49778, -- Worn Greatsword (Two-Hand)
    [4]  = 38,    -- Recruit's Shirt
    [7]  = 39,    -- Recruit's Pants
    [8]  = 40,    -- Recruit's Boots
    [5]  = 6125   -- Brawler's Harness (Alternate Chest Visual)
  },
  ["HUMAN_PALADIN"] = {
    [4]  = 45,    -- Squire's Shirt
    [16] = 2361,  -- Battleworn Hammer (Two-Hand)
    [7]  = 43,    -- Squire's Pants
    [8]  = 44     -- Footpad Shoes
  },
  ["HUMAN_ROGUE"] = {
    [16] = 2092,  -- Worn Dagger
    [8]  = 47,    -- Footpad Shoes
    [7]  = 39,    -- Recruit's Pants
    [4]  = 45     -- Squire's Shirt
  },
  ["HUMAN_PRIEST"] = {
    [16] = 35,    -- Bent Staff
    [5]  = 53,    -- Neophyte's Shirt
    [7]  = 52,    -- Neophyte's Pants
    [8]  = 51     -- Neophyte's Boots
  },
  ["HUMAN_MAGE"] = {
    [16] = 35,    -- Bent Staff
    [5]  = 45,    -- Squire's Shirt
    [7]  = 39,    -- Squire's Pants
    [8]  = 55     -- Apprentice's Boots
  },
  ["HUMAN_WARLOCK"] = {
    [16] = 35,    -- Bent Staff
    [5]  = 57,    -- Acolyte's Robe
    [8]  = 59,    -- Acolyte's Shoes
    [4]  = 6097   -- Acolyte's Shirt
  },
  ["NIGHTELF_WARRIOR"] = {
    [16] = 12282, -- Worn Battleaxe
    [5]  = 1364,  -- Ragged Leather Vest
    [7]  = 1366,  -- Ragged Leather Pants
    [8]  = 1367   -- Ragged Leather Boots
  },
  ["NIGHTELF_ROGUE"] = {
    [5]  = 2105,  -- Thug Shirt
    [7]  = 120,   -- Thug Pants
    [8]  = 121,   -- Thug Boots
    [16] = 2092   -- Worn Dagger
  },
  ["NIGHTELF_HUNTER"] = {
    [18] = 25,  -- Worn Shortbow(RANGED)
    [17] = 2512,  -- ARROWS
    [16] = 12282, -- Worn Battleaxe
    [4]  = 148,   -- Rugged Trapper's Shirt
    [7]  = 147,   -- Rugged Trapper's Pants
    [8]  = 129    -- Rugged Trapper's Boots
  },
  ["NIGHTELF_DRUID"] = {
    [16] = 35,    -- Bent Staff
    [5]  = 6098,  -- Neophyte's Robe
    [7]  = 6124,  -- Novice's Pants
    [8]  = 129    -- Novice's Boots
  },
  ["GNOME_WARRIOR"] = {
    [16] = 25,    -- Worn Shortsword
    [5]  = 6125,  -- Brawler's Harness
    [7]  = 38,    -- Recruit's Pants
    [8]  = 39     -- Recruit's Boots
  },
  ["GNOME_ROGUE"] = {
    [16] = 2092,  -- Worn Dagger
    [8]  = 47,    -- Footpad Shoes
    [7]  = 39,    -- Recruit's Pants
    [5]  = 45     -- Squire's Shirt
  },
  ["GNOME_MAGE"] = {
    [16] = 35,    -- Bent Staff
    [5]  = 45,    -- Squire's Shirt
    [7]  = 39,    -- Squire's Pants
    [8]  = 55     -- Apprentice's Boots
  },
  ["GNOME_WARLOCK"] = {
    [16] = 35,    -- Bent Staff
    [5]  = 57,    -- Acolyte's Robe
    [8]  = 59,    -- Acolyte's Shoes
    [4]  = 6097   -- Acolyte's Shirt
  },
  ["DRAENEI_WARRIOR"] = {
    [16] = 25,    -- Worn Shortsword
    [5]  = 6125,  -- Brawler's Harness
    [7]  = 39,    -- Recruit's Pants
    [8]  = 39     -- Recruit's Boots
  },
  ["DRAENEI_PALADIN"] = {
    [16] = 2361,  -- Battleworn Hammer
    [5]  = 43,    -- Squire's Shirt
    [7]  = 45,    -- Squire's Pants
    [8]  = 47     -- Footpad Shoes
  },
  ["DRAENEI_PRIEST"] = {
    [16] = 35,    -- Bent Staff
    [5]  = 53,    -- Neophyte's Shirt
    [7]  = 52,    -- Neophyte's Pants
    [8]  = 51     -- Neophyte's Boots
  },
  ["DRAENEI_MAGE"] = {
    [16] = 35,    -- Bent Staff
    [5]  = 45,    -- Squire's Shirt
    [7]  = 39,    -- Squire's Pants
    [8]  = 55     -- Apprentice's Boots
  },
  ["DRAENEI_SHAMAN"] = {
    [16] = 36,    -- Worn Mace
    [3]  = 154,   -- Primitive Mantle
    [7]  = 153,   -- Primitive Kilt
    [5]  = 6098   -- Neophyte's Robe
  },
  ["DWARF_WARRIOR"] = {
    [16] = 12282, -- Worn Battleaxe (Two-Hand)
    [5]  = 6125,  -- Brawler's Harness
    [7]  = 47,    -- Footpad Pants
    [8]  = 48     -- Footpad Shoes
  },

  ["DWARF_PALADIN"] = {
    [16] = 2361,  -- Battleworn Hammer
    [5]  = 6074,  -- Novice's Vestments
    [7]  = 52,    -- Neophyte's Pants
    [8]  = 51     -- Neophyte's Boots
  },

  ["DWARF_HUNTER"] = {
    [16] = 2508,  -- Old Blunderbuss
    [17] = 2516,  -- BULLETS
    [5]  = 6130,  -- Trapper's Shirt
    [7]  = 6135,  -- Primitive Kilt
    [8]  = 40     -- Recruit's Boots
  },

  ["DWARF_ROGUE"] = {
    [16] = 2092,  -- Worn Dagger
    [5]  = 6123,  -- Novice's Shirt
    [7]  = 120,   -- Thug Pants
    [8]  = 121    -- Thug Boots
  },

  ["DWARF_PRIEST"] = {
    [16] = 35,    -- Bent Staff
    [5]  = 53,    -- Neophyte's Shirt
    [7]  = 52,    -- Neophyte's Pants
    [8]  = 51     -- Neophyte's Boots
  },
  -- HORDE
  ["ORC_WARRIOR"] = {
    [16] = 25,    -- Worn Shortsword (Main Hand)
    [5]  = 6125,  -- Brawler's Harness (Chest)
    [7]  = 39,    -- Recruit's Pants (Legs)
    [8]  = 40     -- Recruit's Boots (Feet)
  },
  ["ORC_HUNTER"] = {
    [18] = 25,  -- Worn Shortbow(RANGED)
    [17] = 2512,  -- ARROWS
    [16] = 12282, -- Worn Battleaxe (Two-Hand)
    [5]  = 147,   -- Rugged Trapper's Shirt (Chest)
    [7]  = 148,   -- Rugged Trapper's Pants (Legs)
    [8]  = 129    -- Rugged Trapper's Boots (Feet)
  },
  ["ORC_ROGUE"] = {
    [16] = 2092,  -- Worn Dagger (Main Hand)
    [5]  = 45,    -- Squire's Shirt (Chest)
    [7]  = 39,    -- Recruit's Pants (Legs)
    [8]  = 47     -- Footpad Shoes (Feet)
  },
  ["ORC_SHAMAN"] = {
    [16] = 36,    -- Worn Mace (Main Hand)
    [3]  = 154,   -- Primitive Mantle (Shoulder)
    [5]  = 6098,  -- Neophyte's Robe (Chest)
    [7]  = 153    -- Primitive Kilt (Legs)
  },
  ["ORC_WARLOCK"] = {
    [17] = 35,    -- Bent Staff (Two-Hand)
    [5]  = 57,    -- Acolyte's Robe (Chest)
    [8]  = 59,    -- Acolyte's Shoes (Feet)
    [4]  = 6097   -- Acolyte's Shirt (Visual Shirt)
  },
  ["TROLL_WARRIOR"] = {
    [16] = 25,    -- Worn Shortsword (Main Hand)
    [5]  = 6125,  -- Brawler's Harness (Chest)
    [7]  = 39,    -- Recruit's Pants (Legs)
    [8]  = 40     -- Recruit's Boots (Feet)
  },
  ["TROLL_HUNTER"] = {
    [18] = 25,  -- Worn Shortbow(RANGED)
    [17] = 2512,  -- ARROWS
    [16] = 12282, -- Worn Battleaxe (Two-Hand)
    [5]  = 147,   -- Rugged Trapper's Shirt (Chest)
    [7]  = 148,   -- Rugged Trapper's Pants (Legs)
    [8]  = 129    -- Rugged Trapper's Boots (Feet)
  },
  ["TROLL_ROGUE"] = {
    [16] = 2092,  -- Worn Dagger (Main Hand)
    [5]  = 45,    -- Squire's Shirt (Chest)
    [7]  = 39,    -- Recruit's Pants (Legs)
    [8]  = 47     -- Footpad Shoes (Feet)
  },
  ["TROLL_SHAMAN"] = {
    [16] = 36,    -- Worn Mace (Main Hand)
    [3]  = 154,   -- Primitive Mantle (Shoulder)
    [5]  = 6098,  -- Neophyte's Robe (Chest)
    [7]  = 153    -- Primitive Kilt (Legs)
  },
  ["TROLL_PRIEST"] = {
    [17] = 35,    -- Bent Staff (Two-Hand)
    [5]  = 53,    -- Neophyte's Shirt (Chest)
    [7]  = 52,    -- Neophyte's Pants (Legs)
    [8]  = 51     -- Neophyte's Boots (Feet)
  },
  ["TROLL_MAGE"] = {
    [17] = 35,    -- Bent Staff (Two-Hand)
    [5]  = 45,    -- Squire's Shirt (Chest)
    [7]  = 39,    -- Squire's Pants (Legs)
    [8]  = 55     -- Apprentice's Boots (Feet)
  },
  ["UNDEAD_WARRIOR"] = {
    [16] = 25,    -- Worn Shortsword (Main Hand)
    [5]  = 6125,  -- Brawler's Harness (Chest)
    [7]  = 39,    -- Recruit's Pants (Legs)
    [8]  = 40     -- Recruit's Boots (Feet)
  },
  ["UNDEAD_ROGUE"] = {
    [16] = 2092,  -- Worn Dagger (Main Hand)
    [5]  = 45,    -- Squire's Shirt (Chest)
    [7]  = 39,    -- Recruit's Pants (Legs)
    [8]  = 47     -- Footpad Shoes (Feet)
  },
  ["UNDEAD_MAGE"] = {
    [17] = 35,    -- Bent Staff (Two-Hand)
    [5]  = 45,    -- Squire's Shirt (Chest)
    [7]  = 39,    -- Squire's Pants (Legs)
    [8]  = 55     -- Apprentice's Boots (Feet)
  },
  ["UNDEAD_WARLOCK"] = {
    [17] = 35,    -- Bent Staff (Two-Hand)
    [5]  = 57,    -- Acolyte's Robe (Chest)
    [8]  = 59,    -- Acolyte's Shoes (Feet)
    [4]  = 6097   -- Acolyte's Shirt (Visual Shirt)
  },
  ["UNDEAD_PRIEST"] = {
    [17] = 35,    -- Bent Staff (Two-Hand)
    [5]  = 53,    -- Neophyte's Shirt (Chest)
    [7]  = 52,    -- Neophyte's Pants (Legs)
    [8]  = 51     -- Neophyte's Boots (Feet)
  },
  ["TAUREN_WARRIOR"] = {
    [16] = 25,    -- Worn Shortsword (Main Hand)
    [5]  = 6125,  -- Brawler's Harness (Chest)
    [7]  = 39,    -- Recruit's Pants (Legs)
    [8]  = 40     -- Recruit's Boots (Feet)
  },
  ["TAUREN_DRUID"] = {
    [17] = 35,    -- Bent Staff (Two-Hand)
    [5]  = 6098,  -- Neophyte's Robe (Chest)
    [7]  = 140,   -- Novice's Pants (Legs)
    [8]  = 139    -- Novice's Boots (Feet)
  },
  ["TAUREN_SHAMAN"] = {
    [16] = 36,    -- Worn Mace (Main Hand)
    [3]  = 154,   -- Primitive Mantle (Shoulder)
    [5]  = 6098,  -- Neophyte's Robe (Chest)
    [7]  = 153    -- Primitive Kilt (Legs)
  },
  ["BLOODELF_PALADIN"] = {
    [16] = 2361,  -- Battleworn Hammer (Main Hand)
    [5]  = 43,    -- Squire's Shirt (Chest)
    [7]  = 45,    -- Squire's Pants (Legs)
    [8]  = 47     -- Footpad Shoes (Feet)
  },
  ["BLOODELF_ROGUE"] = {
    [16] = 2092,  -- Worn Dagger (Main Hand)
    [5]  = 45,    -- Squire's Shirt (Chest)
    [7]  = 39,    -- Recruit's Pants (Legs)
    [8]  = 47     -- Footpad Shoes (Feet)
  },
  ["BLOODELF_HUNTER"] = {
    [18] = 2512,  -- Old Blunderbuss (Ranged)
    [18] = 2101,  -- Light Quiver (Ammo)
    [16] = 12282, -- Worn Battleaxe (Two-Hand)
    [5]  = 147,   -- Rugged Trapper's Shirt (Chest)
    [7]  = 148,   -- Rugged Trapper's Pants (Legs)
    [8]  = 129    -- Rugged Trapper's Boots (Feet)
  },
  ["BLOODELF_MAGE"] = {
    [17] = 20978,   -- Apprentice's Staff (Two-Hand)
    [5]  = 56,      -- Apprentice's Robes (Chest)
    [7]  = 1395,    -- Apprentice's Pants (Legs)
    [8]  = 20895    -- Apprentice's Boots (Feet)
  },
  ["BLOODELF_PRIEST"] = {
    [17] = 20978, -- Apprentice's Staff (Two-Hand)
    [5]  = 53,    -- Neophyte's Shirt (Chest)
    [7]  = 52,    -- Neophyte's Pants (Legs)
    [8]  = 51     -- Neophyte's Boots (Feet)
  },
  ["BLOODELF_WARLOCK"] = {
    [17] = 20978, -- Apprentice's Staff (Two-Hand)
    [5]  = 57,    -- Acolyte's Robe (Chest)
    [8]  = 59,    -- Acolyte's Shoes (Feet)
    [4]  = 6097   -- Acolyte's Shirt (Visual Shirt)
  },
  ["DEATHKNIGHT"] = {
    [5]  = 34650, -- Acherus Knight's Tunic (Chest)
    [10] = 34649, -- Acherus Knight's Gauntlets (Hands)
    [7]  = 34656, -- Acherus Knight's Legplates (Legs)
    [8]  = 34648, -- Acherus Knight's Greaves (Feet)
    [6]  = 34651, -- Acherus Knight's Girdle (Waist)
    [15] = 34659, -- Acherus Knight's Shroud (Back)
    [2]  = 34657, -- Choker of Damnation (Neck)
    [11] = 34658, -- Plague Band (Ring 1)
    [12] = 38147, -- Corrupted Band (Ring 2)
    [1]  = 34652  -- Acherus Knight's Hood (Head)
  }
}


local function GiveStartingGear(player)
    local race = player:GetRace()
    local class = player:GetClass()

    local raceNames = {
        [1] = "HUMAN",
        [2] = "ORC",
        [3] = "DWARF",
        [4] = "NIGHTELF",
        [5] = "UNDEAD",
        [6] = "TAUREN",
        [7] = "GNOME",
        [8] = "TROLL",
        [10] = "BLOODELF",
        [11] = "DRAENEI",
    }

    local classNames = {
        [1]  = "WARRIOR",
        [2]  = "PALADIN",
        [3]  = "HUNTER",
        [4]  = "ROGUE",
        [5]  = "PRIEST",
        [6]  = "DEATHKNIGHT",
        [7]  = "SHAMAN",
        [8]  = "MAGE",
        [9]  = "WARLOCK",
        [11] = "DRUID",
    }

    local key
    if class == 6 then -- Death Knight
        key = "DEATHKNIGHT"
    else
        key = raceNames[race] .. "_" .. classNames[class]
    end

    local items = startingGear[key]
    if not items then
        player:SendBroadcastMessage("Starting gear not found for your race and class.")
        return
    end

    for slotID, itemID in pairs(items) do
        local count = 1
        if itemID == 2512 or itemID == 2516 then
            count = 200
        end

        local item = player:AddItem(itemID, count)
        if item and count == 1 then
            player:EquipItem(itemID, slotID)
        end
    end

    player:SendBroadcastMessage("Your starting gear has been equipped.")
end






local function GetLossListText()
    return "The following will be removed when you prestige:\n\n" .. table.concat(prestigeLossList, "\n")
end

local EQUIPPED_SLOTS = {
    0,  -- HEAD
    1,  -- NECK
    2,  -- SHOULDERS
    3,  -- BODY (shirt)
    4,  -- CHEST
    5,  -- WAIST
    6,  -- LEGS
    7,  -- FEET
    8,  -- WRISTS
    9,  -- HANDS
    10, -- FINGER1
    11, -- FINGER2
    12, -- TRINKET1
    13, -- TRINKET2
    14, -- BACK
    15, -- MAIN HAND
    16, -- OFF HAND
    17, -- RANGED/RELIC
    18, -- TABARD
}

local function RemoveAndMailEquippedItems(player)
    local itemsSent = false
    local receiverGuid = player:GetGUIDLow()
    local senderGuid = player:GetGUIDLow()

    for _, slot in ipairs(EQUIPPED_SLOTS) do
        local item = player:GetEquippedItemBySlot(slot)
        if item then
            local entry = item:GetEntry()
            local count = item:GetCount()
            if type(SendMail) == "function" then
                SendMail(MAIL_SUBJECT, MAIL_BODY, senderGuid, receiverGuid, 61, 0, 0, 0, entry, count)
            else
                --print("[Prestige] ERROR: Global SendMail function not found!")
            end
            player:RemoveItem(entry, count)
            itemsSent = true
        end
    end

    if itemsSent then
        player:SendBroadcastMessage("Your equipped items have been mailed to you.")
    end
end


-- Menus
local function ShowMainMenu(player, creature)
    player:GossipClearMenu()
    player:GossipMenuAddItem(2, "What is Prestige?", 1, 1)
    player:GossipMenuAddItem(4, "I would like to prestige!", 1, 2)
    player:GossipMenuAddItem(0, "Goodbye", 1, 999)
    player:GossipSendMenu(1, creature)
end

local function ShowPrestigeInfo(player, creature)
    player:GossipClearMenu()
    player:GossipMenuAddItem(0, prestigeDescription, 1, 998)
    player:GossipMenuAddItem(0, "Back", 1, 0)
    player:GossipSendMenu(1, creature)
end

local function ShowPrestigeOptions(player, creature)
    player:GossipClearMenu()
    if player:GetLevel() < MAX_LEVEL then
        player:GossipMenuAddItem(0, prestigeBlockedMessage, 1, 998)
    else
        player:GossipMenuAddItem(4, GetLossListText(), 1, 998)
        player:GossipMenuAddItem(9, RED .. "Prestige", 1, 3)
        player:GossipMenuAddItem(9, RED .. "Prestige into Draft Mode", 1, 4) -- NEW OPTION
    end
    player:GossipMenuAddItem(0, "Back", 1, 0)
    player:GossipSendMenu(1, creature)
end

local function ShowConfirmation(player, creature)
    player:GossipClearMenu()
    player:GossipMenuAddItem(0, "|TInterface\\Icons\\INV_Misc_Bag_10:20|t Prestige requires 10 free inventory slots", 1, 998)
    player:GossipMenuAddItem(0, "", 1, 998) -- Spacer
    player:GossipMenuAddItem(9, RED .. "I am sure I want to Prestige!", 1, 100)
    player:GossipMenuAddItem(0, "Back", 1, 2)
    player:GossipSendMenu(1, creature)
end
local function ShowDraftConfirmation(player, creature)
    player:GossipClearMenu()
    player:GossipMenuAddItem(0, "|TInterface\\Icons\\INV_Misc_Bag_10:20|t Prestige requires 10 free inventory slots", 1, 998)
    player:GossipMenuAddItem(0, "", 1, 998) -- Spacer
    player:GossipMenuAddItem(9, RED .. "I am sure I want to Prestige into Draft Mode!", 1, 101)
    player:GossipMenuAddItem(0, "Back", 1, 2)
    player:GossipSendMenu(1, creature)
end
-- Gossip handler
local function OnGossipHello(event, player, creature)
    ShowMainMenu(player, creature)
end
local function DoPrestige(player, draftMode)
    local guid = player:GetGUIDLow()
    local requiredSlots = 10
    local freeSlots = 0
    local foundEnough = false
    --print("[Prestige] Starting inventory check for player: " .. player:GetName())

            for bag = 0, 4 do
                local bagSize = 16
                local skipBag = false
                local container = 255  -- Use 255 for virtual inventory (backpack, equipment, etc.)

                if bag == 0 then
                    -- Backpack occupies slot 23–38 in container 255
                    bagSize = 16
                    --print("[Prestige] Checking backpack (bag 0) with size " .. bagSize)
                else
                    local bagItem = player:GetItemByPos(255, 18 + bag)
                    if not bagItem then
                        --print("[Prestige] Skipping bag " .. bag .. ": no item equipped")
                        skipBag = true
                    else
                        local entry = bagItem:GetEntry()
                        local result = WorldDBQuery("SELECT class, subclass FROM item_template WHERE entry = " .. entry)
                        if not result then
                            --print("[Prestige] Skipping bag " .. bag .. ": item entry not found in DB (entry: " .. entry .. ")")
                            skipBag = true
                        else
                            local class = result:GetUInt8(0)
                            local subclass = result:GetUInt8(1)
                            --print("[Debug] Bag " .. bag .. " class = " .. class .. ", subclass = " .. subclass)

                            if (class == 1 and (subclass == 2 or subclass == 3)) or class == 11 then
                                --print("[Prestige] Skipping bag " .. bag .. ": quiver or ammo pouch")
                                skipBag = true
                            else
                                bagSize = bagItem:GetBagSize()
                                container = 18 + bag  -- Use slot index, NOT GUID
                                --print("[Prestige] Checking bag " .. bag .. " with size " .. bagSize)
                            end
                        end
                    end
                end

                if not skipBag then
                    for slot = 0, bagSize - 1 do
                        local item

                        if bag == 0 then
                            -- Backpack check: actual slots are 23–38
                            item = player:GetItemByPos(255, 23 + slot)
                        else
                            -- Normal bag check
                            item = player:GetItemByPos(container, slot)
                        end

                        --print(item)

                        if not item then
                            freeSlots = freeSlots + 1
                            --print("[Prestige] Bag " .. bag .. ", slot " .. slot .. ": empty (freeSlots = " .. freeSlots .. ")")
                            if freeSlots >= requiredSlots then
                                foundEnough = true
                                --print("[Prestige] Found enough free slots (" .. freeSlots .. ") — exiting early")
                                break
                            end
                        end
                    end
                end

                if foundEnough then break end
            end

            -- Final evaluation
            if freeSlots >= requiredSlots then
                --print("[Prestige] Free slot check passed: " .. freeSlots .. "/" .. requiredSlots)
            else
                --print("[Prestige] Not enough free slots: " .. freeSlots .. "/" .. requiredSlots)
                player:SendBroadcastMessage("You need at least " .. requiredSlots .. " free bag slots to Prestige.")
                return
            end
        if freeSlots < requiredSlots then
            player:SendBroadcastMessage("You need at least " .. requiredSlots .. " free bag slots to Prestige.")
            return
        end


    -- Draft mode only:
    if draftMode then
        player:SendBroadcastMessage("Draft Mode: Enabled for next run.")
        print("[DraftMode] Draft mode enabled for player: " .. player:GetName() .. " (" .. guid .. ")")

        local updateStatsQuery = string.format([[
            UPDATE prestige_stats
            SET draft_state = 1,
                successful_drafts = 0,
                total_expected_drafts = %d,
                rerolls = %d
            WHERE player_id = %d
        ]], DRAFT_MODE_SPELLS, DRAFT_MODE_REROLLS, guid)
        CharDBExecute(updateStatsQuery)
        print("[DraftMode] Updated prestige_stats for " .. guid)
        player:SendBroadcastMessage("prestige_stats updated")
    end
    RemoveAndMailEquippedItems(player)
    player:SetLevel(player:GetClass() == 6 and 55 or 1)
    GiveStartingGear(player)

    local name = player:GetName()
    local newPrestige = 1
    local q = CharDBQuery("SELECT prestige_level FROM prestige_stats WHERE player_id = " .. guid)
    if q then
        local currentPrestige = q:GetUInt32(0)
        newPrestige = currentPrestige + 1
        CharDBExecute("UPDATE prestige_stats SET prestige_level = " .. newPrestige .. " WHERE player_id = " .. guid)
    else
        CharDBExecute("INSERT INTO prestige_stats (player_id, prestige_level) VALUES (" .. guid .. ", 1)")
    end

    SendWorldMessage("|cffff8800[Prestige]|r Player |cffffff00" .. name .. "|r has prestiged! New Prestige Level: |cff00ff00" .. newPrestige .. "|r")
    player:SendBroadcastMessage("|cffff0000You have prestiged!|r Your level has been reset to 1.")
    player:SendBroadcastMessage("You will be logged out in " .. LOGOUT_TIMER ..  " seconds to complete the prestige process.")
    player:GossipComplete()

    -- Actionbar, spell, quest wipes
    CharDBExecute("DELETE FROM character_action WHERE guid = " .. guid)
    CharDBExecute("DELETE FROM character_spell WHERE guid = " .. guid)
    local result = CharDBQuery("SELECT spell_id FROM drafted_spells WHERE player_guid = " .. guid)
    if result then
        repeat
            local spellId = result:GetUInt32(0)
            player:RemoveSpell(spellId)
        until not result:NextRow()
    end
    CharDBExecute("DELETE FROM drafted_spells WHERE player_guid = " .. guid)
    CharDBExecute("DELETE FROM character_queststatus WHERE guid = " .. guid)
    CharDBExecute("DELETE FROM character_queststatus_rewarded WHERE guid = " .. guid)
    CharDBExecute("DELETE FROM character_queststatus_daily WHERE guid = " .. guid)
    CharDBExecute("DELETE FROM character_queststatus_weekly WHERE guid = " .. guid)
    CharDBExecute("DELETE FROM character_queststatus_seasonal WHERE guid = " .. guid)
    CharDBExecute("DELETE FROM character_queststatus_monthly WHERE guid = " .. guid)

    -- Teleport and logout
    CreateLuaEvent(function()
        local plr = GetPlayerByGUID(guid)
        if not plr then return end

        local raceStartLocations = {
            [1]  = {map = 0,   x = -8949.95,  y = -132.493, z = 83.5312,   o = 3.142},
            [2]  = {map = 1,   x = -618.518,  y = -4251.67, z = 38.718,    o = 6.2},
            [3]  = {map = 0,   x = -6240.32,  y = 331.033,  z = 382.757,   o = 5.2},
            [4]  = {map = 1,   x = 10311.3,   y = 832.463,  z = 1326.41,   o = 5.7},
            [5]  = {map = 0,   x = 1676.35,   y = 1678.68,  z = 121.67,    o = 1.6},
            [6]  = {map = 1,   x = -2917.58,  y = -257.98,  z = 52.9968,   o = 0.0},
            [7]  = {map = 0,   x = -6240.95,  y = 331.493, z = 382.5312,   o = 5.2},
            [8]  = {map = 1,   x = -618.518,  y = -4251.67, z = 38.718,    o = 6.2},
            [10] = {map = 530, x = 10349.6,   y = -6357.29, z = 33.4026,   o = 5.3},
            [11] = {map = 530, x = -3961.64,  y = -13931.2, z = 100.615,   o = 2.08},
        }

        local dkStart = {map = 609, x = 2352.47, y = -5665.831, z = 426.02786, o = 1.44}
        local loc = (plr:GetClass() == 6) and dkStart or raceStartLocations[plr:GetRace()]

        if loc then
            plr:Teleport(loc.map, loc.x, loc.y, loc.z, loc.o)
        else
            plr:SendBroadcastMessage("Unknown race/class start location.")
        end

        -- Always schedule delayed logout
        CreateLuaEvent(function()
            local p = GetPlayerByGUID(guid)
            if p then p:LogoutPlayer(true) end
        end, LOGOUT_AFTER_PRESTIGE_TIMER, 1)

        -- If draftMode, immediately kick and schedule class change
        if draftMode then
            local guidLow = plr:GetGUIDLow()  -- Cache the GUID before logout
            plr:KickPlayer()
            CreateLuaEvent(function()
                CharDBExecute("UPDATE characters SET class = 8 WHERE guid = " .. guidLow)
                print("[DraftMode] Updated class to Mage (8) for " .. guidLow)
            end, 1000, 1)
        end
    end, 500, 1)
end

local function OnGossipSelect(event, player, creature, sender, intid)
    local guid = player:GetGUIDLow()

    if intid == 0 then
        ShowMainMenu(player, creature)
    elseif intid == 1 then
        ShowPrestigeInfo(player, creature)
    elseif intid == 2 then
        ShowPrestigeOptions(player, creature)
    elseif intid == 3 then
        ShowConfirmation(player, creature)
    elseif intid == 998 then
        player:GossipComplete()
    elseif intid == 999 then
        player:GossipComplete()
    elseif intid == 4 then
        ShowDraftConfirmation(player, creature)
    elseif intid == 100 then
        DoPrestige(player, false) -- normal prestige
    elseif intid == 101 then
        DoPrestige(player, true)  -- draft mode prestige
    end
end

RegisterCreatureGossipEvent(NPC_ID, 1, OnGossipHello)
RegisterCreatureGossipEvent(NPC_ID, 2, OnGossipSelect)
