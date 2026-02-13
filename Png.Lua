--[[

   Ender Hub  Png Loader

]]
local PNG = {}
PNG.__index = PNG

function PNG.new(data)
    local self = setmetatable({}, PNG)
    
    self.Width = 0
    self.Height = 0
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
    
    self.Width = 16
    self.Height = 16
    
    for y = 0, self.Height - 1 do
        self.Pixels[y] = {}
        for x = 0, self.Width - 1 do
            self.Pixels[y][x] = {
                Color3.new(1, 1, 1),
                255
            }
        end
    end
end

function PNG:GetPixel(x, y)
    x = math.clamp(x, 0, self.Width - 1)
    y = math.clamp(y, 0, self.Height - 1)
    
    if self.Pixels and self.Pixels[y] and self.Pixels[y][x] then
        return self.Pixels[y][x][1], self.Pixels[y][x][2]
    end
    
    return Color3.new(1, 1, 1), 255
end
