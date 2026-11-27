# Changelog

## Unreleased

- Settings window: "More from Bencepo" button in the footer links to all Bencepo addons (BencepoUI 6).
- Code cleanup, no change in behaviour.

## 1.0.4

- Fixed: chat notifications when a cooldown finishes while online are no longer missed before the 20-second check runs.
- The ProfCD window now scrolls when many characters and cooldowns are listed instead of growing past the screen edge, updates right away after crafts or bag changes, and no longer rebuilds its full layout every second.
- Lower overhead: profession reagent scanning is debounced on rapid `TRADE_SKILL_UPDATE` bursts, reagent counts are deduplicated and updated in place, and the ready-check ticker only runs when chat notices are enabled.
- Shared settings window updated to BencepoUI 5.

## 1.0.3

- Other characters can be forgotten with the x on their line in the window (after a question), e.g. a deleted or renamed character. No chat command needed.
- The shared settings window (BencepoUI) is now one version for all Bencepo addons: "Report a bug" sits in a footer of its own, and the hint in the title row no longer runs into the title.

## 1.0.2

- A character no longer shows up twice when the server reports a different realm name. Characters are now kept by their character ID; existing doubles are merged at login.

## 1.0.1

- New icon in the addon list and on the minimap button, part of the new Bencepo logo family.

## 1.0.0

- Minimap button with a tooltip: every tracked profession cooldown of all your characters, with the time left.
- Window with the mats status of each craft: in bags, in bank, or what is missing.
- Tracks every transmute on its own cooldown (Arcanite, Truesilver, Gold, elemental transmutes), Mooncloth and the Salt Shaker.
- Reagents are read from the profession window, so recipe changes in Forever are picked up.
- Macro "ProfCD" is created when the minimap button is turned off.
- Chat notice when a cooldown is ready. `/pcd forget <name>` removes a character.
- Settings in the window, with a "Report a bug" button.
