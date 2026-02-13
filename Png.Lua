--[[

   Ender Hub  Png Loader

]]

local PNG = {}
PNG.__index = PNG

local HttpService = game:GetService("HttpService")

local bit32 = bit32 or bit

local crc_table = {}
for i = 0, 255 do
	local c = i
	for j = 1, 8 do
		c = bit32.band(c, 1) == 1 and bit32.bxor(0xEDB88320, bit32.rshift(c, 1)) or bit32.rshift(c, 1)
	end
	crc_table[i] = c
end

local function crc32(str)
	local c = 0xFFFFFFFF
	for i = 1, #str do
		c = bit32.bxor(bit32.rshift(c, 8), crc_table[bit32.bxor(bit32.band(c, 0xFF), str:byte(i))])
	end
	return bit32.bxor(c, 0xFFFFFFFF)
end

local function read_uint32(str, pos)
	local b1 = str:byte(pos)
	local b2 = str:byte(pos + 1)
	local b3 = str:byte(pos + 2)
	local b4 = str:byte(pos + 3)
	return b1 * 0x1000000 + b2 * 0x10000 + b3 * 0x100 + b4
end

local function read_uint16(str, pos)
	local b1 = str:byte(pos)
	local b2 = str:byte(pos + 1)
	return b1 * 0x100 + b2
end

local function paeth(a, b, c)
	local p = a + b - c
	local pa = math.abs(p - a)
	local pb = math.abs(p - b)
	local pc = math.abs(p - c)
	if pa <= pb and pa <= pc then return a
	elseif pb <= pc then return b
	else return c end
end

local function inflate(data)
	local result = {}
	local pos = 1
	local len = #data
	
	while pos <= len do
		local b = data:byte(pos)
		pos = pos + 1
		
		if b <= 127 then
			table.insert(result, string.char(b))
		elseif b >= 192 and b <= 223 then
			local length = (b - 192) + 3
			local distance = data:byte(pos)
			pos = pos + 1
			local start = #result - distance + 1
			for i = 1, length do
				table.insert(result, result[start + i - 1])
			end
		elseif b == 256 then
			break
		end
	end
	
	return table.concat(result)
end

function PNG.from_url(url)
	local self = setmetatable({}, PNG)
	
	local data = HttpService:GetAsync(url)
	
	if data:sub(1, 8) ~= "\137PNG\r\n\26\n" then
		return nil, "Invalid PNG"
	end
	
	self.chunks = {}
	self.idat_data = {}
	
	local pos = 9
	
	while pos < #data do
		local length = read_uint32(data, pos)
		local chunk_type = data:sub(pos + 4, pos + 7)
		local chunk_data = data:sub(pos + 8, pos + 7 + length)
		local chunk_crc = read_uint32(data, pos + 8 + length)
		
		if chunk_type == "IHDR" then
			self.width = read_uint32(chunk_data, 1)
			self.height = read_uint32(chunk_data, 5)
			self.bit_depth = chunk_data:byte(9)
			self.color_type = chunk_data:byte(10)
			self.compression = chunk_data:byte(11)
			self.filter = chunk_data:byte(12)
			self.interlace = chunk_data:byte(13)
		elseif chunk_type == "PLTE" then
			self.palette = {}
			for i = 1, length, 3 do
				table.insert(self.palette, {
					chunk_data:byte(i),
					chunk_data:byte(i + 1),
					chunk_data:byte(i + 2)
				})
			end
		elseif chunk_type == "IDAT" then
			table.insert(self.idat_data, chunk_data)
		elseif chunk_type == "IEND" then
			break
		end
		
		pos = pos + length + 12
	end
	
	local compressed = table.concat(self.idat_data)
	local raw = inflate(compressed)
	
	local bpp = 1
	if self.color_type == 2 then bpp = 3
	elseif self.color_type == 6 then bpp = 4 end
	
	local stride = math.floor((self.width * bpp * self.bit_depth + 7) / 8)
	local row_len = stride + 1
	
	self.pixels = {}
	self.colors = {}
	
	for y = 0, self.height - 1 do
		local filter = raw:byte(y * row_len + 1)
		local row_data = raw:sub(y * row_len + 2, (y + 1) * row_len)
		local prev = self.pixels[y] or {}
		local current = {}
		
		for x = 1, stride do
			local byte = row_data:byte(x)
			
			if filter == 0 then
				current[x] = byte
			elseif filter == 1 then
				local left = current[x - bpp] or 0
				current[x] = (byte + left) % 256
			elseif filter == 2 then
				local up = prev[x] or 0
				current[x] = (byte + up) % 256
			elseif filter == 3 then
				local left = current[x - bpp] or 0
				local up = prev[x] or 0
				current[x] = (byte + math.floor((left + up) / 2)) % 256
			elseif filter == 4 then
				local left = current[x - bpp] or 0
				local up = prev[x] or 0
				local upleft = prev[x - bpp] or 0
				current[x] = (byte + paeth(left, up, upleft)) % 256
			end
		end
		
		self.pixels[y + 1] = current
	end
	
	return self
end

