require "gd"

local timer = {value = 0, state = "not ready", savestate = nil, screenshot = "null.png"}
local option = {timer_len = 18000, rotation = 0}
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
	local b = memory.readbyterange(addr, len)
	local v = b[1]
	for i = 2, len do v = bit.lshift(v, 8) + b[i] end
	return v
end

function read_arbitrary_le(addr, len)
	local b = memory.readbyterange(addr, len)
	local v = b[len]
	for i = len - 1, 1, -1 do v = bit.lshift(v, 8) + b[i] end
	return v
end

-- some games (nes especially) use 24 bit numbers
memory.readsword = function(addr) return read_arbitrary(addr, 3) end

-- memory.readword/readdword is supposed to take a boolean is_little_endian
-- argument but it seems to not work, so we have alternatives here
memory.readword_le  = function(addr) return read_arbitrary_le(addr, 2) end
memory.readsword_le = function(addr) return read_arbitrary_le(addr, 3) end
memory.readdword_le = function(addr) return read_arbitrary_le(addr, 4) end

memory.readbcdbyte     = function(addr) return convert_bcd(memory.readbyte(addr))  end
memory.readbcdbyte_le  = function(addr) return convert_bcd(memory.readbyte_le(addr))  end
memory.readbcdword     = function(addr) return convert_bcd(memory.readword(addr))  end
memory.readbcdword_le  = function(addr) return convert_bcd(memory.readword_le(addr))  end
memory.readbcdsword    = function(addr) return convert_bcd(memory.readsword(addr)) end
memory.readbcdsword_le = function(addr) return convert_bcd(memory.readsword_le(addr)) end
memory.readbcddword    = function(addr) return convert_bcd(memory.readdword(addr)) end
memory.readbcddword_le = function(addr) return convert_bcd(memory.readdword_le(addr)) end

-- ========================================================================= --
-- List of games that require special attention
-- ========================================================================= --

gamedb = {
	games = {
		["qix"] = {rotation = 90},
		["puckman"] = {rotation = 270},
		["mspacman"] = {rotation = 270},
		["jrpacman"] = {rotation = 270},
		["superpac"] = {rotation = 270},
		["galaxian"] = {rotation = 270},
		["galaga"] = {rotation = 270},
		["gaplus"] = {rotation = 270},
		["galaga88"] = {rotation = 270},
		["contra"] = {rotation = 270},
		["cairblad"] = {rotation = 90},
		["esprade"] = {rotation = 90},
		["nitrobal"] = {rotation = 90},
		["citybomb"] = {rotation = 90},
		["cyvern"] = {rotation = 270},

		["md_contra"] = {scorefunc = function() return memory.readdword(0xFFFA00) end},
		["md_sparkstru"] = {scorefunc = function() return memory.readbcdword(0xFFAD34) * 100 end},
		["nes_wreckingcrew"] = {scorefunc = function() return memory.readbcdword(0x0085) * 100 end},
		["nes_kidicarus"] = {scorefunc = function() return memory.readsword_le(0x0131) + memory.readsword_le(0x0144) end},
		["nes_contra"] = {scorefunc = function() return memory.readword_le(0x07E2) * 100 end},
		["nes_superc"] = {scorefunc = function() return memory.readbcdsword_le(0x07E3) * 10 end},
		["nes_scat"] = {scorefunc = function() return memory.readsword_le(0x008A) * 10 end},
		["nes_overhorizon"] = {scorefunc = function() return memory.readsword_le(0x00C3) end},

		["triothep"] = {scorefunc = function()
			-- Technically doesn't track score, just assembles it after the game is over using the following criteria...
			credit = memory.readbyte(0x1F1A46)
			if credit == 0 then return 0 end

			win = memory.readbyte(0x1F1A42) * 5400
			item = memory.readword_le(0x1F1A43) * 1200
			boss = memory.readbyte(0x1F1A45) * 60000 
			return (win + item + boss) / credit
		end},

		["nes_legendarywings"] = {scorefunc = function()
			-- saves score as tile offsets, which means it uses 8 bytes for an 8 digit score (?!)
			b = memory.readbyterange(0x00B2, 8)
			v = b[1]
			for i = 2, 8 do v = (v * 10) + b[i] end
			return v
		end},
	},

	fetch = function(self)
		-- Check game first, then parents, then finally assume defaults
		return self.games[fba.romname()] or self.games[fba.parentname()] or {}
	end
}

-- ========================================================================= --
-- This is the font that the timer and score displays use!
-- ========================================================================= --

-- Positional anchors
-- Always returns position from a given corner of the screen, regardless of rotation
anchor = {
	topleft = function(x, y)
		if     option.rotation == 0   then return {x = x, y = y}
		elseif option.rotation == 90  then return {x = fba.screenwidth() - y, y = x}
		elseif option.rotation == 270 then return {x = y, y = fba.screenheight() - x}
		end
	end,
	bottomleft = function(x, y)
		if     option.rotation == 0   then return {x = x, y = fba.screenheight() + y}
		elseif option.rotation == 90  then return {x = -y, y = x}
		elseif option.rotation == 270 then return {x = fba.screenwidth() + y, y = fba.screenheight() - x}
		end
	end,
	topright = function(x, y)
		if     option.rotation == 0   then return {x = fba.screenwidth() + x, y = y}
		elseif option.rotation == 90  then return {x = fba.screenwidth() - y, y = fba.screenheight() + x}
		elseif option.rotation == 270 then return {x = y, y = -x}
		end
	end,
	bottomright = function(x, y)
		if     option.rotation == 0   then return {x = fba.screnwidth() + x, y = fba.screenheight() + y}
		elseif option.rotation == 90  then return {x = -y, y = fba.screenheight() + x}
		elseif option.rotation == 270 then return {x = fba.screenwidth() + y, y = -x}
		end
	end,
	topcenter = function(x, y)
		if     option.rotation == 0   then return {x = (fba.screenwidth() / 2) + x, y = y}
		elseif option.rotation == 90  then return {x = fba.screenwidth() - y, y = (fba.screenheight() / 2) + x}
		elseif option.rotation == 270 then return {x = y, y = (fba.screenheight() / 2) - x}
		end
	end
}

