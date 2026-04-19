# Token Applier
### *make ANYTHING a token.*
##### A universal hover-token controller for Tabletop Simulator

Steam Workshop page https://steamcommunity.com/sharedfiles/filedetails/?id=3691670393

---

Token Applier is a self-contained controller object for TTS that lets you deploy and manage floating tokens attached to any model on the table — without ever placing a token directly on the surface. Works with any game, any miniature, any custom asset.

Built with Warhammer 40,000 and Age of Sigmar in mind, but universal by design.

---

## ✨ Key Features

### Floating Hover Tokens
Tokens automatically follow their assigned model around the table, hovering at a configurable height above it. They stay locked in position, never sitting on the table surface itself — keeping the board clean and readable at all times.

### Universal Template System
Any object in TTS can be captured as a token template using its full JSON data. Token Applier works with any game, any miniature set, and any custom asset without needing per-game configuration.

### Drop-to-Capture
Drag any object on top of the Token Applier controller and it automatically captures it as the new token template, then ejects the object cleanly. No menus needed.

### Token History Grid
The last 8 used templates are stored and displayed as a clickable grid with thumbnail images. Switching between token types mid-session is instant.

### Multi-Token Support Per Model
Up to 6 tokens can be attached to a single model simultaneously. Tokens arrange themselves in a **radial spread** or **line-up** layout, both independently configurable per model.

---

## 🎮 Gameplay Features

**Per-model layout modes** — Each model independently supports radial spread or line-up mode, with an adjustable spread radius and a Z-axis offset to nudge the group forward or back.

**Hide on pickup** — When a model is picked up, its tokens shrink and fly upward to stay out of the way, then restore to full size when the model is set back down.

**Token transfer** — Right-clicking a token gives options to transfer either a single token or all tokens from a model to a different model, just by selecting the destination.

**Per-token transform controls** — Tokens can be scaled, flipped, rotated 180°, toggled vertical, and raised or lowered independently or all at once.

**Token select mode** — Clicking a token's name slot in the dynamic panel selects only that token, so modifier controls apply to just the selected one rather than all tokens on a model.

**Screen HUD** — A persistent on-screen overlay mirrors all core controls (add token, history grid, settings) so players don't need to interact with the controller object directly.

**HUD positioning** — The HUD can be snapped to 8 preset screen positions, or enabled for free-drag anywhere on screen.

---

## ⚙️ Settings & Quality of Life

| Feature | Description |
|---|---|
| Token history edit mode | Delete individual entries from the history grid without clearing everything |
| Size warnings | A warning banner appears for large (>5kb) or very large (>20kb) templates |
| Flip support | Custom Tile objects get a right-click Flip option via the context menu |
| Template preview | A small image or name label above the controller shows the active template |
| HUD minimise | Collapse the HUD to a small restore button and bring it back with one click |
| Drop-template toggle | Disable drop-on-controller capture to prevent accidental template changes |
| Set Template visibility | Hide the Set Template button for a cleaner HUD |
| Restore tokens | Re-spawn any tokens that went missing after a save/load cycle |
| Grace period healing | If a model briefly disappears mid-move, tokens hold position and try to reattach to a nearby object before being removed |
| State persistence | All token assignments, history, layout settings, and HUD preferences survive a TTS save/load |
| Debug mode | Print the full internal token table and history to the console for troubleshooting |

---

## 🚀 Getting Started

1. Add the Token Applier controller object to your TTS table
2. Drop any object onto it to capture it as your token template — or select an object and click **Set Template**
3. Select a model on the table, then click **Add Token** (or use the on-screen HUD)
4. The token will spawn and begin following the model automatically

---

## 📋 Notes

- Designed for use with Warhammer 40,000, Age of Sigmar, Spearhead, and similar miniatures games
- Universal — works with any TTS object type including Custom Images, Custom Meshes, and Custom Tiles
- Tokens persist across saves; use **Restore Tokens** in settings if any go missing after a reload

---

*Built for Tabletop Simulator · [View on GitHub](https://github.com/MrAltF4/Token-Applier)*