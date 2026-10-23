-- =============================================================
--  Token Applier – Token Manager
--  One controller handles any token type via full JSON template
-- =============================================================
-- ================== created by MrAltF4 ========================

-- ──────────────────────────────────────────────────────────────
--  OTHER CONSTANTS
-- ──────────────────────────────────────────────────────────────
	local FLOAT_HEIGHT_LOW  = 5.0
	local HEIGHT_STEP       = 0.5
	local FOLLOW_INTERVAL   = 0.2
	local SPREAD_RADIUS_DEFAULT = 1.0
	local MAX_TOKENS        = 6
	local SCALE_STEP        = 0.1
	local RADIUS_STEP       = 0.5
	local GRACE_PERIOD      = 2.0
	local HEAL_RADIUS       = 0.2
	local HISTORY_SLOTS     = 8    -- slots visible per page (the 2×4 grid)
	local HISTORY_MAX       = 32   -- total history entries kept (4 pages of 8)
	local HISTORY_PAGES     = HISTORY_MAX / HISTORY_SLOTS   -- 4; if this changes, add matching btn_historyPage_N handlers
	local DROP_EJECT_OFFSET = 3.5
	local PICKUP_HEIGHT_BOOST = 50.0
	local PICKUP_SCALE_SHRINK = 0.01
	local TOKEN_TAG         = "TokenApplier_Token"   -- every token we spawn carries this tag (see TOKEN STAMPING)

