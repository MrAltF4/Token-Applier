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
	local tokenNameBtnIndices = {}
	local dynamicState = {
	    removeCount  = 0,
	    scaleShown   = false,
	    radiusShown  = false,
	}
	local followLoopRunning    = false
	local selectionLoopRunning = false
	local tokenHistory         = {}
	local collisionCooldown    = false
	local heldModels           = {}
	local settingsOpen         = false
	local hudVisible           = true   -- HUD toggle state
	local hudEnabled           = true   -- false = HUD fully removed from Global UI

-- ──────────────────────────────────────────────────────────────
--  FORWARD DECLARATIONS
-- ──────────────────────────────────────────────────────────────
	local spawnPreview
	local refreshTemplateButton
	local rebuildXML
	local rebuildHUD          -- NEW: forward-declare HUD builder
	local hudRebuildPending = false

-- ──────────────────────────────────────────────────────────────
--  BUTTON STYLES
--  Centralised colour/transition definitions for all XML buttons.
--  Each style defines the four Unity button states as a pipe-
--  separated string: normal|highlighted|pressed|disabled
--  transition="ColorTint" makes TTS smoothly tint between them.
-- ──────────────────────────────────────────────────────────────

	local BTN_STYLE = {
	    -- Primary action (Add Token)
	    primary = {
	        colors     = "#0D2B40F2|#1A5C8AF2|#0A1F2EF2|#333333AA",
	        textColor  = "#3CCCFF",
	        transition = "ColorTint",
	    },
	    -- Passive/info (Set Template label)
	    template = {
	        colors     = "#111111B2|#222222CC|#0A0A0AB2|#333333AA",
	        textColor  = "#CCCC44",
	        transition = "ColorTint",
	    },
	    -- Settings gear and neutral utility
	    settings = {
	        colors     = "#000000F2|#222222F2|#111111F2|#333333AA",
	        textColor  = "#FDFF6F",
	        transition = "ColorTint",
	    },
	    -- Settings panel inner buttons (restore, debug, clear, HUD)
	    settingsItem = {
	        colors     = "#484716F2|#6B6B22F2|#303010F2|#333333AA",
	        textColor  = "#FFFFFF",
	        transition = "ColorTint",
	    },
	    -- Danger/destructive (clear history, HUD OFF state)
	    danger = {
	        colors     = "#2B0D0DF2|#5A1A1AF2|#1F0A0AF2|#333333AA",
	        textColor  = "#FF6060",
	        transition = "ColorTint",
	    },
	    -- Active/selected (active history slot, HUD ON state)
	    active = {
	        colors     = "#15AFCCF2|#1DCEF0F2|#0F8099F2|#333333AA",
	        textColor  = "#FFFFFF",
	        transition = "ColorTint",
	    },
	    -- Empty/inactive (empty history slot)
	    ghost = {
	        colors     = "#080808B2|#141414CC|#050505B2|#333333AA",
	        textColor  = "#404040",
	        transition = "ColorTint",
	    },
	    -- History slot with content
	    historySlot = {
	        colors     = "#0D140DF2|#1A281AF2|#08100AF2|#333333AA",
	        textColor  = "#FFFFFF",
	        transition = "ColorTint",
	    },
	    -- HUD action buttons
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
	}

	-- Returns a string of XML attributes for a named style.
	-- Usage:  '<Button ' .. btnStyle("primary") .. ' ...>'
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
	    local blob = {
	        hoverEntries  = hoverEntries,
	        modelRadius   = modelRadius,
	        templateJSON  = templateJSON,
	        templateScale = templateScale,
	        previewGUID   = previewGUID,
	        tokenHistory  = tokenHistory,
	    }
	    self.script_state = JSON.encode(blob)
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
	    if type(data.templateJSON)  == "string" then templateJSON  = data.templateJSON  end
	    if type(data.templateScale) == "table"  then templateScale = data.templateScale end
	    if type(data.previewGUID)   == "string" then previewGUID   = data.previewGUID   end
	    if type(data.tokenHistory)  == "table"  then tokenHistory  = data.tokenHistory  end
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
	    saveState()
	    refreshTemplateButton()
	    spawnPreview()
	    rebuildXML()
	    rebuildHUD()   -- keep HUD in sync when history changes
	end

-- ──────────────────────────────────────────────────────────────
--  HISTORY BUTTON HANDLERS  (Object UI — unchanged)
-- ──────────────────────────────────────────────────────────────

	function btn_history_1(_, _) activateHistoryEntry(1) end
	function btn_history_2(_, _) activateHistoryEntry(2) end
	function btn_history_3(_, _) activateHistoryEntry(3) end
	function btn_history_4(_, _) activateHistoryEntry(4) end
	function btn_history_5(_, _) activateHistoryEntry(5) end
	function btn_history_6(_, _) activateHistoryEntry(6) end
	function btn_history_7(_, _) activateHistoryEntry(7) end
	function btn_history_8(_, _) activateHistoryEntry(8) end