-- We have to have three copies of each font to be able to do three rotation angles,
-- because FBNeo doesn't handle rotation automatically ... we have to do it ourselves
ksfont = {
	rotation = 0,
	new = function(self, object)
		object = object or {}
		setmetatable(object, self)
		self.__index = self
		return object
	end,
	get_image = function(self, color)
		r, g, b = gui.parsecolor(color)
		palette = string.char(r, g, b, 0)
		return self.header1 .. palette .. self.header2 .. self.base
	end,
	draw = function(self, x, y, str, color)
		color = color or "white"
		-- Rotations need a bit of position correction to match
		-- the same screen coordinates as an unrotated screen
		if self.rotation == 90 then x = x - self.height
		elseif self.rotation == 270 then y = y - self.width
		end

		local img = self:get_image(color)
		renderchar = {
			[0]        = function(c)
				local lx, ly = self:mapxy(c)
				gui.gdoverlay(x, y, img, lx * self.width, ly * self.height, self.width, self.height)
				x = x + self.kerning
			end, [90]  = function(c)
				local lx, ly = self:mapxy(c)
				gui.gdoverlay(x, y, img, lx * self.height, ly * self.width, self.height, self.width)
				y = y + self.kerning
			end, [270] = function(c)
				local lx, ly = self:mapxy(c)
				gui.gdoverlay(x, y, img, lx * self.height, ly * self.width, self.height, self.width)
				y = y - self.kerning
			end
		}
		str:gsub(".", renderchar[self.rotation])
	end,
	draw_center = function(self, x, y, str, color)
		if     self.rotation == 0   then self:draw(x - (str:len() * self.kerning) / 2, y, str, color)
		elseif self.rotation == 90  then self:draw(x, y - (str:len() * self.kerning) / 2, str, color)
		elseif self.rotation == 270 then self:draw(x, y + (str:len() * self.kerning) / 2, str, color)
		end
	end,
	draw_right = function(self, x, y, str, color)
		if     self.rotation == 0   then self:draw(x - (str:len() * self.kerning), y, str, color)
		elseif self.rotation == 90  then self:draw(x, y - (str:len() * self.kerning), str, color)
		elseif self.rotation == 270 then self:draw(x, y + (str:len() * self.kerning), str, color)
		end
	end
}

