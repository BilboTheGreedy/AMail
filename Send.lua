local _, ns = ...
local UI = ns.UI

local Send = {}
ns.Send = Send

local controls
local batch
local completing

local function nameBox()
	return (ns.Window and ns.Window.NameBox()) or SendMailNameEditBox
end

local function subjectBox()
	return (ns.Window and ns.Window.SubjectBox()) or SendMailSubjectEditBox
end

function Send.Remember(name, subject)
	if type(name) ~= "string" or name == "" then return end
	ns.chardb.lastTo = name
	local recent = ns.db.recent
	for i = #recent, 1, -1 do
		if recent[i]:lower() == name:lower() then table.remove(recent, i) end
	end
	table.insert(recent, 1, name)
	while #recent > 10 do table.remove(recent) end
	if type(subject) == "string" and subject ~= "" and not batch then ns.db.lastSubject = subject end
end

function Send.Names()
	local out, seen = {}, {}
	for _, n in ipairs(ns.Alts()) do
		if not seen[n:lower()] then
			seen[n:lower()] = true
			out[#out + 1] = n
		end
	end
	for _, n in ipairs(ns.db.recent) do
		if not seen[n:lower()] then
			seen[n:lower()] = true
			out[#out + 1] = n
		end
	end
	return out
end

function Send.Complete(text)
	if not text or text == "" then return nil end
	local l = text:lower()
	for _, n in ipairs(Send.Names()) do
		if #n > #l and n:lower():sub(1, #l) == l then return n end
	end
	return nil
end

function Send.SetRecipient(name)
	local box = nameBox()
	if not box then return end
	completing = true
	box:SetText(name)
	completing = false
	local subject = subjectBox()
	if subject and subject.SetFocus then subject:SetFocus() end
end

local function recipientMenu(anchor)
	local entries = {}
	local alts = ns.Alts()
	if #alts > 0 then
		entries[#entries + 1] = { text = "My characters", title = true }
		for _, n in ipairs(alts) do
			entries[#entries + 1] = { text = n, func = function() Send.SetRecipient(n) end }
		end
	end
	if #ns.db.recent > 0 then
		entries[#entries + 1] = { text = "Recent", title = true }
		for _, n in ipairs(ns.db.recent) do
			entries[#entries + 1] = { text = n, func = function() Send.SetRecipient(n) end }
		end
	end
	if #entries == 0 then
		entries[1] = { text = "No characters or recent recipients yet", title = true }
	end
	UI.Menu(anchor, entries)
end
Send.RecipientMenu = recipientMenu

local function slots(bag)
	if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) or 0 end
	if GetContainerNumSlots then return GetContainerNumSlots(bag) or 0 end
	return 0
end

local function slotInfo(bag, slot)
	if C_Container and C_Container.GetContainerItemInfo then
		local ok, t = pcall(C_Container.GetContainerItemInfo, bag, slot)
		if ok and type(t) == "table" and t.itemID then
			return { id = t.itemID, link = t.hyperlink, quality = t.quality, count = t.stackCount or 1, bound = t.isBound, locked = t.isLocked }
		end
	elseif GetContainerItemInfo then
		local _, n, locked, quality, _, _, link, _, _, id = GetContainerItemInfo(bag, slot)
		if id then return { id = id, link = link, quality = quality, count = n or 1, locked = locked } end
	end
	return nil
end

local function pickup(bag, slot)
	if C_Container and C_Container.PickupContainerItem then
		C_Container.PickupContainerItem(bag, slot)
	elseif PickupContainerItem then
		PickupContainerItem(bag, slot)
	end
end

local QUALITY = { [2] = "Uncommon", [3] = "Rare", [4] = "Epic" }

local function groupOf(it)
	local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	if not get then return nil end
	local _, _, _, _, _, itemType, subType, _, _, _, _, classID = get(it.id)
	if not classID then return nil end
	if classID == 2 or classID == 4 then
		local q = QUALITY[it.quality or 0]
		if not q then return nil end
		return "q" .. it.quality, q .. " equipment"
	end
	if classID == 7 or classID == 5 or classID == 9 then
		local label = (subType and subType ~= "" and subType ~= itemType) and subType or itemType
		if not label then return nil end
		return "c" .. classID .. ":" .. label, label
	end
	return nil
end

function Send.Groups()
	local groups, order = {}, {}
	for bag = 0, 4 do
		for slot = 1, slots(bag) do
			local it = slotInfo(bag, slot)
			if it and not it.bound and not it.locked then
				local key, label = groupOf(it)
				if key then
					local g = groups[key]
					if not g then
						g = { key = key, label = label, stacks = {} }
						groups[key] = g
						order[#order + 1] = g
					end
					g.stacks[#g.stacks + 1] = { bag = bag, slot = slot, id = it.id }
				end
			end
		end
	end
	table.sort(order, function(a, b) return a.label < b.label end)
	return order
end

local function target()
	local box = nameBox()
	local name = box and box:GetText() or ""
	if name == "" then name = ns.chardb.lastTo or "" end
	return name
end

local function sendNext()
	if not batch then return end
	if not ns.Open() then
		batch = nil
		return
	end
	local b = batch
	if #b.stacks == 0 then
		batch = nil
		ns.Print("sent " .. b.sent .. " stacks of " .. b.label .. " to " .. b.to .. " in " .. b.mails .. (b.mails == 1 and " mail" or " mails"))
		return
	end
	if not ClickSendMailItemButton or not SendMail then
		batch = nil
		return
	end
	local max = ATTACHMENTS_MAX_SEND or 12
	local n = 0
	while #b.stacks > 0 and n < max do
		local s = table.remove(b.stacks, 1)
		local it = slotInfo(s.bag, s.slot)
		if it and it.id == s.id and not it.locked then
			pickup(s.bag, s.slot)
			ClickSendMailItemButton()
			n = n + 1
		end
	end
	if n == 0 then return sendNext() end
	b.sent = b.sent + n
	b.mails = b.mails + 1
	b.waiting = true
	if SetSendMailCOD then pcall(SetSendMailCOD, 0) end
	if SetSendMailMoney then pcall(SetSendMailMoney, 0) end
	SendMail(b.to, b.label, "")
end

function Send.All(group, to)
	if batch then return end
	if not to or to == "" then
		ns.Print("type a recipient first")
		return
	end
	local stacks = {}
	for i, s in ipairs(group.stacks) do stacks[i] = s end
	batch = { stacks = stacks, label = group.label, to = to, sent = 0, mails = 0 }
	sendNext()
end

local function allMenu(anchor)
	local to = target()
	local entries = { { text = to ~= "" and ("Send to " .. to) or "Type a recipient first", title = true } }
	for _, g in ipairs(Send.Groups()) do
		entries[#entries + 1] = {
			text = g.label .. "  (" .. #g.stacks .. ")",
			func = function()
				if to == "" then
					ns.Print("type a recipient first")
					return
				end
				UI.Confirm("Send " .. #g.stacks .. " stacks of " .. g.label .. " to " .. to .. "?", function() Send.All(g, to) end)
			end,
		}
	end
	if #entries == 1 then
		entries[#entries + 1] = { text = "Nothing in your bags to send in bulk", title = true }
	end
	UI.Menu(anchor, entries)
end
Send.AllMenu = allMenu

function Send.Quick(bag, slot)
	if not ns.db.quick or not ns.Open() or batch then return false end
	if not ClickSendMailItemButton then return false end
	local it = slotInfo(bag, slot)
	if not it or it.bound or it.locked then return false end
	local to = ns.chardb.lastTo
	if MailFrameTab_OnClick and (not SendMailFrame or not SendMailFrame:IsShown()) then
		pcall(MailFrameTab_OnClick, nil, 2)
	end
	if ns.Window and ns.Window.Active() then ns.Window.SetTab("send") end
	local already = 0
	if GetSendMailItem then
		for i = 1, ATTACHMENTS_MAX_SEND or 12 do
			if GetSendMailItem(i) then already = already + 1 end
		end
	end
	pickup(bag, slot)
	ClickSendMailItemButton()
	if already > 0 then
		ns.Print("attached to the mail you are writing")
		return true
	end
	if not to or to == "" or not SendMail then
		ns.Print("attached, no previous recipient to send to")
		return true
	end
	if SetSendMailCOD then pcall(SetSendMailCOD, 0) end
	if SetSendMailMoney then pcall(SetSendMailMoney, 0) end
	local name = it.link and it.link:match("%[(.-)%]") or "Item"
	batch = { stacks = {}, label = name, to = to, sent = 1, mails = 1, waiting = true, quiet = true }
	SendMail(to, name, "")
	ns.Print("sent " .. (it.link or name) .. " to " .. to)
	return true
end

local function build()
	if controls or not SendMailFrame then return end
	controls = {}
	local box = nameBox()
	controls.to = UI.Button(SendMailFrame, "To...", function(self) recipientMenu(self) end)
	if box then
		controls.to:SetPoint("LEFT", box, "RIGHT", 6, 0)
	else
		controls.to:SetPoint("TOPRIGHT", SendMailFrame, "TOPRIGHT", -60, -32)
	end
	controls.all = UI.Button(SendMailFrame, "Send all...", function(self) allMenu(self) end)
	controls.all:SetPoint("BOTTOMLEFT", SendMailFrame, "BOTTOMLEFT", 20, 96)
	if box and box.HookScript then
		box:HookScript("OnTextChanged", function(self, user)
			if completing or not user or not ns.db.autocomplete then return end
			local text = self:GetText() or ""
			if controls.typed and #text < #controls.typed then
				controls.typed = text
				return
			end
			controls.typed = text
			local full = Send.Complete(text)
			if full then
				completing = true
				self:SetText(full)
				if self.HighlightText then self:HighlightText(#text, -1) end
				completing = false
			end
		end)
	end
	if SendMailFrame.HookScript then
		SendMailFrame:HookScript("OnShow", function() Send.Shown() end)
	end
	ns.sendControls = controls
end

function Send.Busy()
	return batch ~= nil
end

function Send.Shown()
	local subject = subjectBox()
	if ns.db.keepSubject and subject and (subject:GetText() or "") == "" and ns.db.lastSubject ~= "" then
		subject:SetText(ns.db.lastSubject)
	end
end

ns:On("MAIL_SHOW", build)
ns:On("MAIL_SEND_SUCCESS", function()
	if not batch then return end
	batch.waiting = false
	if batch.quiet then
		batch = nil
		return
	end
	ns.After(ns.db.delay or 0.3, sendNext)
end)
ns:On("MAIL_FAILED", function()
	if not batch then return end
	local b = batch
	batch = nil
	if ClearCursor then ClearCursor() end
	if not b.quiet then ns.Print("sending stopped, the mail failed") end
end)
ns:On("MAIL_CLOSED", function()
	batch = nil
end)

ns:Listen("LOGIN", function()
	if not hooksecurefunc then return end
	if SendMail then
		pcall(hooksecurefunc, "SendMail", function(name, subject) Send.Remember(name, subject) end)
	end
	if HandleModifiedItemClick then
		pcall(hooksecurefunc, "HandleModifiedItemClick", function(_, location)
			if not (IsAltKeyDown and IsAltKeyDown()) or not ns.Open() then return end
			if type(location) ~= "table" or not location.GetBagAndSlot then return end
			local bag, slot = location:GetBagAndSlot()
			if type(bag) == "number" and type(slot) == "number" then Send.Quick(bag, slot) end
		end)
	end
	if ContainerFrameItemButton_OnModifiedClick then
		pcall(hooksecurefunc, "ContainerFrameItemButton_OnModifiedClick", function(self)
			if not (IsAltKeyDown and IsAltKeyDown()) or not ns.Open() then return end
			if HandleModifiedItemClick then return end
			local parent = self and self.GetParent and self:GetParent()
			local bag = parent and parent.GetID and parent:GetID()
			local slot = self and self.GetID and self:GetID()
			if type(bag) == "number" and type(slot) == "number" then Send.Quick(bag, slot) end
		end)
	end
end)