-- ──────────────────────────────────────────────────────────────
--  HUD HISTORY HANDLERS
--  XML Global UI callbacks receive a Player object, not a colour
--  string. These shims extract player.color and call the real
--  history activator. Named distinctly so they don't conflict
--  with the Object UI handlers above.
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
--  Shims for Add Token and Remove Tokens.
--  player.color extracts the colour string the real functions expect.
-- ──────────────────────────────────────────────────────────────

	-- Add Token via HUD
	function hud_addToken(player, _, _)
	    btn_toggleToken(nil, player.color)
	end

	-- Remove all tokens from selected model via HUD
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
	    clearAllDynamicButtons()
	    local targetObj  = getObjectFromGUID(targetGUID)
	    local targetName = targetObj and targetObj.getName() or "Unknown"
	    printToColor("Removed all tokens from " .. targetName, playerColor, { 1, 0.5, 0.5 })
	end

	-- Toggle HUD visibility
	function hud_toggleVisible(player, _, _)
	    hudVisible = not hudVisible
	    if hudVisible then
	        UI.show("tc_hud_main")
	        UI.hide("tc_hud_restore")
	    else
	        UI.hide("tc_hud_main")
	        UI.show("tc_hud_restore")
	    end
	end

	-- Toggle HUD on/off entirely (called from settings panel)
	function btn_toggleHUD(_, _)
	    hudEnabled = not hudEnabled
	    if hudEnabled then
	        hudVisible = true
	        rebuildHUD()
	        self.UI.setAttribute("hudToggleBtn", "text", "HUD: ON")
	        self.UI.setAttribute("hudToggleBtn", "color", "#484716F2")
	    else
	        local existing = UI.getXml() or ""
	        existing = existing:gsub("<!%-%-TC_HUD_START%-%->.-<!%-%-TC_HUD_END%-%->", "")
	        existing = existing:gsub("%s+$", "")
	        UI.setXml(existing)
	        self.UI.setAttribute("hudToggleBtn", "text", "HUD: OFF")
	        self.UI.setAttribute("hudToggleBtn", "color", "#2B0D0DF2")
	    end
	end

-- ──────────────────────────────────────────────────────────────
--  SETTINGS BUTTON (Object XML)
-- ──────────────────────────────────────────────────────────────

	function btn_toggleSettings(_, _)
	    settingsOpen = not settingsOpen
	    if settingsOpen then
	        self.UI.show("settingsPanel")
	    else
	        self.UI.hide("settingsPanel")
	    end
	    self.UI.setAttribute("settingsBtn", "color", settingsOpen and "#1A6ECC" or "#000000")
	end