function PNG:get_pixel(x, y)
	if x < 0 or x >= self.width or y < 0 or y >= self.height then
		return 0, 0, 0, 0
	end
	
	local row = self.pixels[y + 1]
	local bpp = 1
	if self.color_type == 2 then bpp = 3
	elseif self.color_type == 6 then bpp = 4 end
	
	local start = x * bpp + 1
	
	if self.color_type == 0 then
		local g = row[start] or 0
		return g, g, g, 255
	elseif self.color_type == 2 then
		return row[start] or 0, row[start + 1] or 0, row[start + 2] or 0, 255
	elseif self.color_type == 3 then
		local idx = (row[start] or 0) + 1
		local c = self.palette[idx] or {0, 0, 0}
		return c[1], c[2], c[3], 255
	elseif self.color_type == 6 then
		return row[start] or 0, row[start + 1] or 0, row[start + 2] or 0, row[start + 3] or 255
	end
	
	return 0, 0, 0, 255
end

function PNG:to_blocks(build_func, offset_x, offset_y, offset_z, scale, color_threshold)
	offset_x = offset_x or 0
	offset_y = offset_y or 0
	offset_z = offset_z or 0
	scale = scale or 4
	color_threshold = color_threshold or 8
	
	local blocks = {}
	local last_color = nil
	local start_x = nil
	
	for y = 0, self.height - 1, 1 do
		last_color = nil
		start_x = nil
		
		for x = 0, self.width - 1, 1 do
			local r, g, b, a = self:get_pixel(x, y)
			
			if a > 0 then
				local current_color = {r, g, b}
				
				if not last_color then
					last_color = current_color
					start_x = x
				else
					local diff = math.sqrt((r - last_color[1])^2 + (g - last_color[2])^2 + (b - last_color[3])^2)
					
					if diff > color_threshold then
						local mid_x = math.floor((start_x + x) / 2)
						local pos = Vector3.new(
							offset_x + mid_x * scale,
							offset_y + y * scale,
							offset_z
						)
						
						build_func(pos, Color3.fromRGB(last_color[1], last_color[2], last_color[3]))
						
						last_color = current_color
						start_x = x
					end
				end
			else
				if last_color then
					local mid_x = math.floor((start_x + x) / 2)
					local pos = Vector3.new(
						offset_x + mid_x * scale,
						offset_y + y * scale,
						offset_z
					)
					
					build_func(pos, Color3.fromRGB(last_color[1], last_color[2], last_color[3]))
					
					last_color = nil
					start_x = nil
				end
			end
		end
		
		if last_color then
			local mid_x = math.floor((start_x + self.width) / 2)
			local pos = Vector3.new(
				offset_x + mid_x * scale,
				offset_y + y * scale,
				offset_z
			)
			
			build_func(pos, Color3.fromRGB(last_color[1], last_color[2], last_color[3]))
		end
	end
	
	return blocks
end

function PNG:to_qr_blocks(build_func, offset_x, offset_y, offset_z, scale)
	offset_x = offset_x or 0
	offset_y = offset_y or 0
	offset_z = offset_z or 0
	scale = scale or 4
	
	local width = math.min(self.width, self.height)
	local block_size = math.floor(width / 21)
	
	if block_size < 1 then block_size = 1 end
	
	for y = 0, 20 do
		for x = 0, 20 do
			local px = math.floor(x * width / 21)
			local py = math.floor(y * height / 21)
			local r, g, b = self:get_pixel(px, py)
			
			local brightness = (r + g + b) / 3
			local color = brightness < 128 and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(255, 255, 255)
			
			local pos = Vector3.new(
				offset_x + x * scale,
				offset_y + y * scale,
				offset_z
			)
			
			build_func(pos, color)
		end
	end
end

function PNG:to_grid(width_blocks, height_blocks, build_func, offset_x, offset_y, offset_z, scale)
	offset_x = offset_x or 0
	offset_y = offset_y or 0
	offset_z = offset_z or 0
	scale = scale or 4
	
	local block_w = math.floor(self.width / width_blocks)
	local block_h = math.floor(self.height / height_blocks)
	
	for gy = 0, height_blocks - 1 do
		for gx = 0, width_blocks - 1 do
			local colors = {}
			
			for y = gy * block_h, (gy + 1) * block_h - 1 do
				for x = gx * block_w, (gx + 1) * block_w - 1 do
					local r, g, b, a = self:get_pixel(x, y)
					if a > 0 then
						local key = string.format("%d_%d_%d", r, g, b)
						colors[key] = (colors[key] or 0) + 1
					end
				end
			end
			
			local best_color = nil
			local best_count = 0
			
			for color, count in pairs(colors) do
				if count > best_count then
					best_count = count
					best_color = color
				end
			end
			
			if best_color then
				local r, g, b = string.match(best_color, "(%d+)_(%d+)_(%d+)")
				local pos = Vector3.new(
					offset_x + gx * scale,
					offset_y + gy * scale,
					offset_z
				)
				
				build_func(pos, Color3.fromRGB(tonumber(r), tonumber(g), tonumber(b)))
			end
		end
	end
end

return PNG
