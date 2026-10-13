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
	local HISTORY_MAX       = 8
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
	local REMOVE_ALL_STYLE    = "settingsItem"   -- normal state: same yellow as the settings buttons
	local REMOVE_ARMED_STYLE  = "hudRemove"      -- "Sure?" state: red, so the change pops
	local CLEAR_HISTORY_LABEL = "X Clear All History"
	local CLEAR_HISTORY_STYLE = "settingsItem"   -- normal: yellow (only visible while Edit History is live)
	local CLEAR_ARMED_STYLE   = "danger"         -- "Sure?" state: red
	local HUD_CLEAR_LABEL     = "X Clear All History"     -- HUD wording for the same buttons
	local HUD_EDIT_OFF_LABEL  = "Edit History"
	local HUD_EDIT_ON_LABEL   = "←Stop Editing History"
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
	local hudEnabled            = true
	local dynPanelVisible       = false  -- tracks whether dynamic panel is currently shown
	local historyEditMode 		= false
	local templateCache     	= { label = "Set Template\n(none)", imageURL = "", name = "" }
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
	        textColor  = "#FDFF6F",
	        transition = "ColorTint",
	    },
	    settingsItem = {
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
	    -- Dynamic panel modifier buttons
	    dynMod = {
	        colors     = "#0D0D0DE6|#222222F2|#080808E6|#333333AA",
	        textColor  = "#CC99FF",
	        transition = "ColorTint",
	    },
	    -- Dynamic panel scale up
	    dynGreenBtn = {
	        colors     = "#0D0D0DE6|#1A2B1AE6|#080808E6|#333333AA",
	        textColor  = "#80FF80",
	        transition = "ColorTint",
	    },
	    -- Dynamic panel scale down
	    dynRedBtn = {
	        colors     = "#0D0D0DE6|#2B1A1AE6|#080808E6|#333333AA",
	        textColor  = "#FF8080",
	        transition = "ColorTint",
	    },
	    -- Token name slot (unselected)
	    dynSlot = {
	        colors     = "#0D0D26E6|#141433F2|#08081AE6|#333333AA",
	        textColor  = "#9999CC",
	        transition = "ColorTint",
	    },
	    -- Token name slot (selected)
	    dynSlotSelected = {
	        colors     = "#1A3366F2|#2244AAF2|#0F2244F2|#333333AA",
	        textColor  = "#66CCFF",
	        transition = "ColorTint",
	    },
	    -- Remove button
	    dynRemove = {
	        colors     = "#260D0DE6|#401A1AF2|#1A0808E6|#333333AA",
	        textColor  = "#FFFFFF",
	        transition = "ColorTint",
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
		-- Any toggle in its ON state
		toggleOn = {
			colors     = "#145214F2|#1E7A1EF2|#0E3A0EF2|#333333AA",
			textColor  = "#FFFFFF",
			transition = "ColorTint",
		},
		-- Debug group buttons: lower-mid grey so they don't draw the eye
		debug = {
			colors     = "#3C3C3CF2|#4E4E4EF2|#2C2C2CF2|#333333AA",
			textColor  = "#AAAAAA",
			transition = "ColorTint",
		},
		--lineup and radial button style
		lineUpOff = {
			colors     = "#2B2B0DF2|#4A4A1AF2|#1F1F0AF2|#333333AA",
			textColor  = "#FFFF44",
			transition = "ColorTint",
		},
		lineUpOn = {
			colors     = "#484716F2|#6B6B22F2|#303010F2|#333333AA",
			textColor  = "#FFD700",
			transition = "ColorTint",
		},
	}

	local function btnStyle(name)
	    local s = BTN_STYLE[name] or BTN_STYLE.ghost
	    return 'colors="'     .. s.colors     .. '" '
	        .. 'textColor="'  .. s.textColor  .. '" '
	        .. 'transition="' .. s.transition .. '"'
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

	-- An image worth displaying: nil when there's no image or it's the blank placeholder
	local function usefulImageURL(data)
	    local url = extractImageURL(data)
	    if not url or url:find(BLANK_IMAGE_ID, 1, true) then return nil end
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
		entry.nameOnly = (NAME_ONLY_TYPES[data.Name] and isTinted(data)) or false
		entry.imageURL = entry.nameOnly and "" or (usefulImageURL(data) or "")   -- blank placeholder → name
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
		-- Upgrade history from older saves (adds size info, name-only display)
		for _, entry in ipairs(tokenHistory) do prepareHistoryEntry(entry) end
	    refreshTemplateCache()
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

	local function getTokenName(tokenGUID)
	    local obj = getObjectFromGUID(tokenGUID)
	    if obj then
	        local n = obj.getName()
	        if n and n ~= "" then return n end
	    end
	    if templateJSON then
	        local ok, data = pcall(JSON.decode, templateJSON)
	        if ok and type(data) == "table" then
	            if data.Nickname and data.Nickname ~= "" then return data.Nickname end
	            if data.Name    and data.Name    ~= "" then return data.Name    end
	        end
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

	-- Shows/hides the "Large / Very large object" banner on BOTH the OUI and the HUD to
	-- match the current template (colour + text too). Every path that changes the
	-- template calls this, so the two banners can't get out of step.
	local function refreshSizeWarning()
		local sc = templateJSON and sizeClass(templateCache.byteSize)
		-- HUD banner stays hidden while the HUD itself is minimised or switched off
		local hudShow = sc and hudVisible and hudEnabled
		self.UI.setAttribute("sizeWarningPanel",  "active", sc and "True" or "False")
		UI.setAttribute("tc_hud_sizeWarning",     "active", hudShow and "True" or "False")
		if sc then
			local massive = (sc == "massive")
			self.UI.setAttribute("sizeWarningPanel",  "color", massive and "#5A1A00F2" or "#3A3A0AF2")
			self.UI.setAttribute("sizeWarningText",   "text",  massive and "⚠ Very large object — expect some lag" or "⚠ Large object")
			UI.setAttribute("tc_hud_sizeWarning",     "color", massive and "#5A1A00FF" or "#3A3A0AFF")
			UI.setAttribute("tc_hud_sizeWarningText", "text",  massive and "⚠ Very large" or "⚠ Large object")
		end
	end

-- ──────────────────────────────────────────────────────────────
--  TOKEN HISTORY (data layer)
-- ──────────────────────────────────────────────────────────────

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
	end

	local function activateHistoryEntry(index)
		local entry = tokenHistory[index]
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
		-- Update HUD Set Template button
		local tcShort = shortName(stripBBCode(templateCache.name), 20, 2)
		local tcLabel = templateJSON and tcShort or "No Template"
		UI.setAttribute("tc_hud_setTemplate", "text", tcLabel)
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
			UI.show("tc_hud_deleteOverlayPanel")
		else
			self.UI.hide("deleteOverlayPanel")
			UI.hide("tc_hud_deleteOverlayPanel")
		end
		local style = on and "danger" or "settingsItem"
		setButtonLook(self.UI, "editHistoryBtn", on and "←Stop Editing History" or "Edit History", style)
		self.UI.setAttribute("clearHistoryBtn", "active", on and "True" or "False")
		-- HUD versions
		setHudButtonLook("tc_hud_editHistoryBtn", on and HUD_EDIT_ON_LABEL or HUD_EDIT_OFF_LABEL, style)
		UI.setAttribute("tc_hud_clearHistoryBtn", "active", on and "True" or "False")
	end

	-- HistoryEdit button
	function btn_toggleHistoryEdit(_, _)
		setHistoryEditMode(not historyEditMode)
	end
	
	
	
	local function deleteHistoryEntry(index)
		if not tokenHistory[index] then return end
		local removing = tokenHistory[index]
		table.remove(tokenHistory, index)
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

	function btn_history_1(_, _) activateHistoryEntry(1) end
	function btn_history_2(_, _) activateHistoryEntry(2) end
	function btn_history_3(_, _) activateHistoryEntry(3) end
	function btn_history_4(_, _) activateHistoryEntry(4) end
	function btn_history_5(_, _) activateHistoryEntry(5) end
	function btn_history_6(_, _) activateHistoryEntry(6) end
	function btn_history_7(_, _) activateHistoryEntry(7) end
	function btn_history_8(_, _) activateHistoryEntry(8) end

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
--  HUD HISTORY HANDLERS
-- ──────────────────────────────────────────────────────────────

	function hud_history_1(player, _, _) activateHistoryEntry(1) end
	function hud_history_2(player, _, _) activateHistoryEntry(2) end
	function hud_history_3(player, _, _) activateHistoryEntry(3) end
	function hud_history_4(player, _, _) activateHistoryEntry(4) end
	function hud_history_5(player, _, _) activateHistoryEntry(5) end
	function hud_history_6(player, _, _) activateHistoryEntry(6) end
	function hud_history_7(player, _, _) activateHistoryEntry(7) end
	function hud_history_8(player, _, _) activateHistoryEntry(8) end

-- ──────────────────────────────────────────────────────────────
--  HUD ACTION HANDLERS
-- ──────────────────────────────────────────────────────────────

	function hud_addToken(player, _, _)
	    btn_toggleToken(nil, player.color)
	end

	-- "Are you sure?" state: set by the first click, cleared by the second click or after REMOVE_CONFIRM_TIME
	local removeConfirm = nil   -- { color = playerColor, targetGUID = model }

	-- Switches the Remove All button between its normal (yellow) and armed "Sure?" (red) look
	local function setRemoveAllLook(text, styleName)
		setHudButtonLook("tc_hud_dynRemoveAll", text, styleName)
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

	function hud_toggleVisible(player, _, _)
		hudVisible = not hudVisible
		if hudVisible then
			UI.show("tc_hud_root")
			UI.show("tc_hud_core")
			UI.show("tc_hud_minimize")
			UI.show("tc_hud_settings")
			if not hideSetTemplate then UI.show("tc_hud_setTemplate") end
			UI.hide("tc_hud_restore")
			refreshSizeWarning()   -- bring the size banner back if the template needs it
		else
			UI.hide("tc_hud_root")
			UI.hide("tc_hud_core")
			UI.hide("tc_hud_minimize")
			UI.hide("tc_hud_settings")
			UI.hide("tc_hud_setTemplate")
			UI.hide("tc_hud_settingsPanel")
			UI.hide("tc_hud_off")
			UI.hide("tc_hud_restore_tokens")
			UI.hide("tc_hud_find_tokens")
			UI.hide("tc_hud_debug_ids")
			UI.hide("tc_hud_placeBtn")
			UI.hide("tc_hud_dragToggleBtn")
			UI.hide("tc_hud_templateVis")
			UI.hide("tc_hud_root")
			UI.hide("tc_hud_dynPanel")
			UI.hide("tc_hud_sizeWarning")
			UI.hide("tc_hud_deleteOverlayPanel")
			settingsOpen = false
			UI.show("tc_hud_restore")
		end
	end

	function btn_toggleHUD(_, _)
		hudEnabled = not hudEnabled
		if hudEnabled then
			hudVisible = true
			UI.show("tc_hud_root")
			UI.show("tc_hud_core")
			UI.show("tc_hud_minimize")
			UI.show("tc_hud_settings")
			if not hideSetTemplate then UI.show("tc_hud_setTemplate") end
			UI.hide("tc_hud_restore")
			refreshSizeWarning()   -- bring the size banner back if the template needs it
		else
			UI.hide("tc_hud_core")
			UI.hide("tc_hud_minimize")
			UI.hide("tc_hud_settings")
			UI.hide("tc_hud_setTemplate")
			UI.hide("tc_hud_settingsPanel")
			UI.hide("tc_hud_off")
			UI.hide("tc_hud_restore_tokens")
			UI.hide("tc_hud_find_tokens")
			UI.hide("tc_hud_debug_ids")
			UI.hide("tc_hud_placeBtn")
			UI.hide("tc_hud_dragToggleBtn")
			UI.hide("tc_hud_templateVis")
			UI.hide("tc_hud_restore")
			UI.hide("tc_hud_root")
			UI.hide("tc_hud_dynPanel")
			UI.hide("tc_hud_sizeWarning")
			UI.hide("tc_hud_deleteOverlayPanel")
			settingsOpen = false
		end
		rebuildXML()
		setHudButtonLook("tc_hud_off", hudEnabled and "HUD" or "OFF", hudEnabled and "toggleOn" or "danger")
		rebuildHUD()   -- recolouring in place doesn't stick on HUD buttons (TTS quirk); a rebuild draws them fresh
	end

	function hud_toggleSettings(player, _, _)
		btn_toggleSettings(nil, nil)
	end
	
	
	local function refreshDefaultScaleLabel()
		local label = string.format("%.1f", defaultScaleOffset)
		self.UI.setAttribute("defaultScaleLabel", "text", "Default Scale: " .. label)
		UI.setAttribute("tc_hud_defaultScaleLabel", "text", "Default Scale: " .. label)
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
			local pos = UI.getAttribute("tc_hud_root", "offsetXY")
			print("[DragDebug] getAttribute returned: " .. tostring(pos))
			print("[DragDebug] hudRootOffsetXY is: " .. tostring(hudRootOffsetXY))
			if pos and pos ~= "" then
				hudRootOffsetXY = pos
			end
			saveState()
		end
		UI.setAttribute("tc_hud_root", "allowDragging", hudDraggable and "true" or "false")
		setHudButtonLook("tc_hud_dragToggleBtn", "Drag", hudDraggable and "toggleOn" or "danger")
		rebuildHUD()   -- see btn_toggleHUD: rebuild so the button's text colour is correct
	end

	function btn_toggleHudPlacement(_, _)
		hudPlacementMode = not hudPlacementMode
		if hudPlacementMode then
			UI.show("tc_hud_placementOverlay")
		else
			UI.hide("tc_hud_placementOverlay")
		end
		setHudButtonLook("tc_hud_placeBtn", hudPlacementMode and "Cancel" or "Place", hudPlacementMode and "toggleOn" or "settingsItem")
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
		settingsOpen = false  -- close settings so it doesn't linger

		-- Hide everything before the rebuild fires
		UI.hide("tc_hud_root")
		UI.hide("tc_hud_core")
		UI.hide("tc_hud_minimize")
		UI.hide("tc_hud_settings")
		UI.hide("tc_hud_setTemplate")
		UI.hide("tc_hud_settingsPanel")
		UI.hide("tc_hud_off")
		UI.hide("tc_hud_restore_tokens")
		UI.hide("tc_hud_find_tokens")
		UI.hide("tc_hud_debug_ids")
		UI.hide("tc_hud_placeBtn")
		UI.hide("tc_hud_dragToggleBtn")
		UI.hide("tc_hud_templateVis")
		UI.hide("tc_hud_placementOverlay")
		UI.hide("tc_hud_dynPanel")
		UI.hide("tc_hud_sizeWarning")
		UI.hide("tc_hud_deleteOverlayPanel")
		UI.hide("tc_hud_restore")

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
		end
		if settingsOpen then
			self.UI.show("settingsPanel")
			self.UI.show("clearHistoryPanel")
			self.UI.show("templateSettingsPanel")
			self.UI.show("debugSettingsPanel")
			UI.show("tc_hud_settingsPanel")
			UI.show("tc_hud_off")
			UI.show("tc_hud_restore_tokens")
			UI.show("tc_hud_find_tokens")
			UI.show("tc_hud_debug_ids")
			UI.show("tc_hud_placeBtn")
			UI.show("tc_hud_dragToggleBtn")
			UI.show("tc_hud_templateVis")
		else
			self.UI.hide("settingsPanel")
			self.UI.hide("clearHistoryPanel")
			self.UI.hide("templateSettingsPanel")
			self.UI.hide("debugSettingsPanel")
			UI.hide("tc_hud_settingsPanel")
			UI.hide("tc_hud_off")
			UI.hide("tc_hud_restore_tokens")
			UI.hide("tc_hud_find_tokens")
			UI.hide("tc_hud_debug_ids")
			UI.hide("tc_hud_placeBtn")
			UI.hide("tc_hud_dragToggleBtn")
			UI.hide("tc_hud_templateVis")
		end
		-- Update settings button highlight
		self.UI.setAttribute("settingsBtn", "colors",    BTN_STYLE[settingsOpen and "active" or "settings"].colors)
		self.UI.setAttribute("settingsBtn", "textColor", BTN_STYLE[settingsOpen and "active" or "settings"].textColor)
		-- (No setAttribute "active" on panels here: it skips the Grow/Shrink animation that show()/hide() play)
	end
	
	-- SetTemplate button toggle
	function btn_toggleSetTemplate(_, _)
		hideSetTemplate = not hideSetTemplate
		if hideSetTemplate then
			UI.hide("tc_hud_setTemplate")
		else
			UI.show("tc_hud_setTemplate")
		end
		setHudButtonLook("tc_hud_templateVis", hideSetTemplate and "O" or "I", hideSetTemplate and "danger" or "toggleOn")
		rebuildHUD()   -- see btn_toggleHUD
		rebuildXML()
	end
	
	function btn_toggleDropTemplate(_, _)
		dropTemplateEnabled = not dropTemplateEnabled
		rebuildXML()
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
		UI.hide("tc_hud_dynPanel")
		dynPanelVisible   = false
		lastSelectedGUID  = nil
		selectedTokenGUID = nil
	end

	-- Activates the dynamic panel via .show() (not setAttribute) — .show() is the only mechanism that reliably shows this panel on its very first
	-- activation. Guarded so it's never called while already visible, which avoids retriggering the Grow animation during normal gameplay/polling.
	local function activateDynamicPanel()
		if dynPanelVisible then return end
		self.UI.show("dynamicPanel")
		UI.show("tc_hud_dynPanel")
		dynPanelVisible = true
	end

	-- Shows the dynamic panel populated for the given target model.
	-- Replaces showDynamicButtons().
	function showDynamicPanel(targetGUID, tokenCount)
		if lastSelectedGUID == targetGUID then return end

		local tokens = findTokensForTarget(targetGUID)
		local count  = math.min(tokenCount, MAX_TOKENS)
		--show 
		local isLineUp = modelLineUp[targetGUID] or false
		local s = BTN_STYLE[isLineUp and "lineUpOn" or "lineUpOff"]
		local label    = isLineUp and "Radial" or "Line up"
		local fontSize = isLineUp and "10"     or "12"

		self.UI.setAttribute("dynLineUpToggle",        "colors",    s.colors)
		self.UI.setAttribute("dynLineUpToggle",        "textColor", s.textColor)
		self.UI.setAttribute("dynLineUpToggle_text",   "text",      label)
		self.UI.setAttribute("dynLineUpToggle_text",   "fontSize",  fontSize)
		self.UI.setAttribute("dynLineUpToggle_text",   "color",     "#FFFFFF")
		UI.setAttribute("tc_hud_dynLineUpToggle",      "colors",    s.colors)
		UI.setAttribute("tc_hud_dynLineUpToggle",      "textColor", s.textColor)
		UI.setAttribute("tc_hud_dynLineUpToggle_text", "text",      label)
		UI.setAttribute("tc_hud_dynLineUpToggle_text", "fontSize",  fontSize)
		UI.setAttribute("tc_hud_dynLineUpToggle_text", "color",     "#FFFFFF")
		
		--show spread
		local showSpread = tokenCount >= 2
		self.UI.setAttribute("dynSpreadUp",          "active", showSpread and "True" or "False")
		self.UI.setAttribute("dynSpreadDown",        "active", showSpread and "True" or "False")
		UI.setAttribute("tc_hud_dynSpreadUp",        "active", showSpread and "True" or "False")
		UI.setAttribute("tc_hud_dynSpreadDown",      "active", showSpread and "True" or "False")

		for i = 1, MAX_TOKENS do
			local slotActive = (i <= count)
			local tGUID      = tokens[i]
			local slotId     = "dynSlot_" .. i
			local hudSlotId  = "tc_hud_dynSlot_" .. i

			self.UI.setAttribute(slotId,             "active", slotActive and "True" or "False")
			self.UI.setAttribute("dynRemove_" .. i,  "active", slotActive and "True" or "False")
			UI.setAttribute(hudSlotId,               "active", slotActive and "True" or "False")
			UI.setAttribute("tc_hud_dynRemove_" .. i,"active", slotActive and "True" or "False")

			if slotActive and tGUID then
				local name       = getTokenName(tGUID)
				local isSelected = (selectedTokenGUID == tGUID)
				local slotStyle  = isSelected and "dynSlotSelected" or "dynSlot"
				local label      = shortName(stripBBCode(name), 35, 2)
				local hudLabel   = shortName(stripBBCode(name), 14, 2)

				self.UI.setAttribute(slotId, "text",      label)
				self.UI.setAttribute(slotId, "colors",    BTN_STYLE[slotStyle].colors)
				self.UI.setAttribute(slotId, "textColor", BTN_STYLE[slotStyle].textColor)

				UI.setAttribute(hudSlotId, "text",      hudLabel)
				UI.setAttribute(hudSlotId, "colors",    BTN_STYLE[slotStyle].colors)
				UI.setAttribute(hudSlotId, "textColor", BTN_STYLE[slotStyle].textColor)

				self.setVar("removeSlot_" .. i, tGUID)
				self.setVar("selectSlot_" .. i, tGUID)
			end
		end

		activateDynamicPanel()
		lastSelectedGUID = targetGUID
	end

	-- Refreshes slot highlight states after a select/deselect.
	-- Replaces the self.editButton loop in handleSelectToken.
	local function refreshSlotHighlights()
		local tokens = lastSelectedGUID and findTokensForTarget(lastSelectedGUID) or {}
		for i, tGUID in ipairs(tokens) do
			if i > MAX_TOKENS then break end
			local isSelected = (selectedTokenGUID == tGUID)
			local slotStyle  = isSelected and "dynSlotSelected" or "dynSlot"
			local slotId     = "dynSlot_" .. i
			local hudSlotId  = "tc_hud_dynSlot_" .. i
			self.UI.setAttribute(slotId,    "colors",    BTN_STYLE[slotStyle].colors)
			self.UI.setAttribute(slotId,    "textColor", BTN_STYLE[slotStyle].textColor)
			UI.setAttribute(hudSlotId,      "colors",    BTN_STYLE[slotStyle].colors)
			UI.setAttribute(hudSlotId,      "textColor", BTN_STYLE[slotStyle].textColor)
		end
	end

	--refresh history slots using setAttribute system (prevent need for rebuilds)
	refreshHistorySlots = function()
		for i = 1, HISTORY_MAX do
			local entry    = tokenHistory[i]
			local isActive = entry and (templateJSON == entry.json)
			local style    = isActive and "active" or (entry and "historySlot" or "ghost")
			local hasImage = entry and entry.imageURL and entry.imageURL ~= ""
			local imgURL   = hasImage and entry.imageURL or ""
			local txtLabel = entry and shortName(stripBBCode(entry.name), 5, 3) or "·"
			local txtColor = entry and "#FFFFFF" or "#404040"
			local hudLabel = entry and shortName(stripBBCode(entry.name), 4, 2) or "·"
			local hudColor = entry and "#FFFFFF" or "#303030"
			local sc       = entry and sizeClass(entry.byteSize)

			local tooltipText = historyTooltip(entry)

			-- Size badge (OUI + HUD): shown only for large/massive templates
			self.UI.setAttribute("histBtn" .. i .. "_warn",      "active", sc and "True" or "False")
			UI.setAttribute("tc_hud_hist_" .. i .. "_warn",      "active", sc and "True" or "False")
			if sc then
				self.UI.setAttribute("histBtn" .. i .. "_warn",  "color",  SIZE_BADGE_COLOR[sc])
				UI.setAttribute("tc_hud_hist_" .. i .. "_warn",  "color",  SIZE_BADGE_COLOR[sc])
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
			UI.setAttribute("tc_hud_hist_" .. i,              "colors",    BTN_STYLE[style].colors)
			UI.setAttribute("tc_hud_hist_" .. i,              "textColor", BTN_STYLE[style].textColor)
			UI.setAttribute("tc_hud_hist_" .. i,              "tooltip",   tooltipText)
			UI.setAttribute("tc_hud_hist_" .. i .. "_img",    "image",     imgURL)
			UI.setAttribute("tc_hud_hist_" .. i .. "_img",    "active",    hasImage and "True" or "False")
			UI.setAttribute("tc_hud_hist_" .. i .. "_txt",    "text",      hudLabel)
			UI.setAttribute("tc_hud_hist_" .. i .. "_txt",    "color",     hudColor)
			UI.setAttribute("tc_hud_hist_" .. i .. "_txt",    "active",    hasImage and "False" or "True")
			
			-- OUI delete overlay slot
			local delEntry = tokenHistory[i]
			if delEntry and delEntry.imageURL and delEntry.imageURL ~= "" then
				self.UI.setAttribute("delBtn" .. i, "image", delEntry.imageURL)
			end

			-- HUD delete overlay slot  
			if delEntry and delEntry.imageURL and delEntry.imageURL ~= "" then
				UI.setAttribute("tc_hud_delBtn" .. i, "image", delEntry.imageURL)
			end
			
			-- Update overlay slot images
			self.UI.setAttribute("delBtn" .. i .. "_img",        "image",  imgURL)
			self.UI.setAttribute("delBtn" .. i .. "_img",        "active", hasImage and "True" or "False")
			UI.setAttribute("tc_hud_delBtn" .. i .. "_img",      "image",  imgURL)
			UI.setAttribute("tc_hud_delBtn" .. i .. "_img",      "active", hasImage and "True" or "False")
		end
	end

	--improved dyn_btn animations
	function refreshDynamicPanelSlots(targetGUID)
		local tokens = findTokensForTarget(targetGUID)
		local count  = #tokens

		local showSpread = count >= 2
		self.UI.setAttribute("dynSpreadUp",     "active", showSpread and "True" or "False")
		self.UI.setAttribute("dynSpreadDown",   "active", showSpread and "True" or "False")
		UI.setAttribute("tc_hud_dynSpreadUp",   "active", showSpread and "True" or "False")
		UI.setAttribute("tc_hud_dynSpreadDown", "active", showSpread and "True" or "False")

		for i = 1, MAX_TOKENS do
			local slotActive = (i <= count)
			local tGUID      = tokens[i]
			local slotId     = "dynSlot_" .. i
			local hudSlotId  = "tc_hud_dynSlot_" .. i

			self.UI.setAttribute(slotId,              "active", slotActive and "True" or "False")
			self.UI.setAttribute("dynRemove_" .. i,   "active", slotActive and "True" or "False")
			UI.setAttribute(hudSlotId,                "active", slotActive and "True" or "False")
			UI.setAttribute("tc_hud_dynRemove_" .. i, "active", slotActive and "True" or "False")

			if slotActive and tGUID then
				local name      = getTokenName(tGUID)
				local isSelected = (selectedTokenGUID == tGUID)
				local slotStyle  = isSelected and "dynSlotSelected" or "dynSlot"
				local label      = shortName(stripBBCode(name), 35, 2)
				local hudLabel   = shortName(stripBBCode(name), 14, 2)

				self.UI.setAttribute(slotId, "text",      label)
				self.UI.setAttribute(slotId, "colors",    BTN_STYLE[slotStyle].colors)
				self.UI.setAttribute(slotId, "textColor", BTN_STYLE[slotStyle].textColor)
				UI.setAttribute(hudSlotId,   "text",      hudLabel)
				UI.setAttribute(hudSlotId,   "colors",    BTN_STYLE[slotStyle].colors)
				UI.setAttribute(hudSlotId,   "textColor", BTN_STYLE[slotStyle].textColor)

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
		table.insert(lines, '  <Panel id="previewTextPanel" width="150" height="150" color="#000000CC" rectAlignment="MiddleCenter" active="' .. (hasImage and "False" or "True") .. '">')
		table.insert(lines, '    <Text id="previewText" text="' .. previewText .. '" fontSize="22" color="#FFFFFF" fontStyle="Bold" alignment="MiddleCenter" width="140" height="140" />')
		table.insert(lines, '  </Panel>')
		table.insert(lines, '</Panel>')

	    -- ── History grid ──
	    table.insert(lines, '<Panel id="historyPanel"')
	    table.insert(lines,   ' position="0 -380 -25"')
	    table.insert(lines,   ' rotation="0 0 0"')
	    table.insert(lines,   ' width="448" height="228"')
	    table.insert(lines,   ' color="#00000000">')
	    table.insert(lines, '  <GridLayout cellSize="110 110" spacing="2 2" startCorner="UpperLeft" startAxis="Horizontal" childAlignment="UpperLeft" width="448" height="228">')
	   for i = 1, HISTORY_MAX do
			local entry    = tokenHistory[i]
			local isActive = entry and (templateJSON == entry.json)
			local style    = isActive and "active" or (entry and "historySlot" or "ghost")
			local hasImage = entry and entry.imageURL and entry.imageURL ~= ""
			local imgURL   = hasImage and entry.imageURL or ""
			local txtLabel = entry and shortName(stripBBCode(entry.name), 5, 3) or "·"
			local txtColor = entry and "#FFFFFF" or "#404040"
			local txtSize  = entry and "20" or "20"
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
			table.insert(lines, '        width="100" height="100"')
			table.insert(lines, '        preserveAspect="true"')
			table.insert(lines, '        active="' .. (hasImage and "True" or "False") .. '" />')
			table.insert(lines, '      <Text id="histBtn' .. i .. '_txt"')
			table.insert(lines, '        text="' .. txtLabel .. '"')
			table.insert(lines, '        fontSize="' .. txtSize .. '"')
			table.insert(lines, '        color="' .. txtColor .. '"')
			table.insert(lines, '        alignment="MiddleCenter"')
			table.insert(lines, '        width="80" height="80"')
			table.insert(lines, '        active="' .. (hasImage and "False" or "True") .. '" />')
			table.insert(lines, sizeBadgeXml('histBtn' .. i .. '_warn', sc, 28, 18))
			table.insert(lines, '    </Button>')
		end
	    table.insert(lines, '  </GridLayout>')
	    table.insert(lines, '</Panel>')
		
		
		-- ── Delete overlay panel ──
		table.insert(lines, '<Panel id="deleteOverlayPanel"')
		table.insert(lines, '  active="False"')
		table.insert(lines, '  position="0 -380 -25"')
		table.insert(lines, '  rotation="0 0 0"')
		table.insert(lines, '  width="448" height="228"')
		table.insert(lines, '  color="#00000000">')
		table.insert(lines, '  <GridLayout cellSize="110 110" spacing="2 2" startCorner="UpperLeft" startAxis="Horizontal" childAlignment="UpperLeft" width="448" height="228">')
		for i = 1, HISTORY_MAX do
			local entry = tokenHistory[i]
			table.insert(lines, '    <Button id="delBtn' .. i .. '"')
			table.insert(lines, '      onClick="btn_deleteHistory_' .. i .. '"')
			table.insert(lines, '      ' .. btnStyle("danger"))
			table.insert(lines, '      width="100" height="100"')
			table.insert(lines, '      padding="3 3 3 3">')
			if entry and entry.imageURL and entry.imageURL ~= "" then
				table.insert(lines, '      <Image id="delBtn' .. i .. '_img" image="' .. entry.imageURL .. '" width="100" height="100" preserveAspect="true" />')
			end
			table.insert(lines, '      <Panel width="100" height="100" color="#AA000066" />')
			table.insert(lines, '      <Text text="✕" color="#FF6666FF" fontSize="50" alignment="MiddleCenter" /></Button>')
		end
		table.insert(lines, '  </GridLayout>')
		table.insert(lines, '</Panel>')

	    -- ── Settings button ──
	    table.insert(lines, '<Button id="settingsBtn"')
		table.insert(lines, '  onClick="btn_toggleSettings"')
		table.insert(lines, '  ' .. btnStyle(settingsOpen and "active" or "settings"))
	    table.insert(lines, '  position="0 -530 -25"')
	    table.insert(lines, '  rotation="0 0 0"')
	    table.insert(lines, '  width="448" height="60"')
	    table.insert(lines, '  fontSize="40"')
	    table.insert(lines, '  tooltip="Open/close settings"')
	    local ss = BTN_STYLE.settings
		table.insert(lines, '  padding="5 5 5 5"><Text text="⚙" color="' .. ss.textColor .. '" fontSize="40" /></Button>')

	    -- ── Settings panel ──
		-- Layout (OUI units, y up). History grid spans x -224..224, top at y -266.
		--   Token Creation     x -684..-468  y -266..-426
		--   Token History      x -461..-239  y -266..-438
		--   HUD                x -684..-236  y -446..-504
		--   Debug              x -684..-236  y -512..-588   (last thing the user sees)
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
		table.insert(lines, '  color="#2B1A00F2">')
		table.insert(lines, '  <VerticalLayout spacing="4" padding="4 4 4 4" childAlignment="UpperCenter">')
		table.insert(lines, '    <Text text="Token History" color="' .. BTN_STYLE.template.textColor .. '" fontSize="14" fontStyle="Bold" alignment="MiddleCenter" preferredWidth="214" preferredHeight="20" />')
		local eStyle = historyEditMode and "danger" or "settingsItem"
		table.insert(lines, '    <Button id="editHistoryBtn" onClick="btn_toggleHistoryEdit" tooltip="Toggle delete mode on history slots" ' .. btnStyle(eStyle) .. ' fontSize="20" preferredWidth="214" preferredHeight="44"><Text id="editHistoryBtn_text" text="' .. (historyEditMode and "←Stop Editing History" or "Edit History") .. '" color="' .. BTN_STYLE[eStyle].textColor .. '" fontSize="20" /></Button>')
		-- Default token scale (moved here from the main settings panel)
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
		-- Clear History: last, and only shown while Edit History is live. Two-click confirm (see btn_clearHistory)
		table.insert(lines, '    <Button id="clearHistoryBtn" onClick="btn_clearHistory" tooltip="Clear all token history and reset template (click twice to confirm)" ' .. btnStyle(CLEAR_HISTORY_STYLE) .. ' fontSize="20" preferredWidth="214" preferredHeight="44" active="' .. (historyEditMode and "True" or "False") .. '"><Text id="clearHistoryBtn_text" text="' .. CLEAR_HISTORY_LABEL .. '" color="' .. BTN_STYLE[CLEAR_HISTORY_STYLE].textColor .. '" resizeTextForBestFit="true" resizeTextMinSize="10" resizeTextMaxSize="20" /></Button>')
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
		table.insert(lines, '  color="#1A1A1AF2">')
		table.insert(lines, '  <VerticalLayout spacing="4" padding="4 4 4 4" childAlignment="UpperCenter">')
		table.insert(lines, '    <Text text="Token Creation" color="' .. BTN_STYLE.template.textColor .. '" fontSize="14" fontStyle="Bold" alignment="MiddleCenter" preferredWidth="208" preferredHeight="20" />')
		table.insert(lines, '    <Button onClick="btn_toggleSetTemplate"')
		table.insert(lines, '      tooltip="Show or hide the Set Template button"')
		table.insert(lines, '      ' .. btnStyle(hideSetTemplate and "danger" or "toggleOn"))
		table.insert(lines, '      fontSize="18" preferredWidth="208" preferredHeight="40"')
		table.insert(lines, '      ><Text text="' .. (hideSetTemplate and "Set Template: OFF" or "Set Template: ON") .. '" color="' .. BTN_STYLE[hideSetTemplate and "danger" or "toggleOn"].textColor .. '" fontSize="18" /></Button>')
		table.insert(lines, '    <Button onClick="btn_toggleDropTemplate"')
		table.insert(lines, '      tooltip="Enable or disable dropping objects onto TC to set template"')
		table.insert(lines, '      ' .. btnStyle(dropTemplateEnabled and "toggleOn" or "danger"))
		table.insert(lines, '      fontSize="18" preferredWidth="208" preferredHeight="40"')
		table.insert(lines, '      ><Text text="' .. (dropTemplateEnabled and "Drop Template: ON" or "Drop Template: OFF") .. '" color="' .. BTN_STYLE[dropTemplateEnabled and "toggleOn" or "danger"].textColor .. '" fontSize="18" /></Button>')
		table.insert(lines, '    <Button onClick="btn_toggleTemplatePreview"')
		table.insert(lines, '      tooltip="Spawn a 3D copy of the template next to the Token Applier when it has no image to show"')
		table.insert(lines, '      ' .. btnStyle(showTemplatePreview and "toggleOn" or "danger"))
		table.insert(lines, '      fontSize="18" preferredWidth="208" preferredHeight="40"')
		table.insert(lines, '      ><Text text="' .. (showTemplatePreview and "3D Preview: ON" or "3D Preview: OFF") .. '" color="' .. BTN_STYLE[showTemplatePreview and "toggleOn" or "danger"].textColor .. '" fontSize="18" /></Button>')
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
		table.insert(lines, '  color="#484716F2">')
		table.insert(lines, '  <VerticalLayout padding="4 4 4 4" childAlignment="MiddleCenter">')
		local hStyle = hudEnabled and "toggleOn" or "danger"
		table.insert(lines, '    <Button id="hudToggleBtn"')
		table.insert(lines, '      onClick="btn_toggleHUD"')
		table.insert(lines, '      tooltip="Show or hide the on-screen HUD"')
		table.insert(lines, '      ' .. btnStyle(hStyle))
		table.insert(lines, '      fontSize="22" preferredWidth="440" preferredHeight="50"')
		table.insert(lines, '      >' .. (hudEnabled and "HUD: ON" or "HUD: OFF") .. '</Button>')
		table.insert(lines, '  </VerticalLayout>')
		table.insert(lines, '</Panel>')

		-- ── Debug Settings panel (bottom; grey so it doesn't draw the eye) ──
		table.insert(lines, '<Panel id="debugSettingsPanel"')
		table.insert(lines, '  active="' .. (settingsOpen and "True" or "False") .. '"')
		table.insert(lines, '  showAnimation="Grow"')
		table.insert(lines, '  hideAnimation="Shrink"')
		table.insert(lines, '  animationDuration="0.1"')
		table.insert(lines, '  position="-460 -550 -25"')
		table.insert(lines, '  rotation="0 0 0"')
		table.insert(lines, '  width="448" height="76"') 	-- title 20 + 1 row × 44 + 1 gap × 4 + 8 padding
		table.insert(lines, '  color="#1E1E1EF2">')
		table.insert(lines, '  <VerticalLayout spacing="4" padding="4 4 4 4" childAlignment="UpperCenter">')
		table.insert(lines, '    <Text text="Debug Settings" color="' .. BTN_STYLE.debug.textColor .. '" fontSize="14" fontStyle="Bold" alignment="MiddleCenter" preferredWidth="440" preferredHeight="20" />')
		table.insert(lines, '    <HorizontalLayout spacing="4" childAlignment="MiddleCenter" preferredHeight="44">')
		table.insert(lines, '      <Button onClick="btn_restoreTokens" tooltip="Restore tokens after save/load if any are missing" ' .. btnStyle("debug") .. ' fontSize="18" preferredWidth="144" preferredHeight="44">↺ Restore</Button>')
		table.insert(lines, '      <Button onClick="btn_debug" tooltip="Print current hover-token table to console" ' .. btnStyle("debug") .. ' fontSize="18" preferredWidth="144" preferredHeight="44">Debug IDs</Button>')
		table.insert(lines, '      <Button onClick="btn_findTokens" tooltip="Find and adopt tokens left behind by a deleted or old Token Applier" ' .. btnStyle("debug") .. ' fontSize="18" preferredWidth="144" preferredHeight="44">Find Tokens</Button>')
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
		local warnColor = templateCache.byteSize > SIZE_MASSIVE and "#5A1A00F2" or "#3A3A0AF2"
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
		local s = BTN_STYLE[isLineUp and "active" or "danger"]
		table.insert(lines, '  <Button id="dynLineUpToggle"'
			.. ' onClick="btn_toggleModelLineUp"'
			.. ' tooltip="Toggle line-up mode"'
			.. ' colors="' .. s.colors .. '"'
			.. ' textColor="' .. s.textColor .. '"'
			.. ' transition="' .. s.transition .. '"'
			.. ' width="' .. BW .. '" height="' .. BW .. '"'
			.. ' fontSize="30"'
			.. ' rectAlignment="UpperLeft"'
			.. ' offsetXY="' .. col4() .. ' ' .. row(0) .. '">'
			.. '<Text id="dynLineUpToggle_text" text="Line up" color="#FFFFFF" fontSize="22" width="' .. BW .. '" height="' .. BW .. '" alignment="MiddleCenter" />'
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
	        table.insert(lines, '    fontSize="22">–</Button>')
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
		table.insert(lines, '<Panel id="tc_hud_root"')
		table.insert(lines, '  rectAlignment="LowerCenter"')
		table.insert(lines, '  offsetXY="' .. hudRootOffsetXY .. '"')
		table.insert(lines, '  width="200" height="150"')
		table.insert(lines, '  color="#00000000"')
		table.insert(lines, '  allowDragging="' .. (hudDraggable and "true" or "false") .. '"')
		table.insert(lines, '  restrictDraggingToParentBounds="false"')
		table.insert(lines, '  returnToOriginalPositionWhenReleased="false">')

	    -- ── CORE panel ──
	    -- Contains: Add Token, History Grid (2×4), Minimize footer
	    table.insert(lines, '<Panel id="tc_hud_core"')
		table.insert(lines, '  rectAlignment="LowerCenter"')
		table.insert(lines, '  offsetXY="0 27"')
		table.insert(lines, '  width="233" height="166"')
		table.insert(lines, '  color="#00000000"') -- was CC
		table.insert(lines, '  padding="4 4 4 4">')

		table.insert(lines, '  <VerticalLayout spacing="3" childAlignment="UpperCenter">')

		-- Add Token button
		table.insert(lines, '    <Button id="tc_hud_add"')
		table.insert(lines, '      onClick="' .. g .. '/hud_addToken"')
		table.insert(lines, '      ' .. btnStyle("hudAdd"))
		table.insert(lines, '      fontSize="18" preferredWidth="225" preferredHeight="44"')
		table.insert(lines, '      tooltip="Add token to selected model"')
		table.insert(lines, '      >＋ Add Token</Button>')

		-- History grid (2 rows × 4 cols)
		table.insert(lines, '    <GridLayout id="tc_hud_grid"')
		table.insert(lines, '      cellSize="54 54" spacing="3 3"')
		table.insert(lines, '      startCorner="UpperLeft" startAxis="Horizontal"')
		table.insert(lines, '      childAlignment="UpperLeft"')
		table.insert(lines, '      width="225" height="111">')

	    for i = 1, HISTORY_MAX do
			local entry    = tokenHistory[i]
			local isActive = entry and (templateJSON == entry.json)
			local style    = isActive and "active" or (entry and "historySlot" or "ghost")
			local hasImage = entry and entry.imageURL and entry.imageURL ~= ""
			local imgURL   = hasImage and entry.imageURL or ""
			local txtLabel = entry and shortName(stripBBCode(entry.name), 4, 2) or "·"
			local txtColor = entry and "#FFFFFF" or "#303030"
			local sc       = entry and sizeClass(entry.byteSize)
			local tooltipText = historyTooltip(entry)

			table.insert(lines, '    <Button id="tc_hud_hist_' .. i .. '"')
			table.insert(lines, '      onClick="' .. g .. '/hud_history_' .. i .. '"')
			table.insert(lines, '      tooltip="' .. tooltipText .. '"')
			table.insert(lines, '      ' .. btnStyle(style))
			table.insert(lines, '      width="54" height="54"')
			table.insert(lines, '      padding="2 2 2 2">')
			table.insert(lines, '      <Image id="tc_hud_hist_' .. i .. '_img"')
			table.insert(lines, '        image="' .. imgURL .. '"')
			table.insert(lines, '        width="50" height="50"')
			table.insert(lines, '        preserveAspect="true"')
			table.insert(lines, '        active="' .. (hasImage and "True" or "False") .. '" />')
			table.insert(lines, '      <Text id="tc_hud_hist_' .. i .. '_txt"')
			table.insert(lines, '        text="' .. txtLabel .. '"')
			table.insert(lines, '        fontSize="14"')
			table.insert(lines, '        color="' .. txtColor .. '"')
			table.insert(lines, '        alignment="MiddleCenter"')
			table.insert(lines, '        active="' .. (hasImage and "False" or "True") .. '" />')
			table.insert(lines, sizeBadgeXml('tc_hud_hist_' .. i .. '_warn', sc, 16, 10))
			table.insert(lines, '    </Button>')
		end

	    table.insert(lines, '    </GridLayout>')
		table.insert(lines, '  </VerticalLayout>')
		
		table.insert(lines, '</Panel><!--tc_hud_core-->') -- end tc_hud_core
		
		
		-- ── HUD Delete overlay panel ──
		table.insert(lines, '<Panel id="tc_hud_deleteOverlayPanel"')
		table.insert(lines, '  active="' .. (historyEditMode and "True" or "False") .. '"')	-- survives a rebuild mid-edit
		table.insert(lines, '  rectAlignment="LowerCenter"')
		table.insert(lines, '  offsetXY="0 31"')  --attempt to move the location of this panel
		table.insert(lines, '  width="225" height="111"')
		table.insert(lines, '  color="#00000000">')
		table.insert(lines, '  <GridLayout cellSize="54 54" spacing="3 3" startCorner="UpperLeft" startAxis="Horizontal" childAlignment="UpperLeft" width="225" height="111">')
		for i = 1, HISTORY_MAX do
			local entry = tokenHistory[i]
			local g = guid
			table.insert(lines, '    <Button id="tc_hud_delBtn' .. i .. '"')
			table.insert(lines, '      onClick="' .. g .. '/hud_deleteHistory_' .. i .. '"')
			table.insert(lines, '      ' .. btnStyle("danger"))
			table.insert(lines, '      width="54" height="54"')
			table.insert(lines, '      padding="2 2 2 2">')
			if entry and entry.imageURL and entry.imageURL ~= "" then
				table.insert(lines, '      <Image id="tc_hud_delBtn' .. i .. '_img" image="' .. entry.imageURL .. '" width="50" height="50" preserveAspect="true" />')
			end
			table.insert(lines, '      <Panel width="54" height="54" color="#AA000066" />')
			table.insert(lines, '      <Text text="✕" color="#FF6666FF" fontSize="28" alignment="MiddleCenter" /></Button>')
		end
		table.insert(lines, '  </GridLayout>')
		table.insert(lines, '</Panel><!--tc_hud_deleteOverlayPanel-->') -- end deleteOverlayPanel
	

	    -- ── Footer strip: [⚙][—— minimise ——] ──
	    -- Together they span the CORE width (x -118..118) so they read as one bar:
	    --   ⚙ x -118..-92, 2px gap, minimise x -90..118
	    table.insert(lines, '<Button id="tc_hud_minimize"')
	    table.insert(lines, '  rectAlignment="LowerCenter"')
	    table.insert(lines, '  offsetXY="14 2"')
	    table.insert(lines, '  width="208" height="26"')
	    table.insert(lines, '  onClick="' .. g .. '/hud_toggleVisible"')
	    table.insert(lines, '  ' .. btnStyle("hudHide"))
	    table.insert(lines, '  fontSize="12"')
	    table.insert(lines, '  tooltip="Minimise HUD"')
	    table.insert(lines, '  >— minimise —</Button>')

	    -- ── Settings button (1:1 square, left end of the footer strip) ──
	    table.insert(lines, '<Button id="tc_hud_settings"')
	    table.insert(lines, '  rectAlignment="LowerCenter"')
	    table.insert(lines, '  offsetXY="-105 2"')
	    table.insert(lines, '  width="26" height="26"')
	    table.insert(lines, '  onClick="' .. g .. '/hud_toggleSettings"')
	    table.insert(lines, '  ' .. btnStyle(settingsOpen and "active" or "settings"))
	    table.insert(lines, '  fontSize="14"')
	    table.insert(lines, '  tooltip="Settings"')
		local ss = BTN_STYLE.settings
		table.insert(lines, '  ><Text text="⚙" color="' .. ss.textColor .. '" fontSize="10" width="26" height="26" alignment="MiddleCenter" /></Button>')

		-- HUD layout (offsets from tc_hud_root's bottom-centre; x = button centre, y = button bottom)
		--   Token History panel   x -240..-120  y 61..176   (left of the history grid, which spans x -112..112)
		--   HUD row               x -240..-120  y 31..57    [HUD][Place][Drag]
		--   Debug row             x -207..-121  y 2..28     [F][↺][ID]  then the footer strip [⚙][minimise] (x -118..118)

	    -- ── HUD row: HUD on/off, Place HUD, HUD Drag (only while settings are open) ──
	    local function hudRowBtn(id, onClick, tooltip, style, label, x)
	        local s = BTN_STYLE[style]
	        return '<Button id="' .. id .. '" active="' .. (settingsOpen and "True" or "False") .. '"'
	            .. ' rectAlignment="LowerCenter" offsetXY="' .. x .. ' 31" width="38" height="26"'
	            .. ' onClick="' .. g .. '/' .. onClick .. '" ' .. btnStyle(style) .. ' tooltip="' .. tooltip .. '">'
	            .. '<Text id="' .. id .. '_text" text="' .. label .. '" color="' .. s.textColor .. '" fontSize="9" alignment="MiddleCenter" /></Button>'
	    end
	    table.insert(lines, hudRowBtn("tc_hud_off", "btn_toggleHUD", "Toggle HUD on/off",
	        hudEnabled and "toggleOn" or "danger", hudEnabled and "HUD" or "OFF", -221))
	    table.insert(lines, hudRowBtn("tc_hud_placeBtn", "btn_toggleHudPlacement", "Place HUD: choose a fixed position for the HUD",
	        hudPlacementMode and "toggleOn" or "settingsItem", hudPlacementMode and "Cancel" or "Place", -180))
	    table.insert(lines, hudRowBtn("tc_hud_dragToggleBtn", "btn_toggleHudDraggable", "HUD Drag: allow the HUD to be dragged anywhere on screen",
	        hudDraggable and "toggleOn" or "danger", "Drag", -139))

	    -- ── Set Template button (independent) ──
	    table.insert(lines, '<Button id="tc_hud_setTemplate"')
	    table.insert(lines, '  active="' .. (hideSetTemplate and "False" or "True") .. '"')
	    table.insert(lines, '  rectAlignment="LowerCenter"')
	    table.insert(lines, '  offsetXY="0 190"')  -- old loaction offsetXY="-200 145"'
	    table.insert(lines, '  width="160" height="30"')
	    table.insert(lines, '  onClick="' .. g .. '/btn_setTemplate"')
	    table.insert(lines, '  ' .. btnStyle("template"))
	    table.insert(lines, '  fontSize="14"')
	    table.insert(lines, '  tooltip="Set token template from selected object"')
	    local tcShort = shortName(stripBBCode(templateCache.name), 20, 2)
	    local tcLabel = templateJSON and tcShort or "No Template"
	    table.insert(lines, '  >' .. tcLabel .. '</Button>')
		
		-- ── Size warning ──
		local warnText  = templateCache.byteSize > SIZE_MASSIVE and "⚠ Very large" or "⚠ Large object"
		local warnColor = templateCache.byteSize > SIZE_MASSIVE and "#5A1A00FF" or "#3A3A0AFF"
		local warnActive = templateCache.byteSize > SIZE_LARGE and "True" or "False"
		table.insert(lines, '<Panel id="tc_hud_sizeWarning"')
		table.insert(lines, '  active="' .. warnActive .. '"')
		table.insert(lines, '  rectAlignment="LowerCenter"')
		table.insert(lines, '  offsetXY="0 140"')
		table.insert(lines, '  width="224" height="14"')
		table.insert(lines, '  color="' .. warnColor .. '">')
		table.insert(lines, '  <Text id="tc_hud_sizeWarningText" text="' .. warnText .. '" fontSize="8" color="#FFAA44" alignment="MiddleCenter" />')
		table.insert(lines, '</Panel>')

	    -- ── Token History panel (Edit History / Default Scale / Clear History) — left of the history grid ──
	    -- Keeps the old id "tc_hud_settingsPanel" so existing show/hide code still works.
	    -- Fixed height that fits its contents, so the layout never squashes the buttons.
	    table.insert(lines, '<Panel id="tc_hud_settingsPanel"')
	    table.insert(lines, '  active="' .. (settingsOpen and "True" or "False") .. '"')
	    table.insert(lines, '  showAnimation="Grow"')
	    table.insert(lines, '  hideAnimation="Shrink"')
	    table.insert(lines, '  animationDuration="0.1"')
	    table.insert(lines, '  rectAlignment="LowerCenter"')
		table.insert(lines, '  offsetXY="-180 61"')
	    table.insert(lines, '  width="120" height="115"') 	-- 4 pad + title 14 + 3 rows × 28 + 3 gaps × 3 + 4 pad
		table.insert(lines, '  color="#2B1A00F2">')
	    table.insert(lines, '  <VerticalLayout spacing="3" padding="4 4 4 4" childAlignment="UpperCenter" childForceExpandHeight="false">')
	    table.insert(lines, '    <Text text="Token History" color="' .. BTN_STYLE.template.textColor .. '" fontSize="10" fontStyle="Bold" alignment="MiddleCenter" preferredWidth="112" preferredHeight="14" />')
	    -- Edit History
	    local heStyle = historyEditMode and "danger" or "settingsItem"
	    table.insert(lines, '    <Button id="tc_hud_editHistoryBtn" onClick="' .. g .. '/btn_toggleHistoryEdit"')
	    table.insert(lines, '      ' .. btnStyle(heStyle))
	    table.insert(lines, '      preferredWidth="112" preferredHeight="28"')
	    table.insert(lines, '      tooltip="Toggle delete mode on history slots">')
	    table.insert(lines, '      <Text id="tc_hud_editHistoryBtn_text" text="' .. (historyEditMode and HUD_EDIT_ON_LABEL or HUD_EDIT_OFF_LABEL) .. '" color="' .. BTN_STYLE[heStyle].textColor .. '" resizeTextForBestFit="true" resizeTextMinSize="7" resizeTextMaxSize="12" alignment="MiddleCenter" /></Button>')
		-- Default scale adjust
		-- Stepper layout: label on the left (wraps to 2 lines), [–][+] side by side on the right
		table.insert(lines, '    <HorizontalLayout spacing="2" childAlignment="MiddleCenter" preferredHeight="28">')
		table.insert(lines, '      <Text id="tc_hud_defaultScaleLabel" text="Default Scale: ' .. string.format("%.1f", defaultScaleOffset) .. '" color="#FFFFFF" resizeTextForBestFit="true" resizeTextMinSize="6" resizeTextMaxSize="10" alignment="MiddleLeft" preferredWidth="52" preferredHeight="28" />')
		table.insert(lines, '      <Button onClick="' .. g .. '/btn_defaultScaleDown"')
		table.insert(lines, '        ' .. btnStyle("settingsItem"))
		table.insert(lines, '        tooltip="Decrease default spawn scale"')
		table.insert(lines, '        fontSize="16" preferredWidth="28" preferredHeight="28">–</Button>')
		table.insert(lines, '      <Button onClick="' .. g .. '/btn_defaultScaleUp"')
		table.insert(lines, '        ' .. btnStyle("settingsItem"))
		table.insert(lines, '        tooltip="Increase default spawn scale"')
		table.insert(lines, '        fontSize="16" preferredWidth="28" preferredHeight="28">+</Button>')
		table.insert(lines, '    </HorizontalLayout>')
	    -- Clear History: last, only while Edit History is live; two-click confirm (see btn_clearHistory)
	    table.insert(lines, '    <Button id="tc_hud_clearHistoryBtn" onClick="' .. g .. '/btn_clearHistory"')
	    table.insert(lines, '      ' .. btnStyle(CLEAR_HISTORY_STYLE))
	    table.insert(lines, '      preferredWidth="112" preferredHeight="28"')
	    table.insert(lines, '      active="' .. (historyEditMode and "True" or "False") .. '"')
	    table.insert(lines, '      tooltip="Clear all token history and reset template (click twice to confirm)">')
	    table.insert(lines, '      <Text id="tc_hud_clearHistoryBtn_text" text="' .. HUD_CLEAR_LABEL .. '" color="' .. BTN_STYLE[CLEAR_HISTORY_STYLE].textColor .. '" resizeTextForBestFit="true" resizeTextMinSize="7" resizeTextMaxSize="12" alignment="MiddleCenter" /></Button>')
	    table.insert(lines, '  </VerticalLayout>')
	    table.insert(lines, '</Panel><!--tc_hud_settingsPanel-->') -- end tc_hud_settingsPanel

	    -- ── Restore-Token(s) position button ──
	    table.insert(lines, '<Button id="tc_hud_restore_tokens"')
	    table.insert(lines, '  active="' .. (settingsOpen and "True" or "False") .. '"')
	    table.insert(lines, '  rectAlignment="LowerCenter"')
	    table.insert(lines, '  offsetXY="-164 2"')
	    table.insert(lines, '  width="26" height="26"')
	    table.insert(lines, '  onClick="' .. g .. '/btn_restoreTokens"')
	    table.insert(lines, '  ' .. btnStyle("debug"))
	    table.insert(lines, '  fontSize="10"')
	    table.insert(lines, '  tooltip="Restore tokens after save/load if any are missing"')
	    table.insert(lines, '  >↺</Button>')

	    -- ── Find Tokens button (adopt tokens from a deleted/old Applier) ──
	    table.insert(lines, '<Button id="tc_hud_find_tokens"')
	    table.insert(lines, '  active="' .. (settingsOpen and "True" or "False") .. '"')
	    table.insert(lines, '  rectAlignment="LowerCenter"')
	    table.insert(lines, '  offsetXY="-194 2"')
	    table.insert(lines, '  width="26" height="26"')
	    table.insert(lines, '  onClick="' .. g .. '/btn_findTokens"')
	    table.insert(lines, '  ' .. btnStyle("debug"))
	    table.insert(lines, '  fontSize="10"')
	    table.insert(lines, '  tooltip="Find Tokens: adopt tokens left behind by a deleted or old Token Applier"')
	    table.insert(lines, '  >F</Button>')

	    -- ── Debug IDs button (prints the hover-token table to the console) — in the slot the HUD button used ──
	    table.insert(lines, '<Button id="tc_hud_debug_ids"')
	    table.insert(lines, '  active="' .. (settingsOpen and "True" or "False") .. '"')
	    table.insert(lines, '  rectAlignment="LowerCenter"')
	    table.insert(lines, '  offsetXY="-134 2"')
	    table.insert(lines, '  width="26" height="26"')
	    table.insert(lines, '  onClick="' .. g .. '/btn_debug"')
	    table.insert(lines, '  ' .. btnStyle("debug"))
	    table.insert(lines, '  fontSize="10"')
	    table.insert(lines, '  tooltip="Debug IDs: print the hover-token table to the console"')
	    table.insert(lines, '  >ID</Button>')

	    -- ── Set Template button visibility toggle ──
	    table.insert(lines, '<Button id="tc_hud_templateVis"')
	    table.insert(lines, '  active="' .. (settingsOpen and "True" or "False") .. '"')
	    table.insert(lines, '  rectAlignment="LowerCenter"')
	    table.insert(lines, '  offsetXY="-97 190"')	-- left edge lines up with Add Token's left edge (x -112)
	    table.insert(lines, '  width="30" height="30"')
	    table.insert(lines, '  onClick="' .. g .. '/btn_toggleSetTemplate"')
	    table.insert(lines, '  ' .. btnStyle(hideSetTemplate and "danger" or "toggleOn"))
	    table.insert(lines, '  fontSize="11"')
	    table.insert(lines, '  tooltip="Token Creation: show or hide the Set Template button (O = hidden, I = visible)"')
	    local tvStyle = BTN_STYLE[hideSetTemplate and "danger" or "toggleOn"]
		table.insert(lines, '  ><Text id="tc_hud_templateVis_text" text="' .. (hideSetTemplate and "O" or "I") .. '" color="' .. tvStyle.textColor .. '" fontSize="11" width="26" height="26" alignment="MiddleCenter" /></Button>')

	    

	-- ── HUD Dynamic panel ──
		local HPAD  = 8
		local HBW   = 40    -- mod button size (square)
		local HGAP  = 4
		local HSTEP = HBW + HGAP  -- 44 — used for mod grid layout only

		local HSH   = 24    -- slot button height (independent from mod buttons)
		local HSW   = 200   -- slot button width
		local HRW   = HBW   -- remove button width (stays square, matches mod buttons)
		local HSGAP = 4     -- slot vertical gap

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
				.. exA .. '>'
				.. '<Text text="' .. label .. '" color="' .. s.textColor .. '" fontSize="' .. fontSize .. '" width="' .. HBW .. '" height="' .. HBW .. '" alignment="MiddleCenter" />'
				.. '</Button>'
		end

		-- Total mod grid width: 4 cols = 4*44 = 176, plus padding
		-- Total slot section width: HSW + HGAP + HRW + HPAD = 160+4+40+8 = 212
		-- Panel width: HPAD + 176 + HGAP + 212 = 404
		-- Panel height: 6 slots * (HBW+HGAP) = 6*44 = 264, plus padding = 280
		-- Centre mod grid (3 rows) against slot list (6 rows)
		local modGridH  = HPAD + (3 * HSTEP) + (HGAP * 2) + HSTEP + HPAD
		local slotListH = HPAD + (MAX_TOKENS * (HSH + HSGAP)) + HPAD
		local HDYN_H    = math.max(modGridH, slotListH)
		local HDYN_W = HPAD + (4 * HSTEP) + HGAP + HSW + HGAP + HRW + HPAD
		local centerOffset = math.floor((slotListH - modGridH) / 2) -- Vertical centre offset: mod grid is 3 rows tall, slots up to 6

		table.insert(lines, '<Panel id="tc_hud_dynPanel"')
		table.insert(lines, '  showAnimation="Grow"')
		table.insert(lines, '  hideAnimation="Shrink"')
		table.insert(lines, '  animationDuration="0.1"')
		table.insert(lines, '  active="False"')
		table.insert(lines, '  rectAlignment="LowerCenter"')
		table.insert(lines, '  offsetXY="' .. (116 + HDYN_W/2) .. ' 0"')
		table.insert(lines, '  width="' .. HDYN_W .. '" height="' .. HDYN_H .. '"')
		table.insert(lines, '  color="#00000000">')

		-- Mod grid — rows 0-2, cols 0-3
		-- Row 0: [lineForward] [•] [Flip] [↕]
		table.insert(lines, hmbtn(nil,                  "btn_lineForward",  "Move forward (Z)", "dynMod",      "18", "↑",    0, 0))
		table.insert(lines, hmbtn(nil,                  "btn_scaleUp",      "Scale up",         "dynGreenBtn", "18", "•",    1, 0))
		table.insert(lines, hmbtn(nil,                  "btn_flip",      "Flip token",      "dynMod",      "16", "Flip", 2, 0))
		table.insert(lines, hmbtn(nil,                  "btn_vertical",  "Toggle vertical", "dynMod",      "18", "↕",    3, 0))
		-- Row 1: [⁘] [▲] [▼] [⁛]
		table.insert(lines, hmbtn("tc_hud_dynSpreadDown","btn_radiusDown","Decrease spread", "dynRedBtn",   "18", "⁘",    0, 1, 'active="False"'))
		table.insert(lines, hmbtn(nil,                  "btn_heightUp",  "Raise height",    "dynMod",      "18", "▲",    1, 1))
		table.insert(lines, hmbtn(nil,                  "btn_heightDown","Lower height",     "dynMod",      "18", "▼",    2, 1))
		table.insert(lines, hmbtn("tc_hud_dynSpreadUp", "btn_radiusUp",  "Increase spread", "dynGreenBtn", "18", "⁛",    3, 1, 'active="False"'))
		-- Row 2: [lineBackward] [·] [↻] [  ]
		table.insert(lines, hmbtn(nil,                  "btn_lineBackward", "Move backward (Z)", "dynMod",    "18", "↓",    0, 2))
		table.insert(lines, hmbtn(nil,                  "btn_scaleDown",    "Scale down",        "dynRedBtn", "18", "·",    1, 2))
		table.insert(lines, hmbtn(nil,                  "btn_rotate",       "Rotate 180°",       "dynMod",    "18", "↻",    2, 2))

		-- Row 3 (double-gapped): LineUp toggle
		local HDBLGAP   = HGAP * 2
		local hRow3Y    = -(HPAD + 3 * HSTEP + HDBLGAP)
		local isLineUp  = modelLineUp[lastSelectedGUID or ""] or false
		table.insert(lines, '  <Button id="tc_hud_dynLineUpToggle" '
			.. 'onClick="' .. g .. '/btn_toggleModelLineUp" '
			.. 'tooltip="Toggle line-up mode" '
			.. btnStyle(isLineUp and "danger" or "active") .. ' '
			.. 'width="' .. HBW .. '" height="' .. HBW .. '" '
			.. 'fontSize="18" '
			.. 'rectAlignment="UpperLeft" '
			.. 'offsetXY="' .. hcol(0) .. ' ' .. hRow3Y .. '">'
			.. '<Text id="tc_hud_dynLineUpToggle_text" text="' .. (isLineUp and "Radial" or "Line up") .. '" color="' .. (BTN_STYLE[isLineUp and "danger" or "active"]).textColor .. '" fontSize="12" width="' .. HBW .. '" height="' .. HBW .. '" alignment="MiddleCenter" />'
			.. '</Button>')

		-- Row 3: Remove All Tokens — right of Line-Up, spans cols 1-2 (two buttons + the gap between)
		-- Two-click safeguard: first click arms it, second click removes (see hud_removeTokens)
		local HREMW = HBW * 2 + HGAP
		table.insert(lines, '  <Button id="tc_hud_dynRemoveAll" '
			.. 'onClick="' .. g .. '/hud_removeTokens" '
			.. 'tooltip="Remove ALL tokens from the selected model (click twice to confirm)" '
			.. btnStyle(REMOVE_ALL_STYLE) .. ' '
			.. 'width="' .. HREMW .. '" height="' .. HBW .. '" '
			.. 'rectAlignment="UpperLeft" '
			.. 'offsetXY="' .. hcol(1) .. ' ' .. hRow3Y .. '">'
			.. '<Text id="tc_hud_dynRemoveAll_text" text="' .. REMOVE_ALL_LABEL .. '" color="' .. BTN_STYLE[REMOVE_ALL_STYLE].textColor .. '" '
			.. 'resizeTextForBestFit="true" resizeTextMinSize="7" resizeTextMaxSize="11" '
			.. 'width="' .. (HREMW - 4) .. '" height="' .. HBW .. '" alignment="MiddleCenter" />'
			.. '</Button>')

		-- Slot section — to the right of mod grid
		local slotX = HPAD + (4 * HSTEP) + HGAP
		

		for i = 1, MAX_TOKENS do
			local yOffset = -(HPAD + (i - 1) * (HSH + HSGAP))
			-- Name button
			table.insert(lines, '  <Button id="tc_hud_dynSlot_' .. i .. '"')
			table.insert(lines, '    onClick="' .. g .. '/btn_select_' .. i .. '"')
			table.insert(lines, '    ' .. btnStyle("dynSlot"))
			table.insert(lines, '    active="False"')
			table.insert(lines, '    tooltip="Click to select token"')
			table.insert(lines, '    width="' .. HSW .. '" height="' .. HSH .. '"')
			table.insert(lines, '    rectAlignment="UpperLeft"')
			table.insert(lines, '    offsetXY="' .. slotX .. ' ' .. yOffset .. '"')
			table.insert(lines, '    fontSize="14">–</Button>')
			-- Remove button
			table.insert(lines, '  <Button id="tc_hud_dynRemove_' .. i .. '"')
			table.insert(lines, '    onClick="' .. g .. '/btn_remove_' .. i .. '"')
			table.insert(lines, '    ' .. btnStyle("dynRemove"))
			table.insert(lines, '    active="False"')
			table.insert(lines, '    tooltip="Remove token"')
			table.insert(lines, '    width="' .. HRW .. '" height="' .. HSH .. '"')
			table.insert(lines, '    rectAlignment="UpperLeft"')
			table.insert(lines, '    offsetXY="' .. (slotX + HSW + HGAP) .. ' ' .. yOffset .. '"')
			table.insert(lines, '    fontSize="18"><Text text="✕" color="#FFFFFF" width="' .. HRW .. '" height="' .. HBW .. '" alignment="MiddleCenter" /></Button>')
		end

				table.insert(lines, '</Panel><!--tc_hud_dynPanel-->') -- end tc_hud_dynPanel

			table.insert(lines, '</Panel><!--tc_hud_root-->') -- end tc_hud_root
			
		-- ── Minimised-restore button ──
		table.insert(lines, '<Button id="tc_hud_restore"')
	    table.insert(lines, '  active="' .. (not hudVisible and "True" or "False") .. '"')
	    table.insert(lines, '  rectAlignment="LowerCenter"')
	    table.insert(lines, '  offsetXY="' .. hudRootOffsetXY .. '"')
	    table.insert(lines, '  width="120" height="26"')
	    table.insert(lines, '  onClick="' .. g .. '/hud_toggleVisible"')
	    table.insert(lines, '  ' .. btnStyle("hudAdd"))
	    table.insert(lines, '  fontSize="12"')
	    table.insert(lines, '  tooltip="Show Token Controller HUD"')
	    table.insert(lines, '  >Token Applier</Button>')

		-- ── Placement overlay ──
		table.insert(lines, '<Panel id="tc_hud_placementOverlay"')
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

		table.insert(lines, '</Panel><!--tc_hud_placementOverlay-->') -- end tc_hud_placementOverlay
		
	    return table.concat(lines, "\n")
	end

	local function stripBetween(str, startTag, endTag)
		local s = str:find(startTag, 1, true)
		if not s then return str end
		local e = str:find(endTag, s, true)
		if not e then return str end
		return str:sub(1, s - 1) .. str:sub(e + #endTag)
	end

	rebuildHUD = function()
		if hudRebuildPending then return end
		hudRebuildPending = true
		Wait.time(function()
			hudRebuildPending = false
			local guid   = self.getGUID()
			local hudXml = buildHUDXml(guid)
			-- Wrap in a root panel and write the whole thing fresh
			-- No string surgery — always a clean write
			UI.setXml('<Panel width="1920" height="1080" color="#00000000">\n' .. hudXml .. '\n</Panel>')
			if not hudEnabled then
				-- HUD switched off (from the OUI): nothing on screen, not even the restore button
				UI.hide("tc_hud_root")
				UI.hide("tc_hud_sizeWarning")
				UI.hide("tc_hud_restore")
			elseif not hudVisible then
				UI.hide("tc_hud_root")
				UI.hide("tc_hud_sizeWarning")
				UI.show("tc_hud_restore")
			end
			-- The fresh HUD starts with the dynamic panel closed; clear the flags so the
			-- selection loop re-opens it on its next tick if a model with tokens is selected
			dynPanelVisible  = false
			lastSelectedGUID = nil
		end, 0.1)
	end

-- ──────────────────────────────────────────────────────────────
--  BUTTON LABEL HELPERS
-- ──────────────────────────────────────────────────────────────

	refreshTemplateButton = function()
	    self.UI.setAttribute("setTemplateBtn_text", "text", templateCache.label)
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
		
		-- Update HUD Set Template button
		local tcShort = shortName(stripBBCode(templateCache.name), 20, 2)
		local tcLabel = templateJSON and tcShort or "No Template"
		UI.setAttribute("tc_hud_setTemplate", "text", tcLabel)
		refreshTemplateButton()
		
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
		setHudButtonLook("tc_hud_clearHistoryBtn", hudText, styleName)
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
	
		Wait.condition(function()
			local isLineUp = modelLineUp[lastSelectedGUID or ""] or false
			local s = BTN_STYLE[isLineUp and "lineUpOn" or "lineUpOff"]
			self.UI.setAttribute("dynLineUpToggle",          "colors",    s.colors)
			self.UI.setAttribute("dynLineUpToggle",          "textColor", s.textColor)
			self.UI.setAttribute("dynLineUpToggle_text",     "color",     "#FFFFFF")
			UI.setAttribute("tc_hud_dynLineUpToggle",        "colors",    s.colors)
			UI.setAttribute("tc_hud_dynLineUpToggle",        "textColor", s.textColor)
			UI.setAttribute("tc_hud_dynLineUpToggle_text",   "color",     "#FFFFFF")
		end, function() return not self.UI.loading and not UI.loading end)

	    -- Right-click backup, works even if the HUD is broken by another mod
	    self.addContextMenuItem("Find Tokens", function() btn_findTokens() end)
	    -- Stamp tokens we already track (upgrades tokens from older saves)
	    saveState()

	    startFollowLoop()
	    startSelectionLoop()
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
		-- Update HUD Set Template button
		local tcShort = shortName(stripBBCode(templateCache.name), 20, 2)
		local tcLabel = templateJSON and tcShort or "No Template"
		UI.setAttribute("tc_hud_setTemplate", "text", tcLabel)
		refreshTemplateButton()
		
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
		local isLineUp = modelLineUp[targetGUID]
		local s = BTN_STYLE[isLineUp and "lineUpOn" or "lineUpOff"]
		self.UI.setAttribute("dynLineUpToggle", "colors",    s.colors)
		self.UI.setAttribute("dynLineUpToggle", "textColor", s.textColor)
		UI.setAttribute("tc_hud_dynLineUpToggle", "colors",    s.colors)
		UI.setAttribute("tc_hud_dynLineUpToggle", "textColor", s.textColor)
		self.UI.setAttribute("dynLineUpToggle_text",        "color", s.textColor)
		UI.setAttribute("tc_hud_dynLineUpToggle_text",      "color", s.textColor)
		self.UI.setAttribute("dynLineUpToggle_text",   "text",     isLineUp and "Token Radial" or "Token Line up")
		self.UI.setAttribute("dynLineUpToggle_text",   "fontSize", isLineUp and "14"     or "14")
		UI.setAttribute("tc_hud_dynLineUpToggle_text", "text",     isLineUp and "Token Radial" or "Token Line up")
		UI.setAttribute("tc_hud_dynLineUpToggle_text", "fontSize", isLineUp and "10"     or "10")
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
	                print("      image: " .. (url ~= "" and url or "(none)") .. blank)
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