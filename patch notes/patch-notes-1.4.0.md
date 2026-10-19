Welcome to 1.4.0

A compatibility release: Token Applier now shares the screen with other mods and tables instead of taking it over.

### HUD plays nicely with other HUDs (#80, #60)
- Previously, adding Token Applier removed every other on-screen HUD on the table (table HUDs, other mods' panels). That's fixed.
- TA now adds its HUD alongside whatever is already on screen, and leaves everything else exactly as it was.
- Tested on the LCT 40K table (both its intro screen and in-game HUD) with Yellowscribe rules cards open at the same time.

### HUD repairs itself
- If another mod or table script removes the TA HUD mid-game, it comes back by itself within a few seconds.
- If something keeps removing it over and over, TA stops trying for that session rather than fight it (see HUD: OFF below).

### HUD: ON/OFF reworked
- HUD: OFF now removes the HUD completely: Token Applier won't touch the on-screen UI at all. The Token Applier object itself and the right-click menu keep working.
- The setting is now saved with the object, so it stays the way you left it after a reload.
- Turn it back on from the Token Applier's settings (HUD section).
- Handy if a table's own HUD ever clashes with TA: switch the HUD off, save the object, done.

### For table and mod makers
- You can bundle Token Applier with your table: set HUD: OFF (or leave it on) and save the object, and every player gets it that way.
- All TA HUD elements have ids starting with `TokenApplier_hud_` (since 1.3.1), so they're easy to spot and won't clash with your ids.
- Your table's `<Defaults>` styles no longer change TA's HUD (e.g. a table that makes all text bold).

### Less bugs
- Fixed TA HUD text turning bold (and the token ✕ remove button vanishing) on tables with their own default text styles.
- Fixed errors when the script is put onto a brand-new object.

### Known limits
- When TA redraws its HUD (e.g. flipping a HUD setting), other mods' panels that you've dragged somewhere (e.g. the LCT scoreboard) snap back to their starting position, and open panels may flicker once. Tabletop Simulator doesn't let scripts read a dragged position, so this can't be kept for now.