timerfont = {
	tilemap = {
		["0"] = 0,  ["1"] = 1,  ["2"] = 2,  ["3"] = 3,  ["4"] = 4,
		["5"] = 5,  ["6"] = 6,  ["7"] = 7,  ["8"] = 8,  ["9"] = 9,
		[" "] = 15, ["<"] = 14, [">"] = 13, ["'"] = 11, ["\""] = 10
	},
	[0] = ksfont:new{
		width = 8,
		height = 8,
		kerning = 8,
		header1 = "\255\255\0\128\0\8\0\0\3\0\0\0\0" .. string.rep("\0\0\0\127", 111),
		header2 = string.rep("\0\0\0\0", 144),
		base =
			"__~~~~_____~~____~~~~~___~~~~~___~~__~~__~~~~~____~~~~___~~~~~____~~~~____~~~~_____~_~______~_______~~__________________________"..
			"~~oooo~~~~~oo~~~~ooooo~~~ooooo~~~oo~~oo~~ooooo~~~~oooo~~~ooooo~~~~oooo~~~~oooo~~~~~o~o~~~~~~o~~~~~~~oo~~~~____________~~~~~~~~~~"..
			"~oo~~oo~~~ooo~~~~~~~~oo~~~~~~oo~~oo~~oo~~oo~~~~~~oo~~~~~~~~~~oo~~oo~~oo~~oo~~oo~~~~o~o~~~~~~o~~~~~~o~~o~~~~__________~~~~~~~~~~~"..
			"~oo~~oo~~o~oo~~~~~ooooo~~~ooooo~~~ooooo~~ooooo~~~ooooo~~~~~~~oo~~oooooo~~oo~~oo~~~o~o~~~~~~o~~~~~~~o~~o~~~~~________~~~~~~~~~~~~"..
			"~oo~~oo~~~~oo~~~~oo~~~~~~~~~~oo~~~~~~oo~~~~~~oo~~oo~~oo~~~~~~oo~~oo~~oo~~~ooooo~~~~~~~~~~~~~~~~~~~~~oo~~~~~~________~~~~~~~~~~~~"..
			"~oo~~oo~~~~oo~~~~oo~~~~~~~~~~oo~~~~~~oo~~~~~~oo~~oo~~oo~~~~~~oo~~oo~~oo~~~~~~oo~~~~~~~~~~~~~~~~~~~~~~~~~~~~__________~~~~~~~~~~~"..
			"~~oooo~~~oooooo~~oooooo~~ooooo~~~~~~~oo~~ooooo~~~~oooo~~~~~~~oo~~~oooo~~~ooooo~~~~~~~~~~~~~~~~~~~~~~~~~~~~____________~~~~~~~~~~"..
			"__~~~~___~~~~~~__~~~~~~__~~~~~_______~~__~~~~~____~~~~_______~~___~~~~___~~~~~__________________________________________________",
		mapxy = function(self, c) return timerfont.tilemap[c], 0 end
	},
	[90] = ksfont:new{
		width = 8,
		height = 8,
		kerning = 8,
		rotation = 90,
		header1 = "\255\255\0\128\0\8\0\0\3\0\0\0\0" .. string.rep("\0\0\0\127", 111),
		header2 = string.rep("\0\0\0\0", 144),
		base =
			"_~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__________~~~~~~_"..
			"_~oooo~_~o~~o~~_~ooo~~o~~o~~~~o~_~~~~oo~~o~~ooo~_~oooo~__~~~~~o~_~oooo~_~o~~oo~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__________~~~~~~_"..
			"~oooooo~~o~~~o~_~oooo~o~~o~~o~o~_~~~ooo~~o~~ooo~~oooooo~_~~~~~o~~oooooo~~o~oooo~_~~~o~~__~~~~~~__~~~~~~___~~~~___________~~~~~~_"..
			"~o~~~~o~~oooooo~~o~~o~o~~o~~o~o~_~~~o~~_~o~~o~o~~o~~o~o~_~~~~~o~~o~~o~o~~o~o~~o~_~~~~oo~_~~~o~~__~~~oo~____~~____________~~~~~~_"..
			"~o~~~~o~~oooooo~~o~~o~o~~o~~o~o~_~~~o~~_~o~~o~o~~o~~o~o~_~~~~~o~~o~~o~o~~o~o~~o~_~~~o~~__~~~~oo~_~~o~~o~___________~~____~~~~~~_"..
			"~oooooo~~o~~~~~_~o~~ooo~~oooooo~~oooooo~~oooo~o~~oooo~o~~oooooo~~oooooo~~oooooo~_~~~~oo~_~~~~~~__~~o~~o~__________~~~~___~~~~~~_"..
			"_~oooo~_~o~~~~~_~o~~oo~__~oooo~_~oooooo~_~oo~~~__~oo~~~_~ooooo~__~oooo~__~oooo~__~~~~~~__~~~~~~__~~~oo~__________~~~~~~__~~~~~~_"..
			"_~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__________~~~~~~__~~~~~~_",
		mapxy = function(self, c) return timerfont.tilemap[c], 0 end
	},
	[270] = ksfont:new{
		width = 8,
		height = 8,
		kerning = 8,
		rotation = 270,
		header1 = "\255\255\0\128\0\8\0\0\3\0\0\0\0" .. string.rep("\0\0\0\127", 111),
		header2 = string.rep("\0\0\0\0", 144),
		base =
			"_~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__________~~~~~~__~~~~~~_"..
			"_~oooo~__~~~~~o~_~oo~~o~_~oooo~_~oooooo~_~~~oo~__~~~oo~__~ooooo~_~oooo~__~oooo~__~~~~~~__~~~~~~__~oo~~~__________~~~~~~__~~~~~~_"..
			"~oooooo~_~~~~~o~~ooo~~o~~oooooo~~oooooo~~o~oooo~~o~oooo~~oooooo~~oooooo~~oooooo~~oo~~~~__~~~~~~_~o~~o~~___________~~~~___~~~~~~_"..
			"~o~~~~o~~oooooo~~o~o~~o~~o~o~~o~_~~o~~~_~o~o~~o~~o~o~~o~~o~~~~~_~o~o~~o~~o~~o~o~_~~o~~~_~oo~~~~_~o~~o~~____________~~____~~~~~~_"..
			"~o~~~~o~~oooooo~~o~o~~o~~o~o~~o~_~~o~~~_~o~o~~o~~o~o~~o~~o~~~~~_~o~o~~o~~o~~o~o~~oo~~~~__~~o~~~__~oo~~~____~~____________~~~~~~_"..
			"~oooooo~_~o~~~o~~o~oooo~~o~o~~o~~ooo~~~_~ooo~~o~~oooooo~~o~~~~~_~oooooo~~oooo~o~_~~o~~~__~~~~~~__~~~~~~___~~~~___________~~~~~~_"..
			"_~oooo~__~~o~~o~~o~~ooo~~o~~~~o~~oo~~~~_~ooo~~o~_~oooo~_~o~~~~~__~oooo~__~oo~~o~_~~~~~~__~~~~~~__~~~~~~__~~~~~~__________~~~~~~_"..
			"_~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__~~~~~~__________~~~~~~_",
		mapxy = function(self, c) return timerfont.tilemap[c], 0 end
	},
	
	draw =        function(self, xy, str, color) self[option.rotation]:draw(xy.x, xy.y, str,color) end,
	draw_right =  function(self, xy, str, color) self[option.rotation]:draw_right(xy.x, xy.y, str,color) end,
	draw_center = function(self, xy, str, color) self[option.rotation]:draw_center(xy.x, xy.y, str,color) end
}