-- ──────────────────────────────────────────────────────────────
--  OBJECT XML UI  (unchanged — on the TC object surface)
-- ──────────────────────────────────────────────────────────────

	rebuildXML = function()
	    local lines = {}

	    local previewImage  = ""
	    local previewText   = ""
	    local previewActive = "False"
	    if templateJSON then
	        local ok, data = pcall(JSON.decode, templateJSON)
	        if ok and type(data) == "table" then
	            local url = extractImageURL(data)
	            if url and url ~= "" then
	                previewImage  = url
	                previewActive = "True"
	            else
	                local n = (data.Nickname and data.Nickname ~= "") and data.Nickname
	                       or (data.Name    and data.Name    ~= "") and data.Name
	                       or "Token"
	                previewText   = n
	                previewActive = "True"
	            end
	        end
	    end

	    table.insert(lines, '<Panel id="previewPanel"')
	    table.insert(lines,   ' active="' .. previewActive .. '"')
	    table.insert(lines,   ' position="0 0 -100"')
	    table.insert(lines,   ' rotation="0 0 180"')
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

	    table.insert(lines, '<Panel id="historyPanel"')
	    table.insert(lines,   ' position="0 400 -25"')
	    table.insert(lines,   ' rotation="0 0 180"')
	    table.insert(lines,   ' width="448" height="228"')
	    table.insert(lines,   ' color="#00000000">')
	    table.insert(lines, '  <GridLayout cellSize="110 110" spacing="2 2" startCorner="UpperLeft" startAxis="Horizontal" childAlignment="UpperLeft" width="448" height="228">')
	    for i = 1, HISTORY_MAX do
	        local entry    = tokenHistory[i]
	        local isActive = entry and (templateJSON == entry.json)
	        local style    = isActive and "active" or (entry and "historySlot" or "ghost")
	        local fnName   = "btn_history_" .. i
	        table.insert(lines, '    <Button id="histBtn' .. i .. '"')
	        table.insert(lines, '      onClick="' .. fnName .. '"')
	        table.insert(lines, '      ' .. btnStyle(style))
	        table.insert(lines, '      width="100" height="100"')
	        table.insert(lines, '      padding="3 3 3 3">')
	        if entry and entry.imageURL and entry.imageURL ~= "" then
	            table.insert(lines, '      <Image image="' .. entry.imageURL .. '" width="100" height="100" preserveAspect="true" />')
	        elseif entry then
	            local display = shortName(entry.name, 5, 3)
	            table.insert(lines, '      <Text text="' .. display .. '" fontSize="20" color="#FFFFFF" alignment="MiddleCenter" width="80" height="80" />')
	        else
	            table.insert(lines, '      <Text text="·" fontSize="20" color="#404040" alignment="MiddleCenter" width="58" height="58" />')
	        end
	        table.insert(lines, '    </Button>')
	    end
	    table.insert(lines, '  </GridLayout>')
	    table.insert(lines, '</Panel>')

	    table.insert(lines, '<Button id="settingsBtn"')
	    table.insert(lines, '  onClick="btn_toggleSettings"')
	    table.insert(lines, '  ' .. btnStyle("settings"))
	    table.insert(lines, '  position="0 540 -25"')
	    table.insert(lines, '  rotation="0 0 0"')
	    table.insert(lines, '  width="448" height="60"')
	    table.insert(lines, '  fontSize="40"')
	    table.insert(lines, '  tooltip="Open/close settings"')
	    table.insert(lines, '  padding="5 5 5 5">⚙</Button>')

	    table.insert(lines, '<Panel id="settingsPanel"')
	    table.insert(lines, '  active="' .. (settingsOpen and "True" or "False") .. '"')
	    table.insert(lines, '  showAnimation="SlideIn_Right"')
	    table.insert(lines, '  hideAnimation="SlideIn_Right"')
	    table.insert(lines, '  animationDuration="0.3"')
	    table.insert(lines, '  position="480 540 -25"')
	    table.insert(lines, '  rotation="0 0 180"')
	    table.insert(lines, '  width="448" height="60"')
	    table.insert(lines, '  color="#484716F2">')
	    table.insert(lines, '  <HorizontalLayout spacing="4" padding="8 8 8 8" childAlignment="MiddleCenter">')
	    table.insert(lines, '    <Button onClick="btn_restoreTokens" tooltip="Restore tokens after save/load if any are missing" ' .. btnStyle("settingsItem") .. ' fontSize="28" preferredWidth="130" preferredHeight="80">↺</Button>')
	    table.insert(lines, '    <Button onClick="btn_debug" tooltip="Print current hover-token table to console" ' .. btnStyle("settingsItem") .. ' fontSize="25" preferredWidth="130" preferredHeight="80">Debug IDs</Button>')
	    table.insert(lines, '    <Button onClick="btn_clearHistory" tooltip="Clear all token history and reset template" ' .. btnStyle("settingsItem") .. ' fontSize="28" preferredWidth="130" preferredHeight="80">※</Button>')
	    table.insert(lines, '    <Button id="hudToggleBtn"')
	    table.insert(lines, '      onClick="btn_toggleHUD"')
	    table.insert(lines, '      tooltip="Show or hide the on-screen HUD"')
	    table.insert(lines, '      ' .. btnStyle(hudEnabled and "settingsItem" or "danger"))
	    table.insert(lines, '      fontSize="22" preferredWidth="130" preferredHeight="80"')
	    table.insert(lines, '      >' .. (hudEnabled and "HUD: ON" or "HUD: OFF") .. '</Button>')
	    table.insert(lines, '  </HorizontalLayout>')
	    table.insert(lines, '</Panel>')

	    -- ── Add Token button ──
	    local templateLabel = "Set Template\n(none)"
	    if templateJSON then
	        local ok, data = pcall(JSON.decode, templateJSON)
	        if ok and type(data) == "table" then
	            local n = (data.Nickname and data.Nickname ~= "") and data.Nickname
	                   or (data.Name    and data.Name    ~= "") and data.Name
	            templateLabel = n and ("Set Template\n[" .. n .. "]") or "Set Template\n[custom]"
	        end
	    end

	    table.insert(lines, '<Button id="addTokenBtn"')
	    table.insert(lines, '  onClick="btn_toggleToken"')
	    table.insert(lines, '  ' .. btnStyle("primary"))
	    table.insert(lines, '  tooltip="Select a model, then click to add token"')
	    table.insert(lines, '  position="0 -100 -25"')
	    table.insert(lines, '  rotation="0 0 180"')
	    table.insert(lines, '  width="448" height="200"')
	    table.insert(lines, '  fontSize="60"')
	    table.insert(lines, '  >Add Token</Button>')

	    table.insert(lines, '<Button id="setTemplateBtn"')
	    table.insert(lines, '  onClick="btn_setTemplate"')
	    table.insert(lines, '  ' .. btnStyle("template"))
	    table.insert(lines, '  tooltip="Drop any object onto TC, or select an object then click to capture it as the token template"')
	    table.insert(lines, '  position="0 -330 -25"')
	    table.insert(lines, '  rotation="0 0 180"')
	    table.insert(lines, '  width="448" height="100"')
	    table.insert(lines, '  fontSize="26"')
	    table.insert(lines, '  >' .. templateLabel .. '</Button>')

	    local xml = '<Panel width="2000" height="2000" color="#00000000">\n'
	             .. table.concat(lines, "\n")
	             .. '\n</Panel>'
	    self.UI.setXml(xml)
	end

