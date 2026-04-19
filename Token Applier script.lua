-- =============================================================
--  Token Applier – Token Manager
--  One controller handles any token type via full JSON template
-- =============================================================


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
	local transferTokenGUID     = nil  -- set for single-token transfer mode
	local transferSourceGUID    = nil  -- set for all-tokens transfer mode (model GUID)
	local saveStatePending  	= false
	local saveStateDelay    	= 0.5   -- seconds; tune down to 0.2 if you want snappier persistence
	local targetMapCache    	= nil   -- invalidated when hoverEntries changes
	local seatedColors 			= {}
	local dropTemplateEnabled 	= true
	local hudDraggable 			= false
	local hudRootOffsetXY 		= "0 2"
	local hudPlacementMode 		= false

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
		hudPosition = {
	        colors     = "#1A1A1AF2|#2A2A2AF2|#111111F2|#333333AA",
	        textColor  = "#888888",
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

-- ──────────────────────────────────────────────────────────────
--  PERSISTENCE
-- ──────────────────────────────────────────────────────────────

	local function saveState()
		if saveStatePending then return end
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
			}
			self.script_state = JSON.encode(blob)
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
		local imageURL  = extractImageURL(data) or ""
		templateCache = {
			label    = cleanName and ("Set Template\n[" .. cleanName .. "]") or "Set Template\n[custom]",
			imageURL = imageURL,
			name     = cleanName or "Token",
			byteSize = byteSize,
		}
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
	    table.insert(tokenHistory, 1, {
	        json     = json,
	        scale    = scale,
	        name     = name,
	        imageURL = imageURL or "",
	    })
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
		for i = 1, HISTORY_MAX do
			local e        = tokenHistory[i]
			local isActive = e and (templateJSON == e.json)
			local style    = isActive and "active" or (e and "historySlot" or "ghost")
			self.UI.setAttribute("histBtn" .. i,   "colors",    BTN_STYLE[style].colors)
			self.UI.setAttribute("histBtn" .. i,   "textColor", BTN_STYLE[style].textColor)
			UI.setAttribute("tc_hud_hist_" .. i,   "colors",    BTN_STYLE[style].colors)
			UI.setAttribute("tc_hud_hist_" .. i,   "textColor", BTN_STYLE[style].textColor)
		end
		-- Update size warning
		if templateCache.byteSize > 5000 then
			local warnText  = templateCache.byteSize > 20000 and "⚠ Very large object — expect some lag" or "⚠ Large object"
			self.UI.setAttribute("sizeWarningPanel", "active", "True")
			self.UI.setAttribute("sizeWarningPanel", "color",  templateCache.byteSize > 20000 and "#5A1A00F2" or "#3A3A0AF2")
		else
			self.UI.setAttribute("sizeWarningPanel", "active", "False")
		end
		-- Update HUD Set Template button
		local tcShort = shortName(stripBBCode(templateCache.name), 20, 2)
		local tcLabel = templateJSON and tcShort or "No Template"
		UI.setAttribute("tc_hud_setTemplate", "text", tcLabel)
	end