mainfont = {
	[0] = ksfont:new{
		width = 5,
		height = 8,
		kerning = 4,
		header1 = "\255\255\0\160\0\24\0\0\3\0\0\0\0" .. string.rep("\0\0\0\127", 111),
		header2 = string.rep("\0\0\0\0", 144),
		base = 
			"_______~___~_~__~_~___~~__~_____~____~_____~__~_______________________________~___~~___~____~___~~___~_~__~~~___~~__~~____~____~____~____~_____~_______~_____~~_"..
			"______~o~_~o~o~~o~o~_~oo~~o~~__~o~__~o~___~o~~o~___~_~___~___________________~o~_~oo~_~o~__~o~_~oo~_~o~o~~ooo~_~oo~~oo~__~o~__~o~__~o~__~o~___~o~_~~~_~o~___~oo~"..
			"______~o~_~o~o~~ooo~~oo~__~~o~~o~o~_~o~__~o~__~o~_~o~o~_~o~_______~~~________~o~~o~o~~oo~_~o~o~_~~o~~o~o~~o~~_~o~~__~~o~~o~o~~o~o~__~____~___~o~_~ooo~_~o~_~o~o~"..
			"______~o~__~_~_~o~o~~ooo~_~o~__~o~___~___~o~__~o~__~o~_~ooo~_____~ooo~______~o~_~o~o~_~o~__~~o~_~o~__~oo~~oo~_~oo~___~o~_~o~_~o~o~__________~o~___~~~___~o~_~~o~"..
			"______~o~______~ooo~_~oo~~o~~_~o~o~______~o~__~o~_~o~o~_~o~___~___~~~_______~o~_~o~o~_~o~__~o~___~o~__~o~_~~o~~o~o~__~o~~o~o~_~oo~__~____~___~o~_~ooo~_~o~__~o~_"..
			"_______~_______~o~o~_~oo~_~~o~~o~o~______~o~__~o~__~_~___~___~o~________~__~o~__~o~o~_~o~_~o~~__~~o~__~o~_~~o~~o~o~__~o~~o~o~_~~o~_~o~__~o~___~o~_~~~_~o~____~__"..
			"______~o~_______~_~_~oo~____~__~oo~_______~o~~o~____________~o~________~o~_~o~__~oo~_~ooo~~ooo~~oo~___~o~~oo~__~o~___~o~_~o~_~oo~___~__~o~_____~_______~____~o~_"..
			"_______~_____________~~_________~~_________~__~______________~__________~___~____~~___~~~__~~~__~~_____~__~~____~_____~___~___~~________~____________________~__"..
			"_~~____~~__~~~___~~__~~___~~~__~~~___~~__~_~__~~~___~~__~_~__~____~_~__~~___~~___~~____~~__~~____~~__~~~__~_~__~_~__~_~__~_~__~_~__~~~___~~__~____~~____~_______"..
			"~oo~__~oo~~ooo~_~oo~~oo~_~ooo~~ooo~_~oo~~o~o~~ooo~_~oo~~o~o~~o~__~o~o~~oo~_~oo~_~oo~__~oo~~oo~__~oo~~ooo~~o~o~~o~o~~o~o~~o~o~~o~o~~ooo~_~oo~~o~__~oo~__~o~______"..
			"~o~o~~o~o~~o~o~~o~~_~o~o~~o~~_~o~~_~o~~_~o~o~_~o~___~o~~o~o~~o~__~ooo~~o~o~~o~o~~o~o~~o~o~~o~o~~o~~__~o~_~o~o~~o~o~~o~o~~o~o~~o~o~_~~o~_~o~_~o~___~o~_~o~o~_____"..
			"~ooo~~ooo~~oo~_~o~__~o~o~~ooo~~ooo~~o~~_~ooo~_~o~___~o~~oo~_~o~__~ooo~~o~o~~o~o~~oo~_~o~o~~oo~_~ooo~_~o~_~o~o~~o~o~~o~o~_~o~_~ooo~_~o~__~o~__~o~__~o~_~o~o~_____"..
			"~ooo~~o~o~~o~o~~o~__~o~o~~o~~_~o~~_~o~o~~o~o~_~o~___~o~~o~o~~o~__~o~o~~o~o~~o~o~~o~__~o~o~~o~o~_~~o~_~o~_~o~o~~oo~_~ooo~~o~o~_~o~_~o~___~o~__~o~__~o~__~_~______"..
			"~o~~_~o~o~~o~o~~o~~_~o~o~~o~~_~o~__~o~o~~o~o~_~o~__~~o~~o~o~~o~~_~o~o~~o~o~~o~o~~o~__~oo~_~o~o~_~~o~_~o~_~o~o~~oo~_~ooo~~o~o~_~o~_~o~~__~o~___~o~_~o~_______~~~_"..
			"_~o~_~o~o~~oo~__~oo~~oo~_~ooo~~o~___~oo~~o~o~~ooo~~oo~_~o~o~~ooo~~o~o~~o~o~_~oo~~o~___~oo~~o~o~~oo~__~o~__~oo~~o~__~o~o~~o~o~_~o~_~ooo~_~oo~__~o~~oo~______~ooo~"..
			"__~___~_~__~~____~~__~~___~~~__~_____~~__~_~__~~~__~~___~~~__~~~__~_~__~~~___~~__~_____~~__~_~__~~____~____~~__~~___~_~__~~~___~___~~~___~~____~__~~________~~~_"..
			"__~________~___________~_________~_______~_____~~___~___~_____~_______________________________________~__________________________________~~___~___~~____________"..
			"_~o~___~__~o~____~~___~o~__~~___~o~__~~_~o~___~o~__~o~_~o~~__~o~__~_~__~~___~~___~~____~___~_~___~~__~o~__~_~__~_~__~_~__~_~__~_~__~~~__~oo~_~o~_~oo~___~_______"..
			"__~o~_~o~_~oo~__~oo~_~oo~_~oo~_~o~__~oo~~oo~___~____~__~o~o~_~o~_~o~o~~oo~_~oo~_~oo~__~o~_~o~o~_~oo~_~o~_~o~o~~o~o~~o~o~~o~o~~o~o~~ooo~_~o~__~o~__~o~__~o~______"..
			"___~_~o~o~~o~o~~o~~_~o~o~~o~o~~ooo~~o~o~~o~o~_~o~__~o~_~oo~__~o~_~ooo~~o~o~~o~o~~o~o~~o~o~~oo~_~o~~_~ooo~~o~o~~o~o~~o~o~~o~o~~o~o~_~~o~~o~____~____~o~~ooo~_____"..
			"_____~o~o~~o~o~~o~__~o~o~~oo~__~o~_~ooo~~o~o~_~o~__~o~_~o~o~_~o~_~o~o~~o~o~~o~o~~o~o~~o~o~~o~__~ooo~_~o~_~o~o~~o~o~~o~o~_~o~__~oo~_~o~_~~o~__~o~__~o~__~~o~_____"..
			"_____~o~o~~o~o~~o~~_~o~o~~o~~__~o~__~~o~~o~o~_~o~__~o~_~o~o~_~o~_~o~o~~o~o~~o~o~~oo~_~oo~_~o~___~~o~_~o~_~o~o~~oo~_~ooo~~o~o~_~~o~~o~~__~o~__~o~__~o~____~______"..
			"______~oo~~oo~__~oo~_~oo~_~oo~_~o~_~oo~_~o~o~_~o~_~o~__~o~o~__~o~~o~o~~o~o~_~oo~~o~___~oo~~o~__~oo~___~o~_~oo~~o~__~o~o~~o~o~~oo~_~ooo~_~oo~_~o~_~oo~___________"..
			"_______~~__~~____~~___~~___~~___~___~~___~_~___~___~____~_~____~__~~~__~_~___~~__~_____~~__~____~~_____~___~~__~____~~~__~~~__~~___~~~___~~___~___~~____________",
		mapxy = function(self, c) 
			c = string.byte(c) - 32
			return bit.band(c, 0x1F), bit.rshift(c, 5)
		end
	},
	[90] = ksfont:new{
		width = 5,
		height = 8,
		kerning = 4,
		rotation = 90,
		header1 = "\255\255\0\96\0\40\0\0\3\0\0\0\0" .. string.rep("\0\0\0\127", 111),
		header2 = string.rep("\0\0\0\0", 144),
		base =
			"_~~_~~___~~~~~___~~~~~~__________~~~_~~__~~~~~~__~~~~~~___~~~~~___~~_~___~~~~~__________________"..
			"~oo~oo~_~ooooo~_~oooooo~______~_~ooo~oo~~oooooo~~oooooo~_~ooooo~_~oo~o~_~ooooo~___~~~~__________"..
			"~~~o~~___~o~~o~__~~~~o~______~o~~~~~o~~__~~~o~o~_~~~o~~_~o~oo~o~~o~~o~o~~o~~~~o~_~oooo~_________"..
			"~oo~oo~___~oo~__~oooo~______~o~_~ooo~oo~____~o~_~oooooo~_~~ooo~__~oo~o~__~ooooo~~o~~~~o~________"..
			"_~~_~~_____~~____~~~~________~___~~~_~~______~___~~~~~~____~~~____~~_~____~~~~~__~____~_________"..
			"_~__~~____~~~_____________~~~_______~~~___~~~~___~____~__~~~~~___~__~~___~___~___~____~_________"..
			"~o~~oo~__~ooo~___~~~~_~__~ooo~___~~~ooo~_~oooo~_~o~~~~o~~ooooo~_~o~~oo~_~o~~~o~_~o~~~~o~_~_~~~~_"..
			"~o~o~~__~oo~~o~_~oooo~o~~o~~~o~_~oooo~~_~oo~~~o~~oooooo~_~~~o~o~~o~o~~o~~oooooo~_~oooo~_~o~oooo~"..
			"_~oooo~_~o~oo~___~~~~_~~~oooo~___~~~ooo~~o~oooo~~o~~~~o~~oooooo~_~oooo~_~o~~~~~___~~~~___~_~~~~_"..
			"__~~~~___~_~~____________~~~~_______~~~__~_~~~~__~____~__~~~~~~___~~~~___~______________________"..
			"_~~__~___~~~~~___~_______~~~~~~__~~~__~__~~~~~~__~_______~~~~~~__________~~__~_____~_~_______~~_"..
			"~oo~~o~_~ooooo~_~o~~~_~_~oooooo~~ooo~~o~~oooooo~~o~___~_~oooooo~__~___~_~oo~~o~___~o~o~_____~oo~"..
			"~o~o~o~__~~~o~___~ooo~o~~o~~~o~_~o~~o~o~_~~~o~o~~o~~~~o~~o~~o~o~_~o~_~o~~o~o~~o~___~o~_______~~_"..
			"~o~~oo~_____~o~___~~~_~__~ooo~__~o~_~oo~~ooo~o~__~ooooo~_~oo~oo~__~___~_~o~~oo~___~o~o~_____~oo~"..
			"_~__~~_______~____________~~~____~___~~__~~~_~____~~~~~___~~_~~__________~__~~_____~_~_______~~_"..
			"___~~____~_~~____~~~~~~___~~~____________~__~~___~~~~~~___~~~~___~_______~____~_____~_____~~~~~_"..
			"_~~~o~~_~o~oo~__~oooooo~_~ooo~___~~~~~~_~o~~oo~_~oooooo~_~oooo~_~o~___~_~o~_~~o~___~o~___~ooooo~"..
			"~ooo~oo~~o~o~o~__~~~o~~_~o~~~o~_~oooooo~~o~~o~o~~~~~o~~_~o~~~~o~_~o~_~o~~o~~o~o~__~ooo~___~o~o~_"..
			"~o~~_~o~_~oo~o~_~ooo~o~_~o~_~o~_~o~~~~o~_~ooo~o~~ooo~oo~~o~__~o~__~___~__~oo~o~____~o~___~ooooo~"..
			"_~____~___~~_~___~~~_~___~___~___~____~___~~~_~__~~~_~~__~____~___________~~_~______~_____~~~~~_"..
			"____________~_____________~~~________~~_______~__~~~~~~__~~~~~~_____~________~~__~_______~__~~__"..
			"_~~~_~~___~~o~~___~~~~~__~ooo~_____~~oo~_~~~~~o~~oooooo~~oooooo~___~o~______~oo~~o~_____~o~~oo~_"..
			"~ooo~oo~_~ooooo~_~ooooo~~o~~~o~__~~oo~~_~oooooo~~o~~~~~_~o~~~~o~__~o~o~__~~~o~~__~o~____~oooooo~"..
			"_~~~_~~_~o~~o~~_~o~~~~~_~oooooo~~oo~~____~~~~~o~~o~______~oooo~__~o~_~o~~oooooo~__~______~ooo~o~"..
			"_________~__~____~_______~~~~~~__~~___________~__~________~~~~____~___~__~~~~~~___________~~~_~_"..
			"_~____~___~~~~___~~~~~____~~~____~____~___~~~~~__~~~~~~__~~~~~~____~_~___~__~~~_____~______~__~_"..
			"~o~~_~o~_~oooo~_~ooooo~__~ooo~__~o~~~~o~_~ooooo~~oooooo~~oooooo~__~o~o~_~o~~ooo~___~o~____~o~~o~"..
			"~ooo~oo~~o~~~~__~~~~o~__~o~o~o~_~oooooo~~o~~~~~__~~~oo~_~o~~o~o~__~o~o~_~o~~o~o~___~o~____~~o~~_"..
			"_~~~o~~_~ooooo~_~ooooo~_~o~~oo~__~~~~~~_~oooooo~~oooooo~~o~~o~o~__~o~o~__~oo~~o~___~o~___~o~~o~_"..
			"____~____~~~~~___~~~~~___~__~~___________~~~~~~__~~~~~~__~__~_~____~_~____~~__~_____~_____~__~__"..
			"____~____~~~~~___~~~~~______~_______~~___~~~~~~__~~~~~~__~~~~~~___~___~___~~~~____________~~_~__"..
			"___~o~__~ooooo~_~ooooo~__~~~o~_____~oo~_~oooooo~~oooooo~~oooooo~_~o~_~o~_~oooo~__~_______~oo~o~_"..
			"___~oo~__~o~~~___~~~~o~_~ooooo~_____~~o~~~oo~~~_~~~~~~o~_~~~o~o~__~o~o~_~o~~o~o~~o~_____~o~~o~o~"..
			"__~oo~____~ooo~_~oooo~___~~~o~o~___~oo~___~~ooo~~ooooo~____~o~o~___~o~___~oo~~o~_~______~ooo~o~_"..
			"___~~______~~~___~~~~_______~_~_____~~______~~~__~~~~~______~_~_____~_____~~__~__________~~~_~__"..
			"_________~~~~~____~~~~___~_~~____~_______~~~~~~___~~~~~___~~~~_______~________~__~~_____________"..
			"________~ooooo~__~oooo~_~o~oo~__~o~_____~oooooo~_~ooooo~_~oooo~__~_~~o~______~o~~oo~~________~~_"..
			"________~~o~~~__~o~~~o~_~o~o~o~_~o~______~oo~~~_~o~~~~o~~o~~~~o~~o~o~~o~_~~~~~o~_~~oo~~_____~oo~"..
			"________~ooooo~_~oooo~___~oooo~_~o~_____~oooooo~~ooooo~_~ooo~~o~_~_~ooo~~ooooo~____~~oo~_____~~_"..
			"_________~~~~~___~~~~_____~~~~___~_______~~~~~~__~~~~~___~~~__~_____~~~__~~~~~_______~~_________",
		mapxy = function(self, c)
			c = string.byte(c) - 32
			return 11 - bit.rshift(c, 3), bit.band(c, 0x07)
		end
	},
	[270] = ksfont:new{
		width = 5,
		height = 8,
		kerning = 4,
		rotation = 270,
		header1 = "\255\255\0\96\0\40\0\0\3\0\0\0\0" .. string.rep("\0\0\0\127", 111),
		header2 = string.rep("\0\0\0\0", 144),
		base =
			"_________~~_______~~~~~__~~~_____~__~~~___~~~~~__~~~~~~_______~___~~~~_____~~~~___~~~~~_________"..
			"_~~_____~oo~~____~ooooo~~ooo~_~_~o~~ooo~_~ooooo~~oooooo~_____~o~_~oooo~___~oooo~_~ooooo~________"..
			"~oo~_____~~oo~~_~o~~~~~_~o~~o~o~~o~~~~o~~o~~~~o~_~~~oo~______~o~_~o~o~o~_~o~~~o~__~~~o~~________"..
			"_~~________~~oo~~o~______~o~~_~__~oooo~_~ooooo~_~oooooo~_____~o~__~oo~o~_~oooo~__~ooooo~________"..
			"_____________~~__~________~_______~~~~___~~~~~___~~~~~~_______~____~~_~___~~~~____~~~~~_________"..
			"__~_~~~__________~__~~_____~_____~_~______~~~~~__~~~______~~_____~_~_______~~~~___~~~______~~___"..
			"_~o~ooo~______~_~o~~oo~___~o~___~o~o~____~ooooo~~ooo~~___~oo~___~o~o~~~___~oooo~_~ooo~____~oo~__"..
			"~o~o~~o~_____~o~~o~o~~o~_~o~o~__~o~o~~~_~o~~~~~~_~~~oo~~~o~~_____~ooooo~_~o~~~~___~~~o~__~oo~___"..
			"_~o~oo~_______~__~oooo~_~o~_~o~_~oooooo~~oooooo~~oooooo~_~oo~_____~o~~~__~ooooo~_~ooooo~__~o~___"..
			"__~_~~____________~~~~___~___~___~~~~~~__~~~~~~__~~~~~~___~~_______~______~~~~~___~~~~~____~____"..
			"__~__~_____~_____~__~~____~_~____~_~__~__~~~~~~__~~~~~~___________~~__~___~~~~~___~~~~~____~____"..
			"_~o~~o~___~o~___~o~~oo~__~o~o~__~o~o~~o~~oooooo~~oooooo~_~~~~~~__~oo~~o~_~ooooo~_~ooooo~_~~o~~~_"..
			"_~~o~~____~o~___~o~o~~o~_~o~o~__~o~o~~o~_~oo~~~__~~~~~o~~oooooo~_~o~o~o~__~o~~~~__~~~~o~~oo~ooo~"..
			"~o~~o~____~o~___~ooo~~o~_~o~o~__~oooooo~~oooooo~~ooooo~_~o~~~~o~__~ooo~__~ooooo~_~oooo~_~o~_~~o~"..
			"_~__~______~_____~~~__~___~_~____~~~~~~__~~~~~~__~~~~~___~____~____~~~____~~~~~___~~~~___~____~_"..
			"_~_~~~___________~~~~~~__~___~____~~~~________~__~___________~~__~~~~~~_______~____~__~_________"..
			"~o~ooo~______~__~oooooo~~o~_~o~__~oooo~______~o~~o~~~~~____~~oo~~oooooo~_~~~~~o~_~~o~~o~_~~_~~~_"..
			"~oooooo~____~o~__~~o~~~__~o~o~__~o~~~~o~_~~~~~o~~oooooo~_~~oo~~__~o~~~o~~ooooo~_~ooooo~_~oo~ooo~"..
			"_~oo~~o~_____~o~~oo~______~o~___~oooooo~~oooooo~~o~~~~~_~oo~~_____~ooo~__~~~~~___~~o~~___~~_~~~_"..
			"__~~__~_______~__~~________~_____~~~~~~__~~~~~~__~_______~~________~~~_____________~____________"..
			"_~~~~~_____~______~_~~___________~____~__~~_~~~__~_~~~___~____~___~___~___~_~~~___~_~~___~____~_"..
			"~ooooo~___~o~____~o~oo~__~___~__~o~__~o~~oo~ooo~~o~ooo~_~o~~~~o~_~o~_~o~_~o~ooo~_~o~oo~_~o~_~~o~"..
			"_~o~o~___~ooo~__~o~o~~o~~o~_~o~_~o~~~~o~_~~o~~~~~o~o~~o~~oooooo~_~o~~~o~_~~o~~~__~o~o~o~~oo~ooo~"..
			"~ooooo~___~o~___~o~~_~o~_~___~o~_~oooo~_~oooooo~_~oo~~o~_~~~~~~___~ooo~_~oooooo~__~oo~o~_~~o~~~_"..
			"_~~~~~_____~_____~____~_______~___~~~~___~~~~~~___~~__~____________~~~___~~~~~~____~~_~____~~___"..
			"_~~_______~_~_____~~__~__________~~_~~___~~~~~____~_~~~__~~___~____~~~____________~_______~~__~_"..
			"~oo~_____~o~o~___~oo~~o~_~___~__~oo~oo~_~ooooo~__~o~ooo~~oo~_~o~__~ooo~__~_~~~___~o~_____~oo~~o~"..
			"_~~_______~o~___~o~~o~o~~o~_~o~_~o~o~~o~~o~~~~o~~o~o~~~_~o~o~~o~_~o~~~o~~o~ooo~___~o~~~__~o~o~o~"..
			"~oo~_____~o~o~___~o~~oo~_~___~__~oooooo~_~___~o~~oooooo~~o~~ooo~~oooooo~_~_~~~o~_~ooooo~_~o~~oo~"..
			"_~~_______~_~_____~__~~__________~~~~~~_______~__~~~~~~__~__~~~__~~~~~~_______~___~~~~~___~__~~_"..
			"______________________~___~~~~___~~~~~~__~____~__~~~~_~__~~~_______~~~~____________~~_~___~~~~__"..
			"_~~~~_~___~~~~___~~~~~o~_~oooo~_~oooooo~~o~~~~o~~oooo~o~~ooo~~~___~oooo~~~_~~~~___~oo~o~_~oooo~_"..
			"~oooo~o~_~oooo~_~oooooo~~o~~o~o~~o~o~~~_~oooooo~~o~~~oo~_~~oooo~_~o~~~o~~o~oooo~_~o~~oo~__~~o~o~"..
			"_~~~~_~_~o~~~~o~_~o~~~o~_~oo~~o~_~ooooo~~o~~~~o~_~oooo~_~ooo~~~___~ooo~__~_~~~~___~ooo~__~oo~~o~"..
			"_________~____~___~___~___~~__~___~~~~~__~____~___~~~~___~~~_______~~~_____________~~~____~~__~_"..
			"_________~____~__~~~~~____~_~~____~~~____~~~~~~___~______~~_~~~___~________~~~~____~~_____~~_~~_"..
			"________~o~~~~o~~ooooo~__~o~oo~__~ooo~~_~oooooo~_~o~____~oo~ooo~_~o~______~oooo~__~oo~___~oo~oo~"..
			"_________~oooo~_~o~~~~o~~o~o~~o~~o~oo~o~_~~o~~~_~o~o~~~__~~o~~~~~o~______~o~~~~__~o~~o~___~~o~~~"..
			"__________~~~~___~ooooo~_~o~oo~_~ooooo~_~oooooo~~oooooo~~oo~ooo~_~______~oooooo~_~ooooo~_~oo~oo~"..
			"__________________~~~~~___~_~~___~~~~~___~~~~~~__~~~~~~__~~_~~~__________~~~~~~___~~~~~___~~_~~_",
		mapxy = function(self, c)
			c = string.byte(c) - 32
			return bit.rshift(c, 3), 7 - bit.band(c, 0x07)
		end
	},

	draw =        function(self, xy, str, color) self[option.rotation]:draw(xy.x, xy.y, str,color) end,
	draw_right =  function(self, xy, str, color) self[option.rotation]:draw_right(xy.x, xy.y, str,color) end,
	draw_center = function(self, xy, str, color) self[option.rotation]:draw_center(xy.x, xy.y, str,color) end
}

