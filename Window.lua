local _, ns = ...
local UI = ns.UI
local C = UI.colors
local Inbox = ns.Inbox
local Send = ns.Send

local Window = {}
ns.Window = Window

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local LETTER = "Interface\\Icons\\INV_Letter_15"
local URGENT = { 1, 0.4, 0.3 }
local QUALITY = {
	[0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 },
	[3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 },
}

local frame
local state = { tab = "inbox", selected = nil, key = nil, cod = false, typed = "" }
local closing = false
local setting = false

local function maxReceive()
	return ATTACHMENTS_MAX_RECEIVE or 16
end

local function maxSend()
	return ATTACHMENTS_MAX_SEND or 12
end

local function trim(s)
	return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function keyOf(h)
	return tostring(h.sender) .. "\031" .. tostring(h.subject)
end

function Window.Active()
	return frame ~= nil and frame:IsShown()
end

function Window.NameBox()
	if Window.Active() and state.tab == "send" then return frame.name.box end
	return nil
end

function Window.SubjectBox()
	if Window.Active() and state.tab == "send" then return frame.subject.box end
	return nil
end

local function hideDefault(hide)
	if not MailFrame then return end
	if hide then
		pcall(MailFrame.SetAlpha, MailFrame, 0)
		pcall(MailFrame.EnableMouse, MailFrame, false)
		pcall(MailFrame.SetClampedToScreen, MailFrame, false)
		pcall(MailFrame.ClearAllPoints, MailFrame)
		pcall(MailFrame.SetPoint, MailFrame, "TOPRIGHT", UIParent, "TOPLEFT", -3000, 0)
		state.hidden = true
	elseif state.hidden then
		state.hidden = false
		pcall(MailFrame.SetAlpha, MailFrame, 1)
		pcall(MailFrame.EnableMouse, MailFrame, true)
		pcall(MailFrame.ClearAllPoints, MailFrame)
		pcall(MailFrame.SetPoint, MailFrame, "TOPLEFT", UIParent, "TOPLEFT", 16, -116)
		if UpdateUIPanelPositions then pcall(UpdateUIPanelPositions, MailFrame) end
	end
end

local function releaseFocus()
	for _, name in ipairs({ "SendMailNameEditBox", "SendMailSubjectEditBox", "SendMailBodyEditBox" }) do
		local box = _G[name]
		if type(box) == "table" and box.HasFocus and box.ClearFocus and box:HasFocus() then box:ClearFocus() end
	end
end

local function attachments(index)
	local out = {}
	if not GetInboxItem then return out end
	for a = 1, maxReceive() do
		local name, id, texture, count, quality = GetInboxItem(index, a)
		if name then
			out[#out + 1] = { slot = a, name = name, id = id, texture = texture, count = count or 1, quality = quality }
		end
	end
	return out
end

local function iconButton(parent, size)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size, size)
	UI.Fill(b, { 0.03, 0.03, 0.04, 1 })
	b.edges = UI.Border(b)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 1, -1)
	b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b.count = UI.Text(b, "NumberFontNormalSmall", "RIGHT")
	b.count:SetPoint("BOTTOMRIGHT", -2, 2)
	b.hl = UI.Fill(b, C.hover, "HIGHLIGHT")
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	function b:SetItem(texture, count, quality)
		if texture then
			self.icon:SetTexture(texture)
			self.icon:Show()
		else
			self.icon:Hide()
		end
		self.count:SetText((count and count > 1) and count or "")
		local c = texture and QUALITY[quality or 1] or C.line
		for _, e in ipairs(self.edges) do e:SetColorTexture(c[1], c[2], c[3], 1) end
	end
	return b
end

local function selectedHeader()
	if not state.selected then return nil end
	local h = Inbox.Header(state.selected)
	if not h or keyOf(h) ~= state.key then
		state.selected = nil
		state.key = nil
		return nil
	end
	return h
end

local function takeItem(index, slot)
	local h = Inbox.Header(index)
	if not h or not TakeInboxItem then return end
	if Inbox.FreeSlots() < 1 then
		ns.Print("bags are full")
		return
	end
	if h.cod > 0 then
		UI.Confirm("Pay " .. ACore.Money(h.cod) .. " cash on delivery to " .. (h.sender or "the sender") .. "?", function()
			if ns.Open() then TakeInboxItem(index, slot) end
		end)
	else
		TakeInboxItem(index, slot)
	end
end

local function takeAll(index)
	local h = Inbox.Header(index)
	if not h then return end
	if h.cod > 0 then
		local list = attachments(index)
		if list[1] then takeItem(index, list[1].slot) end
		return
	end
	Inbox.Quick(index, "take")
end

local function deleteMail(index)
	local h = Inbox.Header(index)
	if not h or not DeleteInboxItem then return end
	local function go()
		if not ns.Open() then return end
		DeleteInboxItem(index)
		state.selected = nil
		state.key = nil
		Window.Refresh()
	end
	if h.items > 0 or h.money > 0 then
		UI.Confirm("Delete this mail? It still holds " .. (h.items > 0 and "items" or "money") .. ".", go)
	else
		go()
	end
end

local function reply(h)
	Window.SetTab("send")
	setting = true
	frame.name.box:SetText(h.sender or "")
	local subject = h.subject or ""
	if subject:sub(1, 3):upper() ~= "RE:" then subject = "RE: " .. subject end
	frame.subject.box:SetText(subject:sub(1, 60))
	setting = false
	state.typed = h.sender or ""
end

local function createMailRow(list)
	local row = CreateFrame("Button", nil, list)
	row.sel = UI.Fill(row, C.select)
	row.hl = UI.Fill(row, C.hover, "HIGHLIGHT")
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(26, 26)
	row.icon:SetPoint("LEFT", 6, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.count = UI.Text(row, "NumberFontNormalSmall", "RIGHT")
	row.count:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 1, -1)
	row.days = UI.Text(row, "GameFontDisableSmall", "RIGHT", C.dim)
	row.days:SetPoint("TOPRIGHT", -8, -5)
	row.money = UI.Text(row, "GameFontHighlightSmall", "RIGHT")
	row.money:SetPoint("BOTTOMRIGHT", -8, 5)
	row.sender = UI.Text(row, "GameFontHighlight")
	row.sender:SetPoint("TOPLEFT", 40, -4)
	row.sender:SetPoint("RIGHT", row.days, "LEFT", -6, 0)
	row.subject = UI.Text(row, "GameFontDisableSmall", "LEFT", C.dim)
	row.subject:SetPoint("BOTTOMLEFT", 40, 5)
	row.subject:SetPoint("RIGHT", row.money, "LEFT", -6, 0)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetScript("OnClick", function(self)
		local d = self.data
		if not d then return end
		if IsShiftKeyDown and IsShiftKeyDown() then
			Inbox.Quick(d.index, "take")
		elseif IsControlKeyDown and IsControlKeyDown() then
			if Inbox.Quick(d.index, "return") then
				state.selected = nil
				state.key = nil
			end
		else
			state.selected = d.index
			state.key = keyOf(d.h)
			state.scroll = 0
		end
		Window.Refresh()
	end)
	row:SetScript("OnEnter", function(self)
		list.hovered = self
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(self.data and self.data.h.subject or "", 1, 1, 1)
		GameTooltip:AddLine("Click: read   Shift-click: take everything   Ctrl-click: return", 0.58, 0.6, 0.65)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return row
end

local function updateMailRow(row, d)
	local h = d.h
	row.icon:SetTexture(h.icon or LETTER)
	row.count:SetText(h.items > 1 and h.items or "")
	row.sender:SetText(h.sender or "Unknown")
	row.subject:SetText(h.subject or "")
	if h.read then
		row.sender:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
	elseif h.gm then
		row.sender:SetTextColor(0.35, 0.75, 1)
	else
		row.sender:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
	end
	if h.cod > 0 then
		row.money:SetText("COD " .. ACore.Money(h.cod))
	elseif h.money > 0 then
		row.money:SetText(ACore.Money(h.money))
	else
		row.money:SetText("")
	end
	row.days:SetText(Inbox.Expiry(h.days))
	if ns.db.tint and h.days and h.days < 3 then
		row.days:SetTextColor(URGENT[1], URGENT[2], URGENT[3])
	else
		row.days:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
	end
	row.sel:SetShown(state.selected == d.index)
end

local function refreshDetail()
	local d = frame.detail
	local h = selectedHeader()
	if not h then
		d.from:SetText("")
		d.title:SetText("Pick a mail on the left.")
		d.title:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
		d.body:SetText("")
		d.money:SetText("")
		for _, b in ipairs(d.items) do b:Hide() end
		for _, b in ipairs(d.buttons) do b:Hide() end
		return
	end
	local index = state.selected
	d.title:SetTextColor(C.text[1], C.text[2], C.text[3])
	d.title:SetText(h.subject or "")
	d.from:SetText("From " .. (h.sender or "Unknown") .. (h.days and ("   expires in " .. Inbox.Expiry(h.days)) or ""))
	local body = ""
	if GetInboxText then
		local ok, text = pcall(GetInboxText, index)
		if ok and type(text) == "string" then body = text end
	end
	d.body:SetText(body)
	d.body:ClearAllPoints()
	d.body:SetPoint("TOPLEFT", d.clip, "TOPLEFT", 0, state.scroll or 0)
	d.body:SetPoint("RIGHT", d.clip, "RIGHT", 0, 0)
	local list = attachments(index)
	for i, b in ipairs(d.items) do
		local a = list[i]
		b.entry = a
		b.mail = index
		if a then
			b:SetItem(a.texture or QUESTION, a.count, a.quality)
			b:Show()
		else
			b:Hide()
		end
	end
	if h.cod > 0 then
		d.money:SetText("Cash on delivery: " .. ACore.Money(h.cod))
	elseif h.money > 0 then
		d.money:SetText("Money: " .. ACore.Money(h.money))
	else
		d.money:SetText("")
	end
	local canDelete = true
	if InboxItemCanDelete then
		local ok, v = pcall(InboxItemCanDelete, index)
		canDelete = ok and v and true or false
	end
	d.take:SetShown(h.money > 0 or #list > 0)
	d.take:SetLabel(h.cod > 0 and "Pay and take" or "Take all")
	d.reply:SetShown(h.canReply and true or false)
	d.back:SetShown(not canDelete and not h.returned)
	d.delete:Show()
end

local function refreshInbox()
	local rows = {}
	local n = GetInboxNumItems and GetInboxNumItems() or 0
	if type(n) ~= "number" then n = 0 end
	for i = 1, n do
		local h = Inbox.Header(i)
		if h then rows[#rows + 1] = { index = i, h = h } end
	end
	selectedHeader()
	frame.mailList:SetData(rows, true)
	frame.empty:SetShown(#rows == 0)
	local text, urgent = Inbox.SummaryText()
	frame.summary:SetText(text)
	local c = urgent and URGENT or C.dim
	frame.summary:SetTextColor(c[1], c[2], c[3])
	local running = Inbox.Running()
	frame.openAll:SetLabel(running and "Stop" or "Open all")
	frame.goldOnly:SetShown(not running)
	refreshDetail()
end

local function amount()
	local g = tonumber(frame.gold.box:GetText()) or 0
	local s = tonumber(frame.silver.box:GetText()) or 0
	local c = tonumber(frame.copper.box:GetText()) or 0
	return math.max(0, math.floor(g) * 10000 + math.floor(s) * 100 + math.floor(c))
end

local function sendItems()
	local out = {}
	if not GetSendMailItem then return out end
	for i = 1, maxSend() do
		local name, id, texture, count, quality = GetSendMailItem(i)
		if name then out[i] = { name = name, id = id, texture = texture, count = count or 1, quality = quality } end
	end
	return out
end

local function refreshSend()
	local items = sendItems()
	local n = 0
	for i, b in ipairs(frame.slots) do
		local it = items[i]
		b.entry = it
		if it then
			n = n + 1
			b:SetItem(it.texture or QUESTION, it.count, it.quality)
		else
			b:SetItem(nil)
		end
	end
	local price = GetSendMailPrice and GetSendMailPrice() or 0
	if type(price) ~= "number" then price = 0 end
	frame.postage:SetText("Postage: " .. ACore.Money(price) .. "   " .. n .. " / " .. maxSend() .. " attached")
	frame.mode:SetLabel(state.cod and "Cash on delivery" or "Send money")
	frame.mode:SetActive(state.cod)
	state.attached = n
	state.first = nil
	for i = 1, maxSend() do
		if items[i] then
			state.first = items[i].name
			break
		end
	end
end

local function clearSend(keepName)
	setting = true
	if not keepName then
		frame.name.box:SetText("")
		state.typed = ""
	end
	frame.subject.box:SetText(ns.db.keepSubject and ns.db.lastSubject or "")
	frame.bodyBox:SetText("")
	frame.gold.box:SetText("")
	frame.silver.box:SetText("")
	frame.copper.box:SetText("")
	setting = false
	state.cod = false
end

local function doSend()
	if not ns.Open() or not SendMail then return false end
	if Send.Busy() then
		ns.Print("still sending, wait a moment")
		return false
	end
	local to = trim(frame.name.box:GetText())
	if to == "" then
		ns.Print("type a recipient first")
		return false
	end
	local subject = trim(frame.subject.box:GetText())
	if subject == "" then subject = state.first or "" end
	if subject == "" then
		ns.Print("add a subject")
		return false
	end
	local copper = amount()
	if state.cod and copper > 0 and (state.attached or 0) == 0 then
		ns.Print("cash on delivery needs an attached item")
		return false
	end
	local price = GetSendMailPrice and GetSendMailPrice() or 0
	if type(price) ~= "number" then price = 0 end
	local have = GetMoney and GetMoney()
	if type(have) == "number" and have < price + (state.cod and 0 or copper) then
		ns.Print("not enough money")
		return false
	end
	if SetSendMailCOD then pcall(SetSendMailCOD, 0) end
	if SetSendMailMoney then pcall(SetSendMailMoney, 0) end
	if copper > 0 then
		if state.cod then
			if SetSendMailCOD then pcall(SetSendMailCOD, copper) end
		elseif SetSendMailMoney then
			pcall(SetSendMailMoney, copper)
		end
	end
	SendMail(to, subject, frame.bodyBox:GetText() or "")
	return true
end

local function slotClick(self, button)
	if not ClickSendMailItemButton then return end
	if button == "RightButton" then
		ClickSendMailItemButton(self.index, true)
	else
		ClickSendMailItemButton(self.index)
	end
	refreshSend()
end

local function nameChanged(text)
	if setting or not ns.db.autocomplete then
		state.typed = text
		return
	end
	if #text < #(state.typed or "") then
		state.typed = text
		return
	end
	state.typed = text
	local full = Send.Complete(text)
	if full then
		local box = frame.name.box
		setting = true
		box:SetText(full)
		if box.HighlightText then box:HighlightText(#text, -1) end
		setting = false
	end
end

local function label(parent, text, x, y)
	local l = UI.Text(parent, "GameFontDisableSmall", "LEFT", C.dim)
	l:SetPoint("TOPLEFT", x, y)
	l:SetText(text)
	return l
end

local function buildInbox(body)
	local pane = CreateFrame("Frame", nil, body)
	pane:SetAllPoints(body)
	frame.inboxPane = pane

	local tools = CreateFrame("Frame", nil, pane)
	tools:SetPoint("TOPLEFT")
	tools:SetPoint("TOPRIGHT")
	tools:SetHeight(34)
	UI.Fill(tools, { 0.075, 0.08, 0.1, 1 })
	frame.openAll = UI.Button(tools, "Open all", function() Inbox.OpenAll(false) end)
	frame.openAll:SetPoint("LEFT", 8, 0)
	frame.goldOnly = UI.Button(tools, "Gold only", function() Inbox.OpenAll(true) end)
	frame.goldOnly:SetPoint("LEFT", frame.openAll, "RIGHT", 6, 0)
	frame.summary = UI.Text(tools, "GameFontDisableSmall", "LEFT", C.dim)
	frame.summary:SetPoint("LEFT", frame.goldOnly, "RIGHT", 12, 0)
	frame.summary:SetPoint("RIGHT", -10, 0)

	local left = CreateFrame("Frame", nil, pane)
	left:SetPoint("TOPLEFT", 0, -34)
	left:SetPoint("BOTTOMLEFT")
	left:SetWidth(380)
	UI.Fill(left, C.panel)
	local list = UI.List(left, 38, createMailRow, updateMailRow)
	list:SetPoint("TOPLEFT", 0, -2)
	list:SetPoint("BOTTOMRIGHT", 0, 2)
	frame.mailList = list
	frame.empty = UI.Text(left, "GameFontDisable", "CENTER", C.dim)
	frame.empty:SetPoint("CENTER")
	frame.empty:SetText("No mail.")

	local d = CreateFrame("Frame", nil, pane)
	d:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
	d:SetPoint("BOTTOMRIGHT")
	frame.detail = d
	d.title = UI.Text(d, "GameFontNormal", "LEFT", C.text)
	d.title:SetPoint("TOPLEFT", 12, -10)
	d.title:SetPoint("RIGHT", -12, 0)
	d.from = UI.Text(d, "GameFontDisableSmall", "LEFT", C.dim)
	d.from:SetPoint("TOPLEFT", 12, -28)
	d.from:SetPoint("RIGHT", -12, 0)

	d.clip = CreateFrame("Frame", nil, d)
	d.clip:SetPoint("TOPLEFT", 12, -48)
	d.clip:SetPoint("BOTTOMRIGHT", -12, 150)
	if d.clip.SetClipsChildren then d.clip:SetClipsChildren(true) end
	d.body = UI.Text(d.clip, "GameFontHighlightSmall", "LEFT", C.text)
	d.body:SetWordWrap(true)
	d.body:SetJustifyV("TOP")
	d.body:SetPoint("TOPLEFT")
	d.body:SetPoint("RIGHT")
	d.clip:EnableMouseWheel(true)
	d.clip:SetScript("OnMouseWheel", function(_, delta)
		local max = math.max(0, (d.body:GetStringHeight() or 0) - (d.clip:GetHeight() or 0))
		state.scroll = math.min(max, math.max(0, (state.scroll or 0) - delta * 30))
		refreshDetail()
	end)

	local rule = UI.Tex(d, "ARTWORK", C.line)
	rule:SetPoint("BOTTOMLEFT", 12, 144)
	rule:SetPoint("BOTTOMRIGHT", -12, 144)
	rule:SetHeight(1)

	d.items = {}
	for i = 1, maxReceive() do
		local b = iconButton(d, 36)
		local col, line = (i - 1) % 8, math.floor((i - 1) / 8)
		b:SetPoint("BOTTOMLEFT", 12 + col * 42, 98 - line * 42)
		b:SetScript("OnClick", function(self)
			if self.entry then takeItem(self.mail, self.entry.slot) end
		end)
		b:SetScript("OnEnter", function(self)
			if not self.entry then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			local ok = GameTooltip.SetInboxItem and pcall(GameTooltip.SetInboxItem, GameTooltip, self.mail, self.entry.slot)
			if not ok then GameTooltip:AddLine(self.entry.name, 1, 1, 1) end
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		d.items[i] = b
	end

	d.money = UI.Text(d, "GameFontHighlightSmall", "LEFT", C.text)
	d.money:SetPoint("BOTTOMLEFT", 12, 36)

	d.take = UI.Button(d, "Take all", function()
		if state.selected then takeAll(state.selected) end
	end)
	d.take:SetPoint("BOTTOMLEFT", 12, 8)
	d.reply = UI.Button(d, "Reply", function()
		local h = selectedHeader()
		if h then reply(h) end
	end)
	d.reply:SetPoint("LEFT", d.take, "RIGHT", 6, 0)
	d.back = UI.Button(d, "Return", function()
		if state.selected and Inbox.Quick(state.selected, "return") then
			state.selected = nil
			state.key = nil
			Window.Refresh()
		end
	end)
	d.back:SetPoint("LEFT", d.reply, "RIGHT", 6, 0)
	d.delete = UI.Button(d, "Delete", function()
		if state.selected then deleteMail(state.selected) end
	end)
	d.delete:SetPoint("BOTTOMRIGHT", -12, 8)
	d.buttons = { d.take, d.reply, d.back, d.delete }
end

local function buildSend(body)
	local pane = CreateFrame("Frame", nil, body)
	pane:SetAllPoints(body)
	frame.sendPane = pane

	label(pane, "To", 16, -14)
	frame.name = UI.EditBox(pane, "Recipient", nameChanged)
	frame.name:SetPoint("TOPLEFT", 16, -30)
	frame.name:SetWidth(260)
	frame.name.box:SetScript("OnTabPressed", function() frame.subject.box:SetFocus() end)
	frame.name.box:SetScript("OnEnterPressed", function() frame.subject.box:SetFocus() end)
	frame.to = UI.Button(pane, "To...", function(self) Send.RecipientMenu(self) end)
	frame.to:SetPoint("LEFT", frame.name, "RIGHT", 6, 0)

	label(pane, "Subject", 16, -62)
	frame.subject = UI.EditBox(pane, "Subject")
	frame.subject:SetPoint("TOPLEFT", 16, -78)
	frame.subject:SetWidth(420)
	frame.subject.box:SetMaxLetters(64)
	frame.subject.box:SetScript("OnTabPressed", function() frame.bodyBox:SetFocus() end)
	frame.subject.box:SetScript("OnEnterPressed", function() frame.bodyBox:SetFocus() end)

	label(pane, "Message", 16, -110)
	local holder = CreateFrame("Frame", nil, pane)
	holder:SetPoint("TOPLEFT", 16, -126)
	holder:SetSize(420, 190)
	UI.Fill(holder, { 0.03, 0.03, 0.04, 1 })
	UI.Border(holder)
	if holder.SetClipsChildren then holder:SetClipsChildren(true) end
	local box = CreateFrame("EditBox", nil, holder)
	box:SetPoint("TOPLEFT", 8, -6)
	box:SetPoint("BOTTOMRIGHT", -8, 6)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetFontObject("GameFontHighlightSmall")
	box:SetMaxLetters(500)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:SetScript("OnTabPressed", function() frame.name.box:SetFocus() end)
	holder:EnableMouse(true)
	holder:SetScript("OnMouseDown", function() box:SetFocus() end)
	frame.bodyBox = box

	label(pane, "Money", 16, -328)
	local function coin(text, width, anchor)
		local e = UI.EditBox(pane, text)
		e:SetWidth(width)
		e.box:SetMaxLetters(text == "gold" and 7 or 2)
		if e.box.SetNumeric then e.box:SetNumeric(true) end
		if anchor then
			e:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
		else
			e:SetPoint("TOPLEFT", 16, -344)
		end
		return e
	end
	frame.gold = coin("gold", 110)
	frame.silver = coin("silver", 70, frame.gold)
	frame.copper = coin("copper", 70, frame.silver)
	frame.mode = UI.Button(pane, "Send money", function()
		state.cod = not state.cod
		refreshSend()
	end)
	frame.mode:SetPoint("LEFT", frame.copper, "RIGHT", 10, 0)

	label(pane, "Attachments  (drag items here or right-click them in your bags)", 460, -14)
	frame.slots = {}
	for i = 1, maxSend() do
		local b = iconButton(pane, 40)
		b.index = i
		local col, line = (i - 1) % 6, math.floor((i - 1) / 6)
		b:SetPoint("TOPLEFT", 460 + col * 46, -32 - line * 46)
		b:RegisterForDrag("LeftButton")
		b:SetScript("OnClick", slotClick)
		b:SetScript("OnReceiveDrag", function(self) slotClick(self, "LeftButton") end)
		b:SetScript("OnDragStart", function(self) slotClick(self, "LeftButton") end)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			local ok = self.entry and GameTooltip.SetSendMailItem and pcall(GameTooltip.SetSendMailItem, GameTooltip, self.index)
			if not ok then
				GameTooltip:AddLine(self.entry and self.entry.name or "Empty slot", 1, 1, 1)
			end
			if self.entry then GameTooltip:AddLine("Right-click to remove", 0.58, 0.6, 0.65) end
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		frame.slots[i] = b
	end

	local lines = math.ceil(maxSend() / 6)
	frame.postage = UI.Text(pane, "GameFontHighlightSmall", "LEFT", C.text)
	frame.postage:SetPoint("TOPLEFT", 460, -40 - lines * 46)

	frame.all = UI.Button(pane, "Send all...", function(self) Send.AllMenu(self) end)
	frame.all:SetPoint("TOPLEFT", 460, -68 - lines * 46)

	frame.send = UI.Button(pane, "Send", function() doSend() end)
	frame.send:SetPoint("BOTTOMRIGHT", -16, 14)
	frame.send:SetWidth(90)
	frame.clear = UI.Button(pane, "Clear", function()
		if ClickSendMailItemButton then
			for i = 1, maxSend() do
				if frame.slots[i].entry then ClickSendMailItemButton(i, true) end
			end
		end
		clearSend()
		refreshSend()
	end)
	frame.clear:SetPoint("RIGHT", frame.send, "LEFT", -6, 0)
end

local function build()
	ns.db.window.default = ns.db.window.default or { "LEFT", "LEFT", 60, 40 }
	frame = UI.Window("AMailFrame", "AMail", 760, 500, ns.db.window)
	local bar = frame.bar
	frame.tabInbox = UI.Button(bar, "Inbox", function() Window.SetTab("inbox") end)
	frame.tabInbox:SetPoint("LEFT", 90, 0)
	frame.tabSend = UI.Button(bar, "Send", function() Window.SetTab("send") end)
	frame.tabSend:SetPoint("LEFT", frame.tabInbox, "RIGHT", 6, 0)
	local options = UI.Button(bar, "Options", function(self) UI.Menu(self, ns.Options()) end)
	options:SetPoint("RIGHT", frame.close, "LEFT", -6, 0)
	frame.options = options

	buildInbox(frame.body)
	buildSend(frame.body)

	frame:SetScript("OnHide", function()
		if closing then return end
		if ns.Open() and CloseMail then
			pcall(CloseMail)
			ns.After(1, function()
				if not Window.Active() then hideDefault(false) end
			end)
		else
			hideDefault(false)
		end
	end)
	local elapsed = 0
	frame:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + (dt or 0)
		if elapsed < 0.5 then return end
		elapsed = 0
		if ns.db.reskin and ns.Open() then hideDefault(true) end
	end)
end

function Window.SetTab(tab)
	if not frame then return end
	state.tab = tab
	frame.inboxPane:SetShown(tab == "inbox")
	frame.sendPane:SetShown(tab == "send")
	frame.tabInbox:SetActive(tab == "inbox")
	frame.tabSend:SetActive(tab == "send")
	if MailFrameTab_OnClick then pcall(MailFrameTab_OnClick, nil, tab == "send" and 2 or 1) end
	releaseFocus()
	if tab == "send" then
		if ns.db.keepSubject and (frame.subject.box:GetText() or "") == "" and ns.db.lastSubject ~= "" then
			setting = true
			frame.subject.box:SetText(ns.db.lastSubject)
			setting = false
		end
	end
	Window.Refresh()
end

function Window.Refresh()
	if not Window.Active() then return end
	if state.tab == "inbox" then
		refreshInbox()
	else
		refreshSend()
	end
end

function Window.Open()
	if not ns.db.reskin then return end
	if not frame then build() end
	closing = false
	state.selected = nil
	state.key = nil
	frame:Show()
	hideDefault(true)
	Window.SetTab("inbox")
end

function Window.Close()
	if not frame then return end
	closing = true
	frame:Hide()
	closing = false
	hideDefault(false)
end

function Window.Frame()
	return frame
end

Window.Send = doSend

ns:On("MAIL_SHOW", function() Window.Open() end)
ns:On("MAIL_CLOSED", function() Window.Close() end)
ns:On("MAIL_SEND_INFO_UPDATE", function()
	if Window.Active() and state.tab == "send" then refreshSend() end
end)
ns:On("MAIL_SEND_SUCCESS", function()
	if not Window.Active() then return end
	if not Send.Busy() then clearSend() end
	ns.After(0, function()
		if Window.Active() then releaseFocus() end
		if Window.Active() and state.tab == "send" then refreshSend() end
	end)
end)
ns:On("MAIL_INBOX_UPDATE", function()
	ns.Debounce("window", 0.1, Window.Refresh)
end)
ns:Listen("INBOX", function() Window.Refresh() end)
ns:Listen("OPTIONS", function() Window.Refresh() end)
ns:Listen("RESKIN", function()
	if ns.db.reskin then
		if ns.Open() then Window.Open() end
	else
		Window.Close()
	end
end)
