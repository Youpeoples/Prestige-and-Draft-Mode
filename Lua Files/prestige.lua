local function EnsurePrestigeEntry(event, player)
    local guid = player:GetGUIDLow()
    local name = player:GetName()

    local check = CharDBQuery("SELECT 1 FROM prestige_stats WHERE player_id = " .. guid)
    if check then
        --print("[Prestige] Prestige row already exists for player: " .. name)
    else
        CharDBExecute("INSERT INTO prestige_stats (player_id, prestige_level) VALUES (" .. guid .. ", 0)")
        --print("[Prestige] Created prestige row for new player: " .. name)
    end
end

RegisterPlayerEvent(3, EnsurePrestigeEntry) -- EVENT_ON_LOGIN


