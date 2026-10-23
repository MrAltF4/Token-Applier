Welcome to 1.4.3

A make-it-yours release: a new Customise panel, history you can rename and rearrange, token buttons you can lay out your way, and a more polished HUD all round.

### New: Customise panel
- A **Customise** button in settings opens a separate panel for look-and-feel options, so the everyday settings stay simple.
- **Selection colour** (#102): pick the colour that marks your selected history slot and selected token. 12 one-click colours (including white) or type any hex code. Light colours switch the text to dark automatically. Reset brings back the default cyan.
- **Background** (#100): fill the see-through gaps behind the HUD at 0%, 50% or 100%. Each section of the HUD gets its own rounded backdrop, and buttons get a soft rim so they stand out from it. Separate from Opaque.
- **Token button layout** (#101): see below.

### Token history
- **Names under pictures** (#98): history slots with a picture now show the token's name on a small tab underneath.
- **Rename** (#103): right-click a history slot to rename it. Save, Enter or clicking away keeps the new name; ✕ (or right-clicking the slot again) cancels. Tokens you add from that slot afterwards get the new name too.
- **Move** (#104): the new **Move History** button lets you rearrange your history. Click a slot, then another, and they swap places, even across pages. A yellow frame shows you're in Move mode and the picked slot turns white.
- **Edit History is now Delete History**, so it's clear which does what.
- Token History controls now sit right beside the history grid, with Default Scale on top.

### Token buttons: choose your layout (#101)
- **Layout 1**: the original arrangement.
- **Layout 2**: each column is a pair: up / more on top, down / less below.
- **Layout 3**: grouped. The buttons that affect *all* tokens (move, spread) get their own row above Line up.
- **Custom**: arrange the buttons yourself. Press **Arrange**, click a button, then another (or the empty spot) to swap them. Works even with no model selected. Saved with the object.
- On the HUD, the layout switch sits right above the token buttons, and only shows while the Customise panel is open.
- Rotate now reads **180°**, so it's clear what it does.
- Line up / Radial now read "— Line Up Arrangement" / "⊙ Radial Arrangement" on the HUD.

### Settings and look
- **Debug** toggle (#99): debug buttons are hidden unless you turn them on. Saved, so testers can leave it on.
- Toggles are calmer: "on" is a muted green and "off" a muted red. Real warnings ("Sure? Click again", remove buttons) keep their strong red.
- Buttons that open something (Settings, Customise, Debug, Stop Deleting, Stop Moving, Arrange) now look **pressed in** while open.
- Clear All History and Remove All Tokens share a striking gold.
- HUD text sizes are consistent, the minimise and settings buttons are slimmer, and the Set Template show/hide toggle is smaller.
- Object UI: Token Creation now lists Drop Template first.

### Bug fixes
- Debug and Customise no longer lag when clicked.
- Fixed the Token History panel animating twice when restoring the HUD.
- Fixed the settings backdrop staying too tall after closing settings with Customise open.
- Fixed the Customise button staying lit after closing settings.
- Fixed the HUD colour box not showing what you type.

### Known limits
- The Move History frame has square corners for now; rounded ones need a small image, planned for 1.4.4.
- While arranging a Custom layout, each swap redraws the HUD.
- The Token Applier object's own buttons still have the older look. They'll catch up in 1.4.4.