-- ──────────────────────────────────────────────────────────────
--  GLOBAL HUD INJECTION
--  Appends TC's HUD panel to whatever Global UI the host mod
--  already has. Uses GUID-prefixed onClick routing so all
--  callbacks fire into this object's script.
-- ──────────────────────────────────────────────────────────────

	-- Builds the HUD XML string. Extracted so it can be called for
	-- both initial injection and future re-injection.
	local function buildHUDXml(guid)
	    local lines = {}
	    local g = guid  -- GUID prefix for onClick routing

	    -- ── Main HUD panel (bottom centre) ──
	    table.insert(lines, '<Panel id="tc_hud_main"')
	    table.insert(lines, '  active="' .. (hudVisible and "True" or "False") .. '"')
	    table.insert(lines, '  rectAlignment="LowerCenter"')
	    table.insert(lines, '  offsetXY="0 10"')
	    table.insert(lines, '  width="500" height="214"')
	    table.insert(lines, '  color="#000000CC"')
	    table.insert(lines, '  padding="6 6 6 6">')

	    -- Row 1: history grid (8 slots)
	    table.insert(lines, '  <GridLayout id="tc_hud_grid"')
	    table.insert(lines, '    rectAlignment="UpperCenter"')
	    table.insert(lines, '    cellSize="54 54" spacing="3 3"')
	    table.insert(lines, '    startCorner="UpperLeft" startAxis="Horizontal"')
	    table.insert(lines, '    childAlignment="UpperCenter"')
	    table.insert(lines, '    width="488" height="114">')

	    for i = 1, HISTORY_MAX do
	        local entry    = tokenHistory[i]
	        local isActive = entry and (templateJSON == entry.json)
	        local style    = isActive and "active" or (entry and "historySlot" or "ghost")
	        local fnName   = g .. "/hud_history_" .. i

	        table.insert(lines, '    <Button id="tc_hud_hist_' .. i .. '"')
	        table.insert(lines, '      onClick="' .. fnName .. '"')
	        table.insert(lines, '      ' .. btnStyle(style))
	        table.insert(lines, '      width="54" height="54"')
	        table.insert(lines, '      padding="2 2 2 2">')
	        if entry and entry.imageURL and entry.imageURL ~= "" then
	            table.insert(lines, '      <Image image="' .. entry.imageURL .. '" width="50" height="50" preserveAspect="true" />')
	        elseif entry then
	            local display = shortName(entry.name, 4, 2)
	            table.insert(lines, '      <Text text="' .. display .. '" fontSize="14" color="#FFFFFF" alignment="MiddleCenter" />')
	        else
	            table.insert(lines, '      <Text text="·" fontSize="16" color="#303030" alignment="MiddleCenter" />')
	        end
	        table.insert(lines, '    </Button>')
	    end

	    table.insert(lines, '  </GridLayout>')

	    -- Row 2: action buttons
	    table.insert(lines, '  <HorizontalLayout')
	    table.insert(lines, '    rectAlignment="LowerCenter"')
	    table.insert(lines, '    spacing="6" padding="0 0 0 0"')
	    table.insert(lines, '    childAlignment="MiddleCenter"')
	    table.insert(lines, '    width="488" height="60">')

	    table.insert(lines, '    <Button id="tc_hud_add"')
	    table.insert(lines, '      onClick="' .. g .. '/hud_addToken"')
	    table.insert(lines, '      ' .. btnStyle("hudAdd"))
	    table.insert(lines, '      fontSize="18" preferredWidth="220" preferredHeight="52"')
	    table.insert(lines, '      tooltip="Add token to selected model"')
	    table.insert(lines, '      >＋ Add Token</Button>')

	    table.insert(lines, '    <Button id="tc_hud_remove"')
	    table.insert(lines, '      onClick="' .. g .. '/hud_removeTokens"')
	    table.insert(lines, '      ' .. btnStyle("hudRemove"))
	    table.insert(lines, '      fontSize="18" preferredWidth="220" preferredHeight="52"')
	    table.insert(lines, '      tooltip="Remove all tokens from selected model"')
	    table.insert(lines, '      >✕ Remove</Button>')

	    table.insert(lines, '    <Button id="tc_hud_hide"')
	    table.insert(lines, '      onClick="' .. g .. '/hud_toggleVisible"')
	    table.insert(lines, '      ' .. btnStyle("hudHide"))
	    table.insert(lines, '      fontSize="14" preferredWidth="40" preferredHeight="52"')
	    table.insert(lines, '      tooltip="Hide HUD"')
	    table.insert(lines, '      >_</Button>')

	    table.insert(lines, '  </HorizontalLayout>')
	    table.insert(lines, '</Panel>')

	    -- ── Restore button (shown when HUD is hidden) ──
	    table.insert(lines, '<Button id="tc_hud_restore"')
	    table.insert(lines, '  active="False"')
	    table.insert(lines, '  rectAlignment="LowerCenter"')
	    table.insert(lines, '  offsetXY="0 10"')
	    table.insert(lines, '  width="60" height="32"')
	    table.insert(lines, '  onClick="' .. g .. '/hud_toggleVisible"')
	    table.insert(lines, '  ' .. btnStyle("hudAdd"))
	    table.insert(lines, '  fontSize="14"')
	    table.insert(lines, '  tooltip="Show Token Controller HUD"')
	    table.insert(lines, '  >TC</Button>')

	    return table.concat(lines, "\n")
	end

	-- Assigned to forward-declared local above.
	-- Appends (or replaces) the HUD in Global UI.
	-- Debounced: rapid successive calls coalesce into one rebuild
	-- to avoid the stale-XML race when getXml/setXml are called quickly.
	rebuildHUD = function()
	    if hudRebuildPending then return end
	    hudRebuildPending = true
	    Wait.time(function()
	        hudRebuildPending = false
	        if not hudEnabled then return end
	        local guid    = self.getGUID()
	        local hudXml  = buildHUDXml(guid)
	        local existing = UI.getXml() or ""
	        existing = existing:gsub("<!%-%-TC_HUD_START%-%->.-<!%-%-TC_HUD_END%-%->", "")
	        existing = existing:gsub("%s+$", "")
	        local wrapped = "\n<!--TC_HUD_START-->\n" .. hudXml .. "\n<!--TC_HUD_END-->"
	        UI.setXml(existing .. wrapped)
	    end, 0.1)
	end

-- ──────────────────────────────────────────────────────────────
--  DYNAMIC BUTTON LAYOUT CONSTANTS
-- ──────────────────────────────────────────────────────────────

	local DYN_START       = 0   -- dynamic buttons now start at index 0 (no permanent Lua buttons)
	local SCALE_BTN_X      =  4.4
	local FLIP_BTN_X       =  5.2
	local ROTATE_BTN_X     =  5.2
	local RADIUS_BTN_Z     =  2.3
	local TOKEN_NAME_BTN_X =  4.5
	local REMOVE_BTN_X     =  7
	local REMOVE_BTN_Z_TOP =  4.3
	local REMOVE_BTN_STEP  =  0.8

-- ──────────────────────────────────────────────────────────────
--  BUTTON LABEL HELPERS
-- ──────────────────────────────────────────────────────────────

	refreshTemplateButton = function()
	    local label = "Set Template\n(none)"
	    if templateJSON then
	        local ok, data = pcall(JSON.decode, templateJSON)
	        if ok and type(data) == "table" and data.Nickname and data.Nickname ~= "" then
	            label = "Set Template\n[" .. data.Nickname .. "]"
	        elseif ok and type(data) == "table" and data.Name then
	            label = "Set Template\n[" .. data.Name .. "]"
	        else
	            label = "Set Template\n[custom]"
	        end
	    end
	    self.UI.setAttribute("setTemplateBtn", "text", label)
	end

-- ──────────────────────────────────────────────────────────────
--  DYNAMIC BUTTONS
-- ──────────────────────────────────────────────────────────────

	local dynamicButtonCount = 0

	local function clearAllDynamicButtons()
	    if dynamicButtonCount == 0 then return end
	    for i = DYN_START + dynamicButtonCount - 1, DYN_START, -1 do
	        self.removeButton(i)
	    end
	    dynamicButtonCount       = 0
	    dynamicState.removeCount = 0
	    dynamicState.scaleShown  = false
	    dynamicState.radiusShown = false
	    lastSelectedGUID         = nil
	    selectedTokenGUID        = nil
	end

	local function showDynamicButtons(targetGUID, tokenCount)
	    local expectedCount = 7
	    if tokenCount >= 2 then expectedCount = expectedCount + 2 end
	    expectedCount = expectedCount + math.min(tokenCount, MAX_TOKENS) * 2

	    if lastSelectedGUID == targetGUID and dynamicButtonCount == expectedCount then return end

	    clearAllDynamicButtons()
	    tokenNameBtnIndices = {}

	    self.createButton({
			label = "▲", tooltip = "Raise token height",
			click_function = "btn_heightUp", function_owner = self,
			position = { SCALE_BTN_X, 0.2, 2.3 }, width = 400, height = 400, font_size = 250,
			color = { 0, 0, 0, 0.9 }, font_color = { 0.8, 0.6, 1.0 },
		})
		dynamicButtonCount = dynamicButtonCount + 1

		self.createButton({
			label = "▼", tooltip = "Lower token height",
			click_function = "btn_heightDown", function_owner = self,
			position = { FLIP_BTN_X, 0.2, 2.3 }, width = 400, height = 400, font_size = 250,
			color = { 0, 0, 0, 0.9 }, font_color = { 0.8, 0.6, 1.0 },
		})
		dynamicButtonCount = dynamicButtonCount + 1

	    self.createButton({
	        label = "•", tooltip = "Scale up\nall tokens, or just selected",
	        click_function = "btn_scaleUp", function_owner = self,
	        position = { SCALE_BTN_X, 0.2, 1.5 }, width = 400, height = 400, font_size = 400,
	        color = { 0, 0, 0, 0.9 }, font_color = { 0.5, 1.0, 0.5 },
	    })
	    dynamicButtonCount = dynamicButtonCount + 1

	    self.createButton({
	        label = "·", tooltip = "Scale down\nall tokens, or just selected",
	        click_function = "btn_scaleDown", function_owner = self,
	        position = { SCALE_BTN_X, 0.2, 3.1 }, width = 400, height = 400, font_size = 400,
	        color = { 0, 0, 0, 0.9 }, font_color = { 1.0, 0.5, 0.5 },
	    })
	    dynamicButtonCount      = dynamicButtonCount + 1
	    dynamicState.scaleShown = true

	    self.createButton({
	        label = "Flip", tooltip = "Flip token\nall tokens, or just selected",
	        click_function = "btn_flip", function_owner = self,
	        position = { FLIP_BTN_X, 0.2, 1.5 }, width = 400, height = 400, font_size = 180,
	        color = { 0, 0, 0, 0.9 }, font_color = { 0.8, 0.6, 1.0 },
	    })
	    dynamicButtonCount = dynamicButtonCount + 1

	    self.createButton({
	        label = "↻", tooltip = "Rotate token 180°\nall tokens, or just selected",
	        click_function = "btn_rotate", function_owner = self,
	        position = { ROTATE_BTN_X, 0.2, 3.1 }, width = 400, height = 400, font_size = 180,
	        color = { 0, 0, 0, 0.9 }, font_color = { 0.8, 0.6, 1.0 },
	    })
	    dynamicButtonCount = dynamicButtonCount + 1

		self.createButton({
			label = "↕", tooltip = "Toggle vertical\nall tokens, or just selected",
			click_function = "btn_vertical", function_owner = self,
			position = { 6, 0.2, 1.5 }, width = 400, height = 400, font_size = 180,
			color = { 0, 0, 0, 0.9 }, font_color = { 0.8, 0.6, 1.0 },
		})
		dynamicButtonCount = dynamicButtonCount + 1

	    if tokenCount >= 2 then
	        self.createButton({
	            label = "⁛", tooltip = "Increase spread\ni.e. distance between tokens",
	            click_function = "btn_radiusUp", function_owner = self,
	            position = { 6, 0.2, RADIUS_BTN_Z }, width = 400, height = 400, font_size = 300,
	            color = { 0, 0, 0, 0.9 }, font_color = { 0.5, 1.0, 0.5 },
	        })
	        dynamicButtonCount = dynamicButtonCount + 1

	        self.createButton({
	            label = "⁘", tooltip = "Decrease spread\ni.e. distance between tokens",
	            click_function = "btn_radiusDown", function_owner = self,
	            position = { 3.6, 0.2, RADIUS_BTN_Z }, width = 400, height = 400, font_size = 200,
	            color = { 0, 0, 0, 0.9 }, font_color = { 1.0, 0.5, 0.5 },
	        })
	        dynamicButtonCount       = dynamicButtonCount + 1
	        dynamicState.radiusShown = true
	    end

	    local count  = math.min(tokenCount, MAX_TOKENS)
	    local tokens = findTokensForTarget(targetGUID)
	    for i = 1, count do
	        local tGUID      = tokens[i]
	        local name       = getTokenName(tGUID)
	        local zPos       = REMOVE_BTN_Z_TOP + (i - 1) * REMOVE_BTN_STEP
	        local isSelected = (selectedTokenGUID == tGUID)

	        self.setVar("removeSlot_" .. i, tGUID)
	        self.setVar("selectSlot_" .. i, tGUID)

	        self.createButton({
	            label = name,
	            tooltip = isSelected and "Click to deselect" or "Click to select\n\nModifiers (above) apply to this token only",
	            click_function = "btn_select_" .. i, function_owner = self,
	            position = { TOKEN_NAME_BTN_X, 0.2, zPos }, width = 1800, height = 400, font_size = 150,
	            color      = isSelected and { 0.1, 0.2, 0.4, 0.95 } or { 0.05, 0.05, 0.15, 0.95 },
	            font_color = isSelected and { 0.4, 0.8, 1.0 }        or { 0.6, 0.6, 0.8 },
	        })
	        tokenNameBtnIndices[i] = DYN_START + dynamicButtonCount
	        dynamicButtonCount = dynamicButtonCount + 1

	        self.createButton({
	            label = "✕", tooltip = "Remove: " .. name,
	            click_function = "btn_remove_" .. i, function_owner = self,
	            position = { REMOVE_BTN_X, 0.2, zPos }, width = 400, height = 400, font_size = 250,
	            color = { 0.15, 0.05, 0.05, 0.95 }, font_color = { 1.0, 0.4, 0.4 },
	        })
	        dynamicButtonCount = dynamicButtonCount + 1
	    end
	    dynamicState.removeCount = count
	    lastSelectedGUID         = targetGUID
	end

-- ──────────────────────────────────────────────────────────────
--  REMOVE HANDLERS
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
	    local newTokens = prevTarget and findTokensForTarget(prevTarget) or {}
	    if #newTokens > 0 then
	        showDynamicButtons(prevTarget, #newTokens)
	    else
	        clearAllDynamicButtons()
	    end
	    local targetObj  = prevTarget and getObjectFromGUID(prevTarget)
	    local targetName = targetObj and targetObj.getName() or "Unknown"
	    printToColor("Removed token: " .. name, playerColor, { 1, 0.5, 0.5 })
	    printToColor("  from " .. targetName .. " (" .. (prevTarget or "?") .. ")", playerColor, { 1, 1, 1 })
	end

	function btn_remove_1(_, pc) handleRemove(1, pc) end
	function btn_remove_2(_, pc) handleRemove(2, pc) end
	function btn_remove_3(_, pc) handleRemove(3, pc) end
	function btn_remove_4(_, pc) handleRemove(4, pc) end
	function btn_remove_5(_, pc) handleRemove(5, pc) end
	function btn_remove_6(_, pc) handleRemove(6, pc) end

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
	    local tokens = lastSelectedGUID and findTokensForTarget(lastSelectedGUID) or {}
	    for i, tG in ipairs(tokens) do
	        local idx = tokenNameBtnIndices[i]
	        if idx then
	            local isSelected = (selectedTokenGUID == tG)
	            self.editButton({
	                index      = idx,
	                color      = isSelected and { 0.1, 0.2, 0.4, 0.95 } or { 0.05, 0.05, 0.15, 0.95 },
	                font_color = isSelected and { 0.4, 0.8, 1.0 }        or { 0.6, 0.6, 0.8 },
	            })
	        end
	    end
	end

	function btn_select_1(_, _) handleSelectToken(1) end
	function btn_select_2(_, _) handleSelectToken(2) end
	function btn_select_3(_, _) handleSelectToken(3) end
	function btn_select_4(_, _) handleSelectToken(4) end
	function btn_select_5(_, _) handleSelectToken(5) end
	function btn_select_6(_, _) handleSelectToken(6) end

-- ──────────────────────────────────────────────────────────────
--  SELECTION POLLING LOOP
-- ──────────────────────────────────────────────────────────────

	function startSelectionLoop()
	    if selectionLoopRunning then return end
	    selectionLoopRunning = true
	    local function getSelection()
	        local colours = { "Red","Blue","White","Green","Yellow","Orange","Purple","Pink","Teal" }
	        for _, colour in ipairs(colours) do
	            local ok, sel = pcall(function()
	                local p = Player[colour]
	                if p and p.seated then return p.getSelectedObjects() end
	                return {}
	            end)
	            if ok and sel and #sel > 0 then return sel end
	        end
	        return {}
	    end
	    local function poll()
	        local sel = getSelection()
	        if #sel > 0 then
	            local guid   = sel[1].getGUID()
	            local tokens = findTokensForTarget(guid)
	            if #tokens > 0 then
	                showDynamicButtons(guid, #tokens)
	            else
	                if lastSelectedGUID ~= nil then clearAllDynamicButtons() end
	            end
	        else
	            if dynamicButtonCount > 0 then clearAllDynamicButtons() end
	        end
	        Wait.time(poll, 0.3)
	    end
	    Wait.time(poll, 0.3)
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
	    addToHistory(json, scale, name, imageURL)
	    saveState()
	    refreshTemplateButton()
	    spawnPreview()
	    rebuildXML()
	    rebuildHUD()   -- keep HUD history grid in sync

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
	    if previewGUID then
	        local obj = getObjectFromGUID(previewGUID)
	        if obj then obj.destroy() end
	        previewGUID = nil
	    end
	    saveState()
	    refreshTemplateButton()
	    rebuildXML()
	    rebuildHUD()   -- clear HUD history grid too
	    printToAll("Token history cleared.", { 1, 0.8, 0.3 })
	end

-- ──────────────────────────────────────────────────────────────
--  onLoad
-- ──────────────────────────────────────────────────────────────

	function onLoad()
	    loadState()

	    -- Build Object XML first, then inject HUD into Global UI.
	    -- Both wait for their respective UI loading flags.
	    Wait.condition(function()
	        rebuildXML()
	    end, function() return not self.UI.loading end)

	    Wait.condition(function()
	        rebuildHUD()
	    end, function() return not UI.loading end)

	    startFollowLoop()
	    startSelectionLoop()
	    restorePreview()
	end

-- ──────────────────────────────────────────────────────────────
--  TEMPLATE CAPTURE
-- ──────────────────────────────────────────────────────────────

	function btn_setTemplate(_, playerColor)
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
	    local name     = (data.Nickname and data.Nickname ~= "") and data.Nickname
	                     or (data.Name and data.Name ~= "") and data.Name
	                     or "Token"
	    local imageURL = extractImageURL(data)
	    addToHistory(json, templateScale, name, imageURL)
	    saveState()
	    refreshTemplateButton()
	    spawnPreview()
	    rebuildXML()
	    rebuildHUD()   -- keep HUD in sync
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

	function btn_heightUp(_, playerColor)
		local sel = Player[playerColor].getSelectedObjects()
		if #sel == 0 then printToColor("Select a model first.", playerColor, { 1, 1, 1 }) return end
		applyHeightToTokens(sel[1].getGUID(), HEIGHT_STEP, playerColor)
	end

	function btn_heightDown(_, playerColor)
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

	function btn_scaleUp(_, playerColor)
	    local sel = Player[playerColor].getSelectedObjects()
	    if #sel == 0 then printToColor("Select a model first.", playerColor, { 1, 1, 1 }) return end
	    applyScaleToTokens(sel[1].getGUID(), SCALE_STEP, playerColor)
	end

	function btn_scaleDown(_, playerColor)
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

	function btn_flip(_, playerColor)
	    local sel = Player[playerColor].getSelectedObjects()
	    if #sel == 0 then printToColor("Select a model first.", playerColor, { 1, 1, 1 }) return end
	    applyTransformToTokens(sel[1].getGUID(), playerColor, function(token, entry)
	        local rot = token.getRotation()
	        local newX = (math.abs(rot.x - 180) < 5) and 0 or 180
	        token.setRotation({ newX, rot.y, rot.z })
	        entry.flipped = (newX == 180)
	    end)
	end

	function btn_rotate(_, playerColor)
	    local sel = Player[playerColor].getSelectedObjects()
	    if #sel == 0 then printToColor("Select a model first.", playerColor, { 1, 1, 1 }) return end
	    applyTransformToTokens(sel[1].getGUID(), playerColor, function(token, entry)
	        local rot = token.getRotation()
	        local newY = (math.abs(rot.y - 180) < 5) and 0 or 180
	        token.setRotation({ rot.x, newY, rot.z })
	        entry.rotated = (newY == 180)
	    end)
	end

	function btn_vertical(_, playerColor)
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
--  RADIUS ADJUST
-- ──────────────────────────────────────────────────────────────

	local function applyRadiusToModel(targetGUID, delta, playerColor)
	    local tokens = findTokensForTarget(targetGUID)
	    if #tokens < 2 then printToColor("Need 2+ tokens on model to adjust spread.", playerColor, { 1, 1, 0 }) return end
	    local newRadius = math.max(0.2, getRadiusForTarget(targetGUID) + delta)
	    modelRadius[targetGUID] = newRadius
	    saveState()
	end

	function btn_radiusUp(_, playerColor)
	    local sel = Player[playerColor].getSelectedObjects()
	    if #sel == 0 then printToColor("Select a model first.", playerColor, { 1, 1, 1 }) return end
	    applyRadiusToModel(sel[1].getGUID(), RADIUS_STEP, playerColor)
	end

	function btn_radiusDown(_, playerColor)
	    local sel = Player[playerColor].getSelectedObjects()
	    if #sel == 0 then printToColor("Select a model first.", playerColor, { 1, 1, 1 }) return end
	    applyRadiusToModel(sel[1].getGUID(), -RADIUS_STEP, playerColor)
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
	                if callback then callback(token) end
	            end
	        end,
	    })
	end

-- ──────────────────────────────────────────────────────────────
--  ADD TOKEN
-- ──────────────────────────────────────────────────────────────

	function btn_toggleToken(_, playerColor)
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
	        local targetObj  = getObjectFromGUID(targetGUID)
	        local targetName = targetObj and targetObj.getName() or "Unknown"
	        printToColor("Added token: " .. getTokenName(newGUID), playerColor, { 0.5, 1, 0.5 })
	        printToColor("  to " .. targetName .. " (" .. targetGUID .. ")", playerColor, { 1, 1, 1 })
	    end)
	end

-- ──────────────────────────────────────────────────────────────
--  FOLLOW LOOP
-- ──────────────────────────────────────────────────────────────

	function startFollowLoop()
	    if followLoopRunning then return end
	    followLoopRunning = true

	    local function buildTargetMap()
	        local map = {}
	        for tGUID, entry in pairs(hoverEntries) do
	            if type(entry) == "table" then
	                local tgt = entry.targetGUID
	                if not map[tgt] then map[tgt] = {} end
	                map[tgt][#map[tgt] + 1] = tGUID
	            end
	        end
	        return map
	    end

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
	                    else
	                        local entry = hoverEntries[tGUID]
	                        entry.lastKnownPos = { x=tPos.x, y=tPos.y, z=tPos.z }
	                        entry.missingTime  = nil
	                        local pos
	                        if total == 1 then
	                            pos = { x=tPos.x, y=tPos.y + entry.offset, z=tPos.z }
	                        else
	                            local angle = ((idx-1) / total) * (2 * math.pi)
	                            pos = {
	                                x = tPos.x + radius * math.cos(angle),
	                                y = tPos.y + entry.offset,
	                                z = tPos.z + radius * math.sin(angle),
	                            }
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
	        if dirty then saveState() end
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
	    printToAll("Restored " .. restored .. " hover token(s).", { 0.3, 0.8, 1 })
	end

-- ──────────────────────────────────────────────────────────────
--  PICK UP / DROP
-- ──────────────────────────────────────────────────────────────

	function onObjectPickUp(_, object)
	    local guid = object.getGUID()
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
	    print("──────────────────────────")
	end