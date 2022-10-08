require "gd"

local timer = {value = 0, state = "not ready", savestate = nil, screenshot = "null.png"}
local game_data = {}

-- ========================================================================= --
-- Additional memory management functions
-- ========================================================================= --
function convert_bcd(bcd)
	local num = 0
	local pos = 1
	while bcd ~= 0 do
		num = num + (bit.band(bcd, 0xF) * pos)
		bcd = bit.rshift(bcd, 4)
		pos = pos * 10
	end
	return num
end

function read_arbitrary(addr, len)
	b = memory.readbyterange(addr, len)
	v = b[1]
	for i = 2, len do v = bit.lshift(v, 8) + b[i] end
	return v
end

function read_arbitrary_le(addr, len)
	b = memory.readbyterange(addr, len)
	v = b[len]
	for i = len - 1, 1, -1 do v = bit.lshift(v, 8) + b[i] end
	return v
end

memory.readbcdbyte  = function(addr) return convert_bcd(memory.readbyte(addr))  end
memory.readbcdword  = function(addr) return convert_bcd(memory.readword(addr))  end
memory.readbcddword = function(addr) return convert_bcd(memory.readdword(addr)) end

-- some games (nes especially) use 24 bit numbers
memory.readsword = function(addr) return read_arbitrary(addr, 3) end

-- memory.readword/readdword is supposed to take a boolean is_little_endian
-- argument but it seems to not work, so we have alternatives here
memory.readword_le  = function(addr) return read_arbitrary_le(addr, 2) end
memory.readsword_le = function(addr) return read_arbitrary_le(addr, 3) end
memory.readdword_le = function(addr) return read_arbitrary_le(addr, 4) end

-- ========================================================================= --
-- List of games that require special attention
-- ========================================================================= --
local gamedb = {}
gamedb.games = {}
function gamedb.get(game)
	data = gamedb.games[game]
	if data == nil then data = {} end

	-- Default 5 minute timer
	if data.duration == nil then data.duration = 18000 end
	data.name = game

	return data
end

gamedb.games["md_contra"] = {scorefunc = function() return memory.readdword(0xFFFA00) end}
gamedb.games["md_contraj"] = gamedb.games["md_contra"]
gamedb.games["md_probot"] = gamedb.games["md_contra"]
gamedb.games["md_sparkstru"] = {scorefunc = function() return memory.readbcdword(0xFFAD34) * 100 end}
gamedb.games["nes_wreckingcrew"] = {scorefunc = function() return memory.readbcdword(0x0085) * 100 end}
gamedb.games["nes_kidicarus"] = {scorefunc = function() return memory.readsword_le(0x0131) + memory.readsword_le(0x0144) end}
gamedb.games["nes_contra"] = {scorefunc = function() return memory.readword_le(0x07E2) * 100 end}
gamedb.games["nes_scat"] = {scorefunc = function() return memory.readsword_le(0x008A) * 10 end}
gamedb.games["nes_overhorizon"] = {scorefunc = function() return memory.readsword_le(0x00C3) end}

gamedb.games["nes_legendarywings"] = {scorefunc = function()
	-- saves score as tile offsets, which means it uses 8 bytes for an 8 digit score (?!)
	b = memory.readbyterange(0x00B2, 8)
	v = b[1]
	for i = 2, 8 do v = (v * 10) + b[i] end
	return v
end}

-- ========================================================================= --
-- This is the font that the timer and score displays use!
-- ========================================================================= --
ksfont = {}
ksfont.image = {}
do
	local font =
		"________________________________________________________________________________________________________________________________"..
		"__####=____##=___#####=__#####=__##=_##=_#####=___####=__#####=___####=___####=____#=#=_____#=__________________________________"..
		"=##==##===###========##======##==##==##==##======##==========##==##==##==##==##====#=#======#=====____________=================="..
		"=##==##==#=##========##======##==##==##==##======##==========##==##==##==##==##===#=#======#=======__________==================="..
		"=##==##====##=====#####===#####===#####==#####===#####=======##==######===#####=====================________===================="..
		"=##==##====##====##==========##======##======##==##==##======##==##==##======##====================__________==================="..
		"=##==##====##====##==========##======##======##==##==##======##==##==##======##===================____________=================="..
		"__####=__######=_######=_#####=______##=_#####=___####=______##=__####=__#####=_________________________________________________"
	font = font:gsub("#", "\2")
	font = font:gsub("=", "\1")
	font = font:gsub("_", "\0")

	function font_in_color(color)
		r, g, b = gui.parsecolor(color)
		palette = string.char(r, g, b, 0)
		return "\255\255\0\128\0\8\0\0\3\0\0\0\0\0\0\0\127\0\0\0\0" .. palette .. string.rep("\0\0\0\0", 253) .. font
	end
	ksfont.image["white"] = font_in_color("white")
	ksfont.image["red"]   = font_in_color("red")
end

ksfont.map = {}
ksfont.map[" "] = 14
ksfont.map["<"] = 13
ksfont.map[">"] = 12
ksfont.map["'"] = 11
ksfont.map["\""] = 10
ksfont.map["0"] = 0
ksfont.map["1"] = 1
ksfont.map["2"] = 2
ksfont.map["3"] = 3
ksfont.map["4"] = 4
ksfont.map["5"] = 5
ksfont.map["6"] = 6
ksfont.map["7"] = 7
ksfont.map["8"] = 8
ksfont.map["9"] = 9

function ksfont.draw_horiz(x, y, str, color)
	color = color or "white"
	function drawchar(c)
		gui.gdoverlay(x, y, ksfont.image[color], ksfont.map[c] * 8, 0, 8, 8)
		x = x + 8
	end
	str:gsub(".", drawchar)
end

-- ========================================================================= --
-- Hooks, etc.
-- ========================================================================= --

-- Called when moving to a new game or starting the script for the first time
-- Sets game info and readies timer
function onstartup()
	name = fba.romname()
	game_data = gamedb.get(name)

	timer.value = game_data.duration
	timer.state = "ready"
	timer.screenshot = "screenshot/" .. name .. ".png"
	timer.savestate = "states/" .. name .. ".caravan.fs"

	-- Confirm savestate exists
	local savestate_check = io.open(timer.savestate)
	if savestate_check ~= nil then
		io.close(savestate_check)
	else
		timer.savestate = nil
	end
end
emu.registerstart(onstartup)

-- HUD displayed on screen
function onhudupdate()
	-- Screenshot taking needs to be in the UI to accurately get the final frame
	-- (if it's in the main loop, it gets the frame before the pause happens)
	if request_screenshot then
		gd.createFromGdStr(gui.gdscreenshot()):png(timer.screenshot)
		request_screenshot = false
	end

	local remain = timer.value
	if remain >= 360000 then
		remain = 359999
	elseif remain < 0 then
		remain = 0
	end

	local color = "white"
	if timer.state == "ready" then
		gui.text(fba.screenwidth()-32, 9, "Ready!")
		
		gui.text(2, fba.screenheight()-25, fba.gamename(), "cyan")
		gui.text(2, fba.screenheight()-17, "Press START to start timer.")
		gui.text(2, fba.screenheight()-9, "Hotkey 1 (ALT+1) to end early.")
	elseif timer.state == "ended" or timer.state == "ending" then
		gui.text(fba.screenwidth()-56, 9, "Run is over!")
		if timer.state == "ended" then
			gui.text(2, fba.screenheight()-9, "Hotkey 1 (ALT+1) to restart.")
		end
	else
		if (remain < 600 and remain % 30 >= 15) then color = "red" end
	end

	if game_data.scorefunc ~= nil then
		local score = game_data.scorefunc()
		ksfont.draw_horiz(0, 0, string.format(" %8d   >", score))
		gui.text(76, 1, "SCORE")
	end

	local mins = remain/3600
	local secs = (remain%3600) / 60
	local centi = (remain%60)
	ksfont.draw_horiz(fba.screenwidth()-96, 0, string.format("<  %2d'%02d\"%02d ", mins, secs, centi), color)
	gui.text(fba.screenwidth()-88, 1, "TIME", color)
end
gui.register(onhudupdate)

-- Stop/Restart hotkey
function onhotkey1()
	-- End timer if running
	if timer.state == "running" then
		timer.state = "ending"
	elseif timer.state == "ended" then
		if not timer.savestate then
			joypad.set({Reset = true})
		end
		timer.state = "ready"
		timer.value = game_data.duration
	end
end
input.registerhotkey(1, onhotkey1)

-- ========================================================================= --
-- Timer main loop
-- ========================================================================= --
while true do
	if timer.state == "ready" then
		if joypad.read()["P1 Start"] == true then
			-- Start the timer.
			timer.state = "running"
			if timer.savestate ~= nil then
				savestate.load(timer.savestate)
			end
		end
	elseif timer.state == "running" then
		timer.value = timer.value - 1
		if timer.value == 0 then
			timer.state = "ending"
		end
	elseif timer.state == "ending" then
		-- This must be handled in the main loop due to the pause.
		-- But the screenshot needs to be done after the pause, so we have to do it in the gui callback.
		request_screenshot = true
		fba.pause()

		-- Will show information about restarting after the game is unpaused.
		timer.state = "ended"
	end
	emu.frameadvance()
end
