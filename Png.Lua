--[[

   Ender Hub  Png Images

]]

local PNG = {}
PNG.__index = PNG

local function create_crc_table()
    local crc_table = {}
    for i = 0, 255 do
        local crc = i
        for _ = 1, 8 do
            if crc & 1 == 1 then
                crc = (crc >> 1) ~ 0xEDB88320
            else
                crc = crc >> 1
            end
        end
        crc_table[i] = crc
    end
    return crc_table
end

local CRC_TABLE = create_crc_table()

local function calculate_crc(data, crc)
    crc = crc ~ 0xFFFFFFFF
    for i = 1, #data do
        crc = CRC_TABLE[(crc ~ string.byte(data, i)) & 0xFF] ~ (crc >> 8)
    end
    return crc ~ 0xFFFFFFFF
end

local function paeth_predictor(a, b, c)
    local p = a + b - c
    local pa = math.abs(p - a)
    local pb = math.abs(p - b)
    local pc = math.abs(p - c)
    if pa <= pb and pa <= pc then return a end
    if pb <= pc then return b end
    return c
end

local function unfilter_scanline(filter_type, scanline, prev_scanline, bytes_per_pixel)
    local result = {}
    local length = #scanline
    
    if filter_type == 0 then
        return scanline
    elseif filter_type == 1 then
        for i = 1, length do
            local left = (i > bytes_per_pixel) and result[i - bytes_per_pixel] or 0
            result[i] = (scanline[i] + left) & 0xFF
        end
    elseif filter_type == 2 then
        for i = 1, length do
            result[i] = (scanline[i] + prev_scanline[i]) & 0xFF
        end
    elseif filter_type == 3 then
        for i = 1, length do
            local left = (i > bytes_per_pixel) and result[i - bytes_per_pixel] or 0
            local average = math.floor((left + prev_scanline[i]) / 2)
            result[i] = (scanline[i] + average) & 0xFF
        end
    elseif filter_type == 4 then
        for i = 1, length do
            local left = (i > bytes_per_pixel) and result[i - bytes_per_pixel] or 0
            local up = prev_scanline[i]
            local upleft = (i > bytes_per_pixel) and prev_scanline[i - bytes_per_pixel] or 0
            result[i] = (scanline[i] + paeth_predictor(left, up, upleft)) & 0xFF
        end
    end
    
    return result
end