-- ──────────────────────────────────────────────────────────────
--  HISTORY EDIT OVERLAY
-- ──────────────────────────────────────────────────────────────

	-- HistoryEdit button
	function btn_toggleHistoryEdit(_, _)
		historyEditMode = not historyEditMode
		rebuildXML()
		rebuildHUD()
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
		rebuildXML()
		rebuildHUD()
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
	
	-- DeleteHistory HANDLERS
	function btn_deleteHistory_1(_, _) deleteHistoryEntry(1) end
	function btn_deleteHistory_2(_, _) deleteHistoryEntry(2) end
	function btn_deleteHistory_3(_, _) deleteHistoryEntry(3) end
	function btn_deleteHistory_4(_, _) deleteHistoryEntry(4) end
	function btn_deleteHistory_5(_, _) deleteHistoryEntry(5) end
	function btn_deleteHistory_6(_, _) deleteHistoryEntry(6) end
	function btn_deleteHistory_7(_, _) deleteHistoryEntry(7) end
	function btn_deleteHistory_8(_, _) deleteHistoryEntry(8) end

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
		else
			UI.hide("tc_hud_root")
			UI.hide("tc_hud_core")
			UI.hide("tc_hud_minimize")
			UI.hide("tc_hud_settings")
			UI.hide("tc_hud_setTemplate")
			UI.hide("tc_hud_settingsPanel")
			UI.hide("tc_hud_off")
			UI.hide("tc_hud_restore_tokens")
			UI.hide("tc_hud_templateVis")
			UI.hide("tc_hud_dynPanel")
			UI.hide("tc_hud_sizeWarning")
			settingsOpen = false
			UI.show("tc_hud_restore")
		end
	end

	function btn_toggleHUD(_, _)
		hudEnabled = not hudEnabled
		if hudEnabled then
			hudVisible = true
			UI.show("tc_hud_core")
			UI.show("tc_hud_minimize")
			UI.show("tc_hud_settings")
			if not hideSetTemplate then UI.show("tc_hud_setTemplate") end
			UI.hide("tc_hud_restore")
		else
			UI.hide("tc_hud_core")
			UI.hide("tc_hud_minimize")
			UI.hide("tc_hud_settings")
			UI.hide("tc_hud_setTemplate")
			UI.hide("tc_hud_settingsPanel")
			UI.hide("tc_hud_off")
			UI.hide("tc_hud_restore_tokens")
			UI.hide("tc_hud_templateVis")
			UI.hide("tc_hud_restore")
			settingsOpen = false
		end
		rebuildXML()
		local si = BTN_STYLE[hudEnabled and "settingsItem" or "danger"]
		UI.setAttribute("tc_hud_off", "colors",    si.colors)
		UI.setAttribute("tc_hud_off", "textColor", si.textColor)
		UI.setAttribute("tc_hud_off", "text",      hudEnabled and "HUD" or "OFF")
	end

	function hud_toggleSettings(player, _, _)
		btn_toggleSettings(nil, nil)
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
		UI.setAttribute("tc_hud_dragToggleBtn", "text", hudDraggable and "Drag: ON" or "Drag: OFF")
	end
	
	function btn_toggleHudPlacement(_, _)
		hudPlacementMode = not hudPlacementMode
		if hudPlacementMode then
			UI.show("tc_hud_placementOverlay")
		else
			UI.hide("tc_hud_placementOverlay")
		end
	end

	function btn_selectHudPosition(player, _, id)
		local playerColor = (type(player) == "userdata" and player.color) or player
		-- find the offsetXY for this id
		for _, pos in ipairs(HUD_POSITIONS) do
			if pos.id == id then
				hudRootOffsetXY = pos.hudXY
				break
			end
		end
		hudPlacementMode = false
		UI.hide("tc_hud_placementOverlay")
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
			historyEditMode = false
		end
		if settingsOpen then
			self.UI.show("settingsPanel")
			self.UI.show("clearHistoryPanel")
			UI.show("tc_hud_settingsPanel")
			UI.show("tc_hud_off")
			UI.show("tc_hud_restore_tokens")
			UI.show("tc_hud_templateVis")
		else
			self.UI.hide("settingsPanel")
			self.UI.hide("clearHistoryPanel")
			UI.hide("tc_hud_settingsPanel")
			UI.hide("tc_hud_off")
			UI.hide("tc_hud_restore_tokens")
			UI.hide("tc_hud_templateVis")
		end
		-- Update settings button highlight
		self.UI.setAttribute("settingsBtn", "colors",    BTN_STYLE[settingsOpen and "active" or "settings"].colors)
		self.UI.setAttribute("settingsBtn", "textColor", BTN_STYLE[settingsOpen and "active" or "settings"].textColor)
		-- Update clear history / edit history button labels
		self.UI.setAttribute("clearHistoryPanel", "active", settingsOpen and "True" or "False")
	end
	
	-- SetTemplate button toggle
	function btn_toggleSetTemplate(_, _)
		hideSetTemplate = not hideSetTemplate
		if hideSetTemplate then
			UI.hide("tc_hud_setTemplate")
		else
			UI.show("tc_hud_setTemplate")
		end
		rebuildXML()
	end
	
	function btn_toggleDropTemplate(_, _)
		dropTemplateEnabled = not dropTemplateEnabled
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

		self.UI.show("dynamicPanel")
		UI.show("tc_hud_dynPanel")
		dynPanelVisible  = true
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

	    table.insert(lines, '<Panel id="previewPanel"')
	    table.insert(lines,   ' active="' .. previewActive .. '"')
	    table.insert(lines,   ' position="0 0 -100"')
	    table.insert(lines,   ' rotation="0 0 0"')
	    table.insert(lines,   ' width="300" height="300"')
	    table.insert(lines,   ' color="#00000000">')
	    if previewImage ~= "" then
	        table.insert(lines, '  <Image image="' .. previewImage .. '" width="150" height="150" preserveAspect="true" />')
	    else
	        table.insert(lines, '  <Panel width="150" height="150" color="#000000CC" rectAlignment="MiddleCenter">')
	        table.insert(lines, '    <Text text="' .. previewText .. '" fontSize="22" color="#FFFFFF" fontStyle="Bold" alignment="MiddleCenter" width="140" height="140" />')
	        table.insert(lines, '  </Panel>')
	    end
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

			if historyEditMode and entry then
				-- Edit mode: render X button in place of history button
				table.insert(lines, '    <Button onClick="btn_deleteHistory_' .. i .. '"')
				table.insert(lines, '      ' .. btnStyle("danger"))
				table.insert(lines, '      width="100" height="100"')
				table.insert(lines, '      padding="3 3 3 3">')
				if entry.imageURL and entry.imageURL ~= "" then
					table.insert(lines, '      <Image image="' .. entry.imageURL .. '" width="100" height="100" preserveAspect="true" />')
				end
				-- Red transparent overlay layer
				table.insert(lines, '      <Panel width="100" height="100" color="#AA000066" />')
				table.insert(lines, '      <Text text="✕" color="#FF6666FF" fontSize="50" alignment="MiddleCenter" /></Button>')
			else
				-- Normal mode: render history button as usual
				local style  = isActive and "active" or (entry and "historySlot" or "ghost")
				local fnName = "btn_history_" .. i
				table.insert(lines, '    <Button id="histBtn' .. i .. '"')
				table.insert(lines, '      onClick="' .. fnName .. '"')
				table.insert(lines, '      ' .. btnStyle(style))
				table.insert(lines, '      width="100" height="100"')
				table.insert(lines, '      padding="3 3 3 3">')
				if entry and entry.imageURL and entry.imageURL ~= "" then
					table.insert(lines, '      <Image image="' .. entry.imageURL .. '" width="100" height="100" preserveAspect="true" />')
				elseif entry then
					local display = shortName(stripBBCode(entry.name), 5, 3)
					table.insert(lines, '      <Text text="' .. display .. '" fontSize="20" color="#FFFFFF" alignment="MiddleCenter" width="80" height="80" />')
				else
					table.insert(lines, '      <Text text="·" fontSize="20" color="#404040" alignment="MiddleCenter" width="58" height="58" />')
				end
				table.insert(lines, '    </Button>')
			end
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
		-- clear history panel
		table.insert(lines, '<Panel id="clearHistoryPanel"')
		table.insert(lines, '  active="' .. (settingsOpen and "True" or "False") .. '"')
		table.insert(lines, '  showAnimation="Grow"')
		table.insert(lines, '  hideAnimation="Shrink"')
		table.insert(lines, '  animationDuration="0.1"')
		table.insert(lines, '  position="-350 -330 -20"')
		table.insert(lines, '  rotation="0 0 0"')
		table.insert(lines, '  width="222" height="128"')  -- increased height to fit both buttons
		table.insert(lines, '  color="#2B1A00F2">')
		table.insert(lines, '  <VerticalLayout spacing="4" padding="4 4 4 4" childAlignment="UpperCenter">')
		table.insert(lines, '    <Button onClick="btn_clearHistory" tooltip="Clear all token history and reset template" ' .. btnStyle("danger") .. ' fontSize="22" preferredWidth="214" preferredHeight="60"><Text text="Clear History ✕" color="' .. BTN_STYLE.danger.textColor .. '" fontSize="22" /></Button>')
		table.insert(lines, '    <Button onClick="btn_toggleHistoryEdit" tooltip="Toggle delete mode on history slots" ' .. btnStyle(historyEditMode and "danger" or "settingsItem") .. ' fontSize="22" preferredWidth="214" preferredHeight="60"><Text text="' .. (historyEditMode and "Delete →" or "Edit History") .. '" color="' .. BTN_STYLE[historyEditMode and "danger" or "settingsItem"].textColor .. '" fontSize="22" /></Button>')
		table.insert(lines, '  </VerticalLayout>')
		table.insert(lines, '</Panel>')
		
		-- Settings panel
		table.insert(lines, '<Panel id="settingsPanel"')
		table.insert(lines, '  active="' .. (settingsOpen and "True" or "False") .. '"')
		table.insert(lines, '  showAnimation="Grow"')
		table.insert(lines, '  hideAnimation="Shrink"')
		table.insert(lines, '  animationDuration="0.1"')
		table.insert(lines, '  position="-460 -530 -25"')
		table.insert(lines, '  rotation="0 0 0"')
		table.insert(lines, '  width="448" height="128"')
		table.insert(lines, '  color="#484716F2">')
		table.insert(lines, '  <VerticalLayout spacing="4" padding="8 8 8 8" childAlignment="UpperCenter">')
		table.insert(lines, '    <HorizontalLayout spacing="4" childAlignment="MiddleCenter">')
		table.insert(lines, '      <Button onClick="btn_restoreTokens" tooltip="Restore tokens after save/load if any are missing" ' .. btnStyle("settingsItem") .. ' fontSize="28" preferredWidth="130" preferredHeight="50">↺</Button>')
		table.insert(lines, '      <Button onClick="btn_debug" tooltip="Print current hover-token table to console" ' .. btnStyle("settingsItem") .. ' fontSize="25" preferredWidth="150" preferredHeight="50">Debug IDs</Button>')
		table.insert(lines, '      <Button id="hudToggleBtn"')
		table.insert(lines, '        onClick="btn_toggleHUD"')
		table.insert(lines, '        tooltip="Show or hide the on-screen HUD"')
		table.insert(lines, '        ' .. btnStyle(hudEnabled and "settingsItem" or "danger"))
		table.insert(lines, '        fontSize="22" preferredWidth="130" preferredHeight="50"')
		table.insert(lines, '        >' .. (hudEnabled and "HUD: ON" or "HUD: OFF") .. '</Button>')
		table.insert(lines, '    </HorizontalLayout>')
		table.insert(lines, '    <HorizontalLayout spacing="4" childAlignment="MiddleCenter">')
		table.insert(lines, '      <Button onClick="btn_toggleSetTemplate"')
		table.insert(lines, '        tooltip="Show or hide the Set Template button"')
		table.insert(lines, '        ' .. btnStyle(hideSetTemplate and "danger" or "settingsItem"))
		table.insert(lines, '        fontSize="18" preferredWidth="414" preferredHeight="50"')
		table.insert(lines, '        ><Text text="' .. (hideSetTemplate and "Template: Hidden" or "Template: Visible") .. '" color="' .. BTN_STYLE[hideSetTemplate and "danger" or "settingsItem"].textColor .. '" fontSize="18" /></Button>')
		table.insert(lines, '    </HorizontalLayout>')
			-- Toggle Drop-to-template_Function
		table.insert(lines, '    <HorizontalLayout spacing="4" childAlignment="MiddleCenter">')
		table.insert(lines, '      <Button onClick="btn_toggleDropTemplate"')
		table.insert(lines, '        tooltip="Enable or disable dropping objects onto TC to set template"')
		table.insert(lines, '        ' .. btnStyle(dropTemplateEnabled and "settingsItem" or "danger"))
		table.insert(lines, '        fontSize="18" preferredWidth="414" preferredHeight="50"')
		table.insert(lines, '        ><Text text="' .. (dropTemplateEnabled and "Drop Template: ON" or "Drop Template: OFF") .. '" color="' .. BTN_STYLE[dropTemplateEnabled and "settingsItem" or "danger"].textColor .. '" fontSize="18" /></Button>')
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
		if templateCache.byteSize > 20000 then
			sizeWarning = "\n⚠ Very large object"
		elseif templateCache.byteSize > 5000 then
			sizeWarning = "\n⚠ Large object"
		end
		templateLabel = templateLabel .. sizeWarning
		
		-- ── Size warning panel ──
		if templateCache.byteSize > 5000 then
			local warnText  = templateCache.byteSize > 20000 and "⚠ Very large object — expect some lag" or "⚠ Large object"
			local warnColor = templateCache.byteSize > 20000 and "#5A1A00F2" or "#3A3A0AF2"
			table.insert(lines, '<Panel id="sizeWarningPanel"')
			table.insert(lines, '  active="True"')
			table.insert(lines, '  position="0 -230 -25"')
			table.insert(lines, '  rotation="0 0 0"')
			table.insert(lines, '  width="448" height="36"')
			table.insert(lines, '  color="' .. warnColor .. '">')
			table.insert(lines, '  <Text text="' .. warnText .. '" fontSize="18" color="#FFAA44" alignment="MiddleCenter" />')
			table.insert(lines, '</Panel>')
		else
			table.insert(lines, '<Panel id="sizeWarningPanel" active="False" width="448" height="36" />')
		end

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
			local fnName   = g .. "/hud_history_" .. i

			if historyEditMode and entry then
				table.insert(lines, '    <Button id="tc_hud_hist_' .. i .. '"')
				table.insert(lines, '      onClick="' .. g .. '/btn_deleteHistory_' .. i .. '"')
				table.insert(lines, '      ' .. btnStyle("danger"))
				table.insert(lines, '      width="54" height="54"')
				table.insert(lines, '      padding="2 2 2 2">')
				if entry.imageURL and entry.imageURL ~= "" then
					table.insert(lines, '      <Image image="' .. entry.imageURL .. '" width="50" height="50" preserveAspect="true" />')
				end
				table.insert(lines, '      <Panel width="54" height="54" color="#AA000066" />')
				table.insert(lines, '      <Text text="✕" color="#FF6666FF" fontSize="28" alignment="MiddleCenter" /></Button>')
			else
				local style  = isActive and "active" or (entry and "historySlot" or "ghost")
				table.insert(lines, '    <Button id="tc_hud_hist_' .. i .. '"')
				table.insert(lines, '      onClick="' .. fnName .. '"')
				table.insert(lines, '      ' .. btnStyle(style))
				table.insert(lines, '      width="54" height="54"')
				table.insert(lines, '      padding="2 2 2 2">')
				if entry and entry.imageURL and entry.imageURL ~= "" then
					table.insert(lines, '      <Image image="' .. entry.imageURL .. '" width="50" height="50" preserveAspect="true" />')
				elseif entry then
					local display = shortName(stripBBCode(entry.name), 4, 2)
					table.insert(lines, '      <Text text="' .. display .. '" fontSize="14" color="#FFFFFF" alignment="MiddleCenter" />')
				else
					table.insert(lines, '      <Text text="·" fontSize="16" color="#303030" alignment="MiddleCenter" />')
				end
				table.insert(lines, '    </Button>')
			end
		end

	    table.insert(lines, '    </GridLayout>')
		table.insert(lines, '  </VerticalLayout>')
		table.insert(lines, '</Panel>') -- end tc_hud_core

	    -- ── Minimize footer bar ──
	    -- Spans the CORE width, sits below it
	    table.insert(lines, '<Button id="tc_hud_minimize"')
	    table.insert(lines, '  rectAlignment="LowerCenter"')
	    table.insert(lines, '  offsetXY="0 2"')
	    table.insert(lines, '  width="236" height="26"')
	    table.insert(lines, '  onClick="' .. g .. '/hud_toggleVisible"')
	    table.insert(lines, '  ' .. btnStyle("hudHide"))
	    table.insert(lines, '  fontSize="12"')
	    table.insert(lines, '  tooltip="Minimise HUD"')
	    table.insert(lines, '  >— minimise —</Button>')

	    -- ── Settings button (1:1 square, bottom-left of CORE) ──
	    table.insert(lines, '<Button id="tc_hud_settings"')
	    table.insert(lines, '  rectAlignment="LowerCenter"')
	    table.insert(lines, '  offsetXY="-133 2"')
	    table.insert(lines, '  width="26" height="26"')
	    table.insert(lines, '  onClick="' .. g .. '/hud_toggleSettings"')
	    table.insert(lines, '  ' .. btnStyle(settingsOpen and "active" or "settings"))
	    table.insert(lines, '  fontSize="14"')
	    table.insert(lines, '  tooltip="Settings"')
		local ss = BTN_STYLE.settings
		table.insert(lines, '  ><Text text="⚙" color="' .. ss.textColor .. '" fontSize="10" width="26" height="26" alignment="MiddleCenter" /></Button>')

	    -- ── HUD OFF button (appears left of settings when settings open) ──
	    table.insert(lines, '<Button id="tc_hud_off"')
	    table.insert(lines, '  active="' .. (settingsOpen and "True" or "False") .. '"')
	    table.insert(lines, '  rectAlignment="LowerCenter"')
	    table.insert(lines, '  offsetXY="-160 2"')
	    table.insert(lines, '  width="26" height="26"')
	    table.insert(lines, '  onClick="' .. g .. '/btn_toggleHUD"')
	    table.insert(lines, '  ' .. btnStyle(hudEnabled and "settingsItem" or "danger"))
	    table.insert(lines, '  fontSize="10"')
	    table.insert(lines, '  tooltip="Toggle HUD on/off"')
	    local si = BTN_STYLE[hudEnabled and "settingsItem" or "danger"]
		table.insert(lines, '  ><Text text="' .. (hudEnabled and "HUD" or "OFF") .. '" color="' .. si.textColor .. '" fontSize="8" width="26" height="26" alignment="MiddleCenter" /></Button>')

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
		if templateCache.byteSize > 5000 then
			local warnText  = templateCache.byteSize > 20000 and "⚠ Very large" or "⚠ Large object"
			local warnColor = templateCache.byteSize > 20000 and "#5A1A00FF" or "#3A3A0AFF"
			table.insert(lines, '<Panel id="tc_hud_sizeWarning"')
			table.insert(lines, '  rectAlignment="LowerCenter"')
			table.insert(lines, '  offsetXY="0 140"')
			table.insert(lines, '  width="224" height="14"')
			table.insert(lines, '  color="' .. warnColor .. '">')
			table.insert(lines, '  <Text text="' .. warnText .. '" fontSize="8" color="#FFAA44" alignment="MiddleCenter" />')
			table.insert(lines, '</Panel>')
		else
			table.insert(lines, '<Panel id="tc_hud_sizeWarning" active="False" rectAlignment="LowerCenter" offsetXY="0 222" width="160" height="18" />')
		end

	    -- ── Settings flyout panel (Remove / Clear / Edit History) ──
	    table.insert(lines, '<Panel id="tc_hud_settingsPanel"')
	    table.insert(lines, '  active="' .. (settingsOpen and "True" or "False") .. '"')
	    table.insert(lines, '  showAnimation="Grow"')
	    table.insert(lines, '  hideAnimation="Shrink"')
	    table.insert(lines, '  animationDuration="0.1"')
	    table.insert(lines, '  rectAlignment="LowerCenter"')
	    table.insert(lines, '  offsetXY="-180 75"')
	    table.insert(lines, '  width="120" height="100"')
	    table.insert(lines, '  color="#1A1A1A00">') -- used to have CC at the end
	    table.insert(lines, '  <VerticalLayout spacing="3" padding="4 4 4 4" childAlignment="UpperCenter">')
	    -- Remove Tokens
	    table.insert(lines, '    <Button onClick="' .. g .. '/hud_removeTokens"')
	    table.insert(lines, '      ' .. btnStyle("hudRemove"))
	    table.insert(lines, '      fontSize="13" preferredWidth="112" preferredHeight="36"')
	    table.insert(lines, '      tooltip="Remove all tokens from selected model"')
	    table.insert(lines, '      >Remove Tokens</Button>')
	    -- Clear History
	    table.insert(lines, '    <Button onClick="' .. g .. '/btn_clearHistory"')
	    table.insert(lines, '      ' .. btnStyle("danger"))
	    table.insert(lines, '      fontSize="13" preferredWidth="112" preferredHeight="36"')
	    table.insert(lines, '      tooltip="Clear all token history and reset template"')
	    table.insert(lines, '      >X Clear History</Button>')
	    -- Edit History
	    table.insert(lines, '    <Button onClick="' .. g .. '/btn_toggleHistoryEdit"')
	    table.insert(lines, '      ' .. btnStyle(historyEditMode and "danger" or "settingsItem"))
	    table.insert(lines, '      fontSize="13" preferredWidth="112" preferredHeight="36"')
	    table.insert(lines, '      tooltip="Toggle delete mode on history slots"')
	    table.insert(lines, '      >' .. (historyEditMode and "Delete →" or "Edit History") .. '</Button>')
		-- HUD placement selector
		table.insert(lines, '    <Button id="tc_hud_placeBtn"')
		table.insert(lines, '      onClick="' .. g .. '/btn_toggleHudPlacement"')
		table.insert(lines, '      ' .. btnStyle(hudPlacementMode and "active" or "settingsItem"))
		table.insert(lines, '      fontSize="13" preferredWidth="112" preferredHeight="36"')
		table.insert(lines, '      tooltip="Choose a position for the HUD"')
		table.insert(lines, '      >' .. (hudPlacementMode and "Cancel" or "Place HUD") .. '</Button>')
		-- Toggle HUD draggable
		table.insert(lines, '    <Button id="tc_hud_dragToggleBtn"')
		table.insert(lines, '      onClick="' .. g .. '/btn_toggleHudDraggable"')
		table.insert(lines, '      ' .. btnStyle(hudDraggable and "active" or "settingsItem"))
		table.insert(lines, '      fontSize="13" preferredWidth="112" preferredHeight="36"')
		table.insert(lines, '      tooltip="Allow HUD to be dragged to a new position"')
		table.insert(lines, '      >' .. (hudDraggable and "Drag: ON" or "Drag: OFF") .. '</Button>')
		
	    table.insert(lines, '  </VerticalLayout>')
	    table.insert(lines, '</Panel>') -- end tc_hud_settingsPanel

	    -- ── Restore-Token(s) position button ──
	    table.insert(lines, '<Button id="tc_hud_restore_tokens"')
	    table.insert(lines, '  active="' .. (settingsOpen and "True" or "False") .. '"')
	    table.insert(lines, '  rectAlignment="LowerCenter"')
	    table.insert(lines, '  offsetXY="-190 2"')
	    table.insert(lines, '  width="26" height="26"')
	    table.insert(lines, '  onClick="' .. g .. '/btn_restoreTokens"')
	    table.insert(lines, '  ' .. btnStyle("settingsItem"))
	    table.insert(lines, '  fontSize="10"')
	    table.insert(lines, '  tooltip="Restore tokens after save/load if any are missing"')
	    table.insert(lines, '  >↺</Button>')

	    -- ── Set Template button visibility toggle ──
	    table.insert(lines, '<Button id="tc_hud_templateVis"')
	    table.insert(lines, '  active="' .. (settingsOpen and "True" or "False") .. '"')
	    table.insert(lines, '  rectAlignment="LowerCenter"')
	    table.insert(lines, '  offsetXY="-50 190"')
	    table.insert(lines, '  width="30" height="30"')
	    table.insert(lines, '  onClick="' .. g .. '/btn_toggleSetTemplate"')
	    table.insert(lines, '  ' .. btnStyle(hideSetTemplate and "danger" or "settingsItem"))
	    table.insert(lines, '  fontSize="11"')
	    table.insert(lines, '  tooltip="Show or hide the Set Template button"')
	    local tvStyle = BTN_STYLE[hideSetTemplate and "danger" or "settingsItem"]
		table.insert(lines, '  ><Text text="' .. (hideSetTemplate and "O" or "I") .. '" color="' .. tvStyle.textColor .. '" fontSize="11" width="26" height="26" alignment="MiddleCenter" /></Button>')

	    

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

				table.insert(lines, '</Panel>') -- end tc_hud_dynPanel

			table.insert(lines, '</Panel>') -- end tc_hud_root
			
		-- ── Minimised-restore button ──
	    table.insert(lines, '<Button id="tc_hud_restore"')
	    table.insert(lines, '  active="' .. (not hudVisible and "True" or "False") .. '"')
	    table.insert(lines, '  rectAlignment="LowerCenter"')
	    table.insert(lines, '  offsetXY="0 2"')
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
				table.insert(lines, '    <Text text="+" color="#FFFFFF" fontSize="30" width="60" height="60" alignment="MiddleCenter" /></Button>')
			end
		end

		table.insert(lines, '</Panel>') -- end tc_hud_placementOverlay
		
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
			local existing = UI.getXml() or ""
			existing = existing:gsub("%s+$", "")
			-- Only strip elements that need content rebuilds
			existing = stripBetween(existing, '<Panel id="tc_hud_core"',          '</Panel>')
			existing = stripBetween(existing, '<Button id="tc_hud_minimize"',     '</Button>')
			existing = stripBetween(existing, '<Button id="tc_hud_settings"',     '</Button>')
			existing = stripBetween(existing, '<Button id="tc_hud_off"',          '</Button>')
			existing = stripBetween(existing, '<Button id="tc_hud_setTemplate"',  '</Button>')
			existing = stripBetween(existing, '<Panel id="tc_hud_settingsPanel"', '</Panel>')
			existing = stripBetween(existing, '<Button id="tc_hud_restore_tokens"','</Button>')
			existing = stripBetween(existing, '<Button id="tc_hud_templateVis"',  '</Button>')
			existing = stripBetween(existing, '<Button id="tc_hud_restore"',      '</Button>')
			existing = stripBetween(existing, '<Panel id="tc_hud_sizeWarning"', '</Panel>')
			existing = stripBetween(existing, '<Panel id="tc_hud_dynPanel"', '</Panel>')
			existing = stripBetween(existing, '<Panel id="tc_hud_root"', '</Panel>')
			existing = stripBetween(existing, '<Panel id="tc_hud_placementOverlay"', '</Panel>')
			existing = existing:gsub("%s+$", "")
			UI.setXml(existing .. "\n" .. hudXml)
			--print("[Debug] hudRootOffsetXY at rebuild: " .. tostring(hudRootOffsetXY))
			--print("[Debug] hudVisible at rebuild: " .. tostring(hudVisible))
			--print("[Debug] hudXml length: " .. #hudXml)
			if not hudVisible then
				UI.hide("tc_hud_root")
				UI.hide("tc_hud_sizeWarning")
				UI.show("tc_hud_restore")
			end
		end, 0.1)
	end

