--[[

   Ender Hub  Png Loader

]]
local PNG = {}
PNG.__index = PNG

function PNG.new(data)
    local self = setmetatable({}, PNG)
    
    self.width = 0
    self.height = 0
    self.depth = 8
    self.colorType = 2
    self.pixels = {}
    
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
            self.width = string.byte(data, pos + 8) * 16777216 + string.byte(data, pos + 9) * 65536 + string.byte(data, pos + 10) * 256 + string.byte(data, pos + 11)
            self.height = string.byte(data, pos + 12) * 16777216 + string.byte(data, pos + 13) * 65536 + string.byte(data, pos + 14) * 256 + string.byte(data, pos + 15)
            self.depth = string.byte(data, pos + 16)
            self.colorType = string.byte(data, pos + 17)
            break
        end
        
        pos = pos + length + 12
    end
    
    if self.width == 0 then
        self.width = 16
        self.height = 16
    end
    
    for y = 0, self.height - 1 do
        self.pixels[y] = {}
        for x = 0, self.width - 1 do
            self.pixels[y][x] = {
                R = 255,
                G = 255,
                B = 255,
                A = 255
            }
        end
    end
end

function PNG:GetPixel(x, y)
    x = math.clamp(x, 0, self.width - 1)
    y = math.clamp(y, 0, self.height - 1)
    
    if self.pixels and self.pixels[y] and self.pixels[y][x] then
        return self.pixels[y][x]
    end
    
    return {R = 255, G = 255, B = 255, A = 255}
end