local function decode_deflate(compressed_data)
    local result = {}
    local pos = 1
    local bit_buffer = 0
    local bits_in_buffer = 0
    
    local function read_bits(n)
        while bits_in_buffer < n do
            if pos > #compressed_data then return 0 end
            bit_buffer = bit_buffer + (string.byte(compressed_data, pos) << bits_in_buffer)
            pos = pos + 1
            bits_in_buffer = bits_in_buffer + 8
        end
        local bits = bit_buffer & ((1 << n) - 1)
        bit_buffer = bit_buffer >> n
        bits_in_buffer = bits_in_buffer - n
        return bits
    end
    
    local function decode_huffman(codes, lengths)
        local code = 0
        local len = 1
        while true do
            code = (code << 1) + read_bits(1)
            for sym, sym_len in pairs(lengths) do
                if len == sym_len and code == codes[sym] then
                    return sym
                end
            end
            len = len + 1
        end
    end
    
    local final
    repeat
        final = read_bits(1)
        local type = read_bits(2)
        
        if type == 0 then
            read_bits(bits_in_buffer % 8)
            local len = read_bits(16)
            local nlen = read_bits(16)
            if (len ~ 0xFFFF) ~= nlen then error("Invalid stored block length") end
            for i = 1, len do
                if pos > #compressed_data then break end
                table.insert(result, string.byte(compressed_data, pos))
                pos = pos + 1
            end
        elseif type == 1 or type == 2 then
            local lit_len_codes, dist_codes
            if type == 1 then
                lit_len_codes = {}
                for i = 0, 143 do lit_len_codes[i] = 8 end
                for i = 144, 255 do lit_len_codes[i] = 9 end
                for i = 256, 279 do lit_len_codes[i] = 7 end
                for i = 280, 287 do lit_len_codes[i] = 8 end
                
                dist_codes = {}
                for i = 0, 31 do dist_codes[i] = 5 end
            else
                local hlit = read_bits(5) + 257
                local hdist = read_bits(5) + 1
                local hclen = read_bits(4) + 4
                
                local code_length_order = {16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15}
                local code_lengths = {}
                for i = 1, hclen do
                    code_lengths[code_length_order[i]] = read_bits(3)
                end
                
                lit_len_codes = {}
                local i = 1
                while i <= hlit do
                    local code = decode_huffman({}, code_lengths)
                    if code < 16 then
                        lit_len_codes[i-1] = code
                        i = i + 1
                    elseif code == 16 then
                        local repeat_count = read_bits(2) + 3
                        local prev_len = lit_len_codes[i-2]
                        for _ = 1, repeat_count do
                            lit_len_codes[i-1] = prev_len
                            i = i + 1
                        end
                    elseif code == 17 then
                        local repeat_count = read_bits(3) + 3
                        for _ = 1, repeat_count do
                            lit_len_codes[i-1] = 0
                            i = i + 1
                        end
                    elseif code == 18 then
                        local repeat_count = read_bits(7) + 11
                        for _ = 1, repeat_count do
                            lit_len_codes[i-1] = 0
                            i = i + 1
                        end
                    end
                end
            end
            
            while true do
                local code = decode_huffman({}, lit_len_codes)
                if code == 256 then break end
                
                if code < 256 then
                    table.insert(result, code)
                else
                    local length_base = 3
                    local length_extra_bits = 0
                    if code <= 264 then
                        length_base = code - 254
                    elseif code <= 284 then
                        local index = code - 265
                        length_extra_bits = math.floor(index / 4)
                        length_base = (((index % 4) + 4) << length_extra_bits) + 3
                    elseif code == 285 then
                        length_base = 258
                    end
                    
                    local length = length_base + read_bits(length_extra_bits)
                    
                    local dist_code = decode_huffman({}, dist_codes)
                    local dist_base = 1
                    local dist_extra_bits = 0
                    if dist_code <= 3 then
                        dist_base = dist_code + 1
                    elseif dist_code <= 29 then
                        local index = dist_code - 4
                        dist_extra_bits = math.floor(index / 2)
                        dist_base = (((index % 2) + 2) << dist_extra_bits) + 1
                    end
                    
                    local distance = dist_base + read_bits(dist_extra_bits)
                    
                    for _ = 1, length do
                        table.insert(result, result[#result - distance + 1])
                    end
                end
            end
        else
            error("Invalid block type")
        end
    until final == 1
    
    return string.char(table.unpack(result))
end

function PNG.new(data)
    if type(data) ~= "string" then
        error("PNG data must be a string")
    end
    
    if #data < 8 or string.sub(data, 1, 8) ~= "\137PNG\r\n\26\n" then
        error("Invalid PNG signature")
    end
    
    local self = setmetatable({
        width = 0,
        height = 0,
        bit_depth = 0,
        color_type = 0,
        compression = 0,
        filter_method = 0,
        interlace_method = 0,
        pixels = {},
        alpha_data = {},
        metadata = {},
        _data = data,
        _pos = 9
    }, PNG)
    
    local chunks = {}
    local idat_data = ""
    
    while self._pos <= #self._data do
        if self._pos + 12 > #self._data then break end
        
        local length = string.unpack(">I4", self._data, self._pos)
        local chunk_type = string.sub(self._data, self._pos + 4, self._pos + 7)
        local chunk_data = string.sub(self._data, self._pos + 8, self._pos + 7 + length)
        local crc = string.unpack(">I4", self._data, self._pos + 8 + length)
        
        if calculate_crc(chunk_type .. chunk_data) ~= crc then
            error("CRC32 checksum failed for chunk: " .. chunk_type)
        end
        
        if chunk_type == "IHDR" then
            self.width = string.unpack(">I4", chunk_data, 1)
            self.height = string.unpack(">I4", chunk_data, 5)
            self.bit_depth = string.byte(chunk_data, 9)
            self.color_type = string.byte(chunk_data, 10)
            self.compression = string.byte(chunk_data, 11)
            self.filter_method = string.byte(chunk_data, 12)
            self.interlace_method = string.byte(chunk_data, 13)
            
            if self.compression ~= 0 then
                error("Unsupported compression method")
            end
            if self.filter_method ~= 0 then
                error("Unsupported filter method")
            end
            if self.interlace_method ~= 0 then
                error("Interlaced PNG not supported")
            end
            
        elseif chunk_type == "PLTE" then
            self.palette = {}
            for i = 1, #chunk_data, 3 do
                local r = string.byte(chunk_data, i)
                local g = string.byte(chunk_data, i + 1)
                local b = string.byte(chunk_data, i + 2)
                table.insert(self.palette, {r, g, b})
            end
            
        elseif chunk_type == "tRNS" then
            if self.color_type == 3 then
                self.transparency = {}
                for i = 1, #chunk_data do
                    self.transparency[i] = string.byte(chunk_data, i)
                end
            end
            
        elseif chunk_type == "IDAT" then
            idat_data = idat_data .. chunk_data
            
        elseif chunk_type == "IEND" then
            break
            
        elseif chunk_type == "tEXt" then
            local null_pos = string.find(chunk_data, "\0")
            if null_pos then
                local key = string.sub(chunk_data, 1, null_pos - 1)
                local value = string.sub(chunk_data, null_pos + 1)
                self.metadata[key] = value
            end
        end
        
        chunks[chunk_type] = (chunks[chunk_type] or 0) + 1
        self._pos = self._pos + 12 + length
    end
    
    if not chunks.IHDR then error("Missing IHDR chunk") end
    if not chunks.IDAT then error("Missing IDAT chunk") end
    if not chunks.IEND then error("Missing IEND chunk") end
    
    local image_data = decode_deflate(idat_data)
    
    local bytes_per_pixel
    if self.color_type == 0 then
        bytes_per_pixel = math.max(1, self.bit_depth / 8)
    elseif self.color_type == 2 then
        bytes_per_pixel = 3 * math.max(1, self.bit_depth / 8)
    elseif self.color_type == 3 then
        bytes_per_pixel = 1
    elseif self.color_type == 4 then
        bytes_per_pixel = 2 * math.max(1, self.bit_depth / 8)
    elseif self.color_type == 6 then
        bytes_per_pixel = 4 * math.max(1, self.bit_depth / 8)
    else
        error("Unsupported color type")
    end
    
    local scanline_length = math.ceil(self.width * self.bit_depth * bytes_per_pixel / 8)
    local pos = 1
    local prev_scanline = {}
    for i = 1, scanline_length do prev_scanline[i] = 0 end
    
    self.pixels = {}
    self.alpha_data = {}
    
    for y = 1, self.height do
        local filter_type = string.byte(image_data, pos)
        pos = pos + 1
        
        local scanline = {}
        for i = 1, scanline_length do
            scanline[i] = string.byte(image_data, pos + i - 1)
        end
        
        local unfiltered = unfilter_scanline(filter_type, scanline, prev_scanline, bytes_per_pixel)
        prev_scanline = unfiltered
        
        if not self.pixels[y] then self.pixels[y] = {} end
        if not self.alpha_data[y] then self.alpha_data[y] = {} end
        
        local pixel_pos = 1
        for x = 1, self.width do
            local r, g, b, a = 255, 255, 255, 255
            
            if self.color_type == 0 then
                if self.bit_depth == 8 then
                    r = g = b = unfiltered[pixel_pos]
                    pixel_pos = pixel_pos + 1
                end
            elseif self.color_type == 2 then
                if self.bit_depth == 8 then
                    r = unfiltered[pixel_pos]
                    g = unfiltered[pixel_pos + 1]
                    b = unfiltered[pixel_pos + 2]
                    pixel_pos = pixel_pos + 3
                end
            elseif self.color_type == 3 then
                if self.palette then
                    local index = unfiltered[pixel_pos] + 1
                    if index <= #self.palette then
                        r, g, b = table.unpack(self.palette[index])
                        if self.transparency and self.transparency[index] then
                            a = self.transparency[index]
                        end
                    end
                    pixel_pos = pixel_pos + 1
                end
            elseif self.color_type == 6 then
                if self.bit_depth == 8 then
                    r = unfiltered[pixel_pos]
                    g = unfiltered[pixel_pos + 1]
                    b = unfiltered[pixel_pos + 2]
                    a = unfiltered[pixel_pos + 3]
                    pixel_pos = pixel_pos + 4
                end
            end
            
            self.pixels[y][x] = Color3.fromRGB(r, g, b)
            self.alpha_data[y][x] = a / 255
        end
        
        pos = pos + scanline_length
    end
    
    return self
end

function PNG:GetPixel(x, y)
    if x < 1 or x > self.width or y < 1 or y > self.height then
        error("Pixel coordinates out of bounds")
    end
    
    local color = self.pixels[y] and self.pixels[y][x]
    local alpha = self.alpha_data[y] and self.alpha_data[y][x]
    
    if not color then
        return Color3.new(0, 0, 0), 0
    end
    
    return color, (alpha or 1)
end

function PNG:GetDimensions()
    return self.width, self.height
end

function PNG:GetMetadata(key)
    return self.metadata[key]
end

function PNG:ToImageData()
    local image_data = {}
    for y = 1, self.height do
        local row = {}
        for x = 1, self.width do
            local color, alpha = self:GetPixel(x, y)
            row[x] = {
                color = color,
                alpha = alpha
            }
        end
        table.insert(image_data, row)
    end
    return image_data
end

function PNG:Resize(new_width, new_height, method)
    method = method or "bilinear"
    
    local new_pixels = {}
    local new_alpha = {}
    
    for y = 1, new_height do
        new_pixels[y] = {}
        new_alpha[y] = {}
        for x = 1, new_width do
            local src_x = (x - 1) * self.width / new_width + 1
            local src_y = (y - 1) * self.height / new_height + 1
            
            if method == "nearest" then
                local ix = math.floor(src_x)
                local iy = math.floor(src_y)
                new_pixels[y][x], new_alpha[y][x] = self:GetPixel(ix, iy)
            else
                local x1 = math.floor(src_x)
                local y1 = math.floor(src_y)
                local x2 = math.min(x1 + 1, self.width)
                local y2 = math.min(y1 + 1, self.height)
                
                local c11, a11 = self:GetPixel(x1, y1)
                local c12, a12 = self:GetPixel(x1, y2)
                local c21, a21 = self:GetPixel(x2, y1)
                local c22, a22 = self:GetPixel(x2, y2)
                
                local dx = src_x - x1
                local dy = src_y - y1
                
                local r1 = c11.R * (1 - dx) + c21.R * dx
                local g1 = c11.G * (1 - dx) + c21.G * dx
                local b1 = c11.B * (1 - dx) + c21.B * dx
                local a1 = a11 * (1 - dx) + a21 * dx
                
                local r2 = c12.R * (1 - dx) + c22.R * dx
                local g2 = c12.G * (1 - dx) + c22.G * dx
                local b2 = c12.B * (1 - dx) + c22.B * dx
                local a2 = a12 * (1 - dx) + a22 * dx
                
                local r = r1 * (1 - dy) + r2 * dy
                local g = g1 * (1 - dy) + g2 * dy
                local b = b1 * (1 - dy) + b2 * dy
                local a = a1 * (1 - dy) + a2 * dy
                
                new_pixels[y][x] = Color3.new(r, g, b)
                new_alpha[y][x] = a
            end
        end
    end
    
    local resized = setmetatable({
        width = new_width,
        height = new_height,
        bit_depth = self.bit_depth,
        color_type = self.color_type,
        pixels = new_pixels,
        alpha_data = new_alpha,
        metadata = self.metadata,
        palette = self.palette,
        transparency = self.transparency
    }, PNG)
    
    return resized
end

function PNG:ExtractChannel(channel)
    local channel_map = {
        red = function(c) return c.R end,
        green = function(c) return c.G end,
        blue = function(c) return c.B end,
        alpha = function(_, a) return a end,
        grayscale = function(c) return (c.R + c.G + c.B) / 3 end
    }
    
    local extract_func = channel_map[channel:lower()]
    if not extract_func then
        error("Invalid channel: " .. channel)
    end
    
    local channel_data = {}
    for y = 1, self.height do
        channel_data[y] = {}
        for x = 1, self.width do
            local color, alpha = self:GetPixel(x, y)
            channel_data[y][x] = extract_func(color, alpha)
        end
    end
    
    return channel_data
end

function PNG:ApplyFilter(filter_func)
    for y = 1, self.height do
        for x = 1, self.width do
            local color, alpha = self:GetPixel(x, y)
            local new_color = filter_func(color, x, y)
            if new_color then
                self.pixels[y][x] = new_color
            end
        end
    end
end

function PNG:GetHistogram()
    local histogram = {
        red = {},
        green = {},
        blue = {}
    }
    
    for i = 0, 255 do
        histogram.red[i] = 0
        histogram.green[i] = 0
        histogram.blue[i] = 0
    end
    
    for y = 1, self.height do
        for x = 1, self.width do
            local color = self.pixels[y][x]
            local r = math.floor(color.R * 255)
            local g = math.floor(color.G * 255)
            local b = math.floor(color.B * 255)
            
            histogram.red[r] = histogram.red[r] + 1
            histogram.green[g] = histogram.green[g] + 1
            histogram.blue[b] = histogram.blue[b] + 1
        end
    end
    
    return histogram
end

return PNG