-- ──────────────────────────────────────────────────────────────
--  BUTTON LABEL HELPERS
-- ──────────────────────────────────────────────────────────────

	refreshTemplateButton = function()
	    self.UI.setAttribute("setTemplateBtn_text", "text", templateCache.label)
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
	local function executeTransfer(destGUID, tokenGUIDs)
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
			broadcastToAll(
				"Max tokens reached on \"" .. destName .. "\" — only " .. transferred .. " of " .. total .. " transferred.",
				{ 1, 0.6, 0.2 }
			)
		else
			broadcastToAll(
				"   Transferred " .. transferred .. " token(s) to " .. destName .. ".",
				{ 0.3, 1, 0.5 }
			)
		end
	end



-- ──────────────────────────────────────────────────────────────
--  SELECTION POLLING LOOP
-- ──────────────────────────────────────────────────────────────

	local dynHideDelay = false

	function startSelectionLoop()
		if selectionLoopRunning then return end
		selectionLoopRunning = true
		local function getSelection()
			for colour, _ in pairs(seatedColors) do
				local ok, sel = pcall(function()
					return Player[colour].getSelectedObjects()
				end)
				if ok and sel and #sel > 0 then return sel end
			end
			return {}
		end
		local function poll()
			local sel = getSelection()
			if #sel > 0 then
				if transferTokenGUID or transferSourceGUID then
					local destGUID = sel[1].getGUID()
					if not hoverEntries[destGUID] then
						-- only proceed if destination is a model, not a token
						local sourceModel = transferSourceGUID
						if not sourceModel and transferTokenGUID then
							local e = hoverEntries[transferTokenGUID]
							if e then sourceModel = e.targetGUID end
						end
						if sourceModel then
							if destGUID == sourceModel then
								broadcastToAll("Can't transfer to the same model.", { 1, 0.7, 0.3 })
							elseif destGUID == self.getGUID() or destGUID == previewGUID then
								-- silently ignore TC itself and preview object
							else
								local tokensToMove = transferTokenGUID
									and { transferTokenGUID }
									or  findTokensForTarget(transferSourceGUID)
								executeTransfer(destGUID, tokensToMove)
								transferTokenGUID  = nil
								transferSourceGUID = nil
							end
						end
					end
				else
					dynHideDelay = false
					local guid   = sel[1].getGUID()
					local tokens = findTokensForTarget(guid)
					if #tokens > 0 then
						showDynamicPanel(guid, #tokens)
					else
						if dynPanelVisible then hideDynamicPanel() end
					end
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
			transferSourceGUID = entry.targetGUID
			transferTokenGUID  = nil
			broadcastToAll("Select destination model for all tokens…", { 0.5, 0.8, 1 })
		end)

		token.addContextMenuItem("→ Transfer (single)", function(playerColor)
			local entry = hoverEntries[tGUID]
			if not entry then return end
			transferTokenGUID  = tGUID
			transferSourceGUID = nil
			broadcastToAll("Select destination model for this token…", { 0.5, 0.8, 1 })
		end)
	end


