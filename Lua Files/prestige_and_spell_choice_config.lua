CONFIG = {
    MAX_LEVEL = 70,  --Level Required to venture into Prestige Mode(s) via NPC_ID Gossip

    NPC_ID = 2069426, --Default Custom Chromie npc. But can be put on any npc with a Gossip Flag

    DRAFT_MODE_REROLLS = 5, --Base Amount of Rerolls a player gets when starting Draft

    DRAFT_MODE_SPELLS = 3,  --Base Amount of Spells a player gets when starting Draft

    DRAFT_REROLLS_GAINED_PER_PRESTIGE_LEVEL = 5, --Everytime a player prestiges, on the next run they get this many rerolls at start formula being (players prestige total count * DRAFT_REROLLS_GAINED_PER_PRESTIGE_LEVEL)

    INCLUDE_RARITY_5 = false, --These are broken(like infinitely spammable)spells. They Function but This will ruin any sort of balance on your server. But if you're singleplayer, who cares?

    REROLLS_PER_LEVELUP = 2, --How many extra rerolls a player gets per levelup while in Draft Mode

    POOL_AMOUNT = 45, --How many spells get pooled for the player to choose from. Higher numbers burdens server exponentially playercount goes up. Careful with this.

    RARITY_DISTRIBUTION = { -- Sum of 1.0 Distribution of rarities of spells filling up POOL_AMOUNT
        [0] = 0.50,
        [1] = 0.27,
        [2] = 0.14,
        [3] = 0.06,
        [4] = 0.03,
    },

    PrestigeTitles = {  --Titles Linked to the prestige & draft system. 11 titles for prestige progress and one Temporary 'draft mode only' title to differentiate players from others.
        [1] = 523, [2] = 524, [3] = 525, [4] = 526,
        [5] = 527, [6] = 528, [7] = 529, [8] = 530,
        [9] = 531, [10] = 532, [11] = 537
    },

    --- CHROMIE DIALOGUE

    CHROMIE_LOCATION_HORDE = "Chromie can be found just outside Orgrimmar.",  --At Max level, player gets an on screen message to go visit chromie to prestige. This does not set the location, this is the faction specific part of the phrase. Horde.

    CHROMIE_LOCATION_ALLIANCE = "Chromie can be found just outside Ironforge.",--At Max level, player gets an on screen message to go visit chromie to prestige. This does not set the location, this is the faction specific part of the phrase. Alliance.


    --Lore explaining away prestige in-world
    prestigeDescription = [[
        In the vast weave of time, there are countless realities where your character made different choices.

        Perhaps a Troll warrior learned the secrets of the Light, or a Tauren mage studied the mysteries of the arcane.

        The Prestige System lets you tap into these echoes of alternate timelines, drawing from destinies you never walked.. but could have.

        The Bronze Dragonflight has safeguarded these echoes, and now, with the timelines becoming increasingly unstable, we’ve made these echoes accessible.. with a cost, of course.

        To Prestige is to reset your journey through time, returning to your youth while retaining special memories in the form of unique spells, chosen from other realities.
    ]],

    --Players who are not MAX_LEVEL will see this message
    prestigeBlockedMessage = "You are not yet at max level.\nYou cannot partake in prestigeous events.",

    --This is the displayed list of things lost upon prestige.
    prestigeLossList = {
        "- Earned Levels",
        "- Learned Spells",
        "- Quest History",
        "- Talents and Talent Points",
        "- Equipped Gear(Returned via Mail)"
    }
}