-- ========================================================================= --
-- Options menu, functions for reading controller input for said menu, etc.
-- ========================================================================= --

local controller = {
	-- FBNeo input names which correspond to a menu action
	capture_set = {
		["Start"] = {"Start", "Start 1", "P1 Start"},
		["Left"] = {"Left", "P1 Left"},
		["Right"] = {"Right", "P1 Right"},
		["Up"] = {"Up", "P1 Up"},
		["Down"] = {"Down", "P1 Down"},
		-- Alternate menu button
		["Descend"] = {"Fire 1"}
	},
	disable_input = {},
	data = {},

	enable_reading = function(self)
		function read_controller()
			local joy = joypad.get()
			for name, valid_inputs in pairs(self.capture_set) do
				for _,input in ipairs(valid_inputs) do
					if joy[input] == true then
						self.data[name] = self.data[name] + 1
						return
					end
				end
				self.data[name] = 0
			end
			joypad.set(self.disable_input)
		end
		for name, valid_inputs in pairs(self.capture_set) do
			self.data[name] = 0
		end
		emu.registerbefore(read_controller)
	end,
	disable_reading = function(self)
		emu.registerbefore(nil)
	end,
	was_read = function(self, input)
		i = self.data[input]
		if i > 30 then
			i = i % 3
		end
		return i == 1
	end,

	-- Ignores read inputs, used for starting caravan run
	globally_pressed = function(self, input)
		local joy = joypad.get()
		for _,subinput in ipairs(self.capture_set[input]) do
			if joy[subinput] == true then return true end
		end
		return false
	end
}
for control, input in pairs(joypad.get()) do
	if type(input) == "boolean" then
		controller.disable_input[control] = false
	else -- Save DIP switches, because for _some_ reason they're an input
		controller.disable_input[control] = input
	end
