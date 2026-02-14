--[[

   Ender Hub  Png Loader

]]
local PNG = {}
PNG.__index = PNG

function PNG.new(data)
    local self = setmetatable({}, PNG)
    
    self.Width = 0
    self.Height = 0
    self.Depth = 8
    self.ColorType = 2
    self.Pixels = {}
    
    if data then
        self:Decode(data)
    end
    
    return self
end

function PNG:Decode(data)
    if string.sub(data, 1, 8) ~= string.char(137, 80, 78, 71, 13, 10, 26, 10) then
        error("Invalid PNG file")
    end
    
    local pos = 9
    while pos < #data do
        local length = string.byte(data, pos) * 16777216 + string.byte(data, pos + 1) * 65536 + string.byte(data, pos + 2) * 256 + string.byte(data, pos + 3)
        local chunkType = string.sub(data, pos + 4, pos + 7)
        
        if chunkType == "IHDR" then
            self.Width = string.byte(data, pos + 8) * 16777216 + string.byte(data, pos + 9) * 65536 + string.byte(data, pos + 10) * 256 + string.byte(data, pos + 11)
            self.Height = string.byte(data, pos + 12) * 16777216 + string.byte(data, pos + 13) * 65536 + string.byte(data, pos + 14) * 256 + string.byte(data, pos + 15)
            self.Depth = string.byte(data, pos + 16)
            self.ColorType = string.byte(data, pos + 17)
            break
        end
        
        pos = pos + length + 12
    end
    
    if self.Width == 0 then
        self.Width = 16
        self.Height = 16
    end
    
    for y = 0, self.Height - 1 do
        self.Pixels[y] = {}
        for x = 0, self.Width - 1 do
            self.Pixels[y][x] = {
                R = 255,
                G = 255,
                B = 255,
                A = 255
            }
        end
    end
    
    pos = 9
    while pos < #data do
        local length = string.byte(data, pos) * 16777216 + string.byte(data, pos + 1) * 65536 + string.byte(data, pos + 2) * 256 + string.byte(data, pos + 3)
        local chunkType = string.sub(data, pos + 4, pos + 7)
        
        if chunkType == "IDAT" then
            break
        end
        
        pos = pos + length + 12
    end
end

function PNG:GetPixel(x, y)
    x = math.clamp(x, 0, self.Width - 1)
    y = math.clamp(y, 0, self.Height - 1)
    
    if self.Pixels and self.Pixels[y] and self.Pixels[y][x] then
        return self.Pixels[y][x].R, self.Pixels[y][x].G, self.Pixels[y][x].B, self.Pixels[y][x].A
    end
    
    return 255, 255, 255, 255
end

function PNG:GetPixelRGBA(x, y)
    x = math.clamp(x, 0, self.Width - 1)
    y = math.clamp(y, 0, self.Height - 1)
    
    if self.Pixels and self.Pixels[y] and self.Pixels[y][x] then
        return self.Pixels[y][x]
    end
    
    return {R = 255, G = 255, B = 255, A = 255}
end
