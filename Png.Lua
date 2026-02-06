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
            if (crc & 1) == 1 then
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
        local byte = string.byte(data, i)
        crc = CRC_TABLE[((crc ~ byte) & 0xFF)] ~ (crc >> 8)
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
        for i = 1, length do
            result[i] = scanline[i]
        end
    elseif filter_type == 1 then
        for i = 1, length do
            local left = (i > bytes_per_pixel) and result[i - bytes_per_pixel] or 0
            result[i] = (scanline[i] + left) % 256
        end
    elseif filter_type == 2 then
        for i = 1, length do
            result[i] = (scanline[i] + prev_scanline[i]) % 256
        end
    elseif filter_type == 3 then
        for i = 1, length do
            local left = (i > bytes_per_pixel) and result[i - bytes_per_pixel] or 0
            local average = math.floor((left + prev_scanline[i]) / 2)
            result[i] = (scanline[i] + average) % 256
        end
    elseif filter_type == 4 then
        for i = 1, length do
            local left = (i > bytes_per_pixel) and result[i - bytes_per_pixel] or 0
            local up = prev_scanline[i]
            local upleft = (i > bytes_per_pixel) and prev_scanline[i - bytes_per_pixel] or 0
            result[i] = (scanline[i] + paeth_predictor(left, up, upleft)) % 256
        end
    end
    
    return result
end

function PNG.new(data)
    if type(data) ~= "string" then
        return nil
    end
    
    if #data < 8 or string.sub(data, 1, 8) ~= "\137PNG\r\n\26\n" then
        return nil
    end
    
    local self = setmetatable({
        width = 0,
        height = 0,
        pixels = {},
        _data = data,
        _pos = 9
    }, PNG)
    
    local idat_data = ""
    local width, height
    
    while self._pos <= #self._data do
        if self._pos + 12 > #self._data then break end
        
        local length = string.unpack(">I4", self._data, self._pos)
        local chunk_type = string.sub(self._data, self._pos + 4, self._pos + 7)
        local chunk_data = string.sub(self._data, self._pos + 8, self._pos + 7 + length)
        
        if chunk_type == "IHDR" then
            width = string.unpack(">I4", chunk_data, 1)
            height = string.unpack(">I4", chunk_data, 5)
            self.width = width
            self.height = height
            
        elseif chunk_type == "IDAT" then
            idat_data = idat_data .. chunk_data
            
        elseif chunk_type == "IEND" then
            break
        end
        
        self._pos = self._pos + 12 + length
    end
    
    if not width or not height then
        return nil
    end
    
    local compressed_data = idat_data
    if #compressed_data == 0 then
        return nil
    end
    
    local image_data = ""
    local pos = 1
    
    while pos <= #compressed_data do
        local byte = string.byte(compressed_data, pos)
        image_data = image_data .. string.char(byte)
        pos = pos + 1
    end
    
    self.pixels = {}
    
    local bytes_per_pixel = 3
    local scanline_length = width * bytes_per_pixel
    local data_pos = 1
    local prev_scanline = {}
    for i = 1, scanline_length do prev_scanline[i] = 0 end
    
    for y = 1, height do
        local filter_type = string.byte(image_data, data_pos)
        data_pos = data_pos + 1
        
        local scanline = {}
        for i = 1, scanline_length do
            if data_pos > #image_data then break end
            scanline[i] = string.byte(image_data, data_pos)
            data_pos = data_pos + 1
        end
        
        local unfiltered = unfilter_scanline(filter_type, scanline, prev_scanline, bytes_per_pixel)
        prev_scanline = unfiltered
        
        if not self.pixels[y] then self.pixels[y] = {} end
        
        local pixel_pos = 1
        for x = 1, width do
            local r, g, b = 255, 255, 255
            
            if pixel_pos + 2 <= #unfiltered then
                r = unfiltered[pixel_pos]
                g = unfiltered[pixel_pos + 1]
                b = unfiltered[pixel_pos + 2]
                pixel_pos = pixel_pos + 3
            end
            
            self.pixels[y][x] = Color3.fromRGB(r, g, b)
        end
    end
    
    return self
end

function PNG:GetPixel(x, y)
    if x < 1 or x > self.width or y < 1 or y > self.height then
        return Color3.new(0, 0, 0)
    end
    
    local color = self.pixels[y] and self.pixels[y][x]
    
    if not color then
        return Color3.new(0, 0, 0)
    end
    
    return color
end

function PNG:GetDimensions()
    return self.width, self.height
end

function PNG:Resize(new_width, new_height)
    local new_pixels = {}
    
    for y = 1, new_height do
        new_pixels[y] = {}
        for x = 1, new_width do
            local src_x = math.floor((x - 1) * self.width / new_width) + 1
            local src_y = math.floor((y - 1) * self.height / new_height) + 1
            new_pixels[y][x] = self:GetPixel(src_x, src_y)
        end
    end
    
    local resized = setmetatable({
        width = new_width,
        height = new_height,
        pixels = new_pixels
    }, PNG)
    
    return resized
end

return PNG