end

option_menu = {
	cursor = 1,
	headers = {
		{height = 30, text = "Caravan Mode Configuration"},
		{height = 70, text = "UI Configuration"},
	},
	defs = {
		{
			height = 40,
			label = "Timer Duration",
			bgvaluefunc = function() return string.format("%3d'00\"00", option.timer_len / 3600) end,
			inc = function()
				option.timer_len = math.min(432000, option.timer_len + 3600)
				timer.value = option.timer_len
			end,
			dec = function()
				option.timer_len = math.max(3600, option.timer_len - 3600)
				timer.value = option.timer_len
			end,
		},
		{
			height = 80,
			label = "Screen Rotation",
			bgvaluefunc = function() return string.format("%3d    ", option.rotation) end,
			fgvaluefunc = function() return "degrees" end,
			inc = function()
				local rot_next = {[0] = 90, [90] = 270, [270] = 0}
				option.rotation = rot_next[option.rotation]
			end,
			dec = function()
				local rot_prev = {[270] = 90, [90] = 0, [0] = 270}
				option.rotation = rot_prev[option.rotation]
			end,
		}
	},

	on_update = function()
		for _,header in ipairs(option_menu.headers) do
			timerfont:draw_center(anchor.topcenter(0, header.height), "<                        >")
			mainfont:draw_center(anchor.topcenter(0, header.height), header.text, "cyan")
		end
		for i,option in ipairs(option_menu.defs) do
			local color = "white"
			if option_menu.cursor == i then color = "green" end

			local bgvalue = ""
			local fgvalue = ""
			if option.bgvaluefunc then bgvalue = option.bgvaluefunc() end
			if option.fgvaluefunc then fgvalue = option.fgvaluefunc() end

			timerfont:draw_center(anchor.topcenter(0,   option.height), string.format("< %18s >", bgvalue), color)
			mainfont:draw        (anchor.topcenter(-71, option.height), option.label, color)
			mainfont:draw_right  (anchor.topcenter(71,  option.height), fgvalue, color)

			if option_menu.cursor == i and bit.band(fba.framecount(), 0x02) == 2 then
				mainfont:draw_right(anchor.topcenter(-76, option.height), "[", color)
				mainfont:draw      (anchor.topcenter(76,  option.height), "]", color)
			end
		end
	end,
	on_input = function()
		if controller:was_read("Up") then
			option_menu.cursor = math.max(option_menu.cursor - 1, 1)
		elseif controller:was_read("Down") then
			option_menu.cursor = math.min(option_menu.cursor + 1, #option_menu.defs)
		elseif controller:was_read("Descend") then -- Alternate for cabinets without up/down (e.g. Galaga)
			option_menu.cursor = option_menu.cursor + 1
			if option_menu.cursor > #option_menu.defs then option_menu.cursor = 1 end
		end

		if controller:was_read("Right")    then option_menu.defs[option_menu.cursor].inc()
		elseif controller:was_read("Left") then option_menu.defs[option_menu.cursor].dec()
		end
	end
}

-- ========================================================================= --
-- Hooks, etc.
-- ========================================================================= --

-- Called when moving to a new game or starting the script for the first time
-- Sets game info and readies timer
function onstartup()
	name = fba.romname()
	game_data = gamedb:fetch()

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
	option.rotation = game_data.rotation or 0
	option.timer = game_data.timer or 18000
	timer.value = option.timer
end
emu.registerstart(onstartup)

-- HUD displayed on screen
function onhudupdate()
	-- Screenshot taking needs to be in the UI to accurately get the final frame
	-- (if it's in the main loop, it gets the frame before the pause happens)
	if request_screenshot then
		local scr = gd.createFromGdStr(gui.gdscreenshot())
		-- If the UI is rotated, it's reasonable to assume that the screenshot
		-- should be too to match.
		if option.rotation ~= 0 then
			local tmp = gd.createTrueColor(scr:sizeY(), scr:sizeX())
			tmp:copyRotated(scr, scr:sizeY()/2, scr:sizeX()/2, 0, 0, scr:sizeX(), scr:sizeY(), option.rotation)
			tmp:png(timer.screenshot)
		else
			scr:png(timer.screenshot)
		end
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
		mainfont:draw_right(anchor.topright(-8, 8), "Ready!")
		
		mainfont:draw(anchor.bottomleft(2, -26), fba.gamename(), "cyan")
		mainfont:draw(anchor.bottomleft(2, -18), "Press START to start timer.")
		mainfont:draw(anchor.bottomleft(2, -10), "Hotkey 1 (ALT+1) for options / help.")
	elseif timer.state == "ended" or timer.state == "ending" then
		mainfont:draw_right(anchor.topright(-8, 8), "Run is over!")
		if timer.state == "ended" then
			mainfont:draw(anchor.bottomleft(2, -10), "Hotkey 1 (ALT+1) to restart.")
		end
	else
		if (remain < 600 and remain % 30 >= 15) then color = "red" end
	end

	if game_data.scorefunc ~= nil then
		local score = game_data.scorefunc()
		timerfont:draw(anchor.topleft(0, 0), string.format("%8d   >", score))
		mainfont:draw(anchor.topleft(68, 0), "Score")
	end

	local mins = remain/3600
	local secs = (remain%3600) / 60
	local centi = (remain%60)
	timerfont:draw_right(anchor.topright(0, 0), string.format("<  %2d'%02d\"%02d ", mins, secs, centi), color)
	mainfont:draw_right(anchor.topright(-72, 0), "Time", color)
end
gui.register(onhudupdate)

-- Stop/Restart hotkey
function onhotkey1()
	-- If not started: Options
	if timer.state == "ready" then
		timer.state = "options"
		controller:enable_reading()
		gui.register(option_menu.on_update)
	-- If in options: Return to ready
	elseif timer.state == "options" then
		timer.state = "ready"
		controller:disable_reading()
		gui.register(onhudupdate)
	-- If running: End timer
	elseif timer.state == "running" then
		timer.state = "ending"
	-- If timer ended: Reset
	elseif timer.state == "ended" then
		if not timer.savestate then
			joypad.set({Reset = true})
		end
		timer.state = "ready"
		timer.value = option.timer_len
	end
end
input.registerhotkey(1, onhotkey1)

-- ========================================================================= --
-- Timer main loop
-- ========================================================================= --
while true do
	if timer.state == "running" then
		timer.value = timer.value - 1
		if timer.value == 0 then
			timer.state = "ending"
		end
	elseif timer.state == "ready" then
		if controller:globally_pressed("Start") then
			-- Start the timer.
			timer.state = "running"
			if timer.savestate ~= nil then
				savestate.load(timer.savestate)
			end
		end
	elseif timer.state == "options" then
		option_menu.on_input()
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
