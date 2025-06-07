# Prestige & Draft Mode

**Wrath of the Lich King (3.3.5a)**

A minimally invasive prestige system that lets characters reset back to level one in exchange for unique rewards and progression options. It features both a classic prestige reset and an optional Draft Mode, where players select a new spell from a randomized pool upon each level-up. 

**!!Clientside users have to make changes ONLY if they WANT access to Draft Mode. Otherwise your server will behave as normal!!**

---

## 📦 Repository Structure

```
/                               # Git root
├── Sql & Serverside Files/
│   ├── SQL/
│   │   ├── Acore_characters/
│   │   │   └── prestige.sql
│   │   └── acore_world/
│   │       ├── chromie_spawn.sql
│   │       ├── playercreateinfo_additions.sql
│   │       ├── playercreateinfo_action_additions.sql
│   │       ├── playercreateinfo_items_additions.sql
│   │       └── prestige_draft_specific_tables.sql
│   └── DBC/
│       └── *.dbc               ← Custom DBC overrides
├── Lua Files/
│   ├── Prestige & Draft Mode/
│   │   ├── prestige.lua
│   │   ├── prestige_chromie.lua
│   │   ├── spell_choice.lua
│   │   └── prestige_nameplates_hooks.lua
│   └── prestige_and_spell_choice_config.lua
├── Client Side Files/
│   ├── Client Addon/
│   │   └── PrestigeSystems/    ← WoW AddOn folder
│   └── MPQ Patch/
│       └── patch-P.mpq         ← Client data patch
└── README.md                   ← This file
```

---

## 🔧 Prerequisites

* **AzerothCore** server (3.3.5a/WotLK)
* **Eluna** Lua Engine enabled
* Access to **characters** and **world** MySQL databases
* A working WoW 3.3.5a client

---
(There are simpler to follow install instructions found in Install_Guide.txt)
## 🛠️ Server-Side Installation

Follow these steps on your server machine:

1. **Core Prestige Schema**

   ```sql
   -- characters DB
   SOURCE "Sql & Serverside Files/SQL/Acore_characters/prestige.sql";
   ```

   Creates tables to track prestige and draft state.

2. **Optional Chromie NPC**

   ```sql
   -- world DB
   SOURCE "Sql & Serverside Files/SQL/acore_world/chromie_spawn.sql";
   ```

   Registers NPC (entry 2069426) for a Chromie interface.

3. **Character-Creation Templates**

   ```sql
   -- world DB
   SOURCE "Sql & Serverside Files/SQL/acore_world/playercreateinfo_additions.sql";
   SOURCE "Sql & Serverside Files/SQL/acore_world/playercreateinfo_action_additions.sql";
   SOURCE "Sql & Serverside Files/SQL/acore_world/playercreateinfo_items_additions.sql";
   ```

   *These are **`INSERT IGNORE`** scripts—existing data is preserved.*

4. **Draft-Specific Tables**

   ```sql
   -- world DB
   SOURCE "Sql & Serverside Files/SQL/acore_world/prestige_draft_specific_tables.sql";
   ```

   Adds read-only tables used exclusively by the mod.

5. **DBC Overrides**

   ```bash
   cp "Sql & Serverside Files/DBC/*.dbc" "/path/to/server/Data/dbc/"
   ```

   Place custom DBC files into your server's `Data/dbc/` folder.

6. **Lua Scripts**

   ```bash
   cp -r "Lua Files/Prestige & Draft Mode/" "/path/to/server/lua_scripts/"
   cp "Lua Files/prestige_and_spell_choice_config.lua" "/path/to/server/lua_scripts/"
   ```

   Final layout in `lua_scripts/`:

   ```
   lua_scripts/
   ├── Prestige & Draft Mode/
   └── prestige_and_spell_choice_config.lua
   ```

Your server is now configured for **Prestige & Draft Mode**.

---

## 🎮 Client-Side Installation

On each player's machine:

1. **AddOn Installation**

   ```bash
   cp -r "Client Side Files/Client Addon/PrestigeSystems/" "<WoW Path>/Interface/AddOns/"
   ```

2. **MPQ Patch**

   ```bash
   cp "Client Side Files/Mpq Patch/patch-P.mpq" "<WoW Path>/Data/"
   ```

Restart the client. The AddOn and data patch enable the in-game UI for drafting spells.

---

## 🚀 Usage

1. **Level a character** to max (default 70).
2. **Interact** with the Prestige NPC (or Chromie) to select between Standard and Draft Prestige.
4. **Enjoy** prestige progression!

---

## 📜 Configuration

All adjustable parameters (NPC IDs, max level, rerolls, etc.) live in:

```
Lua Files/prestige_and_spell_choice_config.lua
```

Edit this file before deployment to match your server’s design.

---

## 🙏 Credits & License

* **Author**: Stephen Kania
* **License**: MIT License (see `LICENSE`)
* **Based on**: AzerothCore, TrinityCore, and Eluna

Enjoy prestiging!