-- HUD CONSTANTS
	local HUD_POSITIONS = {
	                             -- LowerCentre        MiddleCentre         X-LR Y-UD
		{ id="top_left",        hudXY="-700 850",  btnXY="-700 375"  },
		{ id="top_center",      hudXY="0 800",     btnXY="0 300"     },
		{ id="top_right",       hudXY="400 850",   btnXY="525 375"   },
		{ id="left_bottom",     hudXY="-700 250",  btnXY="-700 -250" }, 
		{ id="bottom_left",     hudXY="-400 2",    btnXY="-400 -300" },
		{ id="bottom_cenleft",  hudXY="-250 2",    btnXY="-250 -300" },  
		{ id="bottom_center",   hudXY="0 2",       btnXY="0 -300"    },
		{ id="bottom_cenright", hudXY="250 2",     btnXY="250 -300"  },


	}
	local REMOVE_ALL_LABEL    = "X Remove All Tokens from Model"   -- plain X matches "X Clear History" (🗑 doesn't render in TTS)
	local REMOVE_ALL_STYLE    = "cautionStrong"  -- normal state: same striking gold as Clear All History (both remove everything)
	local REMOVE_ARMED_STYLE  = "hudRemove"      -- "Sure?" state: red, so the change pops
	local CLEAR_HISTORY_LABEL = "X Clear All History"
	local CLEAR_HISTORY_STYLE = "cautionStrong"  -- normal: striking gold (only visible while Edit History is live)
	local EDIT_OFF_STYLE      = "settingsItem"   -- Edit History button: grey like the other settings
	local EDIT_ON_STYLE       = "pressed"        -- "Stop Editing History": pressed in (it opened a mode), see setPressedLook
	-- Settings groups (#90): grey, so standard settings don't draw the eye like yellow did
	local SETTINGS_PANEL_COLOR = "#1C1F28F2"     -- background of the Token History / HUD groups
	local SETTINGS_TITLE_COLOR = "#AFC1D8"       -- group titles ("Token History", "Token Creation")
	-- Line up / Radial toggle (dynamic panel). The label names what a click switches TO, with a symbol.
	-- One style for both states (same as the other dynamic buttons), so only the text ever changes live.
	local LINEUP = {
		style = "dynMod",
		-- (⨀ doesn't draw in TTS's font; ⊙ and ○ both do, ⊙ chosen as it reads as a symbol, not a letter)
		hud   = { [true] = "⊙ Radial Arrangement",  [false] = "— Line Up Arrangement" },    -- key = the model is currently in line-up mode
		oui   = { [true] = "⊙\nRadial", [false] = "—\nLine up" },   -- OUI button is a 60px square: short label, symbol on top
	}
	-- Opaque toggle hover text, by current state (OUI + HUD); the toggle rebuilds both UIs, so it stays right
	local OPAQUE_TOOLTIP = {
		[true]  = "Opaque: ON. Click to make backgrounds see-through again (object + HUD)",
		[false] = "Opaque: OFF. Click to make every background fully solid (object + HUD)",
	}
	local CLEAR_ARMED_STYLE   = "danger"         -- "Sure?" state: red
	local HUD_CLEAR_LABEL     = "X Clear All History"     -- HUD wording for the same buttons
	local HUD_EDIT_OFF_LABEL  = "Delete History"   -- (was "Edit History": now there's Move History too, #104)
	local HUD_EDIT_ON_LABEL   = "←Stop Deleting"
	local MOVE_LABEL          = { [false] = "Move History", [true] = "←Stop Moving" }   -- #104, both UIs
	local REMOVE_CONFIRM_TIME = 3.0   -- seconds the "Sure? Click again" state waits for the second click

-- TEMPLATE SIZE / HISTORY DISPLAY CONSTANTS
	local SIZE_LARGE        = 5000    -- template JSON bytes above this = "large" (yellow warning)
	local SIZE_MASSIVE      = 20000   -- above this = "massive" (red warning)
	local SIZE_BADGE_COLOR  = { large = "#E6C619", massive = "#D93030" }   -- history slot badge colours
	local NAME_ONLY_TYPES   = { Custom_Token = true }   -- types whose history slot shows the name instead of the image WHEN TINTED (white silhouettes)

-- ──────────────────────────────────────────────────────────────
--  STATE VARIABLES
-- ──────────────────────────────────────────────────────────────
	
	local hoverEntries      = {}
	local modelRadius       = {}
	local templateJSON      = nil
	local templateScale     = nil
	local previewGUID       = nil
	local PREVIEW_HEIGHT    = 1.0
	local lastSelectedGUID  = nil
	local selectedTokenGUID = nil
	local followLoopRunning     = false
	local selectionLoopRunning  = false
	local tokenHistory          = {}
	local collisionCooldown     = false
	local heldModels            = {}
	local settingsOpen          = false
	local hudVisible            = true
	local dynPanelVisible       = false  -- tracks whether dynamic panel is currently shown
	local historyEditMode 		= false
	local templateCache     	= { label = "Set Template\n(none)", imageURL = "", name = "", byteSize = 0 }   -- byteSize needed: a brand-new object has no saved state to fill it
	local hideSetTemplate 		= true
	local dynHideDelay 			= false
	local templateIsFlippable 	= false
	local modelLineUp     		= {}   -- [targetGUID] = "radial"|"line"
	local modelLineOffset 		= {}   -- [targetGUID] = number (world Z offset)
	local pendingTransfers      = {}   -- [playerColor] = { tokenGUID = single-token mode | sourceGUID = all-tokens mode (model GUID) }
	local saveStatePending  	= false
	local saveStateDelay    	= 0.5   -- seconds; tune down to 0.2 if you want snappier persistence
	local targetMapCache    	= nil   -- invalidated when hoverEntries changes
	local seatedColors 			= {}
	local dropTemplateEnabled 	= true
	local hudDraggable 			= false
	local hudRootOffsetXY 		= "-400 2"
	local hudPlacementMode 		= false
	local defaultScaleOffset 	= -0.1   -- offset from template scale applied when a token spawns (in SCALE_STEP increments)
	local applierDestroyed 		= false  -- set by onDestroy; stops our loops so a deleted Applier can't fight a new one
	local myGUID 				= nil    -- this Applier's GUID, cached in onLoad (still readable after deletion)
	local showTemplatePreview 	= false  -- spawn a copy of image-less templates next to the TA (OUI setting, off by default)
	local imageCheck 			= {}     -- [imageURL] = "ok" | "unsupported" (e.g. WebP, which the UI can't draw); saved
	local imageCheckPending 	= {}     -- [imageURL] = true while its download/check is in flight (not saved)
	local historyPage 			= 0      -- which page of history the 8 slots show (0 = newest)
	local uiOpaque 				= false  -- Opaque mode: all OUI + HUD backgrounds fully solid (saved)
	local hudOff 				= false  -- HUD: OFF = never touch the shared screen UI at all, OUI only (saved)
	local debugOpen 			= false  -- Debug toggle (#99): shows the debug buttons inside settings (saved)

-- ──────────────────────────────────────────────────────────────
--  FORWARD DECLARATIONS
-- ──────────────────────────────────────────────────────────────
	local spawnPreview
	local refreshTemplateButton
	local rebuildXML
	local rebuildHUD
	local hudRebuildPending = false
	local injectContextMenu
	local refreshDynamicPanelSlots
	local refreshHistorySlots
	local refreshPreviewIndicator

-- ──────────────────────────────────────────────────────────────
--  BUTTON STYLES
-- ──────────────────────────────────────────────────────────────

	local BTN_STYLE = {
	    primary = {
	        colors     = "#0D2B40FF|#1A5C8AFF|#0A1F2EFF|#333333AA",
	        textColor  = "#3CCCFF",
	        transition = "ColorTint",
	    },
	    template = {
	        colors     = "#111111B2|#222222CC|#0A0A0AB2|#333333AA",
	        textColor  = "#CCCC44",
	        transition = "ColorTint",
	    },
	    settings = {
	        colors     = "#000000F2|#222222F2|#111111F2|#333333AA",
	        textColor  = "#D8DCE6",   -- ⚙ icon: light grey (#90; was yellow)
	        transition = "ColorTint",
	    },
	    settingsItem = {   -- everyday settings buttons: slate grey (#90; was olive yellow)
	        colors     = "#33394AF2|#454C60F2|#262B38F2|#333333AA",
	        textColor  = "#FFFFFF",
	        transition = "ColorTint",
	    },
	    deleteSlot = {     -- Edit History overlay on each slot: 40% so the token underneath shows through.
	                       -- keepAlpha: Opaque mode leaves it see-through (the overlay is useless solid)
	        colors     = "#2B0D0D66|#5A1A1A99|#1F0A0A66|#333333AA",
	        textColor  = "#FF6060",
	        transition = "ColorTint",
	        keepAlpha  = true,
	    },
	    caution = {        -- "careful" actions (Remove All, Clear History, Stop Editing): the old olive yellow
	        colors     = "#484716F2|#6B6B22F2|#303010F2|#333333AA",
	        textColor  = "#FFFFFF",
	        transition = "ColorTint",
	    },
	    danger = {
	        colors     = "#2B0D0DF2|#5A1A1AF2|#1F0A0AF2|#333333AA",
	        textColor  = "#FF6060",
	        transition = "ColorTint",
	    },
	    active = {
	        colors     = "#15AFCCF2|#1DCEF0F2|#0F8099F2|#333333AA",
	        textColor  = "#FFFFFF",
	        transition = "ColorTint",
	    },
	    histSelected = {   -- selected history slot: colours rebuilt from the chosen colour (CUSTOM, #102)
	        colors     = "#15AFCCF2|#1DCEF0F2|#0F8099F2|#333333AA",
	        textColor  = "#FFFFFF",
	        transition = "ColorTint",
	    },
	    ghost = {
	        colors     = "#080808B2|#141414CC|#050505B2|#333333AA",
	        textColor  = "#404040",
	        transition = "ColorTint",
	    },
	    historySlot = {
	        colors     = "#0D140DF2|#1A281AF2|#08100AF2|#333333AA",
	        textColor  = "#FFFFFF",
	        transition = "ColorTint",
	    },
	    -- ── Dynamic panel (1.4.2 look: navy bodies, rounded, no border; text colours keep their meaning) ──
	    -- Modifier buttons (purple = move / flip / rotate / height)
	    dynMod = {
	        colors     = "#1E2130E6|#2E3246E6|#161824E6|#333333AA",
	        textColor  = "#CC99FF",
	        transition = "ColorTint",
	        round      = true,
	    },
	    -- Scale up / spread up (green text)
	    dynGreenBtn = {
	        colors     = "#1E2130E6|#26402EE6|#161824E6|#333333AA",
	        textColor  = "#80FF80",
	        transition = "ColorTint",
	        round      = true,
	    },
	    -- Scale down / spread down (red text)
	    dynRedBtn = {
	        colors     = "#1E2130E6|#402A2EE6|#161824E6|#333333AA",
	        textColor  = "#FF8080",
	        transition = "ColorTint",
	        round      = true,
	    },
	    -- Token name slot (unselected)
	    dynSlot = {
	        colors     = "#1A1D2CE6|#2A2E42E6|#141622E6|#333333AA",
	        textColor  = "#AFC1D8",
	        transition = "ColorTint",
	        round      = true,
	    },
	    -- Token name slot (selected): same cyan as a selected history slot
	    dynSlotSelected = {
	        colors     = "#15AFCCE6|#1DCEF0E6|#0F8099E6|#333333AA",
	        textColor  = "#FFFFFF",
	        transition = "ColorTint",
	        round      = true,
	    },
	    -- ✕ remove button
	    dynRemove = {
	        colors     = "#3A1A20E6|#5A2630E6|#2A1016E6|#333333AA",
	        textColor  = "#FFFFFF",
	        transition = "ColorTint",
	        round      = true,
	    },
	    hudAdd = {
	        colors     = "#0D2B40F2|#1A5C8AF2|#0A1F2EF2|#333333AA",
	        textColor  = "#3CCCFF",
	        transition = "ColorTint",
	    },
	    hudRemove = {
	        colors     = "#2B0D0DF2|#5A1A1AF2|#1F0A0AF2|#333333AA",
	        textColor  = "#FF6060",
	        transition = "ColorTint",
	    },
	    hudHide = {
	        colors     = "#1A1A1AF2|#2A2A2AF2|#111111F2|#333333AA",
	        textColor  = "#888888",
	        transition = "ColorTint",
	    },
		hudPosition = {   -- Place HUD location icons: same blue as Add Token so they pop
	        colors     = "#0D2B40F2|#1A5C8AF2|#0A1F2EF2|#333333AA",
	        textColor  = "#3CCCFF",
	        transition = "ColorTint",
	    },
		-- History page arrows (‹ ›)
		historyNav = {   -- same dark green as the history slots, so the arrows read as part of the grid
			colors     = "#0D140DF2|#1A281AF2|#08100AF2|#333333AA",
			textColor  = "#FFFFFF",
			transition = "ColorTint",
		},
		-- History page dots: current page bright, others grey
		historyDotOn = {
			colors     = "#FFFFFFFF|#FFFFFFFF|#CCCCCCFF|#333333AA",
			textColor  = "#FFFFFF",
			transition = "ColorTint",
		},
		historyDotOff = {
			colors     = "#666666FF|#999999FF|#444444FF|#333333AA",
			textColor  = "#FFFFFF",
			transition = "ColorTint",
		},
		-- Any toggle in its ON state
		toggleOn = {   -- muted 1.4.3: same green hue, half the saturation (was #145214 / #1E7A1E / #0E3A0E: too eye-catching)
			colors     = "#335233F2|#4C7A4CF2|#243A24F2|#333333AA",
			textColor  = "#FFFFFF",
			transition = "ColorTint",
		},
		-- Any toggle in its OFF state: "danger" red muted the same way (same hue, half the saturation).
		-- Real warnings ("Sure? Click again", ✕ remove, delete overlay) keep the strong red.
		toggleOff = {
			colors     = "#2B1C1CF2|#5A3A3AF2|#1F1414F2|#333333AA",
			textColor  = "#FFB0B0",
			transition = "ColorTint",
		},
		-- "Pressed in": for buttons that OPEN something (a panel, a mode) rather than switch a feature on
		-- (Customise, Stop Editing History). Darker, sunk body + dimmer text + a dark rim; the label is
		-- also nudged 1px down (see setPressedLook). Click again and it pops back to settingsItem.
		pressed = {   -- v2: brighter, thicker rim + clearer text (v1's dark rim got lost on a dark backdrop)
			colors      = "#1C1F28F2|#272B37F2|#16181FF2|#333333AA",
			textColor   = "#D0D6E2",
			transition  = "ColorTint",
			outline     = "#7A86A2",
			outlineSize = "2 2",
		},
		-- Move History (#104): the picked slot. White, so the frame around its picture reads as a white ring
		movePicked = {
			colors     = "#EEF2F8F2|#FFFFFFF2|#C8CED8F2|#333333AA",
			textColor  = "#10141E",
			transition = "ColorTint",
		},
		-- Clear All History: a brighter, more striking gold than "caution" (it wipes everything)
		cautionStrong = {
			colors     = "#9A7D00F2|#B89600F2|#7A6300F2|#333333AA",
			textColor  = "#FFFFFF",
			transition = "ColorTint",
		},
		-- Debug group buttons: lower-mid grey so they don't draw the eye
		debug = {
			colors     = "#3C3C3CF2|#4E4E4EF2|#2C2C2CF2|#333333AA",
			textColor  = "#AAAAAA",
			transition = "ColorTint",
		},
		-- (Line up / Radial now uses dynMod for both states, see LINEUP; the old yellow styles are gone)
		-- ── 1.4.2 shared look (TEST on a few HUD buttons first, see btnStyle) ──
		-- One navy palette like LCT's HUD. A style with an `outline` also gets a thin
		-- lighter border and rounded edges (`round = true` gives rounded edges alone).
		-- Keep bordered styles near-solid (F2): TTS's outline is 4 copies
		-- of the WHOLE button shape (nudged 1px each way) drawn behind it, so a see-through
		-- body just shows those copies, never the table (tested 1.4.2 at B2 / 70%).
		lookPrimary = {   -- main action (Add Token)
			colors     = "#1A5FC8F2|#2A70D8F2|#144CA0F2|#333333AA",
			textColor  = "#FFFFFF",
			transition = "ColorTint",
			outline    = "#6DA8FF",
		},
		-- Borders only on the buttons that should stand out most. The quieter ones below have
		-- no outline, so they can be see-through (B2 ≈ 70%; Opaque mode turns them to FF).
		lookNeutral = {   -- everyday buttons (minimise, settings closed)
			colors     = "#2A2A3AB2|#3A3A4CB2|#20202EB2|#333333AA",
			textColor  = "#AFC1D8",
			transition = "ColorTint",
			round      = true,
		},
		lookTemplate = {  -- Set Template: navy body, keeps its yellow name
			colors     = "#1A1A2AB2|#2A2A3CB2|#12121EB2|#333333AA",
			textColor  = "#CCCC44",
			transition = "ColorTint",
			round      = true,
		},
		lookActive = {    -- "on" state (HUD settings open)
			colors     = "#15AFCCB2|#1DCEF0B2|#0F8099B2|#333333AA",
			textColor  = "#FFFFFF",
			transition = "ColorTint",
			round      = true,
		},
	}

	local LOOK_OUTLINE_SIZE = "1 1"   -- border thickness (x y) for styles with an outline

	-- Rounded background for a Panel. TTS Panels ignore roundEdges/outline (tested 1.4.2), but
	-- Buttons take them, so the panel goes see-through and this non-clickable Button, placed
	-- FIRST inside it, is drawn behind the contents. All 4 colour states are the same, so it
	-- never reacts; raycastTarget="false" lets clicks through to the buttons on top.
	-- outline is optional (nil = no border, which also keeps a see-through colour see-through)
	local function roundedPanelBg(width, height, color, outline)
		local border = outline and (' outline="' .. outline .. '" outlineSize="' .. LOOK_OUTLINE_SIZE .. '"') or ""
		return '<Button width="' .. width .. '" height="' .. height .. '" raycastTarget="false"'
			.. ' colors="' .. color .. '|' .. color .. '|' .. color .. '|' .. color .. '"'
			.. border .. ' roundEdges="true" />'
	end

	-- HUD ⚙ button styles (1.4.2 look test). The OUI ⚙ keeps "settings" / "active".
	local HUD_SETTINGS_CLOSED_STYLE = "lookNeutral"
	local HUD_SETTINGS_OPEN_STYLE   = "pressed"   -- pressed in while settings are open (it opens a panel)

	local function btnStyle(name)
	    local s = BTN_STYLE[name] or BTN_STYLE.ghost
	    local look = ""
	    if s.outline then look = ' outline="' .. s.outline .. '" outlineSize="' .. (s.outlineSize or LOOK_OUTLINE_SIZE) .. '"' end
	    if s.outline or s.round then look = look .. ' roundEdges="true"' end
	    return 'colors="'     .. s.colors     .. '" '
	        .. 'textColor="'  .. s.textColor  .. '" '
	        .. 'transition="' .. s.transition .. '"'
	        .. look
	end

	-- Live-updates a button whose label is a child Text with id "<id>_text".
	-- ui = UI (HUD) or self.UI (OUI).
	-- TTS QUIRK: a Button's own textColor (set at build time by btnStyle) gets re-applied over
	-- its child Text when the button's colours change. So textColor must be updated on the
	-- Button too, or a button built in its red "off" state keeps red text after turning on.
	local function setButtonLook(ui, id, text, styleName)
	    local s = BTN_STYLE[styleName] or BTN_STYLE.ghost
	    ui.setAttribute(id,            "colors",    s.colors)
	    ui.setAttribute(id,            "textColor", s.textColor)
	    if text then ui.setAttribute(id .. "_text", "text", text) end
	    ui.setAttribute(id .. "_text", "color",     s.textColor)
	end

	local function setHudButtonLook(id, text, styleName)
	    setButtonLook(UI, id, text, styleName)
	end

	-- The parts of the "pressed" look that colours can't do, for a live switch (setButtonLook does the
	-- colours): the dark rim, and the label nudged down. nudge = how far (HUD 1, OUI 2: it's drawn bigger).
	local function setPressedExtras(ui, id, pressed, nudge)
	    ui.setAttribute(id, "outline", pressed and BTN_STYLE.pressed.outline or "#00000000")
	    ui.setAttribute(id, "outlineSize", BTN_STYLE.pressed.outlineSize)
	    ui.setAttribute(id .. "_text", "offsetXY", pressed and ("0 " .. -nudge) or "0 0")
	end

-- ──────────────────────────────────────────────────────────────
--  OPACITY  (Opaque mode makes every OUI + HUD background fully solid)
--  A colour's transparency is its last 2 hex digits: #0D2B40F2 → F2 ≈ 95% solid, FF = 100%.
-- ──────────────────────────────────────────────────────────────

	-- The shipped (slightly transparent) button colours, so Opaque mode can switch back
	local BTN_STYLE_ORIGINAL = {}
	for name, s in pairs(BTN_STYLE) do BTN_STYLE_ORIGINAL[name] = s.colors end

	-- One colour "#RRGGBBAA" → fully solid "#RRGGBBFF" while Opaque mode is on.
	-- Fully clear colours (alpha 00, e.g. invisible container panels) are left clear.
	-- Deliberately see-through colours (Edit-mode red tint over images, Place HUD dimmer)
	-- simply aren't passed through this.
	local function op(c)
		if not uiOpaque or type(c) ~= "string" or #c ~= 9 then return c end
		if c:sub(8, 9) == "00" then return c end
		return c:sub(1, 7) .. "FF"
	end

	-- Rewrites every button style for the current mode. Because every build AND every live
	-- update reads BTN_STYLE, this one swap covers all buttons. The 4th state (disabled) is
	-- left as shipped.
	local function applyOpacity()
		for name, s in pairs(BTN_STYLE) do
			if not s.keepAlpha then   -- deliberately see-through styles stay as shipped
				local parts, i = {}, 0
				for part in BTN_STYLE_ORIGINAL[name]:gmatch("[^|]+") do
					i = i + 1
					parts[i] = (i < 4) and op(part) or part
				end
				s.colors = table.concat(parts, "|")
			end
		end
	end

-- ──────────────────────────────────────────────────────────────
--  CUSTOMISE  (1.4.3: its own panel, opened from settings, so normal settings stay simple)
--  First option: the selection colour (#102) for the selected history slot + selected token name.
-- ──────────────────────────────────────────────────────────────

	local CUSTOM = {
		open         = false,       -- customise panel showing (not saved, like settings)
		selectColor  = "#15AFCC",   -- chosen selection colour (saved)
		defaultColor = "#15AFCC",
		presets = {                 -- one-click picks, rainbow order then white (cyan = default); 12 = 2 HUD rows of 6
			{ name = "Red",    hex = "#E53935" },
			{ name = "Orange", hex = "#FB8C00" },
			{ name = "Yellow", hex = "#FDD835" },
			{ name = "Lime",   hex = "#9CCC2C" },
			{ name = "Green",  hex = "#43A047" },
			{ name = "Teal",   hex = "#00897B" },
			{ name = "Cyan",   hex = "#15AFCC" },
			{ name = "Blue",   hex = "#1E63D6" },
			{ name = "Indigo", hex = "#3F51B5" },
			{ name = "Purple", hex = "#8E24AA" },
			{ name = "Pink",   hex = "#D81B60" },
			{ name = "White",  hex = "#FFFFFF" },
		},
		hudPanelH = 116,            -- HUD customise panel height (its top = 240 + this)
		-- Backgrounds (#100): a rounded backdrop behind each HUD group, filling the see-through gaps.
		-- bg = index into bgLevels (saved). Its own setting: Opaque mode does NOT change it.
		-- Every backdrop = its group's outermost content + bgMargin on all four sides, so the
		-- groups' edges match (their lowest buttons all sit at y 2, so the bottoms line up).
		bg       = 1,
		bgMargin = 4,
		bgRim    = "#4A5270",   -- light rim on dynamic buttons while a backdrop is on, so they lift off it
		rimSize  = 1,           -- the rim's width (outlineSize); backdrops add it to their margin
		panelRim = "#4A527080", -- panels get the same rim at half strength (they're not buttons)
		bgLevels = {
			{ label = "0%",   color = nil },           -- off: today's look
			{ label = "50%",  color = "#1C1F2880" },
			{ label = "100%", color = "#1C1F28FF" },
		},
	}

	-- A backdrop for one HUD group at the current Background level ("" when it's off).
	-- A non-clickable rounded Button (Panels can't round), positioned like the HUD's other pieces.
	-- Must be inserted BEFORE the group's buttons so it's drawn behind them.
	function CUSTOM.bgXml(id, rectAlign, x, y, w, h, extra)
		local c = CUSTOM.bgLevels[CUSTOM.bg].color
		if not c then return "" end
		return '<Button id="' .. id .. '" rectAlignment="' .. rectAlign .. '" offsetXY="' .. x .. ' ' .. y .. '"'
			.. ' width="' .. w .. '" height="' .. h .. '" raycastTarget="false" roundEdges="true"'
			.. ' colors="' .. c .. '|' .. c .. '|' .. c .. '|' .. c .. '" ' .. (extra or '') .. ' />'
	end

	-- Is a backdrop showing? (Backgrounds above 0%)
	function CUSTOM.bgOn()
		return CUSTOM.bgLevels[CUSTOM.bg].color ~= nil
	end

	-- Space between a group's content and its backdrop edge: the margin plus the rim width (the edge
	-- buttons/panels carry rims while a backdrop is on, which makes them look bigger)
	function CUSTOM.bgPad()
		return CUSTOM.bgMargin + CUSTOM.rimSize
	end

	-- Main HUD block backdrop width: the history grid (x ±112.5), or the ‹ › arrows (±122.5) when
	-- there's more than one page, plus the padding each side
	function CUSTOM.mainBgW(pages)
		return 2 * ((pages > 1 and 122.5 or 112.5) + CUSTOM.bgPad())
	end

	-- Settings column backdrop height: from below the debug row (y 2) up to the Customise button (236),
	-- or to the customise panel's top (376) while it's open
	function CUSTOM.settingsBgH(customiseOpen)
		return (customiseOpen and (240 + CUSTOM.hudPanelH) or 236) - 2 + 2 * CUSTOM.bgPad()
	end

	-- Half-strength rim colour for a panel background (nil while Backgrounds is off)
	function CUSTOM.panelRimColor()
		return CUSTOM.bgOn() and CUSTOM.panelRim or nil
	end

	-- Rim attributes for a dynamic-panel button ("" while Backgrounds is off, so see-through buttons
	-- stay see-through: an outline is copies of the button drawn behind it, see btnStyle)
	function CUSTOM.rim()
		if not CUSTOM.bgOn() then return "" end
		return ' outline="' .. CUSTOM.bgRim .. '" outlineSize="' .. CUSTOM.rimSize .. ' ' .. CUSTOM.rimSize .. '"'
	end

	-- "#RRGGBB" / "rrggbb" (spaces ignored) → "#RRGGBB", or nil if it isn't a colour
	function CUSTOM.cleanHex(s)
		s = tostring(s or ""):gsub("%s", ""):upper()
		if s:sub(1, 1) ~= "#" then s = "#" .. s end
		if s:match("^#%x%x%x%x%x%x$") then return s end
		return nil
	end

	-- One colour → a button's 4 states: normal, hover (a bit lighter), pressed (darker), disabled
	function CUSTOM.buttonColors(hex, alpha)
		local rgb = { tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16) }
		local function shade(f)   -- f > 0 lightens towards white, f < 0 darkens towards black
			local out = {}
			for k, c in ipairs(rgb) do
				out[k] = math.floor((f > 0 and (c + (255 - c) * f) or (c * (1 + f))) + 0.5)
			end
			return string.format("#%02X%02X%02X%s", out[1], out[2], out[3], alpha)
		end
		return shade(0) .. "|" .. shade(0.2) .. "|" .. shade(-0.3) .. "|#333333AA"
	end

	-- One preset swatch button (OUI or HUD). The chosen colour gets a white ring (outline is fine
	-- here: swatches are fully solid). size = extra size/layout attributes for that UI.
	function CUSTOM.swatchXml(id, onClick, i, size, ring)
		local p = CUSTOM.presets[i]
		local picked = (p.hex == CUSTOM.selectColor)
		return '<Button id="' .. id .. '" onClick="' .. onClick .. '" tooltip="' .. p.name .. '"'
			.. ' colors="' .. CUSTOM.buttonColors(p.hex, "FF") .. '" transition="ColorTint" roundEdges="true" ' .. size
			.. (picked and (' outline="#FFFFFF" outlineSize="' .. ring .. '"') or '') .. ' />'
	end

	-- Puts the chosen colour into the selected-slot styles (history + token panel), then re-applies
	-- Opaque mode on top. Call after loading and after every change; builds and refreshes read BTN_STYLE.
	function CUSTOM.applySelectColor()
		local hist = CUSTOM.buttonColors(CUSTOM.selectColor, "F2")
		local dyn  = CUSTOM.buttonColors(CUSTOM.selectColor, "E6")
		BTN_STYLE_ORIGINAL.histSelected    = hist
		BTN_STYLE_ORIGINAL.dynSlotSelected = dyn
		BTN_STYLE.histSelected.colors      = hist
		BTN_STYLE.dynSlotSelected.colors   = dyn
		-- Light colours (white, yellow, lime…) get dark text, so the selected name stays readable
		local h = CUSTOM.selectColor
		local lum = (0.299 * tonumber(h:sub(2, 3), 16) + 0.587 * tonumber(h:sub(4, 5), 16) + 0.114 * tonumber(h:sub(6, 7), 16)) / 255
		local txt = lum > 0.6 and "#10141E" or "#FFFFFF"
		BTN_STYLE.histSelected.textColor    = txt
		BTN_STYLE.dynSlotSelected.textColor = txt
		applyOpacity()
	end

-- ──────────────────────────────────────────────────────────────
--  IMAGE URL EXTRACTION
-- ──────────────────────────────────────────────────────────────

	local function extractImageURL(data)
	    if type(data) ~= "table" then return nil end
	    if type(data.CustomImage) == "table" then
	        local url = data.CustomImage.ImageURL or data.CustomImage.image
	        if type(url) == "string" and url ~= "" then return url end
	    end
	    if type(data.CustomMesh) == "table" then
	        local url = data.CustomMesh.DiffuseURL
	        if type(url) == "string" and url ~= "" then return url end
	    end
	    if type(data.States) == "table" then
	        for _, state in pairs(data.States) do
	            local url = extractImageURL(state)
	            if url then return url end
	        end
	    end
	    return nil
	end

	-- Blank placeholder image used by tool-built tokens (their artwork comes from elsewhere,
	-- e.g. decals). Matched by its unique ID so any Steam server address counts.
	local BLANK_IMAGE_ID = "E4C9AE9685105F12A3D4D3DC534616786D5D7666"

	-- An image worth displaying: nil when there's no image, it's the blank placeholder,
	-- or a check found it's a format the UI can't draw (see checkImageFormats)
	local function usefulImageURL(data)
	    local url = extractImageURL(data)
	    if not url or url:find(BLANK_IMAGE_ID, 1, true) then return nil end
	    if imageCheck[url] == "unsupported" then return nil end
	    return url
	end

-- ──────────────────────────────────────────────────────────────
--  TOKEN STAMPING
--  Each token carries our tag + a copy of its hoverEntries data in its memo.
--  If the Applier is deleted, a new one can find and adopt them (btn_findTokens).
-- ──────────────────────────────────────────────────────────────

	-- Writes our tag and this token's entry data onto the token itself.
	local function stampToken(token, entry)
		if not token.hasTag(TOKEN_TAG) then token.addTag(TOKEN_TAG) end
		local memo = JSON.encode({
			owner      = myGUID,
			targetGUID = entry.targetGUID,
			offset     = entry.offset,
			scale      = entry.scale,
			flipped    = entry.flipped,
			rotated    = entry.rotated,
			vertical   = entry.vertical,
		})
		if token.memo ~= memo then token.memo = memo end
	end

	-- Strips our stamp from object data (used on templates), so the preview
	-- and new spawns are never mistaken for an old token.
	local function unstampData(data)
		if type(data.Tags) ~= "table" then return end
		local hadTag = false
		for i = #data.Tags, 1, -1 do
			if data.Tags[i] == TOKEN_TAG then
				table.remove(data.Tags, i)
				hadTag = true
			end
		end
		if hadTag then data.Memo = nil end
	end

	-- True if another Applier that is still on the table has taken this token over
	-- (Find Tokens rewrites the owner in the memo). If the owner named in the memo
	-- no longer exists, we keep the token — that also covers our own GUID changing.
	local function isOwnedByAnother(token)
		local owner = (token.memo or ""):match('"owner"%s*:%s*"([^"]+)"')
		return owner ~= nil and owner ~= myGUID and getObjectFromGUID(owner) ~= nil
	end

-- ──────────────────────────────────────────────────────────────
--  HISTORY ENTRY INFO  (size badge + name-only display)
-- ──────────────────────────────────────────────────────────────

	-- True if the object is colour-tinted (any channel noticeably below white).
	-- White silhouette tokens get their colour from a tint; community icons have the
	-- colour baked into the image and are left untinted (r1 g1 b1).
	local function isTinted(data)
		local c = type(data.ColorDiffuse) == "table" and data.ColorDiffuse or nil
		if not c then return false end
		return (c.r or 1) < 0.95 or (c.g or 1) < 0.95 or (c.b or 1) < 0.95
	end

	-- Fills in display info on a history entry: byteSize (for the size badge), and decides
	-- image vs name: a NAME_ONLY_TYPES object that is tinted (likely a white silhouette)
	-- shows its name; everything else shows its image.
	-- Re-decided every time (incl. on load), so older entries pick up rule changes.
	local function prepareHistoryEntry(entry)
		if type(entry) ~= "table" or type(entry.json) ~= "string" then return end
		entry.byteSize = #entry.json
		local ok, data = pcall(JSON.decode, entry.json)
		if not ok or type(data) ~= "table" then return end
		entry.nameOnly    = (NAME_ONLY_TYPES[data.Name] and isTinted(data)) or false
		entry.rawImageURL = extractImageURL(data)   -- the real link, kept so checkImageFormats can test it
		entry.imageURL    = entry.nameOnly and "" or (usefulImageURL(data) or "")   -- blank / unsupported → name
	end

	-- nil (normal size), "large" or "massive"
	local function sizeClass(byteSize)
		if not byteSize then return nil end
		if byteSize > SIZE_MASSIVE then return "massive" end
		if byteSize > SIZE_LARGE   then return "large"   end
		return nil
	end

	-- Small ⚠ badge in a history slot's bottom-right corner (clear of the name text).
	-- raycastTarget="false" lets clicks pass through to the slot button underneath.
	local function sizeBadgeXml(id, sc, size, fontSize)
		return '      <Panel id="' .. id .. '" rectAlignment="LowerRight" offsetXY="-1 1"'
			.. ' width="' .. size .. '" height="' .. size .. '"'
			.. ' color="' .. (SIZE_BADGE_COLOR[sc] or SIZE_BADGE_COLOR.large) .. '"'
			.. ' raycastTarget="false" active="' .. (sc and "True" or "False") .. '">'
			.. '<Text text="⚠" fontSize="' .. fontSize .. '" color="#000000" alignment="MiddleCenter" raycastTarget="false" />'
			.. '</Panel>'
	end

-- ──────────────────────────────────────────────────────────────
--  PERSISTENCE
-- ──────────────────────────────────────────────────────────────

	local function saveState()
		if saveStatePending or applierDestroyed then return end
		saveStatePending = true
		Wait.time(function()
			saveStatePending = false
			local blob = {
				hoverEntries      = hoverEntries,
				modelRadius       = modelRadius,
				modelLineUp       = modelLineUp,
				modelLineOffset   = modelLineOffset,
				templateJSON      = templateJSON,
				templateScale     = templateScale,
				previewGUID       = previewGUID,
				tokenHistory      = tokenHistory,
				hudDraggable      = hudDraggable,
				hudVisible 			= hudVisible,
				defaultScaleOffset  = defaultScaleOffset,
				showTemplatePreview = showTemplatePreview,
				imageCheck          = imageCheck,
				uiOpaque            = uiOpaque,
				hudOff              = hudOff,
				debugOpen           = debugOpen,
				selectColor         = CUSTOM.selectColor,
				bgLevel             = CUSTOM.bg,
			}
			self.script_state = JSON.encode(blob)
			-- Keep each token's own stamp in sync with the notebook
			for tGUID, entry in pairs(hoverEntries) do
				local token = getObjectFromGUID(tGUID)
				if token and type(entry) == "table" then stampToken(token, entry) end
			end
		end, saveStateDelay)
	end

	local function loadState()
	    if type(self.script_state) ~= "string" or self.script_state == "" then return end
	    local ok, data = pcall(JSON.decode, self.script_state)
	    if not ok or type(data) ~= "table" then
	        print("[TokenManager] Corrupt script_state – starting fresh.")
	        return
	    end
	    if type(data.hoverEntries) == "table" then
	        for tGUID, entry in pairs(data.hoverEntries) do
	            if type(entry) == "table" and type(entry.targetGUID) == "string" then
	                hoverEntries[tGUID] = entry
	            end
	        end
	    end
	    if type(data.modelRadius)   == "table"  then modelRadius   = data.modelRadius   end
		if type(data.modelLineUp)     == "table" then modelLineUp     = data.modelLineUp     end
		if type(data.modelLineOffset) == "table" then modelLineOffset = data.modelLineOffset end
	    if type(data.templateJSON)  == "string" then templateJSON  = data.templateJSON  end
	    if type(data.templateScale) == "table"  then templateScale = data.templateScale end
	    if type(data.previewGUID)   == "string" then previewGUID   = data.previewGUID   end
	    if type(data.tokenHistory)  == "table"  then tokenHistory  = data.tokenHistory  end
		if type(data.hudDraggable) == "boolean" then hudDraggable = data.hudDraggable end
		if type(data.hudVisible) == "boolean" then hudVisible = data.hudVisible end
		if type(data.defaultScaleOffset) == "number" then defaultScaleOffset = data.defaultScaleOffset end
		if type(data.showTemplatePreview) == "boolean" then showTemplatePreview = data.showTemplatePreview end
		if type(data.imageCheck) == "table" then imageCheck = data.imageCheck end   -- before history prep, which reads it
		if type(data.uiOpaque) == "boolean" then uiOpaque = data.uiOpaque end
		if type(data.hudOff) == "boolean" then hudOff = data.hudOff end
		if type(data.debugOpen) == "boolean" then debugOpen = data.debugOpen end
		CUSTOM.selectColor = CUSTOM.cleanHex(data.selectColor) or CUSTOM.defaultColor
		if CUSTOM.bgLevels[data.bgLevel] then CUSTOM.bg = data.bgLevel end
		-- Upgrade history from older saves (adds size info, name-only display)
		for _, entry in ipairs(tokenHistory) do prepareHistoryEntry(entry) end
	    refreshTemplateCache()
	end

-- ──────────────────────────────────────────────────────────────
--  IMAGE FORMAT CHECK
--  The 3D tokens can use WebP images, but the screen UI can't draw them: a WebP shows
--  as a white box (or keeps the slot's previous picture). We download each history
--  image once, check its first bytes, and remember the answer in imageCheck (saved).
-- ──────────────────────────────────────────────────────────────

	-- WebP files start with "RIFF", then 4 size bytes, then "WEBP". The download arrives as
	-- text, and the size bytes may get mangled, so look for "WEBP" anywhere near the start.
	local function isWebP(text)
		return type(text) == "string" and text:sub(1, 4) == "RIFF"
		   and text:sub(1, 32):find("WEBP", 1, true) ~= nil
	end

	-- Re-applies image decisions everywhere after a check finds an unsupported image
	local function applyImageCheckResults()
		for _, entry in ipairs(tokenHistory) do prepareHistoryEntry(entry) end
		refreshTemplateCache()
		refreshHistorySlots()
		refreshPreviewIndicator()
		saveState()
	end

	-- Starts a background check for every history image that hasn't been tested yet
	function checkImageFormats()
		for _, entry in ipairs(tokenHistory) do
			local url = entry.rawImageURL
			if type(url) == "string" and url ~= "" and not url:find(BLANK_IMAGE_ID, 1, true)
			   and not imageCheck[url] and not imageCheckPending[url] then
				imageCheckPending[url] = true
				WebRequest.get(url, function(request)
					imageCheckPending[url] = nil
					if request.is_error then return end   -- couldn't download: leave untested, retry next time
					if isWebP(request.text) then
						imageCheck[url] = "unsupported"
						applyImageCheckResults()
					else
						imageCheck[url] = "ok"
						saveState()
					end
				end)
			end
		end
	end

-- ──────────────────────────────────────────────────────────────
--  HELPERS
-- ──────────────────────────────────────────────────────────────

	local function findTokensForTarget(targetGUID)
	    local found = {}
	    for tGUID, entry in pairs(hoverEntries) do
	        if type(entry) == "table" and entry.targetGUID == targetGUID then
	            found[#found + 1] = tGUID
	        end
	    end
	    return found
	end

	function findTokenForTarget(targetGUID)
	    for tGUID, entry in pairs(hoverEntries) do
	        if type(entry) == "table" and entry.targetGUID == targetGUID then
	            return tGUID
	        end
	    end
	    return nil
	end

	-- A token's display name: its own name, or (if it has none) its own object type, e.g.
	-- "Custom_Token" (the same thing its history slot shows). Never the CURRENT TEMPLATE's name:
	-- that used to make every unnamed token show whatever template was set at the time.
	local function getTokenName(tokenGUID)
	    local obj = getObjectFromGUID(tokenGUID)
	    if obj then
	        local n = obj.getName()
	        if n and n ~= "" then return n end
	        if obj.name and obj.name ~= "" then return obj.name end
	    end
	    return "Token"
	end

	local function getRadiusForTarget(targetGUID)
	    return modelRadius[targetGUID] or SPREAD_RADIUS_DEFAULT
	end

	local function shortName(name, maxWidth, maxLines)
		maxWidth  = maxWidth  or 8
		maxLines  = maxLines  or 3
		local lines  = {}
		local current = ""
		for word in name:gmatch("%S+") do
			if current == "" then
				current = word
			elseif #current + 1 + #word <= maxWidth then
				current = current .. " " .. word
			else
				table.insert(lines, current)
				if #lines >= maxLines then
					lines[#lines] = lines[#lines]:sub(1, -2) .. "…"
					return table.concat(lines, "\n")
				end
				current = word
			end
		end
		if current ~= "" then table.insert(lines, current) end
		return table.concat(lines, "\n")
	end
	
	local function stripBBCode(name)
		return name:gsub("%[/?[%a][%a0-9]*%]", "")
	end

	-- Hover text for a history slot: the name, plus a size warning if the template is large/massive
	local function historyTooltip(entry)
		if not entry then return "Empty slot" end
		local text = shortName(stripBBCode(entry.name), 30, 3)
		local sc   = sizeClass(entry.byteSize)
		if sc == "massive" then return text .. "\n⚠ Very large object — expect some lag" end
		if sc == "large"   then return text .. "\n⚠ Large object" end
		return text
	end

	local function isFlippableType(data)
		if type(data) ~= "table" then return false end
		return data.Name == "Custom_Tile"
	end

	local function invalidateTargetMap()
		targetMapCache = nil
	end

	local function buildTargetMap()
		if targetMapCache then return targetMapCache end
		local map = {}
		for tGUID, entry in pairs(hoverEntries) do
			if type(entry) == "table" then
				local tgt = entry.targetGUID
				if not map[tgt] then map[tgt] = {} end
				map[tgt][#map[tgt] + 1] = tGUID
			end
		end
		targetMapCache = map
		return map
	end

-- ──────────────────────────────────────────────────────────────
--  TEMPLATE CACHE
-- ──────────────────────────────────────────────────────────────

	function refreshTemplateCache()
		if not templateJSON then
			templateCache = { label = "Set Template\n(none)", imageURL = "", name = "", byteSize = 0 }
			return
		end
		local byteSize = #templateJSON
		local ok, data = pcall(JSON.decode, templateJSON)
		templateIsFlippable = (ok and isFlippableType(data)) or false
		if not ok or type(data) ~= "table" then
			templateCache = { label = "Set Template\n[custom]", imageURL = "", name = "Token", byteSize = byteSize }
			return
		end
		local n = (data.Nickname and data.Nickname ~= "") and data.Nickname
			   or (data.Name    and data.Name    ~= "") and data.Name
		local cleanName = n and stripBBCode(n) or nil
		local imageURL  = usefulImageURL(data) or ""   -- blank placeholder → TA face shows the name instead
		templateCache = {
			label    = cleanName and ("Set Template\n[" .. cleanName .. "]") or "Set Template\n[custom]",
			imageURL = imageURL,
			name     = cleanName or "Token",
			byteSize = byteSize,
		}
	end

	-- Makes text safe to put inside an XML attribute (names can contain " & < >)
	local function xmlEscape(s)
		return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
	end

	-- xmlEscape + line breaks kept: a raw "\n" inside an XML attribute is read back as a space,
	-- so multi-line labels built into the XML need it written as &#10;
	local function xmlAttrText(s)
		return (xmlEscape(s):gsub("\n", "&#10;"))
	end

	-- The HUD Set Template button's label (the current template's name, or "No Template")
	local function hudTemplateLabel()
		return templateJSON and shortName(stripBBCode(templateCache.name), 20, 2) or "No Template"
	end

	-- ── History slot look (#93 #31 #95 #79) ──
	-- Images sit a little inside the slot so the slot's colour (e.g. the "selected" blue) shows
	-- as a frame around them. Slot size − image size = frame on both sides.
	-- (One table, not separate locals: this file is near Lua's 200-locals-per-chunk limit.)
	local HIST_LOOK = {
		hudImg  = 46,   -- HUD slot is 54  → 4px frame each side (was 50 → 2px)
		ouiImg  = 92,   -- OUI slot is 110 → 9px frame each side (was 100 → 5px)
		-- Name shown on slots with no image: small text, more characters per line, shrinks to fit
		hudFont = 9,    -- was 14 (about 40% smaller)
		ouiFont = 12,   -- was 20
		-- Name tab on slots WITH a picture (#98): a small rounded, solid tab right UNDER the picture,
		-- using the frame below it plus a little of the gap under the slot (never over the art).
		-- Its top edge meets the picture's bottom edge.
		hudStripH = 8,  hudStripFont = 7,  hudStripChars = 11, hudStripDrop = 1,   -- HUD: 1px under the picture, then 8 tall (frame 4 + 5px row gap), bold
		ouiStripH = 16, ouiStripFont = 12, ouiStripChars = 12,   -- OUI: frame 9 + 7 of the (wider) row gap
		-- OUI history rows: gap between the two rows (was 2), widened so the tabs have room.
		-- The grid, edit overlay and ‹ › arrows grow by the extra; the ⚙ button below moves down by it.
		ouiRowGap = 14,
		-- Token History panel: Edit History is double height (two rows + the gap) until edit mode
		-- splits it into "Stop Editing" + "Clear All History" (one row each)
		editH = { hudShort = 28, hudTall = 28, ouiShort = 44, ouiTall = 44 },   -- one row both ways now (user: tall-to-short felt odd, and a fast double/triple click could land on Clear)
		stripColor = "#1A1D2CFF",   -- fully solid navy (see-through was hard to read)
	}
	-- One-line name for the strip ("" when the slot has no picture, so the strip hides)
	function HIST_LOOK.stripName(entry, chars)
		if not (entry and entry.imageURL and entry.imageURL ~= "") then return "" end
		return shortName(stripBBCode(entry.name or ""), chars, 1)
	end
	-- The tab's XML (built hidden/empty when there's no picture; refreshHistorySlots fills it).
	-- A non-clickable Button rather than a Panel, purely for TTS's rounded corners (see roundedPanelBg).
	-- inset = the frame width below the picture; the tab's top sits there, so its bottom pokes out under the slot.
	-- bold: HUD yes (reads better that small), OUI no. drop: px of gap between the picture and the tab.
	function HIST_LOOK.stripXml(id, entry, w, h, font, chars, inset, bold, drop)
		local name = HIST_LOOK.stripName(entry, chars)
		local c = HIST_LOOK.stripColor
		return '      <Button id="' .. id .. '_name" rectAlignment="LowerCenter" offsetXY="0 ' .. (inset - h - (drop or 0)) .. '"'
			.. ' width="' .. w .. '" height="' .. h .. '" colors="' .. c .. '|' .. c .. '|' .. c .. '|' .. c .. '"'
			.. ' roundEdges="true" raycastTarget="false" active="' .. (name ~= "" and "True" or "False") .. '">'
			.. '<Text id="' .. id .. '_nameTxt" text="' .. xmlAttrText(name) .. '" fontSize="' .. font .. '" fontStyle="' .. (bold and "Bold" or "Normal") .. '"'
			.. ' color="#FFFFFF" width="' .. w .. '" height="' .. h .. '" alignment="MiddleCenter" verticalOverflow="Overflow" raycastTarget="false" />'
			.. '</Button>'
	end
	-- ── HUD dynamic panel measurements (#96) ──
	-- Shared by buildHUDXml and refreshDynamicPanelSlots (Remove All follows the token list).
	local HUD_DYN = {
		pad   = 8,
		bw    = 40,    -- modifier button size (square)
		gap   = 4,
		sh    = 24,    -- token name row height
		sw    = 200,   -- token name button width
		sgap  = 4,     -- gap between token rows
		remH  = 20,    -- Remove All bar height (short and wide, under the names)
	}
	HUD_DYN.rw = HUD_DYN.sh                     -- ✕ buttons: square, same height as a name row
	HUD_DYN.gridW = 4 * HUD_DYN.bw + 3 * HUD_DYN.gap                        -- modifier grid width (172)
	HUD_DYN.slotX = HUD_DYN.pad + 4 * (HUD_DYN.bw + HUD_DYN.gap) + HUD_DYN.gap -- left edge of the token list
	HUD_DYN.listW = HUD_DYN.sw + HUD_DYN.gap + HUD_DYN.rw                  -- names + ✕ (Remove All spans this)
	HUD_DYN.panelH = HUD_DYN.pad + 3 * (HUD_DYN.bw + HUD_DYN.gap) + HUD_DYN.gap * 2 + (HUD_DYN.bw + HUD_DYN.gap) + HUD_DYN.pad
	-- Remove All's offset from the panel top, sitting under the last of `count` token rows
	function HUD_DYN.removeAllY(count)
		return -(HUD_DYN.pad + count * (HUD_DYN.sh + HUD_DYN.sgap))
	end

	local function hudHistLabel(entry)
		return entry and shortName(stripBBCode(entry.name), 8, 3) or "·"
	end
	local function ouiHistLabel(entry)
		return entry and shortName(stripBBCode(entry.name), 9, 3) or "·"
	end

	-- Shows/hides the "Large / Very large object" banner on BOTH the OUI and the HUD to
	-- match the current template (colour + text too). Every path that changes the
	-- template calls this, so the two banners can't get out of step.
	local function refreshSizeWarning()
		local sc = templateJSON and sizeClass(templateCache.byteSize)
		-- HUD banner stays hidden while the HUD itself is minimised or switched off
		local hudShow = sc and hudVisible and not hudOff
		self.UI.setAttribute("sizeWarningPanel",  "active", sc and "True" or "False")
		UI.setAttribute("TokenApplier_hud_sizeWarning",     "active", hudShow and "True" or "False")
		if sc then
			local massive = (sc == "massive")
			self.UI.setAttribute("sizeWarningPanel",  "color", op(massive and "#5A1A00F2" or "#3A3A0AF2"))
			self.UI.setAttribute("sizeWarningText",   "text",  massive and "⚠ Very large object — expect some lag" or "⚠ Large object")
			-- HUD banner is a Button (for rounded corners), so it takes "colors" (all 4 states the same)
			local hc = massive and "#5A1A00FF" or "#3A3A0AFF"
			UI.setAttribute("TokenApplier_hud_sizeWarning",     "colors", hc .. "|" .. hc .. "|" .. hc .. "|" .. hc)
			UI.setAttribute("TokenApplier_hud_sizeWarningText", "text",  massive and "⚠ Very large" or "⚠ Large object")
		end
	end

-- ──────────────────────────────────────────────────────────────
--  TOKEN HISTORY (data layer)
-- ──────────────────────────────────────────────────────────────

	-- ── Paging helpers ──
	-- The 8 slots show one "page" of the history list. EVERY slot → entry lookup goes
	-- through histIndex, so slot 3 on page 1 means tokenHistory[11].
	local function histIndex(slot)
		return historyPage * HISTORY_SLOTS + slot
	end

	local function historyPageCount()
		return math.max(1, math.ceil(#tokenHistory / HISTORY_SLOTS))
	end

	-- Page (0-based) holding the active template, or 0 if none
	local function pageOfActive()
		for i, entry in ipairs(tokenHistory) do
			if templateJSON and entry.json == templateJSON then
				return math.floor((i - 1) / HISTORY_SLOTS)
			end
		end
		return 0
	end

	local function addToHistory(json, scale, name, imageURL)
	    for i, entry in ipairs(tokenHistory) do
	        if entry.name == name then
	            table.remove(tokenHistory, i)
	            break
	        end
	    end
	    local newEntry = {
	        json     = json,
	        scale    = scale,
	        name     = name,
	        imageURL = imageURL or "",
	    }
	    prepareHistoryEntry(newEntry)
	    table.insert(tokenHistory, 1, newEntry)
	    while #tokenHistory > HISTORY_MAX do
	        table.remove(tokenHistory)
	    end
	    historyPage = 0       -- new entries go to the front, so jump back to the first page to show it
	    checkImageFormats()   -- test the new entry's image in the background (once per image)
	end

	-- slot = 1..8 on the current page
	local function activateHistoryEntry(slot)
		local entry = tokenHistory[histIndex(slot)]
		if not entry then return end
		templateJSON  = entry.json
		templateScale = entry.scale
		refreshTemplateCache()
		saveState()
		refreshTemplateButton()
		spawnPreview()
		-- Update history slot highlights
		refreshHistorySlots()
		refreshPreviewIndicator()
		refreshSizeWarning()
	end

	-- ── Rename a history entry (#103): right-click a slot ──
	-- A rename bar (HUD + object) opens over Add Token, filled with the current name: [name][Save][✕].
	-- Save, Enter or clicking away keeps the new name; ✕ or right-clicking the same slot again cancels.
	-- (Esc can't cancel: TTS uses it for its own menu.) The new name also goes into the stored template,
	-- so tokens added from that slot afterwards carry it (tokens already placed keep theirs).
	--
	-- TTS QUIRK: pressing a button ends the text box's editing BEFORE that button's click arrives, so
	-- "finished editing" can't save straight away or ✕ would be too late. It waits RENAME.delay seconds;
	-- ✕ / right-click / Save in that time take over.
	local RENAME = {
		index   = nil,   -- tokenHistory index being renamed, or nil when the bar is closed
		text    = "",    -- what's in the box right now (onValueChanged)
		pending = nil,   -- the waiting save from "finished editing", if any
		delay   = 0.5,
	}

	local function closeRename()
		RENAME.index, RENAME.pending = nil, nil
		self.UI.hide("renamePanel")
		UI.hide("TokenApplier_hud_renamePanel")
	end

	local function openRename(slot)
		local entry = tokenHistory[histIndex(slot)]
		if not entry or historyEditMode then return end
		-- Right-clicking the slot that's already being renamed closes the bar (cancel)
		if RENAME.index == histIndex(slot) then closeRename() return end
		RENAME.index, RENAME.pending = histIndex(slot), nil
		local name = stripBBCode(entry.name or "")
		RENAME.text = name
		self.UI.setAttribute("renameInput", "text", name)
		UI.setAttribute("TokenApplier_hud_renameInput", "text", name)
		self.UI.show("renamePanel")
		UI.show("TokenApplier_hud_renamePanel")
	end

	local function renameHistoryEntry(index, newName)
		local entry = tokenHistory[index]
		if not entry then return end
		local ok, data = pcall(JSON.decode, entry.json)
		if ok and type(data) == "table" then
			data.Nickname = newName
			local newJson = JSON.encode(data)
			if templateJSON == entry.json then templateJSON = newJson end   -- keep it the active template
			entry.json = newJson
		end
		entry.name = newName
		prepareHistoryEntry(entry)
		refreshTemplateCache()
		saveState()
		refreshTemplateButton()
		refreshHistorySlots()
		refreshPreviewIndicator()
	end

	-- ── Move history (#104): Move History, click a slot (white ring), click another: they swap ──
	-- Picking works across pages (picked is the tokenHistory index). Picking an empty slot sends the
	-- picked entry to the end, since history can't have gaps. Move and Delete never run together.
	-- start/stop/click are filled in after setHistoryEditMode (they use it).
	local MOVE = {
		on     = false,
		picked = nil,        -- tokenHistory index of the picked entry, or nil
		ring   = "#FFFFFF",  -- frame around the picked slot
		area   = "#FDD835",  -- frame around the whole history grid while Move is on ("act here")
	}

	-- The yellow "act here" frame around the history grid: hollow, so nothing between the slots changes.
	-- A see-through Panel with 4 strips along its edges, so the corners are square: a hollow ROUNDED frame
	-- needs a ring image (images pass). Tried and dropped: an outline (a Button tints its own outline) and
	-- a filled rounded shape behind the grid (filled the gaps between slots). attrs = id / position / active.
	function MOVE.areaXml(attrs, w, h, t)
		local function bar(align, bw, bh)
			return '<Panel rectAlignment="' .. align .. '" width="' .. bw .. '" height="' .. bh .. '" color="' .. MOVE.area .. '" raycastTarget="false" />'
		end
		return '<Panel ' .. attrs .. ' width="' .. w .. '" height="' .. h .. '" color="#00000000" raycastTarget="false">'
			.. bar("UpperCenter", w, t) .. bar("LowerCenter", w, t) .. bar("MiddleLeft", t, h) .. bar("MiddleRight", t, h)
			.. '</Panel>'
	end

	-- A history slot was clicked: in Move mode it picks/swaps; otherwise right-click (value "-2")
	-- renames and any other click picks the template
	local function historyClick(slot, value)
		if MOVE.on then MOVE.click(slot) return end
		if tostring(value) == "-2" then openRename(slot) else activateHistoryEntry(slot) end
	end

	-- Saves what's in the box (empty or unchanged = nothing to save) and closes the bar
	local function applyRename()
		local index = RENAME.index
		if index and tokenHistory[index] then
			local newName = tostring(RENAME.text or ""):gsub("^%s+", ""):gsub("%s+$", "")
			if newName ~= "" and newName ~= stripBBCode(tokenHistory[index].name or "") then
				renameHistoryEntry(index, newName)
			end
		end
		closeRename()
	end

	function btn_renameTyped(_, value, _)
		RENAME.text = value or ""
	end

	-- Box finished editing (Enter or clicking away): save after RENAME.delay unless ✕/right-click/Save step in
	function btn_renameHistory(_, value, _)
		if not RENAME.index then return end
		RENAME.text = value or RENAME.text
		local ticket = {}
		RENAME.pending = ticket
		Wait.time(function()
			if RENAME.pending == ticket then applyRename() end
		end, RENAME.delay)
	end

	function btn_renameSave(_, _)
		RENAME.pending = nil
		applyRename()
	end

	function btn_renameCancel(_, _)
		closeRename()
	end
-- ──────────────────────────────────────────────────────────────
--  HISTORY EDIT OVERLAY
-- ──────────────────────────────────────────────────────────────

	-- Turns Edit History mode on/off and syncs everything that depends on it:
	-- the delete overlays, the Edit History button, and the edit-only Clear History button
	local function setHistoryEditMode(on)
		historyEditMode = on
		if on then
			self.UI.show("deleteOverlayPanel")
			UI.show("TokenApplier_hud_deleteOverlayPanel")
		else
			self.UI.hide("deleteOverlayPanel")
			UI.hide("TokenApplier_hud_deleteOverlayPanel")
		end
		local style = on and EDIT_ON_STYLE or EDIT_OFF_STYLE
		-- Edit History is double height normally; in edit mode it drops to one row and Clear History
		-- takes the other half (the layout gives the space to whichever buttons are showing)
		if on and MOVE.on then MOVE.stop() end   -- Delete and Move never run together
		setButtonLook(self.UI, "editHistoryBtn", on and HUD_EDIT_ON_LABEL or HUD_EDIT_OFF_LABEL, style)
		setPressedExtras(self.UI, "editHistoryBtn", on, 2)   -- "Stop Editing" is pressed in
		self.UI.setAttribute("editHistoryBtn", "preferredHeight", on and HIST_LOOK.editH.ouiShort or HIST_LOOK.editH.ouiTall)
		self.UI.setAttribute("clearHistoryBtn", "active", on and "True" or "False")
		-- HUD versions
		setHudButtonLook("TokenApplier_hud_editHistoryBtn", on and HUD_EDIT_ON_LABEL or HUD_EDIT_OFF_LABEL, style)
		setPressedExtras(UI, "TokenApplier_hud_editHistoryBtn", on, 1)
		UI.setAttribute("TokenApplier_hud_editHistoryBtn", "preferredHeight", on and HIST_LOOK.editH.hudShort or HIST_LOOK.editH.hudTall)
		UI.setAttribute("TokenApplier_hud_clearHistoryBtn", "active", on and "True" or "False")
		-- Row 3: Move History steps aside for Clear All History in delete mode
		if on then self.UI.hide("moveHistoryBtn") ; UI.hide("TokenApplier_hud_moveHistoryBtn")
		else       self.UI.show("moveHistoryBtn") ; UI.show("TokenApplier_hud_moveHistoryBtn") end
	end

	-- HistoryEdit button
	function btn_toggleHistoryEdit(_, _)
		setHistoryEditMode(not historyEditMode)
	end

	-- Move History button look on both UIs: pressed while Move mode is on
	local function setMoveButtonLook(on)
		local style = on and "pressed" or "settingsItem"
		setButtonLook(self.UI, "moveHistoryBtn", MOVE_LABEL[on], style)
		setPressedExtras(self.UI, "moveHistoryBtn", on, 2)
		setHudButtonLook("TokenApplier_hud_moveHistoryBtn", MOVE_LABEL[on], style)
		setPressedExtras(UI, "TokenApplier_hud_moveHistoryBtn", on, 1)
	end

	function MOVE.start()
		if historyEditMode then setHistoryEditMode(false) end   -- Delete and Move never run together
		closeRename()                                             -- its slot index could shift under it
		MOVE.on, MOVE.picked = true, nil
		setMoveButtonLook(true)
		self.UI.show("moveFrame") ; UI.show("TokenApplier_hud_moveFrame")   -- yellow "act here" frame
		refreshHistorySlots()
	end

	function MOVE.stop()
		MOVE.on, MOVE.picked = false, nil
		setMoveButtonLook(false)
		self.UI.hide("moveFrame") ; UI.hide("TokenApplier_hud_moveFrame")
		refreshHistorySlots()   -- clears the picked frame
	end

	function MOVE.click(slot)
		local index = histIndex(slot)
		if not MOVE.picked then
			if tokenHistory[index] then MOVE.picked = index end   -- nothing to pick in an empty slot
		elseif MOVE.picked == index then
			MOVE.picked = nil                                    -- same slot again: un-pick
		else
			local entry = tokenHistory[MOVE.picked]
			if tokenHistory[index] then
				tokenHistory[MOVE.picked], tokenHistory[index] = tokenHistory[index], entry   -- swap
			else
				table.remove(tokenHistory, MOVE.picked)          -- empty slot: send it to the end
				table.insert(tokenHistory, entry)
			end
			MOVE.picked = nil
			saveState()
		end
		refreshHistorySlots()
	end

	function btn_toggleHistoryMove(_, _)
		if MOVE.on then MOVE.stop() else MOVE.start() end
	end
	
	
	
	-- slot = 1..8 on the current page
	local function deleteHistoryEntry(slot)
		local index = histIndex(slot)
		if not tokenHistory[index] then return end
		local removing = tokenHistory[index]
		table.remove(tokenHistory, index)
		-- If that emptied the last page, step back a page
		historyPage = math.min(historyPage, historyPageCount() - 1)
		if templateJSON == removing.json then
			templateJSON  = nil
			templateScale = nil
			refreshTemplateCache()
			if previewGUID then
				local obj = getObjectFromGUID(previewGUID)
				if obj then obj.destroy() end
				previewGUID = nil
			end
		end
		saveState()
		refreshTemplateButton()
		refreshPreviewIndicator()
		
		refreshHistorySlots()
		if #tokenHistory == 0 then
			setHistoryEditMode(false)
		end
	end

-- ──────────────────────────────────────────────────────────────
--  HISTORY BUTTON HANDLERS
-- ──────────────────────────────────────────────────────────────

	function btn_history_1(_, value) historyClick(1, value) end
	function btn_history_2(_, value) historyClick(2, value) end
	function btn_history_3(_, value) historyClick(3, value) end
	function btn_history_4(_, value) historyClick(4, value) end
	function btn_history_5(_, value) historyClick(5, value) end
	function btn_history_6(_, value) historyClick(6, value) end
	function btn_history_7(_, value) historyClick(7, value) end
	function btn_history_8(_, value) historyClick(8, value) end

	-- OUI DeleteHistory HANDLERS
	function btn_deleteHistory_1(_, _) deleteHistoryEntry(1) end
	function btn_deleteHistory_2(_, _) deleteHistoryEntry(2) end
	function btn_deleteHistory_3(_, _) deleteHistoryEntry(3) end
	function btn_deleteHistory_4(_, _) deleteHistoryEntry(4) end
	function btn_deleteHistory_5(_, _) deleteHistoryEntry(5) end
	function btn_deleteHistory_6(_, _) deleteHistoryEntry(6) end
	function btn_deleteHistory_7(_, _) deleteHistoryEntry(7) end
	function btn_deleteHistory_8(_, _) deleteHistoryEntry(8) end

	-- HUD DeleteHistory HANDLERS
	function hud_deleteHistory_1(player, _, _) deleteHistoryEntry(1) end
	function hud_deleteHistory_2(player, _, _) deleteHistoryEntry(2) end
	function hud_deleteHistory_3(player, _, _) deleteHistoryEntry(3) end
	function hud_deleteHistory_4(player, _, _) deleteHistoryEntry(4) end
	function hud_deleteHistory_5(player, _, _) deleteHistoryEntry(5) end
	function hud_deleteHistory_6(player, _, _) deleteHistoryEntry(6) end
	function hud_deleteHistory_7(player, _, _) deleteHistoryEntry(7) end
	function hud_deleteHistory_8(player, _, _) deleteHistoryEntry(8) end

-- ──────────────────────────────────────────────────────────────
--  HISTORY PAGING (arrows + dots, shared by OUI and HUD)
-- ──────────────────────────────────────────────────────────────

	-- Goes to page p (0-based). Keeps the selection on screen: the slot in the SAME
	-- position on the new page is selected, or its first slot if that one's empty.
	-- If nothing is selected, nothing gets selected.
	local function setHistoryPage(p)
		p = math.max(0, math.min(p, historyPageCount() - 1))
		if p == historyPage then return end
		-- Which slot (1-8) holds the active template on the page we're leaving (nil if none)
		local activeSlot = nil
		for slot = 1, HISTORY_SLOTS do
			local e = tokenHistory[histIndex(slot)]
			if templateJSON and e and e.json == templateJSON then activeSlot = slot break end
		end
		historyPage = p
		if templateJSON then
			local slot = (activeSlot and tokenHistory[histIndex(activeSlot)]) and activeSlot or 1
			if tokenHistory[histIndex(slot)] then
				activateHistoryEntry(slot)   -- also refreshes the slots, arrows and dots
				return
			end
		end
		refreshHistorySlots()
	end

	function btn_historyPrev(_, _)   setHistoryPage(historyPage - 1) end   -- towards newer tokens
	function btn_historyNext(_, _)   setHistoryPage(historyPage + 1) end   -- towards older tokens
	function btn_historyPage_1(_, _) setHistoryPage(0) end
	function btn_historyPage_2(_, _) setHistoryPage(1) end
	function btn_historyPage_3(_, _) setHistoryPage(2) end
	function btn_historyPage_4(_, _) setHistoryPage(3) end

-- ──────────────────────────────────────────────────────────────
--  HUD HISTORY HANDLERS
-- ──────────────────────────────────────────────────────────────

	function hud_history_1(player, value, _) historyClick(1, value) end
	function hud_history_2(player, value, _) historyClick(2, value) end
	function hud_history_3(player, value, _) historyClick(3, value) end
	function hud_history_4(player, value, _) historyClick(4, value) end
	function hud_history_5(player, value, _) historyClick(5, value) end
	function hud_history_6(player, value, _) historyClick(6, value) end
	function hud_history_7(player, value, _) historyClick(7, value) end
	function hud_history_8(player, value, _) historyClick(8, value) end

-- ──────────────────────────────────────────────────────────────
--  HUD ACTION HANDLERS
-- ──────────────────────────────────────────────────────────────

	function hud_addToken(player, _, _)
	    btn_toggleToken(nil, player.color)
	end

	-- "Are you sure?" state: set by the first click, cleared by the second click or after REMOVE_CONFIRM_TIME
	local removeConfirm = nil   -- { color = playerColor, targetGUID = model }

	-- Switches the Remove All buttons (HUD + OUI) between their normal (yellow) and armed "Sure?" (red) look
	local function setRemoveAllLook(text, styleName)
		setHudButtonLook("TokenApplier_hud_dynRemoveAll", text, styleName)
		setButtonLook(self.UI, "dynRemoveAll", text, styleName)
	end

	local function resetRemoveConfirm()
		removeConfirm = nil
		setRemoveAllLook(REMOVE_ALL_LABEL, REMOVE_ALL_STYLE)
	end

	function hud_removeTokens(player, _, _)
	    local playerColor = player.color
	    local sel = Player[playerColor].getSelectedObjects()
	    if #sel == 0 then
	        printToColor("Select a model first.", playerColor, { 1, 1, 1 })
	        return
	    end
	    local targetGUID = sel[1].getGUID()
	    local tokens = findTokensForTarget(targetGUID)
	    if #tokens == 0 then
	        printToColor("No tokens on selected model.", playerColor, { 1, 1, 0 })
	        return
	    end

	    -- First click (or a different player/model): arm the button and wait for a second click
	    if not (removeConfirm and removeConfirm.color == playerColor and removeConfirm.targetGUID == targetGUID) then
	        local thisConfirm = { color = playerColor, targetGUID = targetGUID }
	        removeConfirm = thisConfirm
	        setRemoveAllLook("Sure? Click again to remove " .. #tokens .. " token(s)", REMOVE_ARMED_STYLE)
	        Wait.time(function()
	            if removeConfirm == thisConfirm then resetRemoveConfirm() end   -- expired without a second click
	        end, REMOVE_CONFIRM_TIME)
	        return
	    end

	    -- Second click: confirmed
	    resetRemoveConfirm()
	    for _, tGUID in ipairs(tokens) do
	        local token = getObjectFromGUID(tGUID)
	        if token then token.destroy() end
	        hoverEntries[tGUID] = nil
	    end
	    saveState()
		invalidateTargetMap()
	    hideDynamicPanel()
	    local targetObj  = getObjectFromGUID(targetGUID)
	    local targetName = targetObj and targetObj.getName() or "Unknown"
	    printToColor("Removed all tokens from " .. targetName, playerColor, { 1, 0.5, 0.5 })
	end

	-- Minimise / restore. Only the outer root is hidden: everything inside it keeps its own
	-- state, so settings (kept in sync with the OUI), edit mode and the dynamic panel come
	-- back exactly as they were. Hiding the children one by one cut the Token History panel's
	-- Shrink animation short, which left it half-alive and popping back on restore.
	-- Shows/hides every HUD piece that belongs to settings (and edit mode) to match the saved
	-- state. Only call it while the HUD is on screen: a hide inside the hidden (minimised) HUD
	-- can't play the Token History panel's Shrink animation, so that panel would never close.
	-- That's why btn_toggleSettings skips the HUD while minimised and restore calls this instead.
	-- instant = true: hide WITHOUT the Shrink animation (setAttribute "active"). Used on restore while
	-- the HUD is still hidden, so a panel left "open" is gone before anyone sees it shrink away.
	local function syncHudSettings(instant)
		local ids = { "TokenApplier_hud_settingsPanel", "TokenApplier_hud_off", "TokenApplier_hud_placeBtn",
			"TokenApplier_hud_dragToggleBtn", "TokenApplier_hud_opacityBtn", "TokenApplier_hud_templateVis",
			"TokenApplier_hud_debugToggle", "TokenApplier_hud_customiseToggle" }
		-- Debug buttons: only while settings AND the Debug toggle are on (#99)
		local debugIds = { "TokenApplier_hud_restore_tokens", "TokenApplier_hud_find_tokens", "TokenApplier_hud_debug_ids" }
		local function setShown(id, on)
			if on then
				-- Skip what's already showing: show() replays the Grow animation even on a visible panel
				-- (restoring the HUD with settings open made Token History animate twice)
				local a = tostring(UI.getAttribute(id, "active") or "")
				if a:lower() ~= "true" then UI.show(id) end
			elseif instant then UI.setAttribute(id, "active", "False")
			else UI.hide(id) end
		end
		for _, id in ipairs(ids) do setShown(id, settingsOpen) end
		for _, id in ipairs(debugIds) do setShown(id, settingsOpen and debugOpen) end
		setShown("TokenApplier_hud_customisePanel", settingsOpen and CUSTOM.open)
		-- Settings backdrop (#100) only exists when Backgrounds is on
		if CUSTOM.bgLevels[CUSTOM.bg].color then setShown("TokenApplier_hud_settingsBg", settingsOpen) end
		setShown("TokenApplier_hud_deleteOverlayPanel", historyEditMode)
		UI.setAttribute("TokenApplier_hud_clearHistoryBtn", "active", historyEditMode and "True" or "False")
		UI.setAttribute("TokenApplier_hud_settings", "colors",
			BTN_STYLE[settingsOpen and HUD_SETTINGS_OPEN_STYLE or HUD_SETTINGS_CLOSED_STYLE].colors)
		setPressedExtras(UI, "TokenApplier_hud_settings", settingsOpen, 1)   -- pressed in while settings are open
	end

	function hud_toggleVisible(player, _, _)
		hudVisible = not hudVisible
		if hudVisible then
			-- Settings may have changed on the object while the HUD was minimised. Closed: switch the
			-- pieces off instantly BEFORE the HUD reappears (no flicker of the panel shrinking).
			-- Open: show them AFTER, because show animations can't play inside the hidden HUD.
			if not settingsOpen then syncHudSettings(true) end
			UI.show("TokenApplier_hud_root")
			UI.hide("TokenApplier_hud_restore")
			if settingsOpen then syncHudSettings() end
			refreshSizeWarning()   -- bring the size banner back if the template needs it
		else
			UI.hide("TokenApplier_hud_root")
			UI.show("TokenApplier_hud_restore")
		end
	end

	-- HUD: ON / OFF (1.4). OFF = Token Applier stops touching the shared screen UI entirely, for
	-- tables whose own HUD clashes with it; the object's own UI and right-click menu keep working.
	-- Saved with the object, so a table can ship its TA with the HUD off.
	-- Turning it back on is only possible from the OUI (the HUD is gone).
	function btn_toggleHUD(_, _)
		hudOff = not hudOff
		if not hudOff then hudVisible = true end   -- come back open, not minimised
		saveState()
		rebuildXML()   -- redraw the OUI button
		rebuildHUD()   -- OFF: one last write that takes our HUD out; ON: puts it back
	end

	function hud_toggleSettings(player, _, _)
		btn_toggleSettings(nil, nil)
	end
	
	
	local function refreshDefaultScaleLabel()
		local label = string.format("%.1f", defaultScaleOffset)
		self.UI.setAttribute("defaultScaleLabel", "text", "Default Scale: " .. label)
		UI.setAttribute("TokenApplier_hud_defaultScaleLabel", "text", "Default Scale: " .. label)
	end

	function btn_defaultScaleUp(_, _)
		defaultScaleOffset = defaultScaleOffset + SCALE_STEP
		saveState()
		refreshDefaultScaleLabel()
	end

	function btn_defaultScaleDown(_, _)
		defaultScaleOffset = defaultScaleOffset - SCALE_STEP
		saveState()
		refreshDefaultScaleLabel()
	end


	function btn_toggleHudDraggable(_, _)
		hudDraggable = not hudDraggable
		if not hudDraggable then
			local pos = UI.getAttribute("TokenApplier_hud_root", "offsetXY")
			print("[DragDebug] getAttribute returned: " .. tostring(pos))
			print("[DragDebug] hudRootOffsetXY is: " .. tostring(hudRootOffsetXY))
			if pos and pos ~= "" then
				hudRootOffsetXY = pos
			end
			saveState()
		end
		UI.setAttribute("TokenApplier_hud_root", "allowDragging", hudDraggable and "true" or "false")
		setHudButtonLook("TokenApplier_hud_dragToggleBtn", "Drag", hudDraggable and "toggleOn" or "toggleOff")
		rebuildHUD()   -- see btn_toggleHUD: rebuild so the button's text colour is correct
	end

	function btn_toggleHudPlacement(_, _)
		hudPlacementMode = not hudPlacementMode
		if hudPlacementMode then
			UI.show("TokenApplier_hud_placementOverlay")
		else
			UI.hide("TokenApplier_hud_placementOverlay")
		end
		setHudButtonLook("TokenApplier_hud_placeBtn", hudPlacementMode and "Cancel" or "Place", hudPlacementMode and "toggleOn" or "settingsItem")
		rebuildHUD()   -- see btn_toggleHUD
	end

	function btn_selectHudPosition(player, _, id)
		local playerColor = (type(player) == "userdata" and player.color) or player
		for _, pos in ipairs(HUD_POSITIONS) do
			if pos.id == id then
				hudRootOffsetXY = pos.hudXY
				break
			end
		end
		hudPlacementMode = false
		if settingsOpen then btn_toggleSettings() end  -- close settings (OUI too) so it doesn't linger

		-- Hide everything before the rebuild fires
		UI.hide("TokenApplier_hud_root")
		UI.hide("TokenApplier_hud_core")
		UI.hide("TokenApplier_hud_minimize")
		UI.hide("TokenApplier_hud_settings")
		UI.hide("TokenApplier_hud_setTemplate")
		UI.hide("TokenApplier_hud_settingsPanel")
		UI.hide("TokenApplier_hud_off")
		UI.hide("TokenApplier_hud_restore_tokens")
		UI.hide("TokenApplier_hud_find_tokens")
		UI.hide("TokenApplier_hud_debug_ids")
		UI.hide("TokenApplier_hud_placeBtn")
		UI.hide("TokenApplier_hud_dragToggleBtn")
		UI.hide("TokenApplier_hud_opacityBtn")
		UI.hide("TokenApplier_hud_templateVis")
		UI.hide("TokenApplier_hud_placementOverlay")
		UI.hide("TokenApplier_hud_dynPanel")
		UI.hide("TokenApplier_hud_sizeWarning")
		UI.hide("TokenApplier_hud_deleteOverlayPanel")
		UI.hide("TokenApplier_hud_restore")

		saveState()
		rebuildHUD()
	end
	
	function hud_pos_left_bottom(player, _, _)     btn_selectHudPosition(player, nil, "left_bottom")     end
	function hud_pos_bottom_left(player, _, _)  btn_selectHudPosition(player, nil, "bottom_left")  end
	function hud_pos_bottom_center(player, _, _)   btn_selectHudPosition(player, nil, "bottom_center")   end
	function hud_pos_bottom_cenright(player, _, _) btn_selectHudPosition(player, nil, "bottom_cenright") end
	function hud_pos_bottom_cenleft(player, _, _)    btn_selectHudPosition(player, nil, "bottom_cenleft")    end
	function hud_pos_top_left(player, _, _)        btn_selectHudPosition(player, nil, "top_left")        end
	function hud_pos_top_center(player, _, _)      btn_selectHudPosition(player, nil, "top_center")      end
	function hud_pos_top_right(player, _, _)       btn_selectHudPosition(player, nil, "top_right")       end
	
-- ──────────────────────────────────────────────────────────────
--  SETTINGS BUTTONs
-- ──────────────────────────────────────────────────────────────

	function btn_toggleSettings(_, _)
		settingsOpen = not settingsOpen
		if not settingsOpen then
			setHistoryEditMode(false)   -- closing settings also leaves edit mode (hides overlays + Clear History)
			if MOVE.on then MOVE.stop() end   -- ... and Move mode
		end
		if settingsOpen then
			self.UI.show("settingsPanel")
			self.UI.show("clearHistoryPanel")
			self.UI.show("templateSettingsPanel")
			self.UI.show("debugToggleBtn")
			self.UI.show("customiseToggleBtn")
			if debugOpen then self.UI.show("debugSettingsPanel") end   -- debug buttons only with the Debug toggle on (#99)
		else
			self.UI.hide("settingsPanel")
			self.UI.hide("clearHistoryPanel")
			self.UI.hide("templateSettingsPanel")
			self.UI.hide("debugToggleBtn")
			self.UI.hide("customiseToggleBtn")
			if debugOpen then self.UI.hide("debugSettingsPanel") end
			if CUSTOM.open then   -- closing settings closes the customise panel too
				CUSTOM.open = false
				self.UI.hide("customisePanel")
				-- and the HUD settings backdrop drops back to its normal height (it was left tall)
				if CUSTOM.bgOn() then UI.setAttribute("TokenApplier_hud_settingsBg", "height", CUSTOM.settingsBgH(false)) end
				setButtonLook(self.UI, "customiseToggleBtn", nil, "settingsItem")   -- pop the button back out
				setPressedExtras(self.UI, "customiseToggleBtn", false, 2)
				setHudButtonLook("TokenApplier_hud_customiseToggle", nil, "settingsItem")
				setPressedExtras(UI, "TokenApplier_hud_customiseToggle", false, 1)
			end
		end
		-- HUD side (also recolours the HUD ⚙). While minimised, restore catches it up instead.
		if hudVisible then syncHudSettings() end
		-- Update settings button highlight on the OUI
		local sStyle = BTN_STYLE[settingsOpen and "pressed" or "settings"]
		self.UI.setAttribute("settingsBtn", "colors",    sStyle.colors)
		self.UI.setAttribute("settingsBtn", "textColor", sStyle.textColor)
		setPressedExtras(self.UI, "settingsBtn", settingsOpen, 2)   -- pressed in while settings are open
		-- (No setAttribute "active" on panels here: it skips the Grow/Shrink animation that show()/hide() play)
	end
	
	-- Debug toggle (#99): shows/hides the debug buttons inside settings on both UIs. Saved, so it can
	-- stay on while testing. Rebuilds like the other toggles (live text-colour changes don't stick).
	-- Updates in place, no rebuild: a full rebuild of both UIs got slow as the HUD grew (felt as lag)
	function btn_toggleDebug(_, _)
		debugOpen = not debugOpen
		saveState()
		local style = debugOpen and "pressed" or "debug"
		local tip   = debugOpen and "Debug: ON. Click to hide the debug buttons" or "Debug: OFF. Click to show the debug buttons"
		-- Object: the debug panel (only while settings are open)
		if settingsOpen then
			if debugOpen then self.UI.show("debugSettingsPanel") else self.UI.hide("debugSettingsPanel") end
		end
		setButtonLook(self.UI, "debugToggleBtn", nil, style)
		setPressedExtras(self.UI, "debugToggleBtn", debugOpen, 2)
		self.UI.setAttribute("debugToggleBtn", "tooltip", tip)
		-- HUD: the debug buttons (syncHudSettings; while minimised, restore catches up), then the button look
		if hudVisible then syncHudSettings() end
		setHudButtonLook("TokenApplier_hud_debugToggle", nil, style)
		setPressedExtras(UI, "TokenApplier_hud_debugToggle", debugOpen, 1)
		UI.setAttribute("TokenApplier_hud_debugToggle", "tooltip", tip)
	end

	-- Customise panel (1.4.3): opened from settings. Rebuilds like the other toggles.
	-- Updates in place, no rebuild (like Debug above)
	function btn_toggleCustomise(_, _)
		CUSTOM.open = not CUSTOM.open
		local style = CUSTOM.open and "pressed" or "settingsItem"
		-- Object: the customise panel
		if CUSTOM.open then self.UI.show("customisePanel") else self.UI.hide("customisePanel") end
		setButtonLook(self.UI, "customiseToggleBtn", nil, style)
		setPressedExtras(self.UI, "customiseToggleBtn", CUSTOM.open, 2)
		-- HUD: the customise panel (syncHudSettings), the settings backdrop's height, the button look
		if hudVisible then syncHudSettings() end
		if CUSTOM.bgOn() then UI.setAttribute("TokenApplier_hud_settingsBg", "height", CUSTOM.settingsBgH(CUSTOM.open)) end
		setHudButtonLook("TokenApplier_hud_customiseToggle", nil, style)
		setPressedExtras(UI, "TokenApplier_hud_customiseToggle", CUSTOM.open, 1)
	end

	-- Selection colour (#102): a new colour rebuilds both UIs in it (every build reads BTN_STYLE)
	local function setSelectColor(hex)
		if not hex or hex == CUSTOM.selectColor then return end
		CUSTOM.selectColor = hex
		CUSTOM.applySelectColor()
		saveState()
		rebuildXML()
		rebuildHUD()
	end

	-- A preset swatch. The swatch ids end in _<preset number> (OUI "selColor_3", HUD "TokenApplier_hud_selColor_3").
	function btn_selectColorPreset(player, _, id)
		local p = CUSTOM.presets[tonumber(tostring(id):match("selColor_(%d+)$") or "")]
		if p then setSelectColor(p.hex) end
	end

	-- The hex box: typed colour applied when the player presses Enter or clicks away.
	-- Not a colour → tell that player and put the box back.
	function btn_selectColorHex(player, value, _)
		local hex = CUSTOM.cleanHex(value)
		if hex then setSelectColor(hex) return end
		local color = (type(player) == "userdata" and player.color) or nil
		if color then printToColor("Not a colour: \"" .. tostring(value) .. "\". Use a hex code like #15AFCC.", color, { 1, 0.6, 0.3 }) end
		rebuildXML()
		rebuildHUD()
	end

	-- Back to the shipped cyan
	function btn_selectColorReset(_, _)
		setSelectColor(CUSTOM.defaultColor)
	end

	-- Backgrounds (#100): 0% → 50% → 100% → 0%. Rebuilds both UIs (HUD backdrops + the button labels).
	function btn_cycleBackground(_, _)
		CUSTOM.bg = CUSTOM.bg % #CUSTOM.bgLevels + 1
		saveState()
		rebuildXML()
		rebuildHUD()
	end

	-- SetTemplate button toggle
	function btn_toggleSetTemplate(_, _)
		hideSetTemplate = not hideSetTemplate
		if hideSetTemplate then
			UI.hide("TokenApplier_hud_setTemplate")
		else
			UI.show("TokenApplier_hud_setTemplate")
		end
		setHudButtonLook("TokenApplier_hud_templateVis", hideSetTemplate and "O" or "I", hideSetTemplate and "toggleOff" or "toggleOn")
		rebuildHUD()   -- see btn_toggleHUD
		rebuildXML()
	end
	
	function btn_toggleDropTemplate(_, _)
		dropTemplateEnabled = not dropTemplateEnabled
		rebuildXML()
	end

	-- Opaque mode (OUI + HUD): swap every background to fully solid, or back to the shipped look.
	-- Rebuilds both UIs so everything is drawn fresh in the new colours (and the tooltips below).
	function btn_toggleOpacity(_, _)
		uiOpaque = not uiOpaque
		applyOpacity()
		saveState()
		rebuildXML()
		rebuildHUD()
	end

	-- OUI setting: spawn a 3D copy of image-less templates next to the TA
	function btn_toggleTemplatePreview(_, _)
		showTemplatePreview = not showTemplatePreview
		saveState()
		spawnPreview()   -- spawns the copy now, or removes it when switched off
		rebuildXML()
	end

-- ──────────────────────────────────────────────────────────────
--  DYNAMIC PANEL — show/hide helpers
-- ──────────────────────────────────────────────────────────────

	-- Hides the dynamic panel and resets selection state.
	-- Replaces clearAllDynamicButtons().
	function hideDynamicPanel()
		if not dynPanelVisible then return end
		self.UI.hide("dynamicPanel")
		UI.hide("TokenApplier_hud_dynPanel")
		dynPanelVisible   = false
		lastSelectedGUID  = nil
		selectedTokenGUID = nil
	end

	-- Activates the dynamic panel via .show() (not setAttribute) — .show() is the only mechanism that reliably shows this panel on its very first
	-- activation. Guarded so it's never called while already visible, which avoids retriggering the Grow animation during normal gameplay/polling.
	local function activateDynamicPanel()
		if dynPanelVisible then return end
		self.UI.show("dynamicPanel")
		UI.show("TokenApplier_hud_dynPanel")
		dynPanelVisible = true
	end

	-- Line up / Radial label on both UIs (the style never changes, see LINEUP)
	local function setLineUpLabel(isLineUp)
		self.UI.setAttribute("dynLineUpToggle_text", "text", LINEUP.oui[isLineUp])
		UI.setAttribute("TokenApplier_hud_dynLineUpToggle_text", "text", LINEUP.hud[isLineUp])
	end

	-- Shows the dynamic panel populated for the given target model.
	-- Replaces showDynamicButtons().
	function showDynamicPanel(targetGUID, tokenCount)
		if lastSelectedGUID == targetGUID then return end
		setLineUpLabel(modelLineUp[targetGUID] or false)
		-- Spread buttons, token rows and the HUD Remove All position: one shared routine, so opening
		-- the panel and changing its tokens can't lay it out differently (Remove All used to stay at
		-- its build-time spot until a token was added, because this path skipped it).
		refreshDynamicPanelSlots(targetGUID)
		activateDynamicPanel()
		lastSelectedGUID = targetGUID
	end

	-- Refreshes slot highlight states after a select/deselect.
	-- Replaces the self.editButton loop in handleSelectToken.
	-- ── Dynamic panel token rows (#97) ──
	-- Each name button: a small picture of the token on its left (INSIDE the button, so every row
	-- stays the same size), then the name, left-aligned. Rows without a picture keep the same left
	-- gap so the names line up. Only the SELECTED row's name gets a shadow (it sits on cyan).
	-- One table (not separate locals): this file is near Lua's 200-locals-per-chunk limit.
	local DYN_SLOT = {
		hudImg = 20, hudTextX = 26, hudTextW = 170, hudFont = 12,   -- HUD row: 200 × 24
		ouiImg = 52, ouiTextX = 62, ouiTextW = 232, ouiFont = 20,   -- OUI row: 300 × 60
		shadowOn = "#000000CC", shadowOff = "#00000000",           -- off = fully clear, same effect
		images = {},   -- [token GUID] = picture URL, or "" for none (looked up once per token)
	}

	-- The token's own picture, or "" when there's nothing useful to show (same rules as history:
	-- no blank placeholder, no WebP, no tinted white silhouettes)
	function DYN_SLOT.imageFor(tGUID)
		if DYN_SLOT.images[tGUID] then return DYN_SLOT.images[tGUID] end
		local obj = getObjectFromGUID(tGUID)
		if not obj then return "" end
		local ok, custom = pcall(function() return obj.getCustomObject() end)
		local img  = ok and type(custom) == "table" and custom.image or nil
		local tint = obj.getColorTint()
		local tinted = tint and (tint.r < 0.95 or tint.g < 0.95 or tint.b < 0.95)
		local url = ""
		if type(img) == "string" and img ~= "" and not img:find(BLANK_IMAGE_ID, 1, true)
			and imageCheck[img] ~= "unsupported" and not (NAME_ONLY_TYPES[obj.name] and tinted) then
			url = img
		end
		DYN_SLOT.images[tGUID] = url
		return url
	end

	-- Paints token row i on BOTH UIs: colours, name colour + shadow, and (when tGUID is given)
	-- the name and picture. The Button's own textColor is set too (TTS quirk, see setButtonLook).
	function DYN_SLOT.paint(i, tGUID, isSelected)
		local s      = BTN_STYLE[isSelected and "dynSlotSelected" or "dynSlot"]
		local shadow = isSelected and DYN_SLOT.shadowOn or DYN_SLOT.shadowOff
		local ouiId, hudId = "dynSlot_" .. i, "TokenApplier_hud_dynSlot_" .. i
		for _, pair in ipairs({ { self.UI, ouiId }, { UI, hudId } }) do
			local ui, id = pair[1], pair[2]
			ui.setAttribute(id,           "colors",    s.colors)
			ui.setAttribute(id,           "textColor", s.textColor)
			ui.setAttribute(id .. "_text", "color",    s.textColor)
			ui.setAttribute(id .. "_text", "shadow",   shadow)
		end
		if not tGUID then return end
		local name = stripBBCode(getTokenName(tGUID))
		self.UI.setAttribute(ouiId .. "_text", "text", shortName(name, 22, 2))
		UI.setAttribute(hudId .. "_text",      "text", shortName(name, 28, 1))   -- one line, much more of the name
		local url = DYN_SLOT.imageFor(tGUID)
		for _, pair in ipairs({ { self.UI, ouiId }, { UI, hudId } }) do
			local ui, id = pair[1], pair[2]
			if url ~= "" then ui.setAttribute(id .. "_img", "image", url) end
			ui.setAttribute(id .. "_img", "active", url ~= "" and "True" or "False")
		end
	end

	local function refreshSlotHighlights()
		local tokens = lastSelectedGUID and findTokensForTarget(lastSelectedGUID) or {}
		for i, tGUID in ipairs(tokens) do
			if i > MAX_TOKENS then break end
			DYN_SLOT.paint(i, nil, selectedTokenGUID == tGUID)   -- colours + shadow only
		end
	end

	-- Shows/hides the ‹ › arrows and page dots (OUI + HUD) to match the current page.
	-- Dots change their background (colors), which updates reliably in place — unlike text colour.
	local function refreshHistoryNav()
		local pages = historyPageCount()
		local function vis(ouiId, hudId, on)
			if on then self.UI.show(ouiId) ; UI.show(hudId)
			else       self.UI.hide(ouiId) ; UI.hide(hudId) end
		end
		vis("histPrev", "TokenApplier_hud_histPrev", historyPage > 0)
		vis("histNext", "TokenApplier_hud_histNext", historyPage < pages - 1)
		vis("histDots", "TokenApplier_hud_histDots", pages > 1)
		for p = 1, HISTORY_PAGES do
			vis("histDot" .. p, "TokenApplier_hud_histDot" .. p, p <= pages)
			local s = BTN_STYLE[(p - 1 == historyPage) and "historyDotOn" or "historyDotOff"]
			self.UI.setAttribute("histDot" .. p,       "colors", s.colors)
			UI.setAttribute("TokenApplier_hud_histDot" .. p,     "colors", s.colors)
		end
		-- Main HUD backdrop (#100) widens to take in the ‹ › arrows once there's a 2nd page
		if CUSTOM.bgOn() then UI.setAttribute("TokenApplier_hud_mainBg", "width", CUSTOM.mainBgW(pages)) end
	end

	--refresh history slots using setAttribute system (prevent need for rebuilds)
	refreshHistorySlots = function()
		for i = 1, HISTORY_SLOTS do
			local entry    = tokenHistory[histIndex(i)]
			local isActive = entry and (templateJSON == entry.json)
			local style    = isActive and "histSelected" or (entry and "historySlot" or "ghost")
			-- Move History (#104): the picked slot turns white. The frame around its picture IS the slot,
			-- so that's a white, rounded ring (an outline can't do it: a Button tints its own outline)
			local picked   = MOVE.on and MOVE.picked == histIndex(i)
			if picked then style = "movePicked" end
			local hasImage = entry and entry.imageURL and entry.imageURL ~= ""
			local imgURL   = hasImage and entry.imageURL or ""
			local txtLabel = ouiHistLabel(entry)
			local txtColor = picked and BTN_STYLE.movePicked.textColor or (entry and "#FFFFFF" or "#404040")
			local hudLabel = hudHistLabel(entry)
			local hudColor = picked and BTN_STYLE.movePicked.textColor or (entry and "#FFFFFF" or "#303030")
			local sc       = entry and sizeClass(entry.byteSize)

			local tooltipText = historyTooltip(entry)

			-- Size badge (OUI + HUD): shown only for large/massive templates
			self.UI.setAttribute("histBtn" .. i .. "_warn",      "active", sc and "True" or "False")
			UI.setAttribute("TokenApplier_hud_hist_" .. i .. "_warn",      "active", sc and "True" or "False")
			if sc then
				self.UI.setAttribute("histBtn" .. i .. "_warn",  "color",  SIZE_BADGE_COLOR[sc])
				UI.setAttribute("TokenApplier_hud_hist_" .. i .. "_warn",  "color",  SIZE_BADGE_COLOR[sc])
			end

			-- OUI slot
			self.UI.setAttribute("histBtn" .. i,         "colors",    BTN_STYLE[style].colors)
			self.UI.setAttribute("histBtn" .. i,         "textColor", BTN_STYLE[style].textColor)
			self.UI.setAttribute("histBtn" .. i,         "tooltip",   tooltipText)
			self.UI.setAttribute("histBtn" .. i .. "_img", "image",   imgURL)
			self.UI.setAttribute("histBtn" .. i .. "_img", "active",  hasImage and "True" or "False")
			self.UI.setAttribute("histBtn" .. i .. "_txt", "text",    txtLabel)
			self.UI.setAttribute("histBtn" .. i .. "_txt", "color",   txtColor)
			self.UI.setAttribute("histBtn" .. i .. "_txt", "active",  hasImage and "False" or "True")

			-- HUD slot
			UI.setAttribute("TokenApplier_hud_hist_" .. i,              "colors",    BTN_STYLE[style].colors)
			UI.setAttribute("TokenApplier_hud_hist_" .. i,              "textColor", BTN_STYLE[style].textColor)
			UI.setAttribute("TokenApplier_hud_hist_" .. i,              "tooltip",   tooltipText)

			UI.setAttribute("TokenApplier_hud_hist_" .. i .. "_img",    "image",     imgURL)
			UI.setAttribute("TokenApplier_hud_hist_" .. i .. "_img",    "active",    hasImage and "True" or "False")
			UI.setAttribute("TokenApplier_hud_hist_" .. i .. "_txt",    "text",      hudLabel)
			UI.setAttribute("TokenApplier_hud_hist_" .. i .. "_txt",    "color",     hudColor)
			UI.setAttribute("TokenApplier_hud_hist_" .. i .. "_txt",    "active",    hasImage and "False" or "True")

			-- Name strip on picture slots (#98), OUI + HUD
			local ouiStrip = HIST_LOOK.stripName(entry, HIST_LOOK.ouiStripChars)
			local hudStrip = HIST_LOOK.stripName(entry, HIST_LOOK.hudStripChars)
			-- show()/hide(), not setAttribute "active": a Panel built hidden can ignore its first setAttribute show
			self.UI.setAttribute("histBtn" .. i .. "_nameTxt", "text", ouiStrip)
			-- Picked slot (Move History): its name plate hides so the white ring shows all round
			if ouiStrip ~= "" and not picked then self.UI.show("histBtn" .. i .. "_name") else self.UI.hide("histBtn" .. i .. "_name") end
			UI.setAttribute("TokenApplier_hud_hist_" .. i .. "_nameTxt", "text", hudStrip)
			if hudStrip ~= "" and not picked then UI.show("TokenApplier_hud_hist_" .. i .. "_name") else UI.hide("TokenApplier_hud_hist_" .. i .. "_name") end

			-- OUI delete overlay slot
			local delEntry = tokenHistory[histIndex(i)]
			if delEntry and delEntry.imageURL and delEntry.imageURL ~= "" then
				self.UI.setAttribute("delBtn" .. i, "image", delEntry.imageURL)
			end

			-- HUD delete overlay slot  
			if delEntry and delEntry.imageURL and delEntry.imageURL ~= "" then
				UI.setAttribute("TokenApplier_hud_delBtn" .. i, "image", delEntry.imageURL)
			end
			
			-- Update overlay slot images
			self.UI.setAttribute("delBtn" .. i .. "_img",        "image",  imgURL)
			self.UI.setAttribute("delBtn" .. i .. "_img",        "active", hasImage and "True" or "False")
			UI.setAttribute("TokenApplier_hud_delBtn" .. i .. "_img",      "image",  imgURL)
			UI.setAttribute("TokenApplier_hud_delBtn" .. i .. "_img",      "active", hasImage and "True" or "False")
		end
		refreshHistoryNav()
	end

	--improved dyn_btn animations
	function refreshDynamicPanelSlots(targetGUID)
		local tokens = findTokensForTarget(targetGUID)
		local count  = #tokens

		-- HUD Remove All sits right under the last token name (#96)
		UI.setAttribute("TokenApplier_hud_dynRemoveAll", "offsetXY", HUD_DYN.slotX .. " " .. HUD_DYN.removeAllY(math.min(count, MAX_TOKENS)))

		local showSpread = count >= 2
		self.UI.setAttribute("dynSpreadUp",     "active", showSpread and "True" or "False")
		self.UI.setAttribute("dynSpreadDown",   "active", showSpread and "True" or "False")
		UI.setAttribute("TokenApplier_hud_dynSpreadUp",   "active", showSpread and "True" or "False")
		UI.setAttribute("TokenApplier_hud_dynSpreadDown", "active", showSpread and "True" or "False")

		for i = 1, MAX_TOKENS do
			local slotActive = (i <= count)
			local tGUID      = tokens[i]
			local slotId     = "dynSlot_" .. i
			local hudSlotId  = "TokenApplier_hud_dynSlot_" .. i

			self.UI.setAttribute(slotId,              "active", slotActive and "True" or "False")
			self.UI.setAttribute("dynRemove_" .. i,   "active", slotActive and "True" or "False")
			UI.setAttribute(hudSlotId,                "active", slotActive and "True" or "False")
			UI.setAttribute("TokenApplier_hud_dynRemove_" .. i, "active", slotActive and "True" or "False")

			if slotActive and tGUID then
				DYN_SLOT.paint(i, tGUID, selectedTokenGUID == tGUID)   -- name, picture, colours, shadow

				self.setVar("removeSlot_" .. i, tGUID)
				self.setVar("selectSlot_"  .. i, tGUID)
			end
		end
	end



-- ──────────────────────────────────────────────────────────────
--  OBJECT XML UI
-- ──────────────────────────────────────────────────────────────

	rebuildXML = function()
	    local lines = {}

	    -- ── Preview indicator ──
		local previewImage  = templateCache.imageURL
		local previewText   = templateCache.name
		local previewActive = (templateJSON ~= nil) and "True" or "False"
		local hasImage      = previewImage ~= ""

		table.insert(lines, '<Panel id="previewPanel"')
		table.insert(lines, '  active="' .. previewActive .. '"')
		table.insert(lines, '  position="0 0 -100"')
		table.insert(lines, '  rotation="0 0 0"')
		table.insert(lines, '  width="300" height="300"')
		table.insert(lines, '  color="#00000000">')
		table.insert(lines, '  <Image id="previewImg" image="' .. previewImage .. '" width="150" height="150" preserveAspect="true" active="' .. (hasImage and "True" or "False") .. '" />')
		table.insert(lines, '  <Panel id="previewTextPanel" width="150" height="150" color="' .. op("#000000CC") .. '" rectAlignment="MiddleCenter" active="' .. (hasImage and "False" or "True") .. '">')
		table.insert(lines, '    <Text id="previewText" text="' .. previewText .. '" fontSize="22" color="#FFFFFF" fontStyle="Bold" alignment="MiddleCenter" width="140" height="140" />')
		table.insert(lines, '  </Panel>')
		table.insert(lines, '</Panel>')

	    -- Move History (#104): yellow frame around the history grid while Move is on
	    table.insert(lines, MOVE.areaXml('id="moveFrame" position="0 ' .. (-380 - (HIST_LOOK.ouiRowGap - 2) / 2) .. ' -24" rotation="0 0 0" active="' .. (MOVE.on and "True" or "False") .. '"',
	        456, 228 + (HIST_LOOK.ouiRowGap - 2) + 8, 4))

	    -- ── History grid ──
	    table.insert(lines, '<Panel id="historyPanel"')
	    table.insert(lines,   ' position="0 ' .. (-380 - (HIST_LOOK.ouiRowGap - 2) / 2) .. ' -25"')
	    table.insert(lines,   ' rotation="0 0 0"')
	    table.insert(lines,   ' width="448" height="' .. (228 + (HIST_LOOK.ouiRowGap - 2)) .. '"')
	    table.insert(lines,   ' color="#00000000">')
	    table.insert(lines, '  <GridLayout cellSize="110 110" spacing="2 ' .. HIST_LOOK.ouiRowGap .. '" startCorner="UpperLeft" startAxis="Horizontal" childAlignment="UpperLeft" width="448" height="' .. (228 + (HIST_LOOK.ouiRowGap - 2)) .. '">')
	   for i = 1, HISTORY_SLOTS do
			local entry    = tokenHistory[histIndex(i)]
			local isActive = entry and (templateJSON == entry.json)
			local style    = isActive and "histSelected" or (entry and "historySlot" or "ghost")
			local hasImage = entry and entry.imageURL and entry.imageURL ~= ""
			local imgURL   = hasImage and entry.imageURL or ""
			local txtLabel = ouiHistLabel(entry)
			local txtColor = entry and "#FFFFFF" or "#404040"
			local sc       = entry and sizeClass(entry.byteSize)
			local tooltipText = historyTooltip(entry)

			table.insert(lines, '    <Button id="histBtn' .. i .. '"')
			table.insert(lines, '      onClick="btn_history_' .. i .. '"')
			table.insert(lines, '      tooltip="' .. tooltipText .. '"')
			table.insert(lines, '      ' .. btnStyle(style))
			table.insert(lines, '      width="100" height="100"')
			table.insert(lines, '      padding="3 3 3 3">')
			table.insert(lines, '      <Image id="histBtn' .. i .. '_img"')
			table.insert(lines, '        image="' .. imgURL .. '"')
			table.insert(lines, '        width="' .. HIST_LOOK.ouiImg .. '" height="' .. HIST_LOOK.ouiImg .. '"')
			table.insert(lines, '        preserveAspect="true"')
			table.insert(lines, '        active="' .. (hasImage and "True" or "False") .. '" />')
			table.insert(lines, '      <Text id="histBtn' .. i .. '_txt"')
			table.insert(lines, '        text="' .. xmlAttrText(txtLabel) .. '"')
			table.insert(lines, '        fontSize="' .. HIST_LOOK.ouiFont .. '" resizeTextForBestFit="true" resizeTextMinSize="8" resizeTextMaxSize="' .. HIST_LOOK.ouiFont .. '"')
			table.insert(lines, '        fontStyle="Bold" shadow="#000000CC" shadowDistance="2 -2"')   -- readability test (chunk 3)
			table.insert(lines, '        color="' .. txtColor .. '"')
			table.insert(lines, '        alignment="MiddleCenter"')
			table.insert(lines, '        width="' .. HIST_LOOK.ouiImg .. '" height="' .. HIST_LOOK.ouiImg .. '"')
			table.insert(lines, '        active="' .. (hasImage and "False" or "True") .. '" />')
			-- Name strip (#98), then the size badge on top of it
			table.insert(lines, HIST_LOOK.stripXml('histBtn' .. i, entry, HIST_LOOK.ouiImg, HIST_LOOK.ouiStripH,
				HIST_LOOK.ouiStripFont, HIST_LOOK.ouiStripChars, (110 - HIST_LOOK.ouiImg) / 2))
			table.insert(lines, sizeBadgeXml('histBtn' .. i .. '_warn', sc, 28, 18))
			table.insert(lines, '    </Button>')
		end
	    table.insert(lines, '  </GridLayout>')
	    table.insert(lines, '</Panel>')
		
		
		-- ── Delete overlay panel ──
		table.insert(lines, '<Panel id="deleteOverlayPanel"')
		table.insert(lines, '  active="False"')
		table.insert(lines, '  position="0 ' .. (-380 - (HIST_LOOK.ouiRowGap - 2) / 2) .. ' -25"')
		table.insert(lines, '  rotation="0 0 0"')
		table.insert(lines, '  width="448" height="' .. (228 + (HIST_LOOK.ouiRowGap - 2)) .. '"')
		table.insert(lines, '  color="#00000000">')
		table.insert(lines, '  <GridLayout cellSize="110 110" spacing="2 ' .. HIST_LOOK.ouiRowGap .. '" startCorner="UpperLeft" startAxis="Horizontal" childAlignment="UpperLeft" width="448" height="' .. (228 + (HIST_LOOK.ouiRowGap - 2)) .. '">')
		for i = 1, HISTORY_SLOTS do
			local entry = tokenHistory[histIndex(i)]
			table.insert(lines, '    <Button id="delBtn' .. i .. '"')
			table.insert(lines, '      onClick="btn_deleteHistory_' .. i .. '"')
			table.insert(lines, '      ' .. btnStyle("deleteSlot"))
			table.insert(lines, '      width="100" height="100"')
			table.insert(lines, '      padding="3 3 3 3">')
			-- Always created (hidden when empty) so a page turn can fill it via setAttribute
			local dImg = (entry and entry.imageURL) or ""
			table.insert(lines, '      <Image id="delBtn' .. i .. '_img" image="' .. dImg .. '" width="' .. HIST_LOOK.ouiImg .. '" height="' .. HIST_LOOK.ouiImg .. '" preserveAspect="true" active="' .. (dImg ~= "" and "True" or "False") .. '" />')
			table.insert(lines, '      <Panel width="100" height="100" color="#AA000066" />')
			table.insert(lines, '      <Text text="✕" color="#FF6666FF" fontSize="50" alignment="MiddleCenter" /></Button>')
		end
		table.insert(lines, '  </GridLayout>')
		table.insert(lines, '</Panel>')

		-- ── History paging: ‹ › arrows flush against the grid's left/right edges + page dots ──
		-- Grid spans x -224..222, y -266..-488 (both rows, 222 tall). Arrows are 14 wide, full
		-- grid height, 0px gap:  left x -238..-224   right x 222..236
		-- Shown/hidden live by refreshHistoryNav.
		local hPages = historyPageCount()
		local function ouiArrow(id, onClick, tooltip, label, x, on)
			return '<Button id="' .. id .. '" onClick="' .. onClick .. '" ' .. btnStyle("historyNav")
				.. ' position="' .. x .. ' ' .. (-377 - (HIST_LOOK.ouiRowGap - 2) / 2) .. ' -30" rotation="0 0 0" width="14" height="' .. (222 + (HIST_LOOK.ouiRowGap - 2)) .. '" tooltip="' .. tooltip .. '"'
				.. ' active="' .. (on and "True" or "False") .. '">'
				.. '<Text text="' .. label .. '" color="' .. BTN_STYLE.historyNav.textColor .. '" fontSize="18" fontStyle="Bold" alignment="MiddleCenter" /></Button>'
		end
		table.insert(lines, ouiArrow("histPrev", "btn_historyPrev", "Newer tokens", "&lt;", -231, historyPage > 0))
		table.insert(lines, ouiArrow("histNext", "btn_historyNext", "Older tokens", "&gt;",  229, historyPage < hPages - 1))
		-- Page dots in the gap between Add Token and the history (only when there's more than one page)
		table.insert(lines, '<HorizontalLayout id="histDots" position="0 -258 -30" rotation="0 0 0" width="96" height="12" spacing="8" childAlignment="MiddleCenter" childForceExpandWidth="false" childForceExpandHeight="false" active="' .. (hPages > 1 and "True" or "False") .. '">')
		for p = 1, HISTORY_PAGES do
			table.insert(lines, '  <Button id="histDot' .. p .. '" onClick="btn_historyPage_' .. p .. '" '
				.. btnStyle((p - 1 == historyPage) and "historyDotOn" or "historyDotOff")
				.. ' preferredWidth="12" preferredHeight="12" tooltip="Page ' .. p .. '" active="' .. (p <= hPages and "True" or "False") .. '" />')
		end
		table.insert(lines, '</HorizontalLayout>')

	    -- ── Settings button ──
	    table.insert(lines, '<Button id="settingsBtn"')
		table.insert(lines, '  onClick="btn_toggleSettings"')
		table.insert(lines, '  ' .. btnStyle(settingsOpen and "pressed" or "settings"))   -- pressed in while settings are open
	    table.insert(lines, '  position="0 ' .. (-530 - (HIST_LOOK.ouiRowGap - 2)) .. ' -25"')
	    table.insert(lines, '  rotation="0 0 0"')
	    table.insert(lines, '  width="448" height="60"')
	    table.insert(lines, '  fontSize="40"')
	    table.insert(lines, '  tooltip="Open/close settings"')
	    local ss = BTN_STYLE.settings
		table.insert(lines, '  padding="5 5 5 5"><Text id="settingsBtn_text" text="⚙" color="' .. ss.textColor .. '" offsetXY="0 ' .. (settingsOpen and -2 or 0) .. '" fontSize="40" /></Button>')

	    -- ── Settings panel ──
		-- Layout (OUI units, y up). History grid spans x -224..224, top at y -266.
		--   Token Creation     x -684..-468  y -266..-426
		--   Token History      x -461..-239  y -266..-438
		--   HUD                x -684..-236  y -446..-504
		--   Debug panel        x -684..-356  y -512..-588   (only with the Debug toggle on; toggle x -352..-236, #99)
		-- Each panel's centre = top - height/2, so changing a height keeps its top edge in place
		-- only if you also update its position Y.

		-- ── Token History panel (Edit History / Default Scale / Clear History) ──
		table.insert(lines, '<Panel id="clearHistoryPanel"')
		table.insert(lines, '  active="' .. (settingsOpen and "True" or "False") .. '"')
		table.insert(lines, '  showAnimation="Grow"')
		table.insert(lines, '  hideAnimation="Shrink"')
		table.insert(lines, '  animationDuration="0.1"')
		table.insert(lines, '  position="-350 -352 -20"')
		table.insert(lines, '  rotation="0 0 0"')
		table.insert(lines, '  width="222" height="172"')  -- title 20 + 3 rows × 44 + 3 gaps × 4 + 8 padding
		table.insert(lines, '  color="' .. op(SETTINGS_PANEL_COLOR) .. '">')
		table.insert(lines, '  <VerticalLayout spacing="4" padding="4 4 4 4" childAlignment="UpperCenter" childForceExpandHeight="false">')
		table.insert(lines, '    <Text text="Token History" color="' .. SETTINGS_TITLE_COLOR .. '" fontSize="14" fontStyle="Bold" alignment="MiddleCenter" preferredWidth="214" preferredHeight="20" />')
		-- Default token scale (first, under the title)
		-- Stepper layout: label on the left, [–][+] side by side on the right
		table.insert(lines, '    <HorizontalLayout spacing="4" childAlignment="MiddleCenter" preferredHeight="44">')
		table.insert(lines, '      <Text id="defaultScaleLabel" text="Default Scale: ' .. string.format("%.1f", defaultScaleOffset) .. '" color="#FFFFFF" resizeTextForBestFit="true" resizeTextMinSize="10" resizeTextMaxSize="16" alignment="MiddleLeft" preferredWidth="118" preferredHeight="44" />')
		table.insert(lines, '      <Button onClick="btn_defaultScaleDown"')
		table.insert(lines, '        tooltip="Decrease default spawn scale"')
		table.insert(lines, '        ' .. btnStyle("settingsItem"))
		table.insert(lines, '        fontSize="22" preferredWidth="44" preferredHeight="44">–</Button>')
		table.insert(lines, '      <Button onClick="btn_defaultScaleUp"')
		table.insert(lines, '        tooltip="Increase default spawn scale"')
		table.insert(lines, '        ' .. btnStyle("settingsItem"))
		table.insert(lines, '        fontSize="22" preferredWidth="44" preferredHeight="44">+</Button>')
		table.insert(lines, '    </HorizontalLayout>')
		-- Edit History: double height, filling Clear History's space; splits into two rows in edit mode (setHistoryEditMode)
		local eStyle = historyEditMode and EDIT_ON_STYLE or EDIT_OFF_STYLE
		table.insert(lines, '    <Button id="editHistoryBtn" onClick="btn_toggleHistoryEdit" tooltip="Delete History: click slots to remove them" ' .. btnStyle(eStyle) .. ' fontSize="20" preferredWidth="214" preferredHeight="' .. (historyEditMode and HIST_LOOK.editH.ouiShort or HIST_LOOK.editH.ouiTall) .. '"><Text id="editHistoryBtn_text" offsetXY="0 ' .. (historyEditMode and -2 or 0) .. '" text="' .. (historyEditMode and HUD_EDIT_ON_LABEL or HUD_EDIT_OFF_LABEL) .. '" color="' .. BTN_STYLE[eStyle].textColor .. '" fontSize="20" /></Button>')
		-- Clear History: last, and only shown while Edit History is live. Two-click confirm (see btn_clearHistory)
		table.insert(lines, '    <Button id="clearHistoryBtn" onClick="btn_clearHistory" tooltip="Clear all token history and reset template (click twice to confirm)" ' .. btnStyle(CLEAR_HISTORY_STYLE) .. ' fontSize="20" preferredWidth="214" preferredHeight="44" active="' .. (historyEditMode and "True" or "False") .. '"><Text id="clearHistoryBtn_text" text="' .. CLEAR_HISTORY_LABEL .. '" color="' .. BTN_STYLE[CLEAR_HISTORY_STYLE].textColor .. '" resizeTextForBestFit="true" resizeTextMinSize="10" resizeTextMaxSize="20" /></Button>')
		-- Row 3: Move History (#104). Steps aside for Clear All History in delete mode (setHistoryEditMode).
		local mvStyle = MOVE.on and "pressed" or "settingsItem"
		table.insert(lines, '    <Button id="moveHistoryBtn" onClick="btn_toggleHistoryMove" ' .. btnStyle(mvStyle)
			.. ' fontSize="20" preferredWidth="214" preferredHeight="' .. HIST_LOOK.editH.ouiShort .. '" active="' .. (historyEditMode and "False" or "True") .. '"'
			.. ' tooltip="Move History: click a slot, then another, to swap them">'
			.. '<Text id="moveHistoryBtn_text" offsetXY="0 ' .. (MOVE.on and -2 or 0) .. '" text="' .. MOVE_LABEL[MOVE.on] .. '" color="' .. BTN_STYLE[mvStyle].textColor .. '" fontSize="20" /></Button>')
		table.insert(lines, '  </VerticalLayout>')
		table.insert(lines, '</Panel>')

		-- ── Template (Token) Creation panel (settings for how templates get set) — left of History settings ──
		table.insert(lines, '<Panel id="templateSettingsPanel"')
		table.insert(lines, '  active="' .. (settingsOpen and "True" or "False") .. '"')
		table.insert(lines, '  showAnimation="Grow"')
		table.insert(lines, '  hideAnimation="Shrink"')
		table.insert(lines, '  animationDuration="0.1"')
		table.insert(lines, '  position="-576 -346 -20"')
		table.insert(lines, '  rotation="0 0 0"')
		table.insert(lines, '  width="216" height="160"')  -- title 20 + 3 rows × 40 + 3 gaps × 4 + 8 padding
		table.insert(lines, '  color="' .. op("#1A1A1AF2") .. '">')
		table.insert(lines, '  <VerticalLayout spacing="4" padding="4 4 4 4" childAlignment="UpperCenter">')
		table.insert(lines, '    <Text text="Token Creation" color="' .. SETTINGS_TITLE_COLOR .. '" fontSize="14" fontStyle="Bold" alignment="MiddleCenter" preferredWidth="208" preferredHeight="20" />')
		table.insert(lines, '    <Button onClick="btn_toggleDropTemplate"')
		table.insert(lines, '      tooltip="Enable or disable dropping objects onto TC to set template"')
		table.insert(lines, '      ' .. btnStyle(dropTemplateEnabled and "toggleOn" or "toggleOff"))
		table.insert(lines, '      fontSize="18" preferredWidth="208" preferredHeight="40"')
		table.insert(lines, '      ><Text text="' .. (dropTemplateEnabled and "Drop Template: ON" or "Drop Template: OFF") .. '" color="' .. BTN_STYLE[dropTemplateEnabled and "toggleOn" or "toggleOff"].textColor .. '" fontSize="18" /></Button>')
		table.insert(lines, '    <Button onClick="btn_toggleSetTemplate"')
		table.insert(lines, '      tooltip="Show or hide the Set Template button"')
		table.insert(lines, '      ' .. btnStyle(hideSetTemplate and "toggleOff" or "toggleOn"))
		table.insert(lines, '      fontSize="18" preferredWidth="208" preferredHeight="40"')
		table.insert(lines, '      ><Text text="' .. (hideSetTemplate and "Set Template: OFF" or "Set Template: ON") .. '" color="' .. BTN_STYLE[hideSetTemplate and "toggleOff" or "toggleOn"].textColor .. '" fontSize="18" /></Button>')
		table.insert(lines, '    <Button onClick="btn_toggleTemplatePreview"')
		table.insert(lines, '      tooltip="Spawn a 3D copy of the template next to the Token Applier when it has no image to show"')
		table.insert(lines, '      ' .. btnStyle(showTemplatePreview and "toggleOn" or "toggleOff"))
		table.insert(lines, '      fontSize="18" preferredWidth="208" preferredHeight="40"')
		table.insert(lines, '      ><Text text="' .. (showTemplatePreview and "3D Preview: ON" or "3D Preview: OFF") .. '" color="' .. BTN_STYLE[showTemplatePreview and "toggleOn" or "toggleOff"].textColor .. '" fontSize="18" /></Button>')
		table.insert(lines, '  </VerticalLayout>')
		table.insert(lines, '</Panel>')

		-- ── HUD panel (its own space, above Debug) ──
		-- Keeps the old id "settingsPanel" so existing show/hide code still works
		table.insert(lines, '<Panel id="settingsPanel"')
		table.insert(lines, '  active="' .. (settingsOpen and "True" or "False") .. '"')
		table.insert(lines, '  showAnimation="Grow"')
		table.insert(lines, '  hideAnimation="Shrink"')
		table.insert(lines, '  animationDuration="0.1"')
		table.insert(lines, '  position="-460 -475 -25"')
		table.insert(lines, '  rotation="0 0 0"')
		table.insert(lines, '  width="448" height="58"') 	-- 1 row × 50 + 8 padding
		table.insert(lines, '  color="' .. op(SETTINGS_PANEL_COLOR) .. '">')
		-- [ HUD: ON (290) ][ Opaque (146) ] — 290 + 4 gap + 146 = 440 (panel 448 − 8 padding)
		table.insert(lines, '  <HorizontalLayout spacing="4" padding="4 4 4 4" childAlignment="MiddleCenter">')
		local hStyle = hudOff and "toggleOff" or "toggleOn"
		table.insert(lines, '    <Button id="hudToggleBtn"')
		table.insert(lines, '      onClick="btn_toggleHUD"')
		table.insert(lines, '      tooltip="HUD: OFF removes the on-screen HUD completely, for tables whose own HUD clashes with it. Saved with this object."')
		table.insert(lines, '      ' .. btnStyle(hStyle))
		table.insert(lines, '      fontSize="22" preferredWidth="290" preferredHeight="50"')
		table.insert(lines, '      ><Text text="' .. (hudOff and "HUD: OFF" or "HUD: ON") .. '" color="' .. BTN_STYLE[hStyle].textColor .. '" fontSize="22" /></Button>')
		local oStyle = uiOpaque and "toggleOn" or "toggleOff"
		table.insert(lines, '    <Button id="opacityToggleBtn"')
		table.insert(lines, '      onClick="btn_toggleOpacity"')
		table.insert(lines, '      tooltip="' .. OPAQUE_TOOLTIP[uiOpaque] .. '"')
		table.insert(lines, '      ' .. btnStyle(oStyle))
		table.insert(lines, '      fontSize="18" preferredWidth="146" preferredHeight="50"')
		table.insert(lines, '      ><Text text="' .. (uiOpaque and "Opaque: ON" or "Opaque: OFF") .. '" color="' .. BTN_STYLE[oStyle].textColor .. '" fontSize="18" /></Button>')
		table.insert(lines, '  </HorizontalLayout>')
		table.insert(lines, '</Panel>')

		-- ── Customise (1.4.3): button above Token Creation; panel above it, in the space left of Add Token ──
		--   Customise button  x -684..-468  y -222..-258      Customise panel  x -684..-236  y -52..-218
		local cusStyle = CUSTOM.open and "pressed" or "settingsItem"   -- pressed in while its panel is open
		table.insert(lines, '<Button id="customiseToggleBtn" onClick="btn_toggleCustomise"')
		table.insert(lines, '  active="' .. (settingsOpen and "True" or "False") .. '"')
		table.insert(lines, '  tooltip="Customise: look and feel options (selection colour, ...)"')
		table.insert(lines, '  ' .. btnStyle(cusStyle))
		table.insert(lines, '  position="-576 -240 -25" rotation="0 0 0" width="216" height="36" fontSize="18">')
		table.insert(lines, '  <Text id="customiseToggleBtn_text" text="Customise" color="' .. BTN_STYLE[cusStyle].textColor .. '" offsetXY="0 ' .. (CUSTOM.open and -2 or 0) .. '" fontSize="18" width="216" height="36" alignment="MiddleCenter" /></Button>')

		table.insert(lines, '<Panel id="customisePanel"')
		table.insert(lines, '  active="' .. ((settingsOpen and CUSTOM.open) and "True" or "False") .. '"')
		table.insert(lines, '  position="-460 -135 -20" rotation="0 0 0" width="448" height="166"')
		table.insert(lines, '  color="' .. op(SETTINGS_PANEL_COLOR) .. '">')
		table.insert(lines, '  <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="UpperCenter" childForceExpandHeight="false">')
		table.insert(lines, '    <Text text="Selection colour" color="' .. SETTINGS_TITLE_COLOR .. '" fontSize="14" fontStyle="Bold" alignment="MiddleCenter" preferredWidth="432" preferredHeight="20" />')
		table.insert(lines, '    <HorizontalLayout spacing="6" childAlignment="MiddleCenter" childForceExpandWidth="false" preferredHeight="28">')
		for i = 1, #CUSTOM.presets do
			table.insert(lines, '      ' .. CUSTOM.swatchXml('selColor_' .. i, 'btn_selectColorPreset', i, 'preferredWidth="28" preferredHeight="28"', "2 2"))
		end
		table.insert(lines, '    </HorizontalLayout>')
		table.insert(lines, '    <HorizontalLayout spacing="6" childAlignment="MiddleCenter" childForceExpandWidth="false" preferredHeight="40">')
		table.insert(lines, '      <InputField id="selColorHex" onEndEdit="btn_selectColorHex" text="' .. CUSTOM.selectColor .. '"'
			.. ' characterLimit="7" fontSize="20" color="#FFFFFF" textColor="#10141E" placeholder="#15AFCC"'
			.. ' tooltip="Type a colour as a hex code (e.g. #15AFCC), then press Enter" preferredWidth="200" preferredHeight="40" />')
		table.insert(lines, '      <Button onClick="btn_selectColorReset" ' .. btnStyle("settingsItem") .. ' fontSize="18" tooltip="Back to the default cyan" preferredWidth="100" preferredHeight="40">'
			.. '<Text text="Reset" color="' .. BTN_STYLE.settingsItem.textColor .. '" fontSize="18" width="100" height="40" alignment="MiddleCenter" /></Button>')
		table.insert(lines, '    </HorizontalLayout>')
		-- Backgrounds row (#100): label + one button that cycles 0% / 50% / 100% (affects the HUD)
		table.insert(lines, '    <HorizontalLayout spacing="6" childAlignment="MiddleCenter" childForceExpandWidth="false" preferredHeight="40">')
		table.insert(lines, '      <Text text="HUD background" color="' .. SETTINGS_TITLE_COLOR .. '" fontSize="18" fontStyle="Bold" alignment="MiddleLeft" preferredWidth="200" preferredHeight="40" />')
		table.insert(lines, '      <Button onClick="btn_cycleBackground" ' .. btnStyle("settingsItem") .. ' fontSize="18" tooltip="Fill the see-through gaps behind the HUD: 0% / 50% / 100% (click to cycle)" preferredWidth="100" preferredHeight="40">'
			.. '<Text text="' .. CUSTOM.bgLevels[CUSTOM.bg].label .. '" color="' .. BTN_STYLE.settingsItem.textColor .. '" fontSize="18" width="100" height="40" alignment="MiddleCenter" /></Button>')
		table.insert(lines, '    </HorizontalLayout>')
		table.insert(lines, '  </VerticalLayout>')
		table.insert(lines, '</Panel>')

		-- ── Debug toggle + Debug Settings panel (bottom; grey so it doesn't draw the eye) (#99) ──
		-- Toggle: right end of the bottom row, its right edge in line with the Token History panel (x -236).
		-- Panel (only while the toggle is on): fills the rest of the row to the left, x -684..-356.
		local dbgStyle = debugOpen and "pressed" or "debug"   -- pressed in while the debug buttons show
		table.insert(lines, '<Button id="debugToggleBtn" onClick="btn_toggleDebug"')
		table.insert(lines, '  active="' .. (settingsOpen and "True" or "False") .. '"')
		table.insert(lines, '  tooltip="' .. (debugOpen and "Debug: ON. Click to hide the debug buttons" or "Debug: OFF. Click to show the debug buttons") .. '"')
		table.insert(lines, '  ' .. btnStyle(dbgStyle))
		table.insert(lines, '  position="-294 -532 -25" rotation="0 0 0" width="116" height="40" fontSize="18">')
		table.insert(lines, '  <Text id="debugToggleBtn_text" text="Debug" color="' .. BTN_STYLE[dbgStyle].textColor .. '" offsetXY="0 ' .. (debugOpen and -2 or 0) .. '" fontSize="18" width="116" height="40" alignment="MiddleCenter" /></Button>')

		table.insert(lines, '<Panel id="debugSettingsPanel"')
		table.insert(lines, '  active="' .. ((settingsOpen and debugOpen) and "True" or "False") .. '"')
		table.insert(lines, '  showAnimation="Grow"')
		table.insert(lines, '  hideAnimation="Shrink"')
		table.insert(lines, '  animationDuration="0.1"')
		table.insert(lines, '  position="-520 -550 -25"')
		table.insert(lines, '  rotation="0 0 0"')
		table.insert(lines, '  width="328" height="76"') 	-- title 20 + 1 row × 44 + 1 gap × 4 + 8 padding
		table.insert(lines, '  color="' .. op("#1E1E1EF2") .. '">')
		table.insert(lines, '  <VerticalLayout spacing="4" padding="4 4 4 4" childAlignment="UpperCenter">')
		table.insert(lines, '    <Text text="Debug Settings" color="' .. BTN_STYLE.debug.textColor .. '" fontSize="14" fontStyle="Bold" alignment="MiddleCenter" preferredWidth="320" preferredHeight="20" />')
		table.insert(lines, '    <HorizontalLayout spacing="4" childAlignment="MiddleCenter" preferredHeight="44">')
		table.insert(lines, '      <Button onClick="btn_restoreTokens" tooltip="Restore tokens after save/load if any are missing" ' .. btnStyle("debug") .. ' fontSize="16" preferredWidth="104" preferredHeight="44">↺ Restore</Button>')
		table.insert(lines, '      <Button onClick="btn_debug" tooltip="Print current hover-token table to console" ' .. btnStyle("debug") .. ' fontSize="16" preferredWidth="104" preferredHeight="44">Debug IDs</Button>')
		table.insert(lines, '      <Button onClick="btn_findTokens" tooltip="Find and adopt tokens left behind by a deleted or old Token Applier" ' .. btnStyle("debug") .. ' fontSize="16" preferredWidth="104" preferredHeight="44">Find Tokens</Button>')
		table.insert(lines, '    </HorizontalLayout>')
		table.insert(lines, '  </VerticalLayout>')
		table.insert(lines, '</Panel>')

	    -- ── Add Token + Set Template + size warning ──
	    local templateLabel = templateCache.label
		-- Add Token button
	    table.insert(lines, '<Button id="addTokenBtn"')
	    table.insert(lines, '  onClick="btn_toggleToken"')
	    table.insert(lines, '  ' .. btnStyle("primary"))
	    table.insert(lines, '  tooltip="Select a model, then click to add token"')
	    table.insert(lines, '  position="0 -150 -25"') -- X , Y, Z
	    table.insert(lines, '  rotation="0 0 0"')
	    table.insert(lines, '  width="448" height="200"')
	    table.insert(lines, '  fontSize="60"')
	    table.insert(lines, '  >Add Token</Button>')

		-- Rename bar (#103): along the BOTTOM of Add Token (448 wide, y -170..-250), like the HUD's, hidden until
		-- a history slot is right-clicked. Rounded background like the HUD panels (Panels can't round).
		table.insert(lines, '<Panel id="renamePanel" active="False" position="0 -210 -32" rotation="0 0 0" width="448" height="80" color="#00000000">')
		table.insert(lines, '  ' .. roundedPanelBg(448, 80, op(SETTINGS_PANEL_COLOR)))
		table.insert(lines, '  <HorizontalLayout spacing="8" padding="10 10 12 12" childAlignment="MiddleCenter" childForceExpandWidth="false">')
		-- [name 262][Save 90][✕ 56] + 2 gaps of 8 = 424 (448 − 2 × 10 padding = 428)
		table.insert(lines, '    <InputField id="renameInput" onEndEdit="btn_renameHistory" onValueChanged="btn_renameTyped" text=""'
			.. ' characterLimit="40" fontSize="22" color="#FFFFFF" textColor="#10141E" placeholder="New name"'
			.. ' tooltip="Rename this history slot: Enter or Save keeps it, ✕ cancels" preferredWidth="262" preferredHeight="56" />')
		table.insert(lines, '    <Button onClick="btn_renameSave" ' .. btnStyle("settingsItem") .. ' fontSize="20" tooltip="Save the new name" preferredWidth="90" preferredHeight="56">'
			.. '<Text text="Save" color="' .. BTN_STYLE.settingsItem.textColor .. '" fontSize="20" width="90" height="56" alignment="MiddleCenter" /></Button>')
		table.insert(lines, '    <Button onClick="btn_renameCancel" ' .. btnStyle("dynRemove") .. ' fontSize="24" tooltip="Cancel (keep the old name)" preferredWidth="56" preferredHeight="56">'
			.. '<Text text="✕" color="' .. BTN_STYLE.dynRemove.textColor .. '" fontSize="24" width="56" height="56" alignment="MiddleCenter" /></Button>')
		table.insert(lines, '  </HorizontalLayout>')
		table.insert(lines, '</Panel>')

		-- Set Template button
	    table.insert(lines, '<Button id="setTemplateBtn"')
		table.insert(lines, '  active="' .. (hideSetTemplate and "False" or "True") .. '"')
		table.insert(lines, '  onClick="btn_setTemplate"')
	    table.insert(lines, '  ' .. btnStyle("template"))
	    table.insert(lines, '  tooltip="Drop any object onto TC, or select an object then click to capture it as the token template"')
	    table.insert(lines, '  position="0 -620 -25"') -- X , Y, Z
	    table.insert(lines, '  rotation="0 0 0"')
	    table.insert(lines, '  width="448" height="100"')
	    table.insert(lines, '  fontSize="26"')
	    local ts = BTN_STYLE.template
		table.insert(lines, '  ><Text id="setTemplateBtn_text" text="' .. templateLabel .. '" color="' .. ts.textColor .. '" fontSize="26" /></Button>')
		local templateLabel = templateCache.label
		
		-- large token warning
		local sizeWarning   = ""
		if templateCache.byteSize > SIZE_MASSIVE then
			sizeWarning = "\n⚠ Very large object"
		elseif templateCache.byteSize > SIZE_LARGE then
			sizeWarning = "\n⚠ Large object"
		end
		templateLabel = templateLabel .. sizeWarning
		
		-- ── Size warning panel ──
		local warnText  = templateCache.byteSize > SIZE_MASSIVE and "⚠ Very large object — expect some lag" or "⚠ Large object"
		local warnColor = op(templateCache.byteSize > SIZE_MASSIVE and "#5A1A00F2" or "#3A3A0AF2")
		local warnActive = templateCache.byteSize > SIZE_LARGE and "True" or "False"
		table.insert(lines, '<Panel id="sizeWarningPanel"')
		table.insert(lines, '  active="' .. warnActive .. '"')
		table.insert(lines, '  position="0 -230 -25"')
		table.insert(lines, '  rotation="0 0 0"')
		table.insert(lines, '  width="448" height="36"')
		table.insert(lines, '  color="' .. warnColor .. '">')
		table.insert(lines, '  <Text id="sizeWarningText" text="' .. warnText .. '" fontSize="18" color="#FFAA44" alignment="MiddleCenter" />')
		table.insert(lines, '</Panel>')


	    -- ── Dynamic panel ──
	    -- Buttons are direct children of the panel, positioned with
	    -- rectAlignment="UpperLeft" + offsetXY. This is the only
	    -- approach that produces fixed-size square buttons in TTS Object XML.
	    --
	    -- Grid layout (col, row) → offsetXY:
	    --   col: 0=8  1=76  2=144  3=212
	    --   row: 0=-8  1=-76  2=-144
	    --
	    --   [    ] [ •  ] [Flip] [ ↕  ]   row 0
	    --   [ ⁘  ] [ ▲  ] [ ▼  ] [ ⁛  ]   row 1
	    --   [    ] [ ·  ] [ ↻  ] [    ]   row 2
	    --
	    -- Slot rows start at row 3 offset (-212) with 8px extra gap

	    local PAD  = 8
	    local BW   = 60
	    local GAP  = 8
	    local STEP = BW + GAP  -- 68

	    local function col(c) return PAD + c * STEP end
	    local function row(r) return -(PAD + r * STEP) end

	    local function mbtn(id, onClick, tooltip, style, fontSize, label, c, r, extra)
			local idA  = id and ('id="' .. id .. '" ') or ""
			local exA  = extra or ""
			local s    = BTN_STYLE[style] or BTN_STYLE.ghost
			return '  <Button ' .. idA
				.. 'onClick="' .. onClick .. '" '
				.. 'tooltip="' .. tooltip .. '" '
				.. btnStyle(style) .. ' '
				.. 'width="' .. BW .. '" height="' .. BW .. '" '
				.. 'fontSize="' .. fontSize .. '" '
				.. 'rectAlignment="UpperLeft" '
				.. 'offsetXY="' .. col(c) .. ' ' .. row(r) .. '" '
				.. exA .. '>'
				.. '<Text text="' .. label .. '" color="' .. s.textColor .. '" fontSize="' .. fontSize .. '" width="' .. BW .. '" height="' .. BW .. '" alignment="MiddleCenter" />'
				.. '</Button>'
		end

	    local SW = 300   -- slot name button width
		local DBLGAP  = (GAP * 2) + 5
		local function col4() return PAD + 3 * STEP + DBLGAP + BW + DBLGAP end
	    local RW = BW    -- remove button width

	    table.insert(lines, '<Panel id="dynamicPanel"')
		table.insert(lines, '  showAnimation="Grow"')
		table.insert(lines, '  hideAnimation="Shrink"')
	    table.insert(lines, '  animationDuration="0.1"')
	    table.insert(lines, '  active="False"')
	    table.insert(lines, '  position="440 -395 -25"')  -- X , Y, Z(no change needed)
	    table.insert(lines, '  rotation="0 0 0"')
	    table.insert(lines, '  width="' .. (PAD + 3*STEP + DBLGAP + BW + DBLGAP + BW + PAD) .. '" height="700"')
	    table.insert(lines, '  color="#00000000">')

	    -- Row 0: [lineForward] [•] [Flip] [↕]
		table.insert(lines, mbtn(nil,             "btn_lineForward",  "Move tokens forward (Z axis)",               "dynMod",        "30", "↑",    0, 0))
	    table.insert(lines, mbtn(nil,             "btn_scaleUp",   "Scale up\nall tokens, or just selected",        "dynGreenBtn",   "30", "•",    1, 0))
	    table.insert(lines, mbtn(nil,             "btn_flip",      "Flip token\nall tokens, or just selected",      "dynMod",       "30", "Flip", 2, 0))
	    table.insert(lines, mbtn(nil,             "btn_vertical",  "Toggle vertical\nall tokens, or just selected", "dynMod",       "30", "↕",    3, 0))

	    -- Row 1: [⁘] [▲] [▼] [⁛]
	    table.insert(lines, mbtn("dynSpreadDown", "btn_radiusDown","Decrease spread",                               "dynRedBtn", "30", "⁘",    0, 1, 'active="False"'))
	    table.insert(lines, mbtn(nil,             "btn_heightUp",  "Raise token height\nall tokens, or just selected","dynMod",    "30", "▲",    1, 1))
	    table.insert(lines, mbtn(nil,             "btn_heightDown","Lower token height\nall tokens, or just selected","dynMod",    "30", "▼",    2, 1))
	    table.insert(lines, mbtn("dynSpreadUp",   "btn_radiusUp",  "Increase spread",                               "dynGreenBtn",  "30", "⁛",    3, 1, 'active="False"'))

	    -- Row 2: [lineBackward] [·] [↻] [spacer]
		table.insert(lines, mbtn(nil,             "btn_lineBackward", "Move tokens backward (Z axis)",              "dynMod",        "30", "↓",    0, 2))
	    table.insert(lines, mbtn(nil,             "btn_scaleDown", "Scale down\nall tokens, or just selected",      "dynRedBtn", "30", "·",    1, 2))
	    table.insert(lines, mbtn(nil,             "btn_rotate",    "Rotate 180°\nall tokens, or just selected",     "dynMod",       "30", "↻",    2, 2))

		-- Col 4 (double-gapped): LineUp toggle
		local isLineUp = modelLineUp[lastSelectedGUID or ""] or false
		table.insert(lines, '  <Button id="dynLineUpToggle"'
			.. ' onClick="btn_toggleModelLineUp"'
			.. ' tooltip="Switch this model between line-up and radial token layout"'
			.. ' ' .. btnStyle(LINEUP.style)
			.. ' width="' .. BW .. '" height="' .. BW .. '"'
			.. ' fontSize="14"'
			.. ' rectAlignment="UpperLeft"'
			.. ' offsetXY="' .. col4() .. ' ' .. row(0) .. '">'
			.. '<Text id="dynLineUpToggle_text" text="' .. xmlAttrText(LINEUP.oui[isLineUp]) .. '" color="' .. BTN_STYLE[LINEUP.style].textColor .. '" fontSize="14" width="' .. BW .. '" height="' .. BW .. '" alignment="MiddleCenter" />'
			.. '</Button>')

		-- Remove All Tokens (OUI): a wide bar ABOVE the modifier grid, from its left edge to Line up's right edge.
		-- Same two-click confirm and handler as the HUD one (hud_removeTokens).
		local ouiRemW = col4() + BW - PAD
		table.insert(lines, '  <Button id="dynRemoveAll"'
			.. ' onClick="hud_removeTokens"'
			.. ' tooltip="Remove ALL tokens from the selected model (click twice to confirm)"'
			.. ' ' .. btnStyle(REMOVE_ALL_STYLE)
			.. ' width="' .. ouiRemW .. '" height="36"'
			.. ' rectAlignment="UpperLeft"'
			.. ' offsetXY="' .. PAD .. ' 44">'   -- y +44: sits above the panel top (row 0 starts at -8), 16 gap
			.. '<Text id="dynRemoveAll_text" text="' .. REMOVE_ALL_LABEL .. '" color="' .. BTN_STYLE[REMOVE_ALL_STYLE].textColor .. '" fontSize="18" width="' .. ouiRemW .. '" height="36" alignment="MiddleCenter" />'
			.. '</Button>')
			
	    -- Token slots — below modifier grid with extra gap
	    local slotStartRow = 3
	    local slotExtraGap = 8

	    for i = 1, MAX_TOKENS do
	        local yOffset = -(PAD + slotStartRow * STEP + slotExtraGap + (i - 1) * (BW + GAP))
	        -- Name button
	        table.insert(lines, '  <Button id="dynSlot_' .. i .. '"')
	        table.insert(lines, '    onClick="btn_select_' .. i .. '"')
	        table.insert(lines, '    ' .. btnStyle("dynSlot"))
	        table.insert(lines, '    active="False"')
	        table.insert(lines, '    tooltip="Click to select — modifiers apply to selected token only"')
	        table.insert(lines, '    width="' .. SW .. '" height="' .. BW .. '"')
	        table.insert(lines, '    rectAlignment="UpperLeft"')
	        table.insert(lines, '    offsetXY="' .. PAD .. ' ' .. yOffset .. '"')
	        table.insert(lines, '    fontSize="' .. DYN_SLOT.ouiFont .. '">')
	        -- Token picture (left, inside the button) + left-aligned name; filled by DYN_SLOT.paint (#97)
	        table.insert(lines, '    <Image id="dynSlot_' .. i .. '_img" image="" width="' .. DYN_SLOT.ouiImg .. '" height="' .. DYN_SLOT.ouiImg .. '"'
	            .. ' rectAlignment="MiddleLeft" offsetXY="4 0" preserveAspect="true" raycastTarget="false" active="False" />')
	        table.insert(lines, '    <Text id="dynSlot_' .. i .. '_text" text="–" color="' .. BTN_STYLE.dynSlot.textColor .. '" fontSize="' .. DYN_SLOT.ouiFont .. '"'
	            .. ' width="' .. DYN_SLOT.ouiTextW .. '" height="' .. BW .. '" rectAlignment="MiddleLeft" offsetXY="' .. DYN_SLOT.ouiTextX .. ' 0"'
	            .. ' alignment="MiddleLeft" shadow="' .. DYN_SLOT.shadowOff .. '" shadowDistance="2 -2" raycastTarget="false" />')
	        table.insert(lines, '  </Button>')
	        -- Remove button
	        table.insert(lines, '  <Button id="dynRemove_' .. i .. '"')
	        table.insert(lines, '    onClick="btn_remove_' .. i .. '"')
	        table.insert(lines, '    ' .. btnStyle("dynRemove"))
	        table.insert(lines, '    active="False"')
	        table.insert(lines, '    tooltip="Remove token"')
	        table.insert(lines, '    width="' .. RW .. '" height="' .. BW .. '"')
	        table.insert(lines, '    rectAlignment="UpperLeft"')
	        table.insert(lines, '    offsetXY="' .. (PAD + SW + GAP) .. ' ' .. yOffset .. '"')
	        table.insert(lines, '    fontSize="30"><Text text="✕" color="#FFFFFF" /></Button>')
	    end

	    table.insert(lines, '</Panel>')  -- end dynamicPanel

	    local xml = '<Panel width="2000" height="2000" color="#00000000">\n'
	             .. table.concat(lines, "\n")
	             .. '\n</Panel>'
	    self.UI.setXml(xml)
	end

-- ──────────────────────────────────────────────────────────────
--  GLOBAL HUD INJECTION
-- ──────────────────────────────────────────────────────────────

	local function buildHUDXml(guid)
	    local lines = {}
	    local g = guid
		
		
		-- ── Root draggable wrapper ──
		table.insert(lines, '<Panel id="TokenApplier_hud_root"')
		table.insert(lines, '  rectAlignment="LowerCenter"')
		table.insert(lines, '  offsetXY="' .. hudRootOffsetXY .. '"')
		table.insert(lines, '  width="200" height="150"')
		table.insert(lines, '  color="#00000000"')
		table.insert(lines, '  allowDragging="' .. (hudDraggable and "true" or "false") .. '"')
		table.insert(lines, '  restrictDraggingToParentBounds="false"')
		table.insert(lines, '  returnToOriginalPositionWhenReleased="false">')

	    -- ── Backgrounds (#100): backdrops built FIRST so they're drawn behind everything ──
	    -- Each = the group's outer content edges + CUSTOM.bgMargin all round. Lowest content is at y 2
	    -- in every group (minimise, Line up, debug row), so every backdrop starts at y 2 - margin.
	    local BGM    = CUSTOM.bgPad()
	    local bgBase = 2 - BGM
	    -- Main block: minimise (y 2) up to Add Token's size strip (191), or Set Template (220) when showing.
	    -- Width follows the ‹ › arrows (refreshHistoryNav resizes it when the page count changes).
	    local mainTop = hideSetTemplate and 191 or 220
	    table.insert(lines, CUSTOM.bgXml("TokenApplier_hud_mainBg", "LowerCenter", 0, bgBase,
	        CUSTOM.mainBgW(historyPageCount()), mainTop + BGM - bgBase))
	    -- Settings column (only while settings are open): x -252..-132, debug row up to the Customise
	    -- button, or the customise panel while that's open (btn_toggleSettings shrinks it live on close)
	    table.insert(lines, CUSTOM.bgXml("TokenApplier_hud_settingsBg", "LowerCenter", -192, bgBase,
	        120 + 2 * BGM, CUSTOM.settingsBgH(CUSTOM.open), 'active="' .. (settingsOpen and "True" or "False") .. '"'))

	    -- Move History (#104): yellow frame around the history grid (x -112.5..112.5, y 29..142) while Move is on
	    table.insert(lines, MOVE.areaXml('id="TokenApplier_hud_moveFrame" rectAlignment="LowerCenter" offsetXY="0 25" active="' .. (MOVE.on and "True" or "False") .. '"',
	        233, 121, 2))

	    -- ── CORE panel ──
	    -- Contains: Add Token, History Grid (2×4), Minimize footer
	    table.insert(lines, '<Panel id="TokenApplier_hud_core"')
		table.insert(lines, '  rectAlignment="LowerCenter"')
		table.insert(lines, '  offsetXY="0 25"')
		table.insert(lines, '  width="233" height="168"')
		table.insert(lines, '  color="#00000000"') -- was CC
		table.insert(lines, '  padding="4 4 4 4">')

		table.insert(lines, '  <VerticalLayout spacing="3" childAlignment="UpperCenter">')

		-- Add Token button
		table.insert(lines, '    <Button id="TokenApplier_hud_add"')
		table.insert(lines, '      onClick="' .. g .. '/hud_addToken"')
		table.insert(lines, '      ' .. btnStyle("lookPrimary"))   -- 1.4.2 look test
		table.insert(lines, '      fontSize="18" preferredWidth="225" preferredHeight="44"')
		table.insert(lines, '      tooltip="Add token to selected model">')
		-- 1.4.2 look test: text shadow on a bright button (needs a <Text> child; a shadow on the
		-- Button itself would shadow the button shape, not the words)
		table.insert(lines, '      <Text text="＋ Add Token" color="' .. BTN_STYLE.lookPrimary.textColor .. '" shadow="#000000CC" shadowDistance="1 -1" fontSize="18" width="225" height="44" alignment="MiddleCenter" /></Button>')

		-- History grid (2 rows × 4 cols)
		table.insert(lines, '    <GridLayout id="TokenApplier_hud_grid"')
		table.insert(lines, '      cellSize="54 54" spacing="3 5"')
		table.insert(lines, '      startCorner="UpperLeft" startAxis="Horizontal"')
		table.insert(lines, '      childAlignment="UpperLeft"')
		table.insert(lines, '      width="225" height="113">')

	    for i = 1, HISTORY_SLOTS do
			local entry    = tokenHistory[histIndex(i)]
			local isActive = entry and (templateJSON == entry.json)
			local style    = isActive and "histSelected" or (entry and "historySlot" or "ghost")
			local hasImage = entry and entry.imageURL and entry.imageURL ~= ""
			local imgURL   = hasImage and entry.imageURL or ""
			local txtLabel = hudHistLabel(entry)
			local txtColor = entry and "#FFFFFF" or "#303030"
			local sc       = entry and sizeClass(entry.byteSize)
			local tooltipText = historyTooltip(entry)

			table.insert(lines, '    <Button id="TokenApplier_hud_hist_' .. i .. '"')
			table.insert(lines, '      onClick="' .. g .. '/hud_history_' .. i .. '"')
			table.insert(lines, '      tooltip="' .. tooltipText .. '"')
			table.insert(lines, '      ' .. btnStyle(style))
			table.insert(lines, '      width="54" height="54"')
			table.insert(lines, '      padding="2 2 2 2">')
			table.insert(lines, '      <Image id="TokenApplier_hud_hist_' .. i .. '_img"')
			table.insert(lines, '        image="' .. imgURL .. '"')
			table.insert(lines, '        width="' .. HIST_LOOK.hudImg .. '" height="' .. HIST_LOOK.hudImg .. '"')
			table.insert(lines, '        preserveAspect="true"')
			table.insert(lines, '        active="' .. (hasImage and "True" or "False") .. '" />')
			table.insert(lines, '      <Text id="TokenApplier_hud_hist_' .. i .. '_txt"')
			table.insert(lines, '        text="' .. xmlAttrText(txtLabel) .. '"')
			table.insert(lines, '        fontSize="' .. HIST_LOOK.hudFont .. '" resizeTextForBestFit="true" resizeTextMinSize="6" resizeTextMaxSize="' .. HIST_LOOK.hudFont .. '"')
			table.insert(lines, '        fontStyle="Bold" shadow="#000000CC" shadowDistance="1 -1"')   -- readability test (chunk 3)
			table.insert(lines, '        width="' .. HIST_LOOK.hudImg .. '" height="' .. HIST_LOOK.hudImg .. '"')
			table.insert(lines, '        color="' .. txtColor .. '"')
			table.insert(lines, '        alignment="MiddleCenter"')
			table.insert(lines, '        active="' .. (hasImage and "False" or "True") .. '" />')
			-- Name strip (#98), then the size badge on top of it
			table.insert(lines, HIST_LOOK.stripXml('TokenApplier_hud_hist_' .. i, entry, HIST_LOOK.hudImg + 4, HIST_LOOK.hudStripH,   -- HUD plate 2px wider each side than the picture
				HIST_LOOK.hudStripFont, HIST_LOOK.hudStripChars, (54 - HIST_LOOK.hudImg) / 2, true, HIST_LOOK.hudStripDrop))
			table.insert(lines, sizeBadgeXml('TokenApplier_hud_hist_' .. i .. '_warn', sc, 16, 10))
			table.insert(lines, '    </Button>')
		end

	    table.insert(lines, '    </GridLayout>')
		table.insert(lines, '  </VerticalLayout>')
		
		table.insert(lines, '</Panel><!--TokenApplier_hud_core-->') -- end TokenApplier_hud_core

		-- Rename bar (#103): over Add Token (x -112.5..112.5, y 145..189), hidden until a history slot is
		-- right-clicked. The box is 30 tall: an InputField keeps ~13px padding, so its text needs the room.
		table.insert(lines, '<Panel id="TokenApplier_hud_renamePanel" active="False" rectAlignment="LowerCenter" offsetXY="0 145" width="225" height="44" color="#00000000">')
		table.insert(lines, '  ' .. roundedPanelBg(225, 44, op(SETTINGS_PANEL_COLOR), CUSTOM.panelRimColor()))
		table.insert(lines, '  <HorizontalLayout spacing="4" padding="6 6 7 7" childAlignment="MiddleCenter" childForceExpandWidth="false">')
		-- [name 132][Save 45][✕ 28] + 2 gaps of 4 = 213 (225 − 2 × 6 padding)
		table.insert(lines, '    <InputField id="TokenApplier_hud_renameInput" onEndEdit="' .. g .. '/btn_renameHistory" onValueChanged="' .. g .. '/btn_renameTyped" text=""'
			.. ' characterLimit="40" fontSize="10" color="#FFFFFF" textColor="#10141E" placeholder="New name"'
			.. ' tooltip="Rename this history slot: Enter or Save keeps it, ✕ cancels" preferredWidth="132" preferredHeight="30" />')
		table.insert(lines, '    <Button onClick="' .. g .. '/btn_renameSave" ' .. btnStyle("settingsItem") .. ' fontSize="9" tooltip="Save the new name" preferredWidth="45" preferredHeight="30">'
			.. '<Text text="Save" color="' .. BTN_STYLE.settingsItem.textColor .. '" fontSize="9" width="45" height="30" alignment="MiddleCenter" /></Button>')
		table.insert(lines, '    <Button onClick="' .. g .. '/btn_renameCancel" ' .. btnStyle("dynRemove") .. ' fontSize="12" tooltip="Cancel (keep the old name)" preferredWidth="28" preferredHeight="30">'
			.. '<Text text="✕" color="' .. BTN_STYLE.dynRemove.textColor .. '" fontSize="12" width="28" height="30" alignment="MiddleCenter" /></Button>')
		table.insert(lines, '  </HorizontalLayout>')
		table.insert(lines, '</Panel><!--TokenApplier_hud_renamePanel-->')
		
		
		-- ── HUD Delete overlay panel ──
		table.insert(lines, '<Panel id="TokenApplier_hud_deleteOverlayPanel"')
		table.insert(lines, '  active="' .. (historyEditMode and "True" or "False") .. '"')	-- survives a rebuild mid-edit
		table.insert(lines, '  rectAlignment="LowerCenter"')
		table.insert(lines, '  offsetXY="0 29"')  --attempt to move the location of this panel
		table.insert(lines, '  width="225" height="113"')
		table.insert(lines, '  color="#00000000">')
		table.insert(lines, '  <GridLayout cellSize="54 54" spacing="3 5" startCorner="UpperLeft" startAxis="Horizontal" childAlignment="UpperLeft" width="225" height="113">')
		for i = 1, HISTORY_SLOTS do
			local entry = tokenHistory[histIndex(i)]
			local g = guid
			table.insert(lines, '    <Button id="TokenApplier_hud_delBtn' .. i .. '"')
			table.insert(lines, '      onClick="' .. g .. '/hud_deleteHistory_' .. i .. '"')
			table.insert(lines, '      ' .. btnStyle("deleteSlot"))
			table.insert(lines, '      width="54" height="54"')
			table.insert(lines, '      padding="2 2 2 2">')
			-- Always created (hidden when empty) so a page turn can fill it via setAttribute
			local dImg = (entry and entry.imageURL) or ""
			table.insert(lines, '      <Image id="TokenApplier_hud_delBtn' .. i .. '_img" image="' .. dImg .. '" width="' .. HIST_LOOK.hudImg .. '" height="' .. HIST_LOOK.hudImg .. '" preserveAspect="true" active="' .. (dImg ~= "" and "True" or "False") .. '" />')
			table.insert(lines, '      <Panel width="54" height="54" color="#AA000066" />')
			table.insert(lines, '      <Text text="✕" color="#FF6666FF" fontSize="28" alignment="MiddleCenter" /></Button>')
		end
		table.insert(lines, '  </GridLayout>')
		table.insert(lines, '</Panel><!--TokenApplier_hud_deleteOverlayPanel-->') -- end deleteOverlayPanel

		-- ── HUD history paging: ‹ › arrows + page dots (mirrors the OUI) ──
		-- Grid spans x -112..112, y 31..142; row boundary y ≈ 86.
		-- Arrows are 10 wide, full grid height (111), 0px gap against the grid:
		--   left  x -122.5..-112.5 (Token History panel ends at -132)
		--   right x  112.5..122.5  (dynamic panel starts at 128)
		-- Dots sit inside the bottom edge of Add Token (y 145..189) — there's no gap above the grid.
		local hudPages = historyPageCount()
		local function hudArrow(id, onClick, tooltip, label, x, on)
			return '<Button id="' .. id .. '" rectAlignment="LowerCenter" offsetXY="' .. x .. ' 29" width="10" height="113"'
				.. ' onClick="' .. g .. '/' .. onClick .. '" ' .. btnStyle("historyNav") .. ' tooltip="' .. tooltip .. '"'
				.. ' active="' .. (on and "True" or "False") .. '">'
				.. '<Text text="' .. label .. '" color="' .. BTN_STYLE.historyNav.textColor .. '" fontSize="12" fontStyle="Bold" alignment="MiddleCenter" /></Button>'
		end
		table.insert(lines, hudArrow("TokenApplier_hud_histPrev", "btn_historyPrev", "Newer tokens", "&lt;", -117.5, historyPage > 0))
		table.insert(lines, hudArrow("TokenApplier_hud_histNext", "btn_historyNext", "Older tokens", "&gt;",  117.5, historyPage < hudPages - 1))
		table.insert(lines, '<HorizontalLayout id="TokenApplier_hud_histDots" rectAlignment="LowerCenter" offsetXY="0 148" width="60" height="7" spacing="5" childAlignment="MiddleCenter" childForceExpandWidth="false" childForceExpandHeight="false" active="' .. (hudPages > 1 and "True" or "False") .. '">')
		for p = 1, HISTORY_PAGES do
			table.insert(lines, '  <Button id="TokenApplier_hud_histDot' .. p .. '" onClick="' .. g .. '/btn_historyPage_' .. p .. '" '
				.. btnStyle((p - 1 == historyPage) and "historyDotOn" or "historyDotOff")
				.. ' preferredWidth="7" preferredHeight="7" tooltip="Page ' .. p .. '" active="' .. (p <= hudPages and "True" or "False") .. '" />')
		end
		table.insert(lines, '</HorizontalLayout>')
	

	    -- ── Footer strip: [⚙][—— minimise ——] ──
	    -- Together they span the history grid's width (x -112.5..112.5) so they line up with it:
	    --   ⚙ x -112.5..-92.5, 2px gap, minimise x -90.5..112.5; both 20 tall (were 26: room for the history name tabs)
	    table.insert(lines, '<Button id="TokenApplier_hud_minimize"')
	    table.insert(lines, '  rectAlignment="LowerCenter"')
	    table.insert(lines, '  offsetXY="11 2"')
	    table.insert(lines, '  width="203" height="20"')
	    table.insert(lines, '  onClick="' .. g .. '/hud_toggleVisible"')
	    table.insert(lines, '  ' .. btnStyle("lookNeutral") .. CUSTOM.rim())   -- rim while a backdrop is on (#100)
	    table.insert(lines, '  fontSize="9"')   -- HUD standard button text size
	    table.insert(lines, '  tooltip="Minimise HUD"')
	    table.insert(lines, '  >— minimise —</Button>')

	    -- ── Settings button (1:1 square, left end of the footer strip) ──
	    table.insert(lines, '<Button id="TokenApplier_hud_settings"')
	    table.insert(lines, '  rectAlignment="LowerCenter"')
	    table.insert(lines, '  offsetXY="-102.5 2"')
	    table.insert(lines, '  width="20" height="20"')
	    table.insert(lines, '  onClick="' .. g .. '/hud_toggleSettings"')
	    table.insert(lines, '  ' .. btnStyle(settingsOpen and HUD_SETTINGS_OPEN_STYLE or HUD_SETTINGS_CLOSED_STYLE))   -- 1.4.2 look test
	    table.insert(lines, '  fontSize="14"')
	    table.insert(lines, '  tooltip="Settings"')
		local ss = BTN_STYLE.settings
		table.insert(lines, '  ><Text id="TokenApplier_hud_settings_text" text="⚙" color="' .. ss.textColor .. '" offsetXY="0 ' .. (settingsOpen and -1 or 0) .. '" fontSize="8" width="20" height="20" horizontalOverflow="Overflow" verticalOverflow="Overflow" alignment="MiddleCenter" /></Button>')

		-- HUD layout (offsets from TokenApplier_hud_root's bottom-centre; x = button centre, y = button bottom)
		--   Token History panel   x -252..-132  y 31..146   (level with the history grid, y 31..142, beside it; gap holds the < arrow)
		--   HUD block (2×2)       x -252..-132  y 150..206  [HUD][Opaque] over [Place][Drag]   (#91 order; above Token History)
		--   Debug row             x -252..-132  y 2..28     [F][↺][ID] (22 wide, only with Debug on) [Debug] toggle x -174..-132 (#99); footer strip [⚙][minimise] x -112.5..112.5

	    -- ── HUD block: HUD on/off, Opaque, Place HUD, HUD Drag (only while settings are open) ──
	    -- 2×2 of EQUAL buttons with one font size: mixed sizes or widths look unfinished, and four
	    -- words don't fit one 120-wide row at a readable size. 2 × 58 + gap 4 = 120 (x -252..-132).
	    local ROW_FONT, ROW_GAP, ROW_W, ROW_H = 9, 4, 58, 26
	    local function hudRowBtn(id, onClick, tooltip, style, label, col, row)   -- col 0-1 left→right, row 0 = bottom
	        local s = BTN_STYLE[style]
	        local width  = ROW_W
	        local centre = -252 + col * (ROW_W + ROW_GAP) + ROW_W / 2
	        local bottom = 150 + row * (ROW_H + ROW_GAP)   -- above Token History (its top is 146)
	        return '<Button id="' .. id .. '" active="' .. (settingsOpen and "True" or "False") .. '"'
	            .. ' rectAlignment="LowerCenter" offsetXY="' .. centre .. ' ' .. bottom .. '" width="' .. width .. '" height="' .. ROW_H .. '"'
	            .. ' onClick="' .. g .. '/' .. onClick .. '" ' .. btnStyle(style) .. ' tooltip="' .. tooltip .. '">'
	            -- The Text needs the button's size AND horizontalOverflow: without them TTS wraps the word
	            -- inside its own default (narrower) box, giving "HU/D", "Opaq/ue", "Canc/el"
	            .. '<Text id="' .. id .. '_text" text="' .. label .. '" color="' .. s.textColor .. '" fontSize="' .. ROW_FONT .. '"'
	            .. ' width="' .. width .. '" height="' .. ROW_H .. '" horizontalOverflow="Overflow" alignment="MiddleCenter" /></Button>'
	    end
	    -- Reading order: top row HUD, Opaque; bottom row Place, Drag
	    table.insert(lines, hudRowBtn("TokenApplier_hud_off", "btn_toggleHUD", "Turn the HUD off (turn it back on from the Token Applier's settings)",
	        "toggleOn", "HUD", 0, 1))   -- only ever drawn while the HUD is on
	    table.insert(lines, hudRowBtn("TokenApplier_hud_opacityBtn", "btn_toggleOpacity", OPAQUE_TOOLTIP[uiOpaque],
	        uiOpaque and "toggleOn" or "toggleOff", "Opaque", 1, 1))
	    table.insert(lines, hudRowBtn("TokenApplier_hud_placeBtn", "btn_toggleHudPlacement", "Place HUD: choose a fixed position for the HUD",
	        hudPlacementMode and "toggleOn" or "settingsItem", hudPlacementMode and "Cancel" or "Place", 0, 0))
	    table.insert(lines, hudRowBtn("TokenApplier_hud_dragToggleBtn", "btn_toggleHudDraggable", "HUD Drag: allow the HUD to be dragged anywhere on screen",
	        hudDraggable and "toggleOn" or "toggleOff", "Drag", 1, 0))

	    -- ── Set Template button (independent) ──
	    table.insert(lines, '<Button id="TokenApplier_hud_setTemplate"')
	    table.insert(lines, '  active="' .. (hideSetTemplate and "False" or "True") .. '"')
	    table.insert(lines, '  rectAlignment="LowerCenter"')
	    table.insert(lines, '  offsetXY="0 190"')  -- old loaction offsetXY="-200 145"'
	    table.insert(lines, '  width="160" height="30"')
	    table.insert(lines, '  onClick="' .. g .. '/btn_setTemplate"')
	    table.insert(lines, '  ' .. btnStyle("lookTemplate") .. CUSTOM.rim())   -- rim while a backdrop is on (#100)
	    table.insert(lines, '  fontSize="14"')
	    table.insert(lines, '  tooltip="Set token template from selected object">')
	    table.insert(lines, '  <Text id="TokenApplier_hud_setTemplate_text" text="' .. xmlAttrText(hudTemplateLabel()) .. '" color="' .. BTN_STYLE.lookTemplate.textColor .. '" shadow="#000000AA" shadowDistance="1 -1" fontSize="14" resizeTextForBestFit="true" resizeTextMinSize="8" resizeTextMaxSize="14" width="160" height="30" alignment="MiddleCenter" /></Button>')   -- best fit: 2-line names shrink to fit the 30px height instead of losing line 2
		
		-- ── Size warning ──
		local warnText  = templateCache.byteSize > SIZE_MASSIVE and "⚠ Very large" or "⚠ Large object"
		local warnColor = templateCache.byteSize > SIZE_MASSIVE and "#5A1A00FF" or "#3A3A0AFF"
		local warnActive = templateCache.byteSize > SIZE_LARGE and "True" or "False"
		-- Thin strip along the TOP edge inside Add Token (y 180..191: raised 3px so it sits on Add Token's top edge, which is at 189),
		-- same width as Add Token (225). The page dots use Add Token's bottom edge.
		-- It's a non-clickable Button rather than a Panel purely to get TTS's rounded corners
		-- (Panels are always square). All 4 colour states are the same, so it never reacts;
		-- raycastTarget="false" lets clicks on it reach Add Token underneath.
		local warnColors = warnColor .. "|" .. warnColor .. "|" .. warnColor .. "|" .. warnColor
		table.insert(lines, '<Button id="TokenApplier_hud_sizeWarning"')
		table.insert(lines, '  active="' .. warnActive .. '"')
		table.insert(lines, '  rectAlignment="LowerCenter"')
		table.insert(lines, '  offsetXY="0 180"')
		table.insert(lines, '  width="225" height="11"')
		table.insert(lines, '  raycastTarget="false"')
		table.insert(lines, '  colors="' .. warnColors .. '">')
		table.insert(lines, '  <Text id="TokenApplier_hud_sizeWarningText" text="' .. warnText .. '" fontSize="8" color="#FFAA44" alignment="MiddleCenter" raycastTarget="false" />')
		table.insert(lines, '</Button>')

	    -- ── Token History panel (Edit History / Default Scale / Clear History) — left of the history grid ──
	    -- Keeps the old id "TokenApplier_hud_settingsPanel" so existing show/hide code still works.
	    -- Fixed height that fits its contents, so the layout never squashes the buttons.
	    table.insert(lines, '<Panel id="TokenApplier_hud_settingsPanel"')
	    table.insert(lines, '  active="' .. (settingsOpen and "True" or "False") .. '"')
	    table.insert(lines, '  showAnimation="Grow"')
	    table.insert(lines, '  hideAnimation="Shrink"')
	    table.insert(lines, '  animationDuration="0.1"')
	    table.insert(lines, '  rectAlignment="LowerCenter"')
	table.insert(lines, '  offsetXY="-192 29"')   -- level with the history grid (bottom 29); the 2×2 HUD block sits above
	    table.insert(lines, '  width="120" height="115"') 	-- 4 pad + title 14 + 3 rows × 28 + 3 gaps × 3 + 4 pad
		table.insert(lines, '  color="#00000000">')   -- see-through: the rounded background below does the colour
		table.insert(lines, '  ' .. roundedPanelBg(120, 115, op(SETTINGS_PANEL_COLOR), CUSTOM.panelRimColor()))   -- 1.4.2 look test
	    table.insert(lines, '  <VerticalLayout spacing="3" padding="4 4 4 4" childAlignment="UpperCenter" childForceExpandHeight="false">')
	    table.insert(lines, '    <Text text="Token History" color="' .. SETTINGS_TITLE_COLOR .. '" fontSize="10" fontStyle="Bold" alignment="MiddleCenter" preferredWidth="112" preferredHeight="14" />')
		-- Default scale adjust (first, under the title)
		-- Stepper layout: label on the left (wraps to 2 lines), [–][+] side by side on the right
		table.insert(lines, '    <HorizontalLayout spacing="2" childAlignment="MiddleCenter" preferredHeight="28">')
		table.insert(lines, '      <Text id="TokenApplier_hud_defaultScaleLabel" text="Default Scale: ' .. string.format("%.1f", defaultScaleOffset) .. '" color="#FFFFFF" resizeTextForBestFit="true" resizeTextMinSize="6" resizeTextMaxSize="10" alignment="MiddleLeft" preferredWidth="52" preferredHeight="28" />')
		table.insert(lines, '      <Button onClick="' .. g .. '/btn_defaultScaleDown"')
		table.insert(lines, '        ' .. btnStyle("settingsItem"))
		table.insert(lines, '        tooltip="Decrease default spawn scale"')
		table.insert(lines, '        fontSize="16" preferredWidth="28" preferredHeight="28">–</Button>')
		table.insert(lines, '      <Button onClick="' .. g .. '/btn_defaultScaleUp"')
		table.insert(lines, '        ' .. btnStyle("settingsItem"))
		table.insert(lines, '        tooltip="Increase default spawn scale"')
		table.insert(lines, '        fontSize="16" preferredWidth="28" preferredHeight="28">+</Button>')
		table.insert(lines, '    </HorizontalLayout>')
	    -- Edit History: double height, filling the space Clear History uses. In edit mode it shrinks to one row
	    -- ("←Stop Editing History") and Clear History appears under it: one button splits into two (setHistoryEditMode)
	    local heStyle = historyEditMode and EDIT_ON_STYLE or EDIT_OFF_STYLE
	    table.insert(lines, '    <Button id="TokenApplier_hud_editHistoryBtn" onClick="' .. g .. '/btn_toggleHistoryEdit"')
	    table.insert(lines, '      ' .. btnStyle(heStyle))
	    table.insert(lines, '      preferredWidth="112" preferredHeight="' .. (historyEditMode and HIST_LOOK.editH.hudShort or HIST_LOOK.editH.hudTall) .. '"')
	    table.insert(lines, '      tooltip="Delete History: click slots to remove them">')
	    table.insert(lines, '      <Text id="TokenApplier_hud_editHistoryBtn_text" offsetXY="0 ' .. (historyEditMode and -1 or 0) .. '" text="' .. (historyEditMode and HUD_EDIT_ON_LABEL or HUD_EDIT_OFF_LABEL) .. '" color="' .. BTN_STYLE[heStyle].textColor .. '" fontSize="9" width="112" height="28" horizontalOverflow="Overflow" alignment="MiddleCenter" /></Button>')
	    -- Clear History: last, only while Edit History is live; two-click confirm (see btn_clearHistory)
	    table.insert(lines, '    <Button id="TokenApplier_hud_clearHistoryBtn" onClick="' .. g .. '/btn_clearHistory"')
	    table.insert(lines, '      ' .. btnStyle(CLEAR_HISTORY_STYLE))
	    table.insert(lines, '      preferredWidth="112" preferredHeight="28"')
	    table.insert(lines, '      active="' .. (historyEditMode and "True" or "False") .. '"')
	    table.insert(lines, '      tooltip="Clear all token history and reset template (click twice to confirm)">')
	    table.insert(lines, '      <Text id="TokenApplier_hud_clearHistoryBtn_text" text="' .. HUD_CLEAR_LABEL .. '" color="' .. BTN_STYLE[CLEAR_HISTORY_STYLE].textColor .. '" fontSize="9" width="112" height="28" horizontalOverflow="Overflow" alignment="MiddleCenter" /></Button>')
	    -- Row 3: Move History (#104). Steps aside for Clear All History in delete mode (setHistoryEditMode).
	    -- Built as "pressed" when Move mode is on (a rebuild keeps the mode).
	    local mvStyle = MOVE.on and "pressed" or "settingsItem"
	    table.insert(lines, '    <Button id="TokenApplier_hud_moveHistoryBtn" onClick="' .. g .. '/btn_toggleHistoryMove" ' .. btnStyle(mvStyle)
	        .. ' preferredWidth="112" preferredHeight="' .. HIST_LOOK.editH.hudShort .. '" active="' .. (historyEditMode and "False" or "True") .. '"'
	        .. ' tooltip="Move History: click a slot, then another, to swap them">')
	    table.insert(lines, '      <Text id="TokenApplier_hud_moveHistoryBtn_text" offsetXY="0 ' .. (MOVE.on and -1 or 0) .. '" text="' .. MOVE_LABEL[MOVE.on] .. '" color="' .. BTN_STYLE[mvStyle].textColor .. '" fontSize="9" width="112" height="28" horizontalOverflow="Overflow" alignment="MiddleCenter" /></Button>')
	    table.insert(lines, '  </VerticalLayout>')
	    table.insert(lines, '</Panel><!--TokenApplier_hud_settingsPanel-->') -- end TokenApplier_hud_settingsPanel

	    -- ── Restore-Token(s) position button ──
	    table.insert(lines, '<Button id="TokenApplier_hud_restore_tokens"')
	    table.insert(lines, '  active="' .. ((settingsOpen and debugOpen) and "True" or "False") .. '"')
	    table.insert(lines, '  rectAlignment="LowerCenter"')
	    table.insert(lines, '  offsetXY="-215 2"')
	    table.insert(lines, '  width="22" height="26"')
	    table.insert(lines, '  onClick="' .. g .. '/btn_restoreTokens"')
	    table.insert(lines, '  ' .. btnStyle("debug"))
	    table.insert(lines, '  fontSize="10"')
	    table.insert(lines, '  tooltip="Restore tokens after save/load if any are missing"')
	    table.insert(lines, '  >↺</Button>')

	    -- ── Find Tokens button (adopt tokens from a deleted/old Applier) ──
	    table.insert(lines, '<Button id="TokenApplier_hud_find_tokens"')
	    table.insert(lines, '  active="' .. ((settingsOpen and debugOpen) and "True" or "False") .. '"')
	    table.insert(lines, '  rectAlignment="LowerCenter"')
	    table.insert(lines, '  offsetXY="-241 2"')
	    table.insert(lines, '  width="22" height="26"')
	    table.insert(lines, '  onClick="' .. g .. '/btn_findTokens"')
	    table.insert(lines, '  ' .. btnStyle("debug"))
	    table.insert(lines, '  fontSize="10"')
	    table.insert(lines, '  tooltip="Find Tokens: adopt tokens left behind by a deleted or old Token Applier"')
	    table.insert(lines, '  >F</Button>')

	    -- ── Debug IDs button (prints the hover-token table to the console) — in the slot the HUD button used ──
	    table.insert(lines, '<Button id="TokenApplier_hud_debug_ids"')
	    table.insert(lines, '  active="' .. ((settingsOpen and debugOpen) and "True" or "False") .. '"')
	    table.insert(lines, '  rectAlignment="LowerCenter"')
	    table.insert(lines, '  offsetXY="-189 2"')
	    table.insert(lines, '  width="22" height="26"')
	    table.insert(lines, '  onClick="' .. g .. '/btn_debug"')
	    table.insert(lines, '  ' .. btnStyle("debug"))
	    table.insert(lines, '  fontSize="10"')
	    table.insert(lines, '  tooltip="Debug IDs: print the hover-token table to the console"')
	    table.insert(lines, '  >ID</Button>')

	    -- ── Debug toggle (#99): right end of the bottom row, right edge in line with Token History (x -132) ──
	    local hDbgStyle = debugOpen and "pressed" or "debug"   -- pressed in while the debug buttons show
	    table.insert(lines, '<Button id="TokenApplier_hud_debugToggle"')
	    table.insert(lines, '  active="' .. (settingsOpen and "True" or "False") .. '"')
	    table.insert(lines, '  rectAlignment="LowerCenter" offsetXY="-153 2" width="42" height="26"')
	    table.insert(lines, '  onClick="' .. g .. '/btn_toggleDebug"')
	    table.insert(lines, '  ' .. btnStyle(hDbgStyle))
	    table.insert(lines, '  fontSize="9"')
	    table.insert(lines, '  tooltip="' .. (debugOpen and "Debug: ON. Click to hide the debug buttons" or "Debug: OFF. Click to show the debug buttons") .. '">')
	    table.insert(lines, '  <Text id="TokenApplier_hud_debugToggle_text" text="Debug" color="' .. BTN_STYLE[hDbgStyle].textColor .. '" offsetXY="0 ' .. (debugOpen and -1 or 0) .. '" fontSize="9" width="42" height="26" horizontalOverflow="Overflow" alignment="MiddleCenter" /></Button>')

	    -- ── Customise (1.4.3): button right above the Token History panel; its panel opens above that ──
	    --   Customise button  x -252..-132  y 210..236        Customise panel  x -252..-132  y 240..356 (CUSTOM.hudPanelH)
	    local hCusStyle = CUSTOM.open and "pressed" or "settingsItem"   -- pressed in while its panel is open
	    table.insert(lines, '<Button id="TokenApplier_hud_customiseToggle"')
	    table.insert(lines, '  active="' .. (settingsOpen and "True" or "False") .. '"')
	    table.insert(lines, '  rectAlignment="LowerCenter" offsetXY="-192 210" width="120" height="26"')
	    table.insert(lines, '  onClick="' .. g .. '/btn_toggleCustomise" ' .. btnStyle(hCusStyle) .. ' fontSize="9"')
	    table.insert(lines, '  tooltip="Customise: look and feel options (selection colour, ...)">')
	    table.insert(lines, '  <Text id="TokenApplier_hud_customiseToggle_text" text="Customise" color="' .. BTN_STYLE[hCusStyle].textColor .. '" offsetXY="0 ' .. (CUSTOM.open and -1 or 0) .. '" fontSize="9" width="120" height="26" horizontalOverflow="Overflow" alignment="MiddleCenter" /></Button>')

	    table.insert(lines, '<Panel id="TokenApplier_hud_customisePanel"')
	    table.insert(lines, '  active="' .. ((settingsOpen and CUSTOM.open) and "True" or "False") .. '"')
	    table.insert(lines, '  rectAlignment="LowerCenter" offsetXY="-192 240" width="120" height="' .. CUSTOM.hudPanelH .. '" color="#00000000">')
	    table.insert(lines, '  ' .. roundedPanelBg(120, CUSTOM.hudPanelH, op(SETTINGS_PANEL_COLOR), CUSTOM.panelRimColor()))
	    table.insert(lines, '  <VerticalLayout spacing="4" padding="2 2 2 4" childAlignment="UpperCenter" childForceExpandHeight="false">')
	    table.insert(lines, '    <Text text="Selection colour" color="' .. SETTINGS_TITLE_COLOR .. '" fontSize="10" fontStyle="Bold" alignment="MiddleCenter" preferredWidth="116" preferredHeight="12" />')
	    table.insert(lines, '    <GridLayout cellSize="16 16" spacing="4 4" startCorner="UpperLeft" startAxis="Horizontal" childAlignment="UpperLeft" preferredWidth="116" preferredHeight="36">')
	    for i = 1, #CUSTOM.presets do
	        table.insert(lines, '      ' .. CUSTOM.swatchXml('TokenApplier_hud_selColor_' .. i, g .. '/btn_selectColorPreset', i, 'width="16" height="16"', "1 1"))
	    end
	    table.insert(lines, '    </GridLayout>')
	    table.insert(lines, '    <HorizontalLayout spacing="4" childAlignment="MiddleCenter" childForceExpandWidth="false" preferredHeight="26">')   -- 26: an InputField keeps ~13px padding; at 22 its text was cut off
	    table.insert(lines, '      <InputField id="TokenApplier_hud_selColorHex" onEndEdit="' .. g .. '/btn_selectColorHex" text="' .. CUSTOM.selectColor .. '"'
	        .. ' characterLimit="7" fontSize="9" color="#FFFFFF" textColor="#10141E" placeholder="#15AFCC"'
	        .. ' tooltip="Type a colour as a hex code (e.g. #15AFCC), then press Enter" preferredWidth="62" preferredHeight="26" />')
	    table.insert(lines, '      <Button onClick="' .. g .. '/btn_selectColorReset" ' .. btnStyle("settingsItem") .. ' fontSize="9" tooltip="Back to the default cyan" preferredWidth="50" preferredHeight="26">'
	        .. '<Text text="Reset" color="' .. BTN_STYLE.settingsItem.textColor .. '" fontSize="9" width="50" height="26" alignment="MiddleCenter" /></Button>')
	    table.insert(lines, '    </HorizontalLayout>')
	    -- Backgrounds row (#100): label + one button that cycles 0% / 50% / 100%
	    table.insert(lines, '    <HorizontalLayout spacing="4" childAlignment="MiddleCenter" childForceExpandWidth="false" preferredHeight="22">')
	    table.insert(lines, '      <Text text="Background" color="' .. SETTINGS_TITLE_COLOR .. '" fontSize="9" fontStyle="Bold" alignment="MiddleLeft" preferredWidth="62" preferredHeight="22" />')
	    table.insert(lines, '      <Button onClick="' .. g .. '/btn_cycleBackground" ' .. btnStyle("settingsItem") .. ' fontSize="9" tooltip="Fill the see-through gaps behind the HUD: 0% / 50% / 100% (click to cycle)" preferredWidth="50" preferredHeight="22">'
	        .. '<Text text="' .. CUSTOM.bgLevels[CUSTOM.bg].label .. '" color="' .. BTN_STYLE.settingsItem.textColor .. '" fontSize="9" width="50" height="22" alignment="MiddleCenter" /></Button>')
	    table.insert(lines, '    </HorizontalLayout>')
	    table.insert(lines, '  </VerticalLayout>')
	    table.insert(lines, '</Panel><!--TokenApplier_hud_customisePanel-->')

	    -- ── Set Template button visibility toggle ──
	    table.insert(lines, '<Button id="TokenApplier_hud_templateVis"')
	    table.insert(lines, '  active="' .. (settingsOpen and "True" or "False") .. '"')
	    table.insert(lines, '  rectAlignment="LowerCenter"')
	    table.insert(lines, '  offsetXY="-103 196"')	-- 18×18 (was 30): left edge on Add Token's (x -112), centred on Set Template's height (190..220)
	    table.insert(lines, '  width="18" height="18"')
	    table.insert(lines, '  onClick="' .. g .. '/btn_toggleSetTemplate"')
	    table.insert(lines, '  ' .. btnStyle(hideSetTemplate and "toggleOff" or "toggleOn"))
	    table.insert(lines, '  fontSize="8"')
	    table.insert(lines, '  tooltip="Token Creation: show or hide the Set Template button (O = hidden, I = visible)"')
	    local tvStyle = BTN_STYLE[hideSetTemplate and "toggleOff" or "toggleOn"]
		table.insert(lines, '  ><Text id="TokenApplier_hud_templateVis_text" text="' .. (hideSetTemplate and "O" or "I") .. '" color="' .. tvStyle.textColor .. '" fontSize="8" width="18" height="18" alignment="MiddleCenter" /></Button>')

	    

	-- ── HUD Dynamic panel ──
		-- Measurements live in HUD_DYN (shared with refreshDynamicPanelSlots). Layout, panel y up from root bottom:
		--   modifier grid rows 0-2   y 192..64      token names + ✕   top y 192, one row per token
		--   divider line             y 46           Remove All bar    right under the last token row
		--   Line up strip            y 2..28 (same bottom line and height as the minimise strip)
		local HPAD  = HUD_DYN.pad
		local HBW   = HUD_DYN.bw
		local HGAP  = HUD_DYN.gap
		local HSTEP = HBW + HGAP  -- 44 — used for mod grid layout only

		local HSH   = HUD_DYN.sh
		local HSW   = HUD_DYN.sw
		local HRW   = HUD_DYN.rw   -- ✕ buttons: square (#96)
		local HSGAP = HUD_DYN.sgap

		local function hcol(c) return HPAD + c * HSTEP end
		local function hrow(r) return -(HPAD + r * HSTEP) end

		local function hmbtn(id, onClick, tooltip, style, fontSize, label, c, r, extra)
			local idA = id and ('id="' .. id .. '" ') or ""
			local exA = extra or ""
			local s   = BTN_STYLE[style] or BTN_STYLE.ghost
			return '  <Button ' .. idA
				.. 'onClick="' .. g .. '/' .. onClick .. '" '
				.. 'tooltip="' .. tooltip .. '" '
				.. btnStyle(style) .. ' '
				.. 'width="' .. HBW .. '" height="' .. HBW .. '" '
				.. 'fontSize="' .. fontSize .. '" '
				.. 'rectAlignment="UpperLeft" '
				.. 'offsetXY="' .. hcol(c) .. ' ' .. hrow(r) .. '" '
				.. exA .. CUSTOM.rim() .. '>'   -- rim only while a backdrop is on (#100)
				.. '<Text text="' .. label .. '" color="' .. s.textColor .. '" fontSize="' .. fontSize .. '" width="' .. HBW .. '" height="' .. HBW .. '" alignment="MiddleCenter" />'
				.. '</Button>'
		end

		-- Panel: 200 tall (modifier grid + Line up), 424 wide (grid + token list + padding)
		local HDYN_H = HUD_DYN.panelH
		local HDYN_W = HUD_DYN.slotX + HUD_DYN.listW + HPAD

		table.insert(lines, '<Panel id="TokenApplier_hud_dynPanel"')
		table.insert(lines, '  showAnimation="Grow"')
		table.insert(lines, '  hideAnimation="Shrink"')
		table.insert(lines, '  animationDuration="0.1"')
		table.insert(lines, '  active="False"')
		table.insert(lines, '  rectAlignment="LowerCenter"')
		table.insert(lines, '  offsetXY="' .. (128 + HDYN_W/2) .. ' 0"')
		table.insert(lines, '  width="' .. HDYN_W .. '" height="' .. HDYN_H .. '"')
		table.insert(lines, '  color="#00000000">')
		-- Backgrounds (#100): first child, so it opens/closes with the panel and sits behind its buttons
		-- Content sits HPAD inside the panel on every side except the bottom (Line up at y 2), so:
		-- width = panel − 2 × (HPAD − margin), from y 2 − margin up to (panel top − HPAD) + margin.
		-- Margin + the rim's width (CUSTOM.bgPad), like the other backdrops.
		local dynM = CUSTOM.bgPad()
		table.insert(lines, '  ' .. CUSTOM.bgXml("TokenApplier_hud_dynBg", "LowerCenter", 0, 2 - dynM,
			HDYN_W - 2 * (HPAD - dynM), (HDYN_H - HPAD + dynM) - (2 - dynM)))

		-- Mod grid — rows 0-2, cols 0-3
		-- Row 0: [lineForward] [•] [Flip] [↕]
		table.insert(lines, hmbtn(nil,                  "btn_lineForward",  "Move forward (Z)", "dynMod",      "18", "↑",    0, 0))
		table.insert(lines, hmbtn(nil,                  "btn_scaleUp",      "Scale up",         "dynGreenBtn", "18", "•",    1, 0))
		table.insert(lines, hmbtn(nil,                  "btn_flip",      "Flip token",      "dynMod",      "16", "Flip", 2, 0))
		table.insert(lines, hmbtn(nil,                  "btn_vertical",  "Toggle vertical", "dynMod",      "18", "↕",    3, 0))
		-- Row 1: [⁘] [▲] [▼] [⁛]
		table.insert(lines, hmbtn("TokenApplier_hud_dynSpreadDown","btn_radiusDown","Decrease spread", "dynRedBtn",   "18", "⁘",    0, 1, 'active="False"'))
		table.insert(lines, hmbtn(nil,                  "btn_heightUp",  "Raise height",    "dynMod",      "18", "▲",    1, 1))
		table.insert(lines, hmbtn(nil,                  "btn_heightDown","Lower height",     "dynMod",      "18", "▼",    2, 1))
		table.insert(lines, hmbtn("TokenApplier_hud_dynSpreadUp", "btn_radiusUp",  "Increase spread", "dynGreenBtn", "18", "⁛",    3, 1, 'active="False"'))
		-- Row 2: [lineBackward] [·] [↻] [  ]
		table.insert(lines, hmbtn(nil,                  "btn_lineBackward", "Move backward (Z)", "dynMod",    "18", "↓",    0, 2))
		table.insert(lines, hmbtn(nil,                  "btn_scaleDown",    "Scale down",        "dynRedBtn", "18", "·",    1, 2))
		table.insert(lines, hmbtn(nil,                  "btn_rotate",       "Rotate 180°",       "dynMod",    "18", "↻",    2, 2))

		-- Divider between the modifier grid and the Line up strip (#96). Not clickable.
		local LINEUP_H = 20   -- same height as the minimise strip
		-- A dark 1px line right under the light one acts as its shadow, so it shows on light and dark tables
		-- (Panels ignore the shadow attribute, like they ignore outline).
		table.insert(lines, '  <Panel width="' .. HUD_DYN.gridW .. '" height="1" color="#8A96B0CC" raycastTarget="false"'
			.. ' rectAlignment="UpperLeft" offsetXY="' .. hcol(0) .. ' ' .. -(HDYN_H - 46) .. '" />')
		table.insert(lines, '  <Panel width="' .. HUD_DYN.gridW .. '" height="1" color="#000000AA" raycastTarget="false"'
			.. ' rectAlignment="UpperLeft" offsetXY="' .. hcol(0) .. ' ' .. -(HDYN_H - 45) .. '" />')

		-- Line up strip: as wide as the modifier grid, sitting on the same bottom line as minimise (y 2)
		local isLineUp  = modelLineUp[lastSelectedGUID or ""] or false
		table.insert(lines, '  <Button id="TokenApplier_hud_dynLineUpToggle" '
			.. 'onClick="' .. g .. '/btn_toggleModelLineUp" '
			.. 'tooltip="Toggle line-up mode" '
			.. btnStyle(LINEUP.style) .. CUSTOM.rim() .. ' '
			.. 'width="' .. HUD_DYN.gridW .. '" height="' .. LINEUP_H .. '" '
			.. 'fontSize="12" '
			.. 'rectAlignment="UpperLeft" '
			.. 'offsetXY="' .. hcol(0) .. ' ' .. -(HDYN_H - 2 - LINEUP_H) .. '">'
			.. '<Text id="TokenApplier_hud_dynLineUpToggle_text" text="' .. LINEUP.hud[isLineUp] .. '" color="' .. BTN_STYLE[LINEUP.style].textColor .. '" fontSize="12" width="' .. HUD_DYN.gridW .. '" height="' .. LINEUP_H .. '" alignment="MiddleCenter" />'
			.. '</Button>')

		-- Remove All Tokens: a short, wide bar right under the token names (what it removes). Its y is
		-- moved under the last token row by refreshDynamicPanelSlots; built under row 1 as a placeholder.
		-- Two-click safeguard: first click arms it, second click removes (see hud_removeTokens)
		table.insert(lines, '  <Button id="TokenApplier_hud_dynRemoveAll" '
			.. 'onClick="' .. g .. '/hud_removeTokens" '
			.. 'tooltip="Remove ALL tokens from the selected model (click twice to confirm)" '
			.. btnStyle(REMOVE_ALL_STYLE) .. ' '
			.. 'width="' .. HUD_DYN.listW .. '" height="' .. HUD_DYN.remH .. '" '
			.. 'rectAlignment="UpperLeft" '
			.. 'offsetXY="' .. HUD_DYN.slotX .. ' ' .. HUD_DYN.removeAllY(1) .. '">'
			.. '<Text id="TokenApplier_hud_dynRemoveAll_text" text="' .. REMOVE_ALL_LABEL .. '" color="' .. BTN_STYLE[REMOVE_ALL_STYLE].textColor .. '" '
			.. 'fontSize="10" '
			.. 'width="' .. HUD_DYN.listW .. '" height="' .. HUD_DYN.remH .. '" alignment="MiddleCenter" />'
			.. '</Button>')

		-- Slot section — to the right of mod grid
		local slotX = HUD_DYN.slotX
		

		for i = 1, MAX_TOKENS do
			local yOffset = -(HPAD + (i - 1) * (HSH + HSGAP))
			-- Name button
			table.insert(lines, '  <Button id="TokenApplier_hud_dynSlot_' .. i .. '"')
			table.insert(lines, '    onClick="' .. g .. '/btn_select_' .. i .. '"')
			table.insert(lines, '    ' .. btnStyle("dynSlot") .. CUSTOM.rim())
			table.insert(lines, '    active="False"')
			table.insert(lines, '    tooltip="Click to select token"')
			table.insert(lines, '    width="' .. HSW .. '" height="' .. HSH .. '"')
			table.insert(lines, '    rectAlignment="UpperLeft"')
			table.insert(lines, '    offsetXY="' .. slotX .. ' ' .. yOffset .. '"')
			table.insert(lines, '    fontSize="' .. DYN_SLOT.hudFont .. '">')
			-- Token picture (left, inside the button) + left-aligned name; filled by DYN_SLOT.paint (#97)
			table.insert(lines, '    <Image id="TokenApplier_hud_dynSlot_' .. i .. '_img" image="" width="' .. DYN_SLOT.hudImg .. '" height="' .. DYN_SLOT.hudImg .. '"'
				.. ' rectAlignment="MiddleLeft" offsetXY="3 0" preserveAspect="true" raycastTarget="false" active="False" />')
			table.insert(lines, '    <Text id="TokenApplier_hud_dynSlot_' .. i .. '_text" text="–" color="' .. BTN_STYLE.dynSlot.textColor .. '" fontSize="' .. DYN_SLOT.hudFont .. '"'
				.. ' width="' .. DYN_SLOT.hudTextW .. '" height="' .. HSH .. '" rectAlignment="MiddleLeft" offsetXY="' .. DYN_SLOT.hudTextX .. ' 0"'
				.. ' alignment="MiddleLeft" horizontalOverflow="Overflow" shadow="' .. DYN_SLOT.shadowOff .. '" shadowDistance="1 -1" raycastTarget="false" />')
			table.insert(lines, '  </Button>')
			-- Remove button
			table.insert(lines, '  <Button id="TokenApplier_hud_dynRemove_' .. i .. '"')
			table.insert(lines, '    onClick="' .. g .. '/btn_remove_' .. i .. '"')
			table.insert(lines, '    ' .. btnStyle("dynRemove") .. CUSTOM.rim())
			table.insert(lines, '    active="False"')
			table.insert(lines, '    tooltip="Remove token"')
			table.insert(lines, '    width="' .. HRW .. '" height="' .. HSH .. '"')
			table.insert(lines, '    rectAlignment="UpperLeft"')
			table.insert(lines, '    offsetXY="' .. (slotX + HSW + HGAP) .. ' ' .. yOffset .. '"')
			table.insert(lines, '    fontSize="14"><Text text="✕" color="#FFFFFF" fontSize="14" width="' .. HRW .. '" height="' .. HSH .. '" alignment="MiddleCenter" /></Button>')
		end

				table.insert(lines, '</Panel><!--TokenApplier_hud_dynPanel-->') -- end TokenApplier_hud_dynPanel

			table.insert(lines, '</Panel><!--TokenApplier_hud_root-->') -- end TokenApplier_hud_root
			
		-- ── Minimised-restore button ──
		table.insert(lines, '<Button id="TokenApplier_hud_restore"')
	    table.insert(lines, '  active="' .. (not hudVisible and "True" or "False") .. '"')
	    table.insert(lines, '  rectAlignment="LowerCenter"')
	    table.insert(lines, '  offsetXY="' .. hudRootOffsetXY .. '"')
	    table.insert(lines, '  width="120" height="26"')
	    table.insert(lines, '  onClick="' .. g .. '/hud_toggleVisible"')
	    table.insert(lines, '  ' .. btnStyle("hudAdd"))
	    table.insert(lines, '  fontSize="12"')
	    table.insert(lines, '  tooltip="Show Token Applier HUD"')
	    table.insert(lines, '  >Token Applier</Button>')

		-- ── Placement overlay ──
		table.insert(lines, '<Panel id="TokenApplier_hud_placementOverlay"')
		table.insert(lines, '  active="' .. (hudPlacementMode and "True" or "False") .. '"')
		table.insert(lines, '  rectAlignment="MiddleCenter"')
		table.insert(lines, '  offsetXY="0 0"')
		table.insert(lines, '  width="1920" height="1080"')
		table.insert(lines, '  color="#000000F2">')

		for _, pos in ipairs(HUD_POSITIONS) do
			if pos.hudXY ~= hudRootOffsetXY then
				table.insert(lines, '  <Button')
				table.insert(lines, '    onClick="' .. g .. '/hud_pos_' .. pos.id .. '"')
				table.insert(lines, '    ' .. btnStyle("hudPosition"))
				table.insert(lines, '    rectAlignment="MiddleCenter"')
				table.insert(lines, '    offsetXY="' .. pos.btnXY .. '"')
				table.insert(lines, '    width="60" height="60"')
				table.insert(lines, '    fontSize="30"')
				table.insert(lines, '    tooltip="Move HUD here">')
				table.insert(lines, '    <Text text="+" color="' .. BTN_STYLE.hudPosition.textColor .. '" fontSize="30" width="60" height="60" alignment="MiddleCenter" /></Button>')
			end
		end

		-- Big Cancel at the bottom centre: the small HUD "Cancel" is hard to spot under the dark overlay.
	-- Same handler as the HUD button (toggling placement off).
	table.insert(lines, '  <Button onClick="' .. g .. '/btn_toggleHudPlacement" ' .. btnStyle("lookNeutral")
		.. ' rectAlignment="MiddleCenter" offsetXY="0 -420" width="220" height="56" fontSize="24" tooltip="Keep the HUD where it is">'
		.. '<Text text="Cancel" color="' .. BTN_STYLE.lookNeutral.textColor .. '" fontSize="24" width="220" height="56" alignment="MiddleCenter" /></Button>')

	table.insert(lines, '</Panel><!--TokenApplier_hud_placementOverlay-->') -- end TokenApplier_hud_placementOverlay
		
	    return table.concat(lines, "\n")
	end

	-- ── Sharing the screen UI with other mods (1.4) ──
	-- The Global (screen) UI is shared by the table and every mod on it, so we never replace it.
	-- Each rebuild: read what's there, drop only OUR old pieces (ids starting HUD_PREFIX),
	-- turn the rest back into XML, add our fresh HUD on the end, and write it all back.
	-- getXmlTable returns the LIVE values (tested on LCT), so other mods keep their current state.
	local HUD_PREFIX  = "TokenApplier_hud"
	local HUD_ROOT_ID = "TokenApplier_hud_root"

	-- Is our HUD on the screen UI right now? (getAttribute on a missing id returns nil, no error)
	local function hudIsOnScreen()
		return UI.getAttribute(HUD_ROOT_ID, "id") ~= nil
	end

	local function isOurElement(el)
		local id = el.attributes and el.attributes.id
		return type(id) == "string" and id:sub(1, #HUD_PREFIX) == HUD_PREFIX
	end

	-- The same list with every TA element removed, at any depth
	local function withoutOurElements(elements)
		local kept = {}
		for _, el in ipairs(elements or {}) do
			if not isOurElement(el) then
				el.children = withoutOurElements(el.children)
				table.insert(kept, el)
			end
		end
		return kept
	end

	-- Another mod's <Defaults> block applies to EVERY element in the shared screen UI, ours too
	-- (LCT's makes all Buttons and Texts bold, and Texts size 100 / black). So any of our Buttons
	-- and Texts that don't set these themselves get TTS's normal values written in explicitly.
	local DEFAULTS_GUARD = { fontStyle = "Normal", fontSize = "14" }
	local function guardAgainstOtherDefaults(xml)
		return (xml:gsub("<(%a+)([^>]*)>", function(tag, attrs)
			if tag ~= "Button" and tag ~= "Text" then return nil end   -- nil = leave as it is
			local extra = ""
			for name, value in pairs(DEFAULTS_GUARD) do
				if not attrs:find("%s" .. name .. '="') then
					extra = extra .. " " .. name .. '="' .. value .. '"'
				end
			end
			return "<" .. tag .. extra .. attrs .. ">"
		end))
	end

	-- Table form (from UI.getXmlTable) back into XML text, added to `out`
	local function elementsToXml(elements, out)
		for _, el in ipairs(elements or {}) do
			local open = { "<" .. el.tag }
			for name, value in pairs(el.attributes or {}) do
				table.insert(open, ' ' .. name .. '="' .. xmlEscape(value) .. '"')
			end
			table.insert(out, table.concat(open) .. ">")
			if el.value and el.value ~= "" then table.insert(out, xmlEscape(el.value)) end
			elementsToXml(el.children, out)
			table.insert(out, "</" .. el.tag .. ">")
		end
		return out
	end

	-- HUD debug report (1.4 testing on LCT): what we read before the FIRST rebuild of this load,
	-- and what's on screen once our write lands. Switch HUD_DEBUG to true to turn it back on.
	local HUD_DEBUG = false
	local debugReportDone = false
	local function attrsText(el)
		local parts = {}
		for name, value in pairs(el.attributes or {}) do table.insert(parts, name .. "=" .. tostring(value)) end
		table.sort(parts)
		return table.concat(parts, "  ")
	end
	local function debugFind(elements, id)
		for _, el in ipairs(elements or {}) do
			if el.attributes and el.attributes.id == id then return el end
			local found = debugFind(el.children, id)
			if found then return found end
		end
	end
	local function debugReport(ui, stage)
		local main = debugFind(ui, "main")
		print("[HUD 1.4 debug] " .. stage .. "  main: " .. (main and attrsText(main) or "NOT FOUND"))
		print("[HUD 1.4 debug]   main getAttribute active=" .. tostring(UI.getAttribute("main", "active")))
		for _, p in ipairs(Player.getPlayers()) do
			print("[HUD 1.4 debug]   player " .. p.steam_name .. "  colour=" .. tostring(p.color) .. "  team=" .. tostring(p.team))
		end
		if stage ~= "BEFORE write" then return end
		for _, el in ipairs(ui) do
			if el.tag == "Defaults" then
				for _, d in ipairs(el.children or {}) do
					print("[HUD 1.4 debug]   Defaults <" .. tostring(d.tag) .. ">  " .. attrsText(d))
				end
			end
		end
	end

	rebuildHUD = function()
		if hudRebuildPending then return end
		hudRebuildPending = true
		Wait.time(function()
			-- Wait out any UI write still being applied (ours or another mod's): until it lands,
			-- getXmlTable returns the OLD UI and we'd write stale pieces back
			Wait.condition(function()
				hudRebuildPending = false
				-- HUD: OFF: don't touch the screen UI at all. The one exception is when our HUD
				-- is still on it (the setting was just switched on): one last write takes it out.
				if hudOff and not hudIsOnScreen() then return end
				local guid   = self.getGUID()
				local others = withoutOurElements(UI.getXmlTable())
				local ours   = hudOff and "" or guardAgainstOtherDefaults(buildHUDXml(guid))
				local xml    = table.concat(elementsToXml(others, {}), "\n") .. "\n" .. ours
				if HUD_DEBUG then print("[HUD 1.4 test] kept " .. #others .. " other top-level UI element(s)") end
				if HUD_DEBUG and not debugReportDone then
					debugReportDone = true
					debugReport(others, "BEFORE write")
					Wait.time(function()
						Wait.condition(function() debugReport(UI.getXmlTable(), "AFTER write (1s)") end,
							function() return not UI.loading end)
					end, 1)
				end
				UI.setXml(xml)
				if hudOff then return end
				if not hudVisible then
					UI.hide("TokenApplier_hud_root")
					UI.hide("TokenApplier_hud_sizeWarning")
					UI.show("TokenApplier_hud_restore")
				end
				-- The fresh HUD starts with the dynamic panel closed; clear the flags so the
				-- selection loop re-opens it on its next tick if a model with tokens is selected
				dynPanelVisible  = false
				lastSelectedGUID = nil
			end, function() return not UI.loading end)
		end, 0.1)
	end

	-- ── HUD self-repair (1.4) ──
	-- If another script rewrites the screen UI without our HUD in it, put it back (the merge keeps theirs).
	-- A cheap check every HUD_WATCH_INTERVAL seconds. If something wipes us again and again
	-- (HUD_REPAIR_LIMIT times inside HUD_REPAIR_WINDOW seconds), stop for this session rather than
	-- fight it: HUD: OFF (saved with the object) is the fix for that table.
	local HUD_WATCH_INTERVAL = 3
	local HUD_REPAIR_LIMIT   = 3
	local HUD_REPAIR_WINDOW  = 60
	local hudRepairTimes     = {}   -- os.time() of each recent repair

	local function startHudWatch()
		local watchId
		watchId = Wait.time(function()
			if applierDestroyed then Wait.stop(watchId) return end
			if hudOff or hudRebuildPending or UI.loading or hudIsOnScreen() then return end

			local now, recent = os.time(), {}
			for _, t in ipairs(hudRepairTimes) do
				if now - t < HUD_REPAIR_WINDOW then table.insert(recent, t) end
			end
			hudRepairTimes = recent
			if #hudRepairTimes >= HUD_REPAIR_LIMIT then
				if HUD_DEBUG then print("[HUD 1.4 test] HUD keeps being removed by another script; self-repair stopped") end
				Wait.stop(watchId)
				return
			end
			table.insert(hudRepairTimes, now)
			if HUD_DEBUG then print("[HUD 1.4 test] HUD missing from the screen UI; putting it back") end
			rebuildHUD()
		end, HUD_WATCH_INTERVAL, -1)
	end

-- ──────────────────────────────────────────────────────────────
--  BUTTON LABEL HELPERS
-- ──────────────────────────────────────────────────────────────

	-- Updates the Set Template label on BOTH the OUI and the HUD. Every path that changes the
	-- template calls this (set, drop, history pick, delete, clear), so the two can't drift.
	-- The HUD label lives on a <Text> child: setting "text" on the Button itself made TTS
	-- redraw it in its default black.
	refreshTemplateButton = function()
	    self.UI.setAttribute("setTemplateBtn_text", "text", templateCache.label)
	    UI.setAttribute("TokenApplier_hud_setTemplate_text", "text", hudTemplateLabel())
	end

	-- refresh Preview indicator
	refreshPreviewIndicator = function()
		local previewImage  = templateCache.imageURL
		local previewText   = templateCache.name
		local previewActive = templateJSON ~= nil and "True" or "False"
		self.UI.setAttribute("previewPanel",     "active",  previewActive)
		self.UI.setAttribute("previewImg",       "image",   previewImage)
		self.UI.setAttribute("previewImg",       "active",  previewImage ~= "" and "True" or "False")
		self.UI.setAttribute("previewTextPanel", "active",  previewImage == "" and previewActive or "False")
		self.UI.setAttribute("previewText",      "text",    previewText)
	end

-- ──────────────────────────────────────────────────────────────
--  REMOVE HANDLERS  (unchanged)
-- ──────────────────────────────────────────────────────────────

	local function handleRemove(slotIndex, playerColor)
	    local tGUID = self.getVar("removeSlot_" .. slotIndex)
	    if not tGUID then return end
	    local name  = getTokenName(tGUID)
	    local token = getObjectFromGUID(tGUID)
	    if token then token.destroy() end
	    local prevTarget = lastSelectedGUID
	    hoverEntries[tGUID] = nil
	    saveState()
		invalidateTargetMap()
	    local newTokens = prevTarget and findTokensForTarget(prevTarget) or {}
	    if #newTokens > 0 then
			refreshDynamicPanelSlots(prevTarget)
		else
			hideDynamicPanel()
		end
	    local targetObj  = prevTarget and getObjectFromGUID(prevTarget)
	    local targetName = targetObj and targetObj.getName() or "Unknown"
	    printToColor("Removed token: " .. name, playerColor, { 1, 0.5, 0.5 })
	    printToColor("  from " .. targetName .. " (" .. (prevTarget or "?") .. ")", playerColor, { 1, 1, 1 })
	end

	function btn_remove_1(player, pc) pc = (type(player) == "userdata" and player.color) or pc handleRemove(1, pc) end
	function btn_remove_2(player, pc) pc = (type(player) == "userdata" and player.color) or pc handleRemove(2, pc) end
	function btn_remove_3(player, pc) pc = (type(player) == "userdata" and player.color) or pc handleRemove(3, pc) end
	function btn_remove_4(player, pc) pc = (type(player) == "userdata" and player.color) or pc handleRemove(4, pc) end
	function btn_remove_5(player, pc) pc = (type(player) == "userdata" and player.color) or pc handleRemove(5, pc) end
	function btn_remove_6(player, pc) pc = (type(player) == "userdata" and player.color) or pc handleRemove(6, pc) end

-- ──────────────────────────────────────────────────────────────
--  TOKEN SELECT HANDLERS
-- ──────────────────────────────────────────────────────────────

	local function handleSelectToken(slotIndex)
	    local tGUID = self.getVar("selectSlot_" .. slotIndex)
	    if not tGUID then return end
	    if selectedTokenGUID == tGUID then
	        selectedTokenGUID = nil
	    else
	        selectedTokenGUID = tGUID
	    end
	    refreshSlotHighlights()
	end

	function btn_select_1(_, _) handleSelectToken(1) end
	function btn_select_2(_, _) handleSelectToken(2) end
	function btn_select_3(_, _) handleSelectToken(3) end
	function btn_select_4(_, _) handleSelectToken(4) end
	function btn_select_5(_, _) handleSelectToken(5) end
	function btn_select_6(_, _) handleSelectToken(6) end



-- ──────────────────────────────────────────────────────────────
--  Transfer_tokens-to-model
-- ──────────────────────────────────────────────────────────────
	local function executeTransfer(destGUID, tokenGUIDs, playerColor)
		local destObj  = getObjectFromGUID(destGUID)
		local destName = destObj and destObj.getName() or "Unknown"
		local existingMap = buildTargetMap()
		local existing    = existingMap[destGUID] or {}
		local available   = MAX_TOKENS - #existing
		local total     = #tokenGUIDs
		local transferred = 0

		for _, tGUID in ipairs(tokenGUIDs) do
			if available <= 0 then break end
			local entry = hoverEntries[tGUID]
			if entry then
				entry.targetGUID = destGUID
				transferred = transferred + 1
				available   = available - 1
			end
		end

		saveState()
		invalidateTargetMap()
		hideDynamicPanel()

		if transferred < total then
			broadcastToColor(
				"Max tokens reached on \"" .. destName .. "\" — only " .. transferred .. " of " .. total .. " transferred.",
				playerColor, { 1, 0.6, 0.2 }
			)
		else
			broadcastToColor(
				"   Transferred " .. transferred .. " token(s) to " .. destName .. ".",
				playerColor, { 0.3, 1, 0.5 }
			)
		end
	end

	-- Finishes playerColor's pending transfer onto destGUID (if it's a valid model).
	-- Only that player's own selection / pick-up ever calls this for their transfer.
	local function tryCompleteTransfer(playerColor, destGUID)
		local pending = pendingTransfers[playerColor]
		if not pending then return end
		-- Destination must be a model: not a token, the Applier, or the preview
		if hoverEntries[destGUID] or destGUID == myGUID or destGUID == previewGUID then return end

		local sourceModel = pending.sourceGUID
		if not sourceModel and pending.tokenGUID then
			local e = hoverEntries[pending.tokenGUID]
			if e then sourceModel = e.targetGUID end
		end
		if not sourceModel then
			pendingTransfers[playerColor] = nil   -- token was removed meanwhile; nothing to move
			return
		end

		if destGUID == sourceModel then
			-- Warn once, not every poll while the source model stays selected
			if not pending.warnedSame then
				broadcastToColor("Can't transfer to the same model.", playerColor, { 1, 0.7, 0.3 })
				pending.warnedSame = true
			end
			return
		end

		local tokensToMove = pending.tokenGUID and { pending.tokenGUID } or findTokensForTarget(pending.sourceGUID)
		pendingTransfers[playerColor] = nil
		executeTransfer(destGUID, tokensToMove, playerColor)
	end



-- ──────────────────────────────────────────────────────────────
--  SELECTION POLLING LOOP
-- ──────────────────────────────────────────────────────────────

	local dynHideDelay = false

	function startSelectionLoop()
		if selectionLoopRunning then return end
		selectionLoopRunning = true
		local function getPlayerSelection(colour)
			local ok, sel = pcall(function()
				return Player[colour].getSelectedObjects()
			end)
			return (ok and sel) or {}
		end
		-- First selection from a player who is NOT mid-transfer (drives the dynamic panel)
		local function getSelection()
			for colour, _ in pairs(seatedColors) do
				if not pendingTransfers[colour] then
					local sel = getPlayerSelection(colour)
					if #sel > 0 then return sel end
				end
			end
			return {}
		end
		local function poll()
			if applierDestroyed then selectionLoopRunning = false return end
			-- Each player mid-transfer: only THEIR OWN selection picks the destination
			for colour, _ in pairs(pendingTransfers) do
				local sel = getPlayerSelection(colour)
				if #sel > 0 then tryCompleteTransfer(colour, sel[1].getGUID()) end
			end
			local sel = getSelection()
			if #sel > 0 then
				dynHideDelay = false
				local guid   = sel[1].getGUID()
				local tokens = findTokensForTarget(guid)
				if #tokens > 0 then
					showDynamicPanel(guid, #tokens)
				else
					if dynPanelVisible then hideDynamicPanel() end
				end
			else
				if dynPanelVisible then
					if dynHideDelay then
						hideDynamicPanel()
						dynHideDelay = false
					else
						dynHideDelay = true
					end
				end
			end
			Wait.time(poll, 0.3)
		end
		Wait.time(poll, 0.3)
	end



-- ──────────────────────────────────────────────────────────────
--  CONTEXT MENU INJECTION (right-click-flip, Transfer_tokens-to-model)
-- ──────────────────────────────────────────────────────────────

	injectContextMenu = function(token)
		local tGUID = token.getGUID()

		if templateIsFlippable then
			token.addContextMenuItem("Flip", function(playerColor)
				local entry = hoverEntries[tGUID]
				token.setLock(false)
				local rot = token.getRotation()
				local newX = (math.abs(rot.x - 180) < 5) and 0 or 180
				token.setRotation({ newX, rot.y, rot.z })
				if entry then entry.flipped = (newX == 180) end
				token.setLock(true)
				saveState()
			end)
		end

		token.addContextMenuItem("⇒ Transfer (all)", function(playerColor)
			local entry = hoverEntries[tGUID]
			if not entry then return end
			-- Belongs to the player who clicked; replaces any transfer they already had waiting
			pendingTransfers[playerColor] = { sourceGUID = entry.targetGUID }
			broadcastToColor("Select destination model for all tokens…", playerColor, { 0.5, 0.8, 1 })
		end)

		token.addContextMenuItem("→ Transfer (single)", function(playerColor)
			local entry = hoverEntries[tGUID]
			if not entry then return end
			pendingTransfers[playerColor] = { tokenGUID = tGUID }
			broadcastToColor("Select destination model for this token…", playerColor, { 0.5, 0.8, 1 })
		end)
	end


-- ──────────────────────────────────────────────────────────────
--  TEMPLATE PREVIEW
-- ──────────────────────────────────────────────────────────────

	spawnPreview = function()
	    -- Setting off (default): remove any existing copy and spawn nothing
	    if not showTemplatePreview then
	        if previewGUID then
	            local existing = getObjectFromGUID(previewGUID)
	            if existing then existing.destroy() end
	            previewGUID = nil
	            saveState()
	        end
	        return
	    end
	    if not templateJSON then return end
	    local ok, data = pcall(JSON.decode, templateJSON)
	    if not ok or type(data) ~= "table" then return end
	    unstampData(data)

	    local hasUsefulImage = usefulImageURL(data) ~= nil
	    if hasUsefulImage then
	        if previewGUID then
	            local existing = getObjectFromGUID(previewGUID)
	            if existing then existing.destroy() end
	            previewGUID = nil
	            saveState()
	        end
	        return
	    end

	    if previewGUID then
	        local existing = getObjectFromGUID(previewGUID)
	        if existing then existing.destroy() end
	        previewGUID = nil
	    end
	    local pos = self.getPosition()
	    pos.y = pos.y + PREVIEW_HEIGHT
	    pos.z = pos.z + 1.5
	    if type(data.Transform) ~= "table" then data.Transform = {} end
	    data.Transform.posX = pos.x
	    data.Transform.posY = pos.y
	    data.Transform.posZ = pos.z
	    data.Transform.rotX = 0
	    data.Transform.rotY = 0
	    data.Transform.rotZ = 0
	    data.Sticky    = false
	    data.Grid      = false
	    data.Snap      = false
	    data.Autoraise = false
	    local previewAlpha = 1.0
	    if type(data.ColorDiffuse) == "table" and type(data.ColorDiffuse.a) == "number" then
	        previewAlpha = data.ColorDiffuse.a
	    end
	    spawnObjectJSON({
	        json = JSON.encode(data),
	        callback_function = function(token)
	            if token then
	                token.setLock(true)
	                pcall(function()
	                    local c = token.getColorTint()
	                    token.setColorTint({ r = c.r, g = c.g, b = c.b, a = previewAlpha })
	                end)
	                previewGUID = token.getGUID()
	                saveState()
	            end
	        end,
	    })
	end

	local function restorePreview()
	    if not templateJSON then return end
	    if previewGUID then
	        local existing = getObjectFromGUID(previewGUID)
	        if existing then return end
	        previewGUID = nil
	    end
	    spawnPreview()
	end

-- ──────────────────────────────────────────────────────────────
--  DROP-ON-TC
-- ──────────────────────────────────────────────────────────────

	function onCollisionEnter(info)
		if not dropTemplateEnabled then return end
	    if collisionCooldown then return end
	    local obj = info.collision_object
	    if not obj then return end
	    local guid = obj.getGUID()
	    if guid == self.getGUID()  then return end
	    if hoverEntries[guid]      then return end
	    if guid == previewGUID     then return end
	    if obj.getLock()           then return end
	    local data = obj.getData()
	    if not data then return end
	    unstampData(data)
	    local json  = JSON.encode(data)
	    local ts    = data.Transform
	    local scale = {
	        x = (ts and ts.scaleX) or 1.0,
	        y = (ts and ts.scaleY) or 1.0,
	        z = (ts and ts.scaleZ) or 1.0,
	    }
	    local name = (data.Nickname and data.Nickname ~= "") and data.Nickname
	                 or (data.Name and data.Name ~= "") and data.Name
	                 or "Token"
	    local imageURL = extractImageURL(data)
	    templateJSON  = json
	    templateScale = scale
	    refreshTemplateCache()
	    addToHistory(json, scale, name, imageURL)
	    saveState()
	    refreshTemplateButton()
	    spawnPreview()
	    refreshHistorySlots()
		refreshPreviewIndicator()
		
		refreshSizeWarning()

	    collisionCooldown = true
	    Wait.time(function() collisionCooldown = false end, 2.0)

	    local tcPos = self.getPosition()
	    local ejectPos = { x = tcPos.x + DROP_EJECT_OFFSET, y = tcPos.y + 1.0, z = tcPos.z }
	    Wait.time(function()
	        local o = getObjectFromGUID(guid)
	        if o then o.setPositionSmooth(ejectPos, false, true) end
	    end, 0.6)
	    printToAll("Template set from drop: " .. name, { 0.3, 1, 0.5 })
	end

-- ──────────────────────────────────────────────────────────────
--  CLEAR HISTORY
-- ──────────────────────────────────────────────────────────────

	-- "Are you sure?" for Clear History — same pattern as Remove All Tokens.
	-- Holds the colour of the player who armed it, until confirmed or REMOVE_CONFIRM_TIME runs out.
	local clearConfirm = nil   -- { color = playerColor } while waiting for the second click

	-- Switches both Clear History buttons (OUI + HUD) between normal and armed "Sure?" look
	local function setClearHistoryLook(text, hudText, styleName)
		setButtonLook(self.UI, "clearHistoryBtn", text, styleName)
		setHudButtonLook("TokenApplier_hud_clearHistoryBtn", hudText, styleName)
	end

	local function resetClearConfirm()
		clearConfirm = nil
		setClearHistoryLook(CLEAR_HISTORY_LABEL, HUD_CLEAR_LABEL, CLEAR_HISTORY_STYLE)
	end

	function btn_clearHistory(player, _)
	    local playerColor = (type(player) == "userdata" and player.color) or "any"
	    -- First click (or another player's click): arm it and wait for a second click
	    if not (clearConfirm and clearConfirm.color == playerColor) then
	        local thisConfirm = { color = playerColor }
	        clearConfirm = thisConfirm
	        setClearHistoryLook("Sure? Click again to clear ALL history", "Sure? Click again", CLEAR_ARMED_STYLE)
	        Wait.time(function()
	            if clearConfirm == thisConfirm then resetClearConfirm() end   -- expired
	        end, REMOVE_CONFIRM_TIME)
	        return
	    end
	    -- Second click: confirmed
	    resetClearConfirm()
	    tokenHistory  = {}
	    historyPage   = 0
	    templateJSON  = nil
	    templateScale = nil
	    refreshTemplateCache()
	    if previewGUID then
	        local obj = getObjectFromGUID(previewGUID)
	        if obj then obj.destroy() end
	        previewGUID = nil
	    end
	    saveState()
	    refreshTemplateButton()
	    refreshHistorySlots()
		refreshPreviewIndicator()
		setHistoryEditMode(false)   -- nothing left to edit
	    printToAll("Token history cleared.", { 1, 0.8, 0.3 })
	end

-- ──────────────────────────────────────────────────────────────
--  onLoad
-- ──────────────────────────────────────────────────────────────

	function onLoad()
	    myGUID = self.getGUID()
	    loadState()
	    CUSTOM.applySelectColor()      -- saved selection colour (also runs applyOpacity)
	    applyOpacity()                 -- before the UIs are built, so they're drawn in the saved mode
	    historyPage = pageOfActive()   -- open on the page holding the selected template, so it's on screen
	    checkImageFormats()   -- test any history images not checked yet (e.g. from older saves)
		hudPlacementMode = false
			--print("[Debug] hudVisible on load: " .. tostring(hudVisible))
			--print("[Debug] hudPlacementMode on load: " .. tostring(hudPlacementMode))
		--hudRootOffsetXY = "0 2" -- TO PREVENT THE HUD FROM RUNNING AWAY - DELETE ONCE ALL THE POSITIONS HAVE BEEN LOCKED IN.
		-- Re-inject context menus on existing tokens after load
		for tGUID, entry in pairs(hoverEntries) do
			if type(entry) == "table" then
				local token = getObjectFromGUID(tGUID)
				if token then
					injectContextMenu(token)
				end
			end
		end

	    Wait.condition(function()
	        rebuildXML()
	    end, function() return not self.UI.loading end)

	    Wait.condition(function()
	        rebuildHUD()
	    end, function() return not UI.loading end)
	

	    -- Right-click backup, works even if the HUD is broken by another mod
	    self.addContextMenuItem("Find Tokens", function() btn_findTokens() end)
	    -- Stamp tokens we already track (upgrades tokens from older saves)
	    saveState()

	    startFollowLoop()
	    startSelectionLoop()
	    startHudWatch()
	    restorePreview()
		for _, colour in ipairs({"Red","Blue","White","Green","Yellow","Orange","Purple","Pink","Teal"}) do
			local p = Player[colour]
			if p and p.seated then
				seatedColors[colour] = true
			end
		end
	end

	-- Called by TTS when this Applier is deleted. Its script would otherwise keep
	-- running until the game reloads and fight a new Applier over the same tokens.
	function onDestroy()
		applierDestroyed = true
		-- Remove our right-click options from tokens; a new Applier re-adds its own on Find Tokens
		for tGUID, _ in pairs(hoverEntries) do
			local token = getObjectFromGUID(tGUID)
			if token then pcall(function() token.clearContextMenu() end) end
		end
	end

-- ──────────────────────────────────────────────────────────────
--  TEMPLATE CAPTURE
-- ──────────────────────────────────────────────────────────────

	function btn_setTemplate(player, playerColor)
	    playerColor = (type(player) == "userdata" and player.color) or playerColor
	    local sel = Player[playerColor].getSelectedObjects()
	    if #sel == 0 then
	        printToColor("Select an object first to use as the token template.", playerColor, { 1, 1, 0 })
	        return
	    end
	    local obj = sel[1]
	    if obj == self then
	        printToColor("You cannot use the controller itself as a template.", playerColor, { 1, 0.3, 0.3 })
	        return
	    end
	    if hoverEntries[obj.getGUID()] then
	        printToColor("That object is already an active hover token.", playerColor, { 1, 0.5, 0 })
	        return
	    end
	    if previewGUID and obj.getGUID() == previewGUID then
	        printToColor("That is the template preview — select a different object.", playerColor, { 1, 0.5, 0 })
	        return
	    end
	    local data = obj.getData()
	    if not data then
	        printToColor("Could not read object data.", playerColor, { 1, 0.3, 0.3 })
	        return
	    end
	    unstampData(data)
	    local json = JSON.encode(data)
	    local ts   = data.Transform
	    templateScale = {
	        x = (ts and ts.scaleX) or 1.0,
	        y = (ts and ts.scaleY) or 1.0,
	        z = (ts and ts.scaleZ) or 1.0,
	    }
	    templateJSON = json
	    refreshTemplateCache()
	    local name     = (data.Nickname and data.Nickname ~= "") and data.Nickname
	                     or (data.Name and data.Name ~= "") and data.Name
	                     or "Token"
	    local imageURL = extractImageURL(data)
	    addToHistory(json, templateScale, name, imageURL)
	    saveState()
	    refreshTemplateButton()
	    spawnPreview()
	    refreshHistorySlots()
		refreshPreviewIndicator()
		refreshSizeWarning()

	    printToColor("Template set from: " .. name, playerColor, { 0.3, 1, 0.5 })
	end

-- ──────────────────────────────────────────────────────────────
--  HEIGHT TOKENS
-- ──────────────────────────────────────────────────────────────

	local function applyHeightToTokens(targetGUID, delta, playerColor)
	    local tokens = findTokensForTarget(targetGUID)
	    if #tokens == 0 then printToColor("No tokens on selected model.", playerColor, { 1, 1, 0 }) return end
	    local targets = {}
	    if selectedTokenGUID and hoverEntries[selectedTokenGUID]
	        and hoverEntries[selectedTokenGUID].targetGUID == targetGUID then
	        targets = { selectedTokenGUID }
	    else
	        targets = tokens
	    end
	    for _, tGUID in ipairs(targets) do
	        local entry = hoverEntries[tGUID]
	        if entry then entry.offset = entry.offset + delta end
	    end
	    saveState()
	end

	function btn_heightUp(player, playerColor)
	    playerColor = (type(player) == "userdata" and player.color) or playerColor
	    local sel = Player[playerColor].getSelectedObjects()
	    if #sel == 0 then printToColor("Select a model first.", playerColor, { 1, 1, 1 }) return end
	    applyHeightToTokens(sel[1].getGUID(), HEIGHT_STEP, playerColor)
	end

	function btn_heightDown(player, playerColor)
	    playerColor = (type(player) == "userdata" and player.color) or playerColor
	    local sel = Player[playerColor].getSelectedObjects()
	    if #sel == 0 then printToColor("Select a model first.", playerColor, { 1, 1, 1 }) return end
	    applyHeightToTokens(sel[1].getGUID(), -HEIGHT_STEP, playerColor)
	end

-- ──────────────────────────────────────────────────────────────
--  SCALE TOKENS
-- ──────────────────────────────────────────────────────────────

	local function applyScaleToTokens(targetGUID, delta, playerColor)
	    local tokens = findTokensForTarget(targetGUID)
	    if #tokens == 0 then printToColor("No tokens on selected model.", playerColor, { 1, 1, 0 }) return end
	    local targets = {}
	    if selectedTokenGUID and hoverEntries[selectedTokenGUID]
	        and hoverEntries[selectedTokenGUID].targetGUID == targetGUID then
	        targets = { selectedTokenGUID }
	    else
	        targets = tokens
	    end
	    for _, tGUID in ipairs(targets) do
	        local entry = hoverEntries[tGUID]
	        local token = getObjectFromGUID(tGUID)
	        if not entry.scale then
	            entry.scale = templateScale and { x=templateScale.x, y=templateScale.y, z=templateScale.z }
	                       or { x=1.0, y=1.0, z=1.0 }
	        end
	        local newX = math.max(0.1, entry.scale.x + delta)
	        local newZ = math.max(0.1, entry.scale.z + delta)
	        entry.scale.x = newX
	        entry.scale.z = newZ
	        if token then pcall(function() token.setScale({ newX, entry.scale.y, newZ }) end) end
	    end
	    saveState()
	end

	function btn_scaleUp(player, playerColor)
	    playerColor = (type(player) == "userdata" and player.color) or playerColor
	    local sel = Player[playerColor].getSelectedObjects()
	    if #sel == 0 then printToColor("Select a model first.", playerColor, { 1, 1, 1 }) return end
	    applyScaleToTokens(sel[1].getGUID(), SCALE_STEP, playerColor)
	end

	function btn_scaleDown(player, playerColor)
	    playerColor = (type(player) == "userdata" and player.color) or playerColor
	    local sel = Player[playerColor].getSelectedObjects()
	    if #sel == 0 then printToColor("Select a model first.", playerColor, { 1, 1, 1 }) return end
	    applyScaleToTokens(sel[1].getGUID(), -SCALE_STEP, playerColor)
	end

-- ──────────────────────────────────────────────────────────────
--  FLIP, ROTATE & VERTICAL TOKENS
-- ──────────────────────────────────────────────────────────────

	local function applyTransformToTokens(targetGUID, playerColor, transformFn)
	    local tokens = findTokensForTarget(targetGUID)
	    if #tokens == 0 then printToColor("No tokens on selected model.", playerColor, { 1, 1, 0 }) return end
	    local targets = {}
	    if selectedTokenGUID and hoverEntries[selectedTokenGUID]
	        and hoverEntries[selectedTokenGUID].targetGUID == targetGUID then
	        targets = { selectedTokenGUID }
	    else
	        targets = tokens
	    end
	    for _, tGUID in ipairs(targets) do
	        local token = getObjectFromGUID(tGUID)
	        if token then
	            token.setLock(false)
	            pcall(function() transformFn(token, hoverEntries[tGUID]) end)
	            token.setLock(true)
	        end
	    end
	    saveState()
	end

	function btn_flip(player, playerColor)
	    playerColor = (type(player) == "userdata" and player.color) or playerColor
	    local sel = Player[playerColor].getSelectedObjects()
	    if #sel == 0 then printToColor("Select a model first.", playerColor, { 1, 1, 1 }) return end
	    applyTransformToTokens(sel[1].getGUID(), playerColor, function(token, entry)
	        local rot = token.getRotation()
	        local newX = (math.abs(rot.x - 180) < 5) and 0 or 180
	        token.setRotation({ newX, rot.y, rot.z })
	        entry.flipped = (newX == 180)
	    end)
	end

	function btn_rotate(player, playerColor)
	    playerColor = (type(player) == "userdata" and player.color) or playerColor
	    local sel = Player[playerColor].getSelectedObjects()
	    if #sel == 0 then printToColor("Select a model first.", playerColor, { 1, 1, 1 }) return end
	    applyTransformToTokens(sel[1].getGUID(), playerColor, function(token, entry)
	        local rot = token.getRotation()
	        local newY = (math.abs(rot.y - 180) < 5) and 0 or 180
	        token.setRotation({ rot.x, newY, rot.z })
	        entry.rotated = (newY == 180)
	    end)
	end

	function btn_vertical(player, playerColor)
	    playerColor = (type(player) == "userdata" and player.color) or playerColor
	    local sel = Player[playerColor].getSelectedObjects()
	    if #sel == 0 then printToColor("Select a model first.", playerColor, { 1, 1, 1 }) return end
	    applyTransformToTokens(sel[1].getGUID(), playerColor, function(token, entry)
	        entry.vertical = not entry.vertical
	        local rot = token.getRotation()
	        local newX = entry.vertical and 90 or 0
	        token.setRotation({ newX, rot.y, rot.z })
	    end)
	end

-- ──────────────────────────────────────────────────────────────
--  RADIUS & OFFSET ADJUST
-- ──────────────────────────────────────────────────────────────

	local function applyRadiusToModel(targetGUID, delta, playerColor)
	    local tokens = findTokensForTarget(targetGUID)
	    if #tokens < 2 then printToColor("Need 2+ tokens on model to adjust spread.", playerColor, { 1, 1, 0 }) return end
	    local newRadius = math.max(0.2, getRadiusForTarget(targetGUID) + delta)
	    modelRadius[targetGUID] = newRadius
	    saveState()
	end

	function btn_radiusUp(player, playerColor)
	    playerColor = (type(player) == "userdata" and player.color) or playerColor
	    local sel = Player[playerColor].getSelectedObjects()
	    if #sel == 0 then printToColor("Select a model first.", playerColor, { 1, 1, 1 }) return end
	    applyRadiusToModel(sel[1].getGUID(), RADIUS_STEP, playerColor)
	end

	function btn_radiusDown(player, playerColor)
	    playerColor = (type(player) == "userdata" and player.color) or playerColor
	    local sel = Player[playerColor].getSelectedObjects()
	    if #sel == 0 then printToColor("Select a model first.", playerColor, { 1, 1, 1 }) return end
	    applyRadiusToModel(sel[1].getGUID(), -RADIUS_STEP, playerColor)
	end

	function btn_lineForward(player, playerColor)
		playerColor = (type(player) == "userdata" and player.color) or playerColor
		local sel = Player[playerColor].getSelectedObjects()
		if #sel == 0 then printToColor("Select a model first.", playerColor, { 1, 1, 1 }) return end
		local targetGUID = sel[1].getGUID()
		modelLineOffset[targetGUID] = (modelLineOffset[targetGUID] or 0) + RADIUS_STEP
		saveState()
	end

	function btn_lineBackward(player, playerColor)
		playerColor = (type(player) == "userdata" and player.color) or playerColor
		local sel = Player[playerColor].getSelectedObjects()
		if #sel == 0 then printToColor("Select a model first.", playerColor, { 1, 1, 1 }) return end
		local targetGUID = sel[1].getGUID()
		modelLineOffset[targetGUID] = (modelLineOffset[targetGUID] or 0) - RADIUS_STEP
		saveState()
	end

	function btn_toggleModelLineUp(player, playerColor)
		playerColor = (type(player) == "userdata" and player.color) or playerColor
		local sel = Player[playerColor].getSelectedObjects()
		if #sel == 0 then printToColor("Select a model first.", playerColor, { 1, 1, 1 }) return end
		local targetGUID = sel[1].getGUID()
		modelLineUp[targetGUID] = not modelLineUp[targetGUID]
		saveState()
		setLineUpLabel(modelLineUp[targetGUID])
	end

-- ──────────────────────────────────────────────────────────────
--  TOKEN SPAWN
-- ──────────────────────────────────────────────────────────────

	local function spawnTemplateAt(position, scale, flipped, rotated, callback)
	    if not templateJSON then return nil end
	    local ok, data = pcall(JSON.decode, templateJSON)
	    if not ok or type(data) ~= "table" then
	        print("[TokenManager] templateJSON is corrupt, cannot spawn.")
	        return nil
	    end
	    unstampData(data)
	    local spawnAlpha = 1.0
	    if type(data.ColorDiffuse) == "table" and type(data.ColorDiffuse.a) == "number" then
	        spawnAlpha = data.ColorDiffuse.a
	    end
	    if type(data.Transform) ~= "table" then data.Transform = {} end
	    data.Transform.posX = position.x
	    data.Transform.posY = position.y
	    data.Transform.posZ = position.z
	    data.Transform.rotX = flipped and 180 or 0
	    data.Transform.rotY = rotated and 180 or 0
	    data.Transform.rotZ = 0
	    if scale then
	        data.Transform.scaleX = scale.x
	        data.Transform.scaleY = scale.y
	        data.Transform.scaleZ = scale.z
	    end
	    data.Sticky = false ; data.Grid = false ; data.Snap = false ; data.Autoraise = false
	    return spawnObjectJSON({
	        json = JSON.encode(data),
	        callback_function = function(token)
	            if token then
	                pcall(function()
	                    local c = token.getColorTint()
	                    token.setColorTint({ r=c.r, g=c.g, b=c.b, a=spawnAlpha })
	                end)
					injectContextMenu(token)
	                if callback then callback(token) end
	            end
	        end,
	    })
	end

-- ──────────────────────────────────────────────────────────────
--  ADD TOKEN
-- ──────────────────────────────────────────────────────────────

	function btn_toggleToken(player, playerColor)
	    playerColor = (type(player) == "userdata" and player.color) or playerColor
	    if not templateJSON then
	        printToColor("No template set — use 'Set Template' first.", playerColor, { 1, 1, 0 })
	        return
	    end
	    local sel = Player[playerColor].getSelectedObjects()
	    if #sel == 0 then printToColor("Select a model first.", playerColor, { 1, 1, 1 }) return end
	    local target     = sel[1]
	    local targetGUID = target.getGUID()
	    if target == self then
	        printToColor("Cannot attach a token to the controller.", playerColor, { 1, 0.3, 0.3 }) return
	    end
	    if previewGUID and targetGUID == previewGUID then
	        printToColor("Cannot attach a token to the template preview.", playerColor, { 1, 0.3, 0.3 }) return
	    end
	    local existing = findTokensForTarget(targetGUID)
	    if #existing >= MAX_TOKENS then
	        printToColor("Maximum tokens (" .. MAX_TOKENS .. ") already attached.", playerColor, { 1, 0.5, 0 }) return
	    end
	    local offset = FLOAT_HEIGHT_LOW
	    local scale
	    if templateScale then
	        local sx = math.max(0.1, templateScale.x + defaultScaleOffset)
	        local sz = math.max(0.1, templateScale.z + defaultScaleOffset)
	        scale = { x = sx, y = templateScale.y, z = sz }
	    end
	    local pos    = target.getPosition()
	    pos.y = pos.y + offset
	    spawnTemplateAt(pos, scale, false, false, function(token)
	        if not token then
	            printToColor("Failed to spawn token.", playerColor, { 1, 0.3, 0.3 }) return
	        end
	        token.setLock(true)
	        local newGUID = token.getGUID()
	        hoverEntries[newGUID] = { targetGUID=targetGUID, offset=offset, scale=scale, flipped=false, rotated=false, vertical=false }
	        saveState()
			invalidateTargetMap()
	        local targetObj  = getObjectFromGUID(targetGUID)
	        local targetName = targetObj and targetObj.getName() or "Unknown"
	        printToColor("Added token: " .. getTokenName(newGUID), playerColor, { 0.5, 1, 0.5 })
	        printToColor("  to " .. targetName .. " (" .. targetGUID .. ")", playerColor, { 1, 1, 1 })
		-- Force panel refresh
			lastSelectedGUID = targetGUID
			refreshDynamicPanelSlots(targetGUID)
			activateDynamicPanel()
		end)
	end

-- ──────────────────────────────────────────────────────────────
--  FOLLOW LOOP
-- ──────────────────────────────────────────────────────────────

	function startFollowLoop()
	    if followLoopRunning then return end
	    followLoopRunning = true

	    local function dist(a, b)
	        local dx=a.x-b.x ; local dy=a.y-b.y ; local dz=a.z-b.z
	        return math.sqrt(dx*dx + dy*dy + dz*dz)
	    end

	    local function findNearbyObject(pos)
	        for _, obj in ipairs(getAllObjects()) do
	            local guid = obj.getGUID()
	            if guid ~= self.getGUID()
	                and not hoverEntries[guid]
	                and guid ~= previewGUID
	                and dist(obj.getPosition(), pos) <= HEAL_RADIUS then
	                return obj
	            end
	        end
	        return nil
	    end

	    local function tick()
	        if applierDestroyed then followLoopRunning = false return end
	        local toRemove  = {}
	        local dirty     = false

	        -- Handover: let go of tokens another Applier has adopted (drop from notebook, never destroy)
	        local released = {}
	        for tGUID, _ in pairs(hoverEntries) do
	            local token = getObjectFromGUID(tGUID)
	            if token and isOwnedByAnother(token) then released[#released + 1] = tGUID end
	        end
	        for _, tGUID in ipairs(released) do hoverEntries[tGUID] = nil end
	        if #released > 0 then
	            invalidateTargetMap()
	            dirty = true
	        end

	        local targetMap = buildTargetMap()
	        local now       = os.time()

	        for targetGUID, tokenList in pairs(targetMap) do
	            local target = getObjectFromGUID(targetGUID)
	            if not target then
	                for _, tGUID in ipairs(tokenList) do
	                    local entry = hoverEntries[tGUID]
	                    local token = getObjectFromGUID(tGUID)
	                    if not entry.missingTime then
	                        entry.missingTime = now
	                        if token and entry.lastKnownPos then
	                            token.setPositionSmooth(entry.lastKnownPos, false, false)
	                        end
	                    else
	                        local elapsed = now - entry.missingTime
	                        if elapsed <= GRACE_PERIOD then
	                            if entry.lastKnownPos then
	                                local nearby = findNearbyObject(entry.lastKnownPos)
	                                if nearby then
	                                    local newTargetGUID = nearby.getGUID()
	                                    entry.targetGUID  = newTargetGUID
	                                    entry.missingTime = nil
	                                    if modelRadius[targetGUID] then
	                                        modelRadius[newTargetGUID] = modelRadius[targetGUID]
	                                        modelRadius[targetGUID]    = nil
	                                    end
	                                    dirty = true
	                                elseif token and entry.lastKnownPos then
	                                    token.setPositionSmooth(entry.lastKnownPos, false, false)
	                                end
	                            end
	                        else
	                            toRemove[#toRemove + 1] = tGUID
	                        end
	                    end
	                end
	            else
	                local total  = #tokenList
	                local tPos   = target.getPosition()
	                local radius = getRadiusForTarget(targetGUID)
	                for idx, tGUID in ipairs(tokenList) do
	                    local token = getObjectFromGUID(tGUID)
							if not token then
								toRemove[#toRemove + 1] = tGUID
							elseif heldModels[targetGUID] then
								-- model is being carried, skip follow so tokens stay hidden up high
							else
	                        local entry = hoverEntries[tGUID]
	                        entry.lastKnownPos = { x=tPos.x, y=tPos.y, z=tPos.z }
	                        entry.missingTime  = nil
	                        local pos
	                        if total == 1 then -- single token
								local zOffset = modelLineOffset[targetGUID] or 0
								pos = { x=tPos.x, y=tPos.y + entry.offset, z=tPos.z + zOffset }
	                        else
	                            if modelLineUp[targetGUID] then
									local spacing = getRadiusForTarget(targetGUID)
									local zOffset = modelLineOffset[targetGUID] or 0
									pos = {
										x = tPos.x + (idx - (total + 1) / 2) * spacing,
										y = tPos.y + entry.offset,
										z = tPos.z + zOffset,
									}
								else -- multi token
									local angle   = ((idx-1) / total) * (2 * math.pi)
									local zOffset = modelLineOffset[targetGUID] or 0
									pos = {
										x = tPos.x + radius * math.cos(angle),
										y = tPos.y + entry.offset,
										z = tPos.z + radius * math.sin(angle) + zOffset,
									}
								end
	                        end
	                        token.setPositionSmooth(pos, false, false)
	                    end
	                end
	            end
	        end

	        for _, guid in ipairs(toRemove) do
	            local orphan = getObjectFromGUID(guid)
	            if orphan then orphan.destroy() end
	            hoverEntries[guid] = nil
	            dirty = true
	        end
	        if dirty then
				saveState()
				invalidateTargetMap()
			end
	        Wait.time(tick, FOLLOW_INTERVAL)
	    end

	    Wait.time(tick, FOLLOW_INTERVAL)
	end

-- ──────────────────────────────────────────────────────────────
--  RESTORE TOKENS
-- ──────────────────────────────────────────────────────────────

	function btn_restoreTokens(_, playerColor)
	    if not templateJSON then
	        printToAll("No template stored — nothing to restore.", { 1, 1, 0 }) return
	    end
	    local restored  = 0
	    local toReplace = {}
	    for tokenGUID, entry in pairs(hoverEntries) do
	        if type(entry) ~= "table" then
	            hoverEntries[tokenGUID] = nil
	        else
	            local token  = getObjectFromGUID(tokenGUID)
	            local target = getObjectFromGUID(entry.targetGUID)
	            if not target then
	                if token then token.destroy() end
	                hoverEntries[tokenGUID] = nil
	            elseif token then
	                restored = restored + 1
	            else
	                toReplace[#toReplace + 1] = { oldGUID=tokenGUID, entry=entry }
	            end
	        end
	    end
	    for _, r in ipairs(toReplace) do
	        hoverEntries[r.oldGUID] = nil
	        local target = getObjectFromGUID(r.entry.targetGUID)
	        if target then
	            local pos = target.getPosition()
	            pos.y = pos.y + r.entry.offset
	            spawnTemplateAt(pos, r.entry.scale, r.entry.flipped, r.entry.rotated, function(newToken)
	                if newToken then
	                    newToken.setLock(true)
						injectContextMenu(newToken)
	                    local newGUID = newToken.getGUID()
	                    hoverEntries[newGUID] = {
	                        targetGUID = r.entry.targetGUID,
	                        offset     = r.entry.offset,
	                        scale      = r.entry.scale,
	                        flipped    = r.entry.flipped,
	                        rotated    = r.entry.rotated,
	                        vertical   = r.entry.vertical or false,
	                    }
	                    saveState()
	                end
	            end)
	            restored = restored + 1
	        end
	    end
	    saveState()
		invalidateTargetMap()
	    printToAll("Restored " .. restored .. " hover token(s).", { 0.3, 0.8, 1 })
	end

-- ──────────────────────────────────────────────────────────────
--  FIND TOKENS  (adopt stamped tokens left by a deleted/old Applier)
-- ──────────────────────────────────────────────────────────────

	function btn_findTokens(_, _)
		local targetMap = buildTargetMap()
		local adopted, noModel, owned, full = 0, 0, 0, 0

		for _, token in ipairs(getObjectsWithTag(TOKEN_TAG)) do
			local tGUID = token.getGUID()
			-- Skip tokens we already manage, and our own preview
			if not hoverEntries[tGUID] and tGUID ~= previewGUID then
				local ok, data = pcall(JSON.decode, token.memo or "")
				if ok and type(data) == "table" and type(data.targetGUID) == "string" then
					local otherOwner = data.owner and data.owner ~= myGUID and getObjectFromGUID(data.owner)
					local count      = targetMap[data.targetGUID] and #targetMap[data.targetGUID] or 0
					if otherOwner then
						owned = owned + 1        -- another Applier on the table still runs this token
					elseif not getObjectFromGUID(data.targetGUID) then
						noModel = noModel + 1    -- its model isn't on the table; leave it alone
					elseif count >= MAX_TOKENS then
						full = full + 1
					else
						hoverEntries[tGUID] = {
							targetGUID = data.targetGUID,
							offset     = data.offset or FLOAT_HEIGHT_LOW,
							scale      = data.scale,
							flipped    = data.flipped or false,
							rotated    = data.rotated or false,
							vertical   = data.vertical or false,
						}
						targetMap[data.targetGUID] = targetMap[data.targetGUID] or {}
						table.insert(targetMap[data.targetGUID], tGUID)
						token.setLock(true)
						-- Handover: wipe the old Applier's right-click options, add ours,
						-- and stamp us as owner right away so the old Applier lets go
						pcall(function() token.clearContextMenu() end)
						injectContextMenu(token)
						stampToken(token, hoverEntries[tGUID])
						adopted = adopted + 1
					end
				end
			end
		end

		if adopted > 0 then
			saveState()   -- also re-stamps adopted tokens with us as the new owner
			invalidateTargetMap()
		end
		printToAll("Find Tokens: adopted " .. adopted .. " token(s).", { 0.3, 0.8, 1 })
		if owned   > 0 then printToAll("  " .. owned   .. " skipped — still run by another Token Applier (delete it first).", { 1, 0.7, 0.3 }) end
		if noModel > 0 then printToAll("  " .. noModel .. " skipped — their model isn't on the table.", { 1, 0.7, 0.3 }) end
		if full    > 0 then printToAll("  " .. full    .. " skipped — model already has " .. MAX_TOKENS .. " tokens.", { 1, 0.7, 0.3 }) end
	end

-- ──────────────────────────────────────────────────────────────
--  onPlayerConnect event handlers
-- ──────────────────────────────────────────────────────────────
	function onPlayerConnect(player)
		seatedColors[player.color] = true
	end

	function onPlayerDisconnect(player)
		seatedColors[player.color] = nil
		pendingTransfers[player.color] = nil   -- don't leave their transfer waiting for whoever sits next
	end

-- ──────────────────────────────────────────────────────────────
--  PICK UP / DROP
-- ──────────────────────────────────────────────────────────────

	function onObjectPickUp(playerColor, object)
	    local guid = object.getGUID()
		-- Transfer mode: picking up a model counts as selecting the destination,
		-- but only for the player who started that transfer.
		-- Falls through to normal pickup handling so tokens still hide.
		tryCompleteTransfer(playerColor, guid)
	    local tokens = findTokensForTarget(guid)
	    if #tokens == 0 then return end
	    heldModels[guid] = true
	    for _, tGUID in ipairs(tokens) do
	        local token = getObjectFromGUID(tGUID)
	        local entry = hoverEntries[tGUID]
	        if token and entry then
	            token.setLock(false)
	            pcall(function()
	                token.setScale({ PICKUP_SCALE_SHRINK, PICKUP_SCALE_SHRINK, PICKUP_SCALE_SHRINK })
	                token.setPosition({
	                    token.getPosition().x,
	                    token.getPosition().y + PICKUP_HEIGHT_BOOST,
	                    token.getPosition().z,
	                })
	            end)
	            token.setLock(true)
	        end
	    end
	end

	function onObjectDrop(_, object)
	    local guid = object.getGUID()
	    if not heldModels[guid] then return end
	    heldModels[guid] = nil
	    local tokens = findTokensForTarget(guid)
	    for _, tGUID in ipairs(tokens) do
	        local token = getObjectFromGUID(tGUID)
	        local entry = hoverEntries[tGUID]
		if token and entry then
	            local s = entry.scale or { x=1.0, y=1.0, z=1.0 }
	            token.setLock(false)
	            pcall(function()
	                token.setScale({ s.x, s.y, s.z })
	            end)
	            token.setLock(true)
	        end
	    end
	end

-- ──────────────────────────────────────────────────────────────
--  DEBUG
-- ──────────────────────────────────────────────────────────────

	function btn_debug(_, _)
	    print("──────── Hover Token Table ────────")
	    local byTarget = {} ; local corrupt = {}
	    for tokenGUID, entry in pairs(hoverEntries) do
	        if type(entry) == "table" then
	            local tgt = entry.targetGUID
	            if not byTarget[tgt] then byTarget[tgt] = {} end
	            byTarget[tgt][#byTarget[tgt] + 1] = tokenGUID
	        else
	            corrupt[#corrupt + 1] = tokenGUID
	        end
	    end
	    local count = 0
	    for targetGUID, tokens in pairs(byTarget) do
	        local targetObj  = getObjectFromGUID(targetGUID)
	        local targetName = targetObj and targetObj.getName() or "Unknown"
	        print(string.format("  Target %s (%s)  →  %s", targetName, targetGUID, table.concat(tokens, ", ")))
	        count = count + 1
	    end
	    for _, tokenGUID in ipairs(corrupt) do
	        print("  Token " .. tokenGUID .. "  →  CORRUPT ENTRY")
	    end
	    if count == 0 then print("  (empty)") end
	    print("──────── Token History ────────")
	    if #tokenHistory == 0 then
	        print("  (empty)")
	    else
	        for i, entry in ipairs(tokenHistory) do
	            print(string.format("  [%d] %s  img:%s", i, entry.name,
	                (entry.imageURL and entry.imageURL ~= "") and "yes" or "no"))
	            -- Image investigation: read straight from the saved template data
	            -- (entry.imageURL may have been blanked by the name-only rule)
	            local ok, data = pcall(JSON.decode, entry.json or "")
	            if ok and type(data) == "table" then
	                local url  = extractImageURL(data) or ""
	                local c    = type(data.ColorDiffuse) == "table" and data.ColorDiffuse or {}
	                local tint = string.format("r%.2f g%.2f b%.2f", c.r or 1, c.g or 1, c.b or 1)
	                print(string.format("      type:%s  nameOnly:%s  tint:%s", tostring(data.Name), tostring(entry.nameOnly), tint))
	                local blank = url:find(BLANK_IMAGE_ID, 1, true) and "  (BLANK placeholder)" or ""
	                local check = url ~= "" and ("  [check: " .. (imageCheck[url] or (imageCheckPending[url] and "checking…" or "not yet")) .. "]") or ""
	                print("      image: " .. (url ~= "" and url or "(none)") .. blank .. check)
	                -- Where else the visible artwork might come from (tool-built tokens)
	                local decals = type(data.AttachedDecals) == "table" and #data.AttachedDecals or 0
	                local hasLua = type(data.LuaScript) == "string" and data.LuaScript ~= ""
	                local hasXml = type(data.XmlUI) == "string" and data.XmlUI ~= ""
	                print(string.format("      decals:%d  script:%s  objectUI:%s", decals, hasLua and "yes" or "no", hasXml and "yes" or "no"))
	            end
	        end
	    end
		if templateJSON then
			local bytes = #templateJSON
			local kb    = math.floor(bytes / 1024)
			local mb    = string.format("%.2f", bytes / 1048576)
			print(string.format("  Template size: %d bytes  (%d kb  /  %s mb)", bytes, kb, mb))
		else
			print("  Template size: (no template set)")
		end
	    print("──────────────────────────")
	end