-- ProfCD
-- Copyright (c) 2026 Bencepo. All rights reserved.
--
-- Profession cooldowns at a glance:
--   * hover the minimap button: remaining time of every tracked cooldown, for all
--     your characters
--   * click it: a window with the same timers and, per craft, whether the character
--     has the mats (in bags, in the bank, or what is missing)
-- Other characters are shown as of their last login. Reagents are read from the
-- profession window whenever you open it, so recipe changes in Forever are picked up
-- on their own; until then the Classic recipes below are used.

local ADDON = ...
local issecret = issecretvalue or function() return false end
local BUG_URL = "https://github.com/Bencepo/ProfCD/issues/new/choose"
local ACCENT = { 0.55, 0.80, 0.95, 1 }
local ACCENT_HEX = "|cff8cccf2"

local DEFAULTS = {
	showMinimap = true, -- minimap button
	showAlts = true,    -- other characters in tooltip and window
	notify = true,      -- chat notice when a cooldown is ready
}

-- Tracked cooldowns. In Forever every transmute has its own cooldown (Gold and
-- Truesilver 1 hour, Arcanite its own), so each recipe is an entry of its own.
-- icon: item id whose icon is shown. item: cooldown of an item instead of a spell.
-- reagents: { itemID, count } pairs, overwritten by what the profession window says.
local function transmute(id, label, icon, reagents)
	return { key = "tm" .. id, label = "Transmute: " .. label, icon = icon,
		recipes = { { id = id, label = label, reagents = reagents } } }
end

local TRACKED = {
	transmute(17187, "Arcanite", 12360, { { 12359, 1 }, { 12363, 1 } }),
	transmute(11480, "Truesilver", 6037, { { 3860, 1 } }),
	transmute(11479, "Gold", 3577, { { 3575, 1 } }),
	transmute(17559, "Air to Fire", 7078, { { 7082, 1 } }),
	transmute(17560, "Fire to Earth", 7076, { { 7078, 1 } }),
	transmute(17561, "Earth to Water", 7080, { { 7076, 1 } }),
	transmute(17562, "Water to Air", 7082, { { 7080, 1 } }),
	transmute(17563, "Undeath to Water", 7080, { { 12808, 1 } }),
	transmute(17564, "Water to Undeath", 12808, { { 7080, 1 } }),
	transmute(17565, "Life to Earth", 7076, { { 12803, 1 } }),
	transmute(17566, "Earth to Life", 12803, { { 7076, 1 } }),
	transmute(25146, "Elemental Fire", 7068, { { 7077, 1 } }),
	{ key = "mooncloth", label = "Mooncloth", icon = 14342, recipes = {
		{ id = 18560, label = "Mooncloth", reagents = { { 14256, 2 } } },
	} },
	{ key = "saltshaker", label = "Salt Shaker", icon = 15846, item = 15846, recipes = {
		{ id = "salt", label = "Refined Deeprock Salt", reagents = { { 8150, 1 } } },
	} },
}

-- English names for items the client has not cached yet.
local ITEM_NAMES = {
	[12359] = "Thorium Bar", [12363] = "Arcane Crystal", [3860] = "Mithril Bar", [3575] = "Iron Bar",
	[7082] = "Essence of Air", [7078] = "Essence of Fire", [7076] = "Essence of Earth",
	[7080] = "Essence of Water", [12808] = "Essence of Undeath", [12803] = "Living Essence",
	[7077] = "Heart of Fire", [14256] = "Felcloth", [8150] = "Deeprock Salt",
}

local SPELL_RECIPE = {} -- [spellID] = recipe
for _, cd in ipairs(TRACKED) do
	for _, r in ipairs(cd.recipes) do
		if type(r.id) == "number" then SPELL_RECIPE[r.id] = r end
	end
end

local db, me, myRealm, myServer, win, LDBIcon

---------------------------------------------------------------- helpers
-- Older API functions, used only where the C_ namespaces are missing.
local LEGACY = setmetatable({}, { __index = function(_, name) return _G[name] end })
local function itemCount(id, bank)
	if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id, bank) or 0 end
	return LEGACY.GetItemCount and LEGACY.GetItemCount(id, bank) or 0
end

local function itemName(id)
	local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
	if not n and LEGACY.GetItemInfo then n = (LEGACY.GetItemInfo(id)) end
	return n or ITEM_NAMES[id] or ("item " .. id)
end

local function itemIcon(id)
	return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id))
		or (LEGACY.GetItemIcon and LEGACY.GetItemIcon(id)) or 134400
end

local function isKnown(id)
	if LEGACY.IsPlayerSpell and LEGACY.IsPlayerSpell(id) then return true end
	if LEGACY.IsSpellKnown and LEGACY.IsSpellKnown(id) then return true end
	if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(id, 0) then return true end
	return false
end

-- Seconds left, 0 when ready, nil when the value cannot be trusted right now.
local function normalize(start, duration)
	if start == nil or duration == nil or issecret(start) or issecret(duration) then return nil end
	if duration == 0 then return 0 end
	if duration < 60 then return nil end -- global cooldown
	local t = GetTime()
	if start > t + 2147483.648 then start = start - 4294967.296 end
	return math.max(0, start + duration - t)
end

local function spellCD(id)
	if C_Spell and C_Spell.GetSpellCooldown then
		local info = C_Spell.GetSpellCooldown(id)
		if not info then return nil end
		return normalize(info.startTime, info.duration)
	elseif LEGACY.GetSpellCooldown then
		return normalize(LEGACY.GetSpellCooldown(id))
	end
end

local function itemCD(id)
	if C_Container and C_Container.GetItemCooldown then return normalize(C_Container.GetItemCooldown(id)) end
	if LEGACY.GetItemCooldown then return normalize(LEGACY.GetItemCooldown(id)) end
end

local function reagentsOf(r)
	return (type(r.id) == "number" and db.reagents[r.id]) or r.reagents
end

local function fmt(readyAt)
	local rem = readyAt - time()
	if rem <= 0 then return "|cff60ff60Ready|r" end
	local d, h, m = math.floor(rem / 86400), math.floor(rem % 86400 / 3600), math.floor(rem % 3600 / 60)
	if d > 0 then return format("%dd %dh", d, h) end
	if h > 0 then return format("%dh %02dm", h, m) end
	return format("%dm", math.max(m, 1))
end

local function nameOf(c)
	local n = c.name
	-- realm suffix only for characters on another server (the realm name itself can vary)
	local other = (c.server and myServer) and c.server ~= myServer or (not c.server and c.realm ~= myRealm)
	if other then n = n .. "-" .. c.realm end
	local col = RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]
	if col and col.colorStr then return "|c" .. col.colorStr .. n .. "|r" end
	return n
end

local function matStatus(c, r)
	local missing, inBank, n = {}, false, math.huge
	for _, rg in ipairs(reagentsOf(r)) do
		local id, need = rg[1], rg[2]
		local m = c.mats[id]
		local bags, total = m and m[1] or 0, m and m[2] or 0
		n = math.min(n, math.floor(total / need))
		if bags < need then
			if total >= need then inBank = true
			else missing[#missing + 1] = (need - total) .. "x " .. itemName(id) end
		end
	end
	if #missing > 0 then return "|cffff6060Missing: " .. table.concat(missing, ", ") .. "|r" end
	local txt = inBank and "|cffffd24dMats in bank|r" or "|cff60ff60Mats in bags|r"
	if n ~= math.huge and n > 1 then txt = txt .. " |cff8d97a5(" .. n .. "x)|r" end
	return txt
end

local function charList(alts)
	local list = { me }
	if alts then
		local others = {}
		for _, c in pairs(db.chars) do
			if c ~= me and next(c.cds) then others[#others + 1] = c end
		end
		table.sort(others, function(a, b) return a.name < b.name end)
		for _, c in ipairs(others) do list[#list + 1] = c end
	end
	return list
end

---------------------------------------------------------------- scanning
local function scan()
	if not me then return end
	local now = time()
	for _, cd in ipairs(TRACKED) do
		local any, unsure, best = false, false, 0
		local inBags = cd.item and itemCount(cd.item, false) > 0
		for _, r in ipairs(cd.recipes) do
			local known
			if cd.item then known = itemCount(cd.item, true) > 0 else known = isKnown(r.id) end
			me.known[r.id] = known or nil
			if known then
				any = true
				local rem
				if cd.item then
					if inBags then rem = itemCD(cd.item) end -- the cooldown only shows while it is in the bags
				else
					rem = spellCD(r.id)
				end
				if rem == nil then unsure = true elseif rem > best then best = rem end
			end
		end
		if not any then
			me.cds[cd.key] = nil
		elseif best > 0 then
			me.cds[cd.key] = math.floor(now + best + 0.5)
		elseif not unsure or me.cds[cd.key] == nil then
			me.cds[cd.key] = 0
		end
	end
	-- mats of every known craft: bags and bags + bank
	for _, cd in ipairs(TRACKED) do
		for _, r in ipairs(cd.recipes) do
			if me.known[r.id] then
				for _, rg in ipairs(reagentsOf(r)) do
					local bags = itemCount(rg[1], false)
					me.mats[rg[1]] = { bags, math.max(itemCount(rg[1], true), bags) }
				end
			end
		end
	end
	me.seen = now
end

-- Reagents as the open profession window lists them (Classic trade skill API).
local function learnReagents()
	if not (GetNumTradeSkills and GetTradeSkillRecipeLink and GetTradeSkillNumReagents) then return end
	for i = 1, GetNumTradeSkills() or 0 do
		local link = GetTradeSkillRecipeLink(i)
		local id = link and tonumber(link:match("enchant:(%d+)"))
		if id and SPELL_RECIPE[id] then
			local list = {}
			for j = 1, GetTradeSkillNumReagents(i) or 0 do
				local _, _, need = GetTradeSkillReagentInfo(i, j)
				local rl = GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(i, j)
				local item = rl and tonumber(rl:match("item:(%d+)"))
				if item and need and need > 0 then list[#list + 1] = { item, need } end
			end
			if #list > 0 then db.reagents[id] = list end
		end
	end
end

local scanQueued = false
local function queueScan(delay)
	if scanQueued then return end
	scanQueued = true
	C_Timer.After(delay or 1, function()
		scanQueued = false
		scan()
	end)
end

---------------------------------------------------------------- tooltip
local function fillTooltip(tt)
	scan()
	tt:AddLine("ProfCD", ACCENT[1], ACCENT[2], ACCENT[3])
	local any = false
	for _, c in ipairs(charList(db.showAlts)) do
		if next(c.cds) then
			any = true
			tt:AddLine(" ")
			tt:AddLine(nameOf(c))
			for _, cd in ipairs(TRACKED) do
				local ra = c.cds[cd.key]
				if ra then
					tt:AddDoubleLine("|T" .. itemIcon(cd.icon) .. ":14|t " .. cd.label, fmt(ra), 0.9, 0.9, 0.9, 1, 1, 1)
				end
			end
		end
	end
	if not any then tt:AddLine("No profession cooldowns known yet.", 0.6, 0.6, 0.6) end
	tt:AddLine(" ")
	tt:AddLine("|cffffffffClick:|r mats and details", 0.8, 0.8, 0.8)
	tt:AddLine("|cffffffffDrag:|r move this button", 0.8, 0.8, 0.8)
end

---------------------------------------------------------------- window
local rows = {}
local TOP = -72

local function getRow(i)
	if rows[i] then return rows[i] end
	local r = {}
	r.icon = win:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(16, 16)
	r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	r.label = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	r.label:SetJustifyH("LEFT")
	r.time = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	r.time:SetJustifyH("RIGHT")
	r.status = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.status:SetJustifyH("LEFT")
	r.status:SetWidth(250)
	r.status:SetWordWrap(false)
	rows[i] = r
	return r
end

local function drawWindow()
	if not (win and win:IsShown()) then return end
	local i, y = 0, TOP
	local function add(kind, icon, label, timeTxt, status, indent)
		i = i + 1
		local r = getRow(i)
		if kind == "char" and i > 1 then y = y - 8 end
		local x = 16 + (indent or 0)
		r.icon:ClearAllPoints()
		r.icon:SetPoint("TOPLEFT", win, "TOPLEFT", x, y)
		if icon then r.icon:SetTexture(icon) end
		r.icon:SetShown(icon ~= nil)
		r.label:ClearAllPoints()
		r.label:SetPoint("TOPLEFT", win, "TOPLEFT", icon and x + 22 or x, y - 2)
		r.label:SetFontObject(kind == "char" and "GameFontNormal" or (kind == "recipe" and "GameFontHighlightSmall" or "GameFontHighlight"))
		r.label:SetText(label)
		r.label:Show()
		r.time:ClearAllPoints()
		r.time:SetPoint("TOPRIGHT", win, "TOPLEFT", 300, y - 2)
		r.time:SetText(timeTxt or "")
		r.time:Show()
		r.status:ClearAllPoints()
		r.status:SetPoint("TOPLEFT", win, "TOPLEFT", 316, y - 3)
		r.status:SetText(status or "")
		r.status:Show()
		y = y - (kind == "char" and 22 or 18)
	end
	for _, c in ipairs(charList(db.showAlts)) do
		if next(c.cds) then
			local sub = c == me and "this character" or ("as of " .. date("%d.%m. %H:%M", c.seen or 0))
			add("char", nil, nameOf(c) .. "  |cff8d97a5" .. sub .. "|r")
			for _, cd in ipairs(TRACKED) do
				local ra = c.cds[cd.key]
				if ra then
					local r = cd.recipes[1]
					add("cd", itemIcon(cd.icon), cd.label, fmt(ra), c.known[r.id] and matStatus(c, r))
				end
			end
		end
	end
	if i == 0 then
		add("char", nil, "|cff8d97a5No profession cooldowns known yet. Log in once with each crafter.|r")
	end
	for j = i + 1, #rows do
		local r = rows[j]
		r.icon:Hide(); r.label:Hide(); r.time:Hide(); r.status:Hide()
	end
	win:SetHeight(-y + 46)
end

-- Players without the minimap button get an account-wide macro "ProfCD" (/pcd):
-- one click opens the window, the next closes it. Made when the button is turned
-- off; at login only once, so a macro the player deleted is not forced back.
local MACRO_NAME = "ProfCD"
local macroPending, macroForce = false, false

local function ensureMacro(force)
	if not CreateMacro or not GetMacroIndexByName then return end
	if GetMacroIndexByName(MACRO_NAME) > 0 then db.macroMade = true; return end
	if db.macroMade and not force then return end
	if InCombatLockdown() then macroPending, macroForce = true, force; return end
	local accountMacros = GetNumMacros()
	if accountMacros >= (MAX_ACCOUNT_MACROS or 120) then
		print(ACCENT_HEX .. "ProfCD:|r no free account macro slot. Type /pcd to open the window.")
		return
	end
	local ok = pcall(CreateMacro, MACRO_NAME, "INV_Misc_PocketWatch_01", "/pcd", nil)
	if not ok then ok = pcall(CreateMacro, MACRO_NAME, "INV_MISC_QUESTIONMARK", "/pcd", nil) end
	if ok then
		db.macroMade = true
		print(ACCENT_HEX .. "ProfCD:|r created the macro \"" .. MACRO_NAME .. "\" (/macro, general tab). Put it on a bar: one click opens the window, the next closes it.")
	end
end

local function applyMinimap(fromOption)
	if not LDBIcon then return end
	db.minimap.hide = not db.showMinimap
	if db.showMinimap then LDBIcon:Show(ADDON) else LDBIcon:Hide(ADDON) end
	if not db.showMinimap then ensureMacro(fromOption) end
end

local function buildWindow()
	local UI = LibStub("BencepoUI-1.0")
	win = UI:CreateWindow({
		name = "ProfCDWindow", title = "ProfCD", subtitle = "profession cooldowns",
		width = 580, height = 200, accent = ACCENT, db = db, posKey = "winPos",
		bugUrl = BUG_URL, hint = "drag to move",
		onShow = function() scan(); drawWindow() end,
	})
	win:Check(16, -44, "Minimap button", 'Show the ProfCD button at the minimap. Turned off, a macro "ProfCD" is made for you: one click opens this window, the next closes it. /pcd works too.',
		function() return db.showMinimap end, function(v) db.showMinimap = v; applyMinimap(true) end)
	win:Check(170, -44, "Show other characters", "Cooldowns and mats of your other characters, as of their last login.",
		function() return db.showAlts end, function(v) db.showAlts = v; drawWindow() end)
	win:Check(380, -44, "Chat notice when ready", "A line in the chat when a cooldown of this character is ready.",
		function() return db.notify end, function(v) db.notify = v end)
	local acc = 0
	win:HookScript("OnUpdate", function(_, e)
		acc = acc + e
		if acc >= 1 then acc = 0; drawWindow() end
	end)
end

local function toggleWindow()
	if not win then buildWindow() end
	win:Toggle()
end

---------------------------------------------------------------- notices
local announced = {}
local function say(msg) print(ACCENT_HEX .. "ProfCD:|r " .. msg) end

local function checkReady(login)
	if not (me and db.notify) then return end
	local now, ready = time(), {}
	for _, cd in ipairs(TRACKED) do
		local ra = me.cds[cd.key]
		if ra and ra <= now and announced[cd.key] ~= ra then
			announced[cd.key] = ra
			if login or ra > 0 then ready[#ready + 1] = cd.label end
		end
	end
	if #ready > 0 then say(table.concat(ready, ", ") .. (#ready > 1 and " are" or " is") .. " ready.") end
end

---------------------------------------------------------------- minimap, slash
local function registerMinimap()
	local LDB = LibStub("LibDataBroker-1.1", true)
	LDBIcon = LibStub("LibDBIcon-1.0", true)
	if not (LDB and LDBIcon) then return end
	local obj = LDB:NewDataObject(ADDON, {
		type = "launcher",
		text = ADDON,
		icon = "Interface\\AddOns\\ProfCD\\Icons\\minimap",
		OnClick = function() toggleWindow() end,
		OnTooltipShow = fillTooltip,
	})
	db.minimap.hide = not db.showMinimap
	LDBIcon:Register(ADDON, obj, db.minimap)
end

function ProfCD_OnCompartmentClick() toggleWindow() end

SLASH_PROFCD1 = "/profcd"
SLASH_PROFCD2 = "/pcd"
SlashCmdList.PROFCD = function(msg)
	msg = strtrim(msg or "")
	local cmd, arg = msg:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()
	if cmd == "forget" and arg ~= "" then
		local removed = false
		for key, c in pairs(db.chars) do
			if c ~= me and (c.name:lower() == arg:lower() or key:lower() == arg:lower()) then
				db.chars[key] = nil
				removed = true
			end
		end
		say(removed and ("forgot " .. arg .. ".") or ("no other character named " .. arg .. "."))
		drawWindow()
	elseif cmd == "minimap" then
		db.showMinimap = not db.showMinimap
		applyMinimap(true)
	else
		toggleWindow()
	end
end

---------------------------------------------------------------- events
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		ProfCDDB = ProfCDDB or {}
		db = ProfCDDB
		for k, v in pairs(DEFAULTS) do
			if db[k] == nil then db[k] = v end
		end
		db.chars = db.chars or {}
		db.reagents = db.reagents or {}
		db.minimap = db.minimap or {}
	elseif event == "PLAYER_LOGIN" then
		myRealm = GetRealmName()
		local name = UnitName("player")
		local class = select(2, UnitClass("player"))
		-- Characters are kept by their GUID: the realm name the server reports can change
		-- (seen on Forever), which made the same character show up twice. Older entries of
		-- this character (same GUID, or same name and class without a GUID) are merged.
		local guid = UnitGUID("player")
		if guid and issecret(guid) then guid = nil end
		myServer = guid and guid:match("^Player%-(%d+)%-")
		local key = guid or (name .. "-" .. myRealm)
		local best
		for k, c in pairs(db.chars) do
			if k == key or (guid and c.guid == guid) or (not c.guid and c.name == name and c.class == class) then
				if not best or (c.seen or 0) > (best.seen or 0) then best = c end
				db.chars[k] = nil
			end
		end
		me = best or {}
		db.chars[key] = me
		me.name, me.realm, me.class, me.guid, me.server = name, myRealm, class, guid, myServer
		me.cds = me.cds or {}
		me.known = me.known or {}
		me.mats = me.mats or {}
		registerMinimap()
		if not db.showMinimap then ensureMacro(false) end
		for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "SPELL_UPDATE_COOLDOWN", "SPELLS_CHANGED",
			"TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "BANKFRAME_OPENED", "PLAYERBANKSLOTS_CHANGED", "PLAYER_LOGOUT", "PLAYER_REGEN_ENABLED" }) do
			pcall(self.RegisterEvent, self, e)
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		if not self.loggedIn then
			self.loggedIn = true
			-- cooldowns and spells are not reliable in the first moments after login
			C_Timer.After(5, function()
				scan()
				checkReady(true)
				C_Timer.NewTicker(20, function() checkReady(false) end)
			end)
		else
			queueScan(2)
		end
	elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" then
		learnReagents()
		queueScan(1)
	elseif event == "PLAYER_REGEN_ENABLED" then
		if macroPending then
			macroPending = false
			ensureMacro(macroForce)
		end
	elseif event == "PLAYER_LOGOUT" then
		scan()
	else
		queueScan(1)
	end
end)
