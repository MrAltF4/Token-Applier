Welcome to 1.4.2

A look-and-feel release: Token Applier's HUD gets a cleaner, more polished design, a reworked token panel, and a batch of fixes.

### A fresh new look (#106)
- New navy colour scheme with rounded buttons across the HUD's main controls and the token panel.
- Add Token is now the one button with a border, so your eye goes straight to it.
- Quieter buttons stay slightly see-through, so the table still shows through the HUD (Opaque makes everything solid).
- Panels like Token History now have rounded corners to match.
- Text shadows where text sits on bright colours, so it stays easy to read.

### Settings are calmer (#90, #92)
- Settings buttons and panels are now grey instead of yellow, so everyday settings don't grab your attention.
- Yellow now means "careful, this removes things": Remove All Tokens, Clear All History and Stop Editing History.
- Red still means "Sure? Click again".
- HUD settings buttons are now a neat 2×2 block (HUD, Opaque / Place, Drag), all the same size (#91).
- "Solid" and "Opaque" were two names for the same switch. It's now called Opaque everywhere, and its tooltip tells you what clicking it will do.
- Placing the HUD: a big Cancel button now sits at the bottom of the placement screen, easy to find under the dark overlay.

### Token history (#93, #95, #79, #31)
- Pictures sit slightly inside each slot, so the selected slot's highlight frames the picture and stands out clearly.
- Tokens without a picture show their name in smaller, bold text with a shadow, with more of the name visible.
- Fixed two-line names sometimes showing on one line.
- Edit History's red delete overlay is now see-through, so you can see which token you're about to delete (even with Opaque on).

### Token panel reworked (#96, #97)
- Each token now shows a small picture of itself next to its name.
- Names line up on the left, and the HUD shows much more of long names.
- The selected token is highlighted in the same cyan as a selected history slot.
- Remove All Tokens now sits right under the list of tokens it removes, and moves as tokens are added or removed.
- The token object itself now has a Remove All Tokens button too, above its token buttons.
- The ✕ remove buttons are now neat squares.
- Line up / Radial matches the other buttons and tells you what a click switches to: "— Line up" or "⊙ Radial".
- On the HUD, Line up sits on the same line as Minimise, with a divider above it.

### Bug fixes
- Fixed tokens with no name of their own showing the name of whichever template was currently set. They now show their own type (e.g. Custom_Token).
- Fixed Remove All Tokens appearing in the wrong place until a token was added.
- Fixed the HUD's settings getting out of step with the object's when settings were opened or closed while the HUD was minimised.
- Fixed the HUD settings button staying blue after closing settings.
- Fixed minimising and restoring the HUD bringing back half of the settings.
- Fixed the HUD Set Template text sometimes turning black (e.g. on the LCT table), and long template names losing their second line.
- Fixed the HUD's Set Template button showing an old name after deleting the active history entry or clearing history.
- Fixed button labels breaking onto two lines ("HU / D").

### Known limits
- In the Token History panel, see-through buttons on a see-through panel add up to look almost solid. A fix is planned.
- The object's own buttons and a few HUD pieces (history arrows, debug buttons) still have the old look. They'll get it in a later update.
