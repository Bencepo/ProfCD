# Notes for Claude

ProfCD: profession cooldown tracker for WoW Forever (Lua 5.1, modern C_Spell/C_Item/C_Container APIs). Minimap button (LibDBIcon) with a tooltip of all characters' cooldowns, a BencepoUI window with the mats status per craft. Author and rights holder: Bencepo. All rights reserved, no open-source license.

## Layout

- `ProfCD.lua`: everything (tracked list, scanning, tooltip, window, macro, events).
- `Libs/`: LibStub, CallbackHandler, LibDataBroker, LibDBIcon (minimap button), BencepoUI (shared settings-window toolkit, also in TrinketDock, ProcFlare, VendorFloor, TransmogSweep, SpikeSpotter; bump its LibStub minor version on every change). `opts.bugUrl` gives the "Report a bug" button.
- `media/logo.png`: project logo for CurseForge, Wago and the website (not packaged).

## Forever facts (from Ben)

- Transmutes do NOT share a cooldown in Forever: Gold and Truesilver have 1 hour each, Arcanite its own. Every recipe is its own entry in `TRACKED` (helper `transmute()`).
- Cooldown durations are never hardcoded: they come from `C_Spell.GetSpellCooldown` / `C_Container.GetItemCooldown`. Durations under 60 s are treated as the GCD and ignored.

## Rules

- Data: `ProfCDDB.chars["Name-Realm"]` = { name, realm, class, cds = { key = readyAt (epoch, 0 = ready) }, known = { recipeId = true }, mats = { itemID = { bags, bags+bank } }, seen }. Alts are shown as of `seen`.
- Reagents: hardcoded Classic defaults, replaced by `db.reagents[spellID]` read from the open profession window (`learnReagents`, Classic trade skill API).
- Salt Shaker: item cooldown is only read while the shaker is in the bags; in the bank the stored value is kept.
- Macro: account macro "ProfCD" (`/pcd`) is created when the minimap button is turned off (always) and at login when it is hidden (only once, `db.macroMade`), so a deleted macro is not forced back. Not in combat: deferred to `PLAYER_REGEN_ENABLED`.
- Scans are coalesced (`queueScan`), never per event. Window redraws once a second only while shown.
- UI texts in English. Settings in the BencepoUI window, not in Blizzard's options.
- CI runs luacheck and LuaLS with the WoW API annotations; LuaLS must report zero diagnostics or the release stops. New Blizzard globals go into `.luarc.json`; older API fallbacks go through `LEGACY` so they do not show as deprecated.
- Release: new version heading at the top of `CHANGELOG.md` (`## 1.0.1`), push to `main`; the workflow tags, builds and uploads to CurseForge and Wago (secrets `CF_API_KEY`, `WAGO_API_TOKEN`). The release reaches players right away, so test changes in the game before pushing.
