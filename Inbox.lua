local _, ns = ...
local UI = ns.UI
local C = UI.colors

local Inbox = {}
ns.Inbox = Inbox

local run
local controls

local function numItems()
	if not GetInboxNumItems then return 0 end
	local n = GetInboxNumItems()
	if type(n) ~= "number" then return 0 end
	return n
end

function Inbox.Header(i)
	if not GetInboxHeaderInfo then return nil end
	local package, stationery, sender, subject, money, cod, daysLeft, items, wasRead, wasReturned, _, canReply, isGM = GetInboxHeaderInfo(i)
	if money == nil and subject == nil and sender == nil then return nil end
	return {
		sender = sender, subject = subject, money = type(money) == "number" and money or 0,
		cod = type(cod) == "number" and cod or 0, days = type(daysLeft) == "number" and daysLeft or nil,
		items = type(items) == "number" and items or 0, returned = wasReturned, canReply = canReply, gm = isGM,
		icon = package or stationery, read = wasRead and true or false,
	}
end

local function freeSlots()
	local free = 0
	for bag = 0, 4 do
		local n
		if C_Container and C_Container.GetContainerNumFreeSlots then
			n = C_Container.GetContainerNumFreeSlots(bag)
		elseif GetContainerNumFreeSlots then
			n = GetContainerNumFreeSlots(bag)
		end
		if type(n) == "number" then free = free + n end
	end
	return free
end

function Inbox.Summary()
	local gold, items, soonest, count = 0, 0, nil, numItems()
	for i = 1, count do
		local h = Inbox.Header(i)
		if h then
			gold = gold + h.money
			items = items + h.items
			if h.days and (not soonest or h.days < soonest) then soonest = h.days end
		end
	end
	return count, gold, items, soonest
end

local function expiry(days)
	if not days then return "" end
	if days < 1 then return math.max(1, math.floor(days * 24 + 0.5)) .. " h" end
	return math.floor(days) .. " d"
end

Inbox.FreeSlots = freeSlots

function Inbox.SummaryText()
	local count, gold, items, soonest = Inbox.Summary()
	local parts = { count .. (count == 1 and " mail" or " mails") }
	if gold > 0 then parts[#parts + 1] = ACore.Money(gold) end
	if items > 0 then parts[#parts + 1] = items .. (items == 1 and " item" or " items") end
	if soonest then parts[#parts + 1] = "first expires in " .. expiry(soonest) end
	if run then parts = { "opening " .. run.done .. " / " .. run.total, ACore.Money(run.gold) } end
	return table.concat(parts, "   "), (soonest and soonest < 3 and not run) and true or false
end

Inbox.Expiry = expiry

function Inbox.Refresh()
	if controls then
		local text, urgent = Inbox.SummaryText()
		controls.summary:SetText(text)
		if urgent then
			controls.summary:SetTextColor(1, 0.4, 0.3)
		else
			controls.summary:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
		end
		controls.open:SetLabel(run and "Stop" or "Open all")
		controls.gold:SetShown(not run)
		Inbox.Tint()
	end
	ns:Fire("INBOX")
end

function Inbox.Tint()
	if not ns.db.tint or not InboxFrame then return end
	local page = InboxFrame.pageNum
	if type(page) ~= "number" then page = 1 end
	local per = INBOXITEMS_TO_DISPLAY or 7
	for slot = 1, per do
		local subject = _G["MailItem" .. slot .. "Subject"]
		local h = Inbox.Header((page - 1) * per + slot)
		if subject and subject.SetTextColor and h and h.days and h.days < 3 then
			subject:SetTextColor(1, 0.4, 0.3)
		end
	end
end

function Inbox.Stop(why)
	if not run then return end
	local r = run
	run = nil
	local parts = { "opened " .. r.done .. (r.done == 1 and " mail" or " mails") }
	if r.gold > 0 then parts[#parts + 1] = "collected " .. ACore.Money(r.gold) end
	if r.sales > 0 then parts[#parts + 1] = ACore.Money(r.sales) .. " from auctions" end
	if r.skipped > 0 then parts[#parts + 1] = r.skipped .. " skipped" end
	if why then parts[#parts + 1] = why end
	ns.Print(table.concat(parts, ", "))
	Inbox.Refresh()
end

local function step()
	if not run then return end
	if not ns.Open() then return Inbox.Stop("mailbox closed") end
	local r = run
	while r.index >= 1 do
		local h = Inbox.Header(r.index)
		local wantMoney = h and h.money > 0
		local wantItems = h and h.items > 0 and not r.goldOnly
		local skip = not h or (h.cod > 0 and ns.db.skipCod) or (h.gm and ns.db.skipGm)
		if h and skip and (h.money > 0 or h.items > 0) and r.tries == 0 then r.skipped = r.skipped + 1 end
		if skip or not (wantMoney or wantItems) or r.tries >= 4 then
			if r.touched then r.done = r.done + 1 end
			r.index = r.index - 1
			r.tries = 0
			r.touched = false
		else
			r.tries = r.tries + 1
			r.touched = true
			if wantMoney and TakeInboxMoney then
				if r.tries == 1 then
					r.gold = r.gold + h.money
					if GetInboxInvoiceInfo then
						local ok, kind = pcall(GetInboxInvoiceInfo, r.index)
						if ok and kind == "seller" then r.sales = r.sales + h.money end
					end
				end
				TakeInboxMoney(r.index)
			elseif wantItems then
				if freeSlots() < 1 then return Inbox.Stop("bags are full") end
				if AutoLootMailItem then
					AutoLootMailItem(r.index)
				elseif TakeInboxItem then
					TakeInboxItem(r.index, 1)
				end
			end
			Inbox.Refresh()
			ns.After(ns.db.delay or 0.3, step)
			return
		end
	end
	Inbox.Stop()
end

function Inbox.OpenAll(goldOnly)
	if run then return Inbox.Stop("stopped") end
	if not ns.Open() then
		ns.Print("open a mailbox first")
		return
	end
	local total = 0
	for i = 1, numItems() do
		local h = Inbox.Header(i)
		if h and (h.money > 0 or (h.items > 0 and not goldOnly)) then total = total + 1 end
	end
	if total == 0 then
		ns.Print(goldOnly and "no gold to collect" or "nothing to open")
		return
	end
	run = { index = numItems(), goldOnly = goldOnly, total = total, done = 0, gold = 0, sales = 0, skipped = 0, tries = 0, touched = false }
	Inbox.Refresh()
	step()
end

function Inbox.Running()
	return run ~= nil
end

function Inbox.Click(slot)
	if not ns.Open() or not InboxFrame then return end
	local page = InboxFrame.pageNum
	if type(page) ~= "number" then page = 1 end
	local index = (page - 1) * (INBOXITEMS_TO_DISPLAY or 7) + slot
	if IsShiftKeyDown and IsShiftKeyDown() then
		Inbox.Quick(index, "take")
	elseif IsControlKeyDown and IsControlKeyDown() then
		Inbox.Quick(index, "return")
	end
end

function Inbox.Quick(index, mode)
	if not ns.Open() then return false end
	local h = Inbox.Header(index)
	if not h then return false end
	if mode == "take" then
		if h.cod > 0 then
			ns.Print("that mail is cash on delivery, open it normally")
			return false
		end
		if h.money > 0 and TakeInboxMoney then TakeInboxMoney(index) end
		if h.items > 0 then
			if freeSlots() < 1 then
				ns.Print("bags are full")
			elseif AutoLootMailItem then
				ns.After(h.money > 0 and (ns.db.delay or 0.3) or 0, function()
					if ns.Open() then AutoLootMailItem(index) end
				end)
			end
		end
		if InboxFrame and InboxFrame.openMailID then InboxFrame.openMailID = nil end
		if OpenMailFrame and OpenMailFrame.Hide then OpenMailFrame:Hide() end
		return true
	elseif mode == "return" then
		local deletable = InboxItemCanDelete and InboxItemCanDelete(index)
		if deletable or h.returned or not ReturnInboxItem then
			ns.Print("that mail cannot be returned")
			return false
		end
		ReturnInboxItem(index)
		ns.Print("returned " .. (h.subject or "mail") .. " to " .. (h.sender or "sender"))
		if OpenMailFrame and OpenMailFrame.Hide then OpenMailFrame:Hide() end
		return true
	end
	return false
end

local function build()
	if controls or not InboxFrame then return end
	controls = {}
	controls.open = UI.Button(InboxFrame, "Open all", function() Inbox.OpenAll(false) end)
	controls.open:SetPoint("TOPLEFT", InboxFrame, "TOPLEFT", 70, -32)
	controls.gold = UI.Button(InboxFrame, "Gold only", function() Inbox.OpenAll(true) end)
	controls.gold:SetPoint("LEFT", controls.open, "RIGHT", 6, 0)
	controls.options = UI.Button(InboxFrame, "...", function(self) UI.Menu(self, ns.Options()) end)
	controls.options:SetPoint("LEFT", controls.gold, "RIGHT", 6, 0)
	controls.summary = UI.Text(InboxFrame, "GameFontDisableSmall", "LEFT", C.dim)
	controls.summary:SetPoint("TOPLEFT", controls.open, "BOTTOMLEFT", 0, -4)
	for slot = 1, INBOXITEMS_TO_DISPLAY or 7 do
		local button = _G["MailItem" .. slot .. "Button"]
		if button and button.HookScript then
			button:HookScript("OnClick", function() Inbox.Click(slot) end)
			button:HookScript("OnEnter", function()
				if GameTooltip and GameTooltip:IsShown() then
					GameTooltip:AddLine("Shift-click: take everything   Ctrl-click: return", 0.58, 0.6, 0.65)
					GameTooltip:Show()
				end
			end)
		end
	end
	if hooksecurefunc and InboxFrame_Update then
		pcall(hooksecurefunc, "InboxFrame_Update", function() Inbox.Tint() end)
	end
	ns.controls = controls
end

ns:On("MAIL_SHOW", function()
	build()
	if CheckInbox then pcall(CheckInbox) end
	Inbox.Refresh()
end)
ns:On("MAIL_INBOX_UPDATE", function()
	ns.Debounce("inbox", 0.1, Inbox.Refresh)
end)
ns:On("MAIL_CLOSED", function()
	if run then Inbox.Stop("mailbox closed") end
end)
ns:On("UI_ERROR_MESSAGE", function(_, message)
	if run and message and (message == ERR_INV_FULL or message == ERR_ITEM_MAX_COUNT) then
		Inbox.Stop("bags are full")
	end
end)
ns:Listen("OPTIONS", Inbox.Refresh)
