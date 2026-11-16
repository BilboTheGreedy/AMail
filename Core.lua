local ADDON, ns = ...

local defaults = {
	skipCod = true,
	skipGm = true,
	delay = 0.3,
	autocomplete = true,
	keepSubject = true,
	quick = true,
	tint = true,
	chars = {},
	recent = {},
	lastSubject = "",
	reskin = true,
	window = { scale = 1 },
}

local charDefaults = {}

ACore.New(ADDON, ns, { db = "AMailDB", defaults = defaults, profile = true, shared = { "chars", "recent", "lastSubject" }, char = "AMailCharDB", charDefaults = charDefaults })

ACore.Register({
	name = "AMail",
	options = function() return ns.Options() end,
	title = "AMail",
	slash = "/amail",
	desc = "open all mail, send to alts",
	toggle = function() ns.UI.Menu(ACoreMinimapButton or UIParent, ns.Options()) end,
})

function ns.Open()
	return MailFrame and MailFrame:IsShown()
end

function ns.Realm()
	local realm = GetRealmName and GetRealmName() or "Realm"
	if type(realm) ~= "string" then realm = "Realm" end
	return realm
end

function ns.Alts()
	local out = {}
	local realm = ns.db.chars[ns.Realm()]
	local mine = realm and realm[ns.playerFaction]
	local me = UnitName and UnitName("player")
	for name in pairs(mine or {}) do
		if name ~= me then out[#out + 1] = name end
	end
	table.sort(out)
	return out
end

ns:Listen("LOGIN", function()
	local name = UnitName and UnitName("player")
	if type(name) ~= "string" or name == "" then return end
	local chars = ns.db.chars
	local realm = ns.Realm()
	chars[realm] = chars[realm] or {}
	chars[realm][ns.playerFaction] = chars[realm][ns.playerFaction] or {}
	chars[realm][ns.playerFaction][name] = true
end)

function ns.Options()
	local db = ns.db
	local UI = ns.UI
	local entries = {
		{ text = "Window", title = true },
		{
			text = "Use the default mailbox window", checked = not db.reskin,
			func = function()
				db.reskin = not db.reskin
				ns:Fire("RESKIN")
			end,
		},
		{ text = "Inbox", title = true },
		UI.Check(db, "skipCod", "Open all skips cash on delivery"),
		UI.Check(db, "skipGm", "Open all skips game master mail"),
		UI.Check(db, "tint", "Mark mail that expires soon", function() ns:Fire("OPTIONS") end),
		{ text = "Sending", title = true },
		UI.Check(db, "autocomplete", "Complete names of my characters"),
		UI.Check(db, "keepSubject", "Remember the last subject"),
		UI.Check(db, "quick", "Alt-click a bag item sends it to the last recipient"),
		{ text = "Open all speed", title = true },
	}
	for _, d in ipairs({ 0.2, 0.3, 0.5, 0.8 }) do
		entries[#entries + 1] = {
			text = d .. " s per mail", checked = math.abs(db.delay - d) < 0.01,
			func = function() db.delay = d end,
		}
	end
	entries[#entries + 1] = { text = "Forget recent recipients", func = function()
		db.recent = {}
		ns.chardb.lastTo = nil
	end }
	return entries
end

SLASH_AMAIL1 = "/amail"
SlashCmdList["AMAIL"] = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if msg == "open" then
		ns.Inbox.OpenAll(false)
	elseif msg == "gold" then
		ns.Inbox.OpenAll(true)
	elseif msg == "stop" then
		ns.Inbox.Stop("stopped")
	elseif msg == "" then
		ns.UI.Menu(ACoreMinimapButton or UIParent, ns.Options())
	else
		ns.Print("/amail, /amail open, /amail gold, /amail stop")
	end
end