-- ──────────────────────────────────────────────────────────────
--  TEMPLATE PREVIEW
-- ──────────────────────────────────────────────────────────────

	spawnPreview = function()
	    if not templateJSON then return end
	    local ok, data = pcall(JSON.decode, templateJSON)
	    if not ok or type(data) ~= "table" then return end

	    local BLANK_IMAGE = "https://steamusercontent-a.akamaihd.net/ugc/2521536445208860998/E4C9AE9685105F12A3D4D3DC534616786D5D7666/"
	    local imageURL = extractImageURL(data)
	    local hasUsefulImage = imageURL and imageURL ~= "" and imageURL ~= BLANK_IMAGE
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
	    rebuildXML()
	    rebuildHUD()

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

	function btn_clearHistory(_, playerColor)
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
	    rebuildXML()
	    rebuildHUD()
	    printToAll("Token history cleared.", { 1, 0.8, 0.3 })
	end

-- ──────────────────────────────────────────────────────────────
--  onLoad
-- ──────────────────────────────────────────────────────────────

	function onLoad()
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
	    rebuildXML()
	    rebuildHUD()
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
	    local scale  = templateScale and { x=templateScale.x, y=templateScale.y, z=templateScale.z } or nil
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
		lastSelectedGUID = nil
		local tokens = findTokensForTarget(targetGUID)
		showDynamicPanel(targetGUID, #tokens)
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
	        local toRemove  = {}
	        local dirty     = false
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
--  onPlayerConnect event handlers
-- ──────────────────────────────────────────────────────────────
	function onPlayerConnect(player)
		seatedColors[player.color] = true
	end

	function onPlayerDisconnect(player)
		seatedColors[player.color] = nil
	end

-- ──────────────────────────────────────────────────────────────
--  PICK UP / DROP
-- ──────────────────────────────────────────────────────────────

	function onObjectPickUp(_, object)
	    local guid = object.getGUID()
		-- Transfer mode: picking up a model counts as selecting the destination
		if transferTokenGUID or transferSourceGUID then
			if not hoverEntries[guid] and guid ~= self.getGUID() and guid ~= previewGUID then
				local sourceModel = transferSourceGUID
				if not sourceModel and transferTokenGUID then
					local e = hoverEntries[transferTokenGUID]
					if e then sourceModel = e.targetGUID end
				end
				if sourceModel then
					if guid == sourceModel then
						broadcastToAll("Can't transfer to the same model.", { 1, 0.7, 0.3 })
					else
						local tokensToMove = transferTokenGUID
							and { transferTokenGUID }
							or  findTokensForTarget(transferSourceGUID)
						executeTransfer(guid, tokensToMove)
						transferTokenGUID  = nil
						transferSourceGUID = nil
					end
				end
			end
			-- fall through to normal pickup handling so tokens still hide
		end
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