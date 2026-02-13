--[[

   Ender Hub  Png Loader

]]

local EnderHubPngLibrary = {}
EnderHubPngLibrary.__index = EnderHubPngLibrary

function EnderHubPngLibrary.new(data)
    local self = setmetatable({}, EnderHubPngLibrary)
    self.data = data
    self.position = 1
    self:readSignature()
    self:readIHDR()
    self:readData()
    return self
end

function EnderHubPngLibrary:readBytes(n)
    local bytes = {}
    for i = 1, n do
        bytes[i] = string.byte(self.data, self.position)
        self.position = self.position + 1
    end
    return bytes
end

function EnderHubPngLibrary:readUint32()
    local b1 = string.byte(self.data, self.position) or 0
    local b2 = string.byte(self.data, self.position + 1) or 0
    local b3 = string.byte(self.data, self.position + 2) or 0
    local b4 = string.byte(self.data, self.position + 3) or 0
    self.position = self.position + 4
    return (b1 * 16777216) + (b2 * 65536) + (b3 * 256) + b4
end

function EnderHubPngLibrary:readSignature()
    local sig = string.sub(self.data, 1, 8)
    if sig ~= "\137PNG\r\n\26\n" then
        error("Invalid PNG file")
    end
    self.position = 9
end

function EnderHubPngLibrary:readIHDR()
    local length = self:readUint32()
    local chunkType = string.sub(self.data, self.position, self.position + 3)
    self.position = self.position + 4
    
    if chunkType ~= "IHDR" then
        error("IHDR chunk not found")
    end
    
    self.Width = self:readUint32()
    self.Height = self:readUint32()
    self.bitDepth = self:readBytes(1)[1]
    self.colorType = self:readBytes(1)[1]
    self.compression = self:readBytes(1)[1]
    self.filter = self:readBytes(1)[1]
    self.interlace = self:readBytes(1)[1]
    
    self.position = self.position + 4
end

function EnderHubPngLibrary:readData()
    self.pixels = {}
    
    while self.position < #self.data do
        local length = self:readUint32()
        local chunkType = string.sub(self.data, self.position, self.position + 3)
        self.position = self.position + 4
        
        if chunkType == "IDAT" then
            local compressed = string.sub(self.data, self.position, self.position + length - 1)
            self:parseIDAT(compressed)
            self.position = self.position + length
        elseif chunkType == "IEND" then
            break
        else
            self.position = self.position + length
        end
        
        self.position = self.position + 4
    end
end

function EnderHubPngLibrary:parseIDAT(data)
    local pos = 1
    local bytesPerPixel = 4
    
    for y = 0, self.Height - 1 do
        self.pixels[y] = {}
        local filter = string.byte(data, pos) or 0
        pos = pos + 1
        
        for x = 0, self.Width - 1 do
            local r = string.byte(data, pos) or 0
            local g = string.byte(data, pos + 1) or 0
            local b = string.byte(data, pos + 2) or 0
            local a = string.byte(data, pos + 3) or 255
            pos = pos + bytesPerPixel
            
            self.pixels[y][x] = {
                r = r / 255,
                g = g / 255,
                b = b / 255,
                a = a
            }
        end
    end
end

function EnderHubPngLibrary:GetPixel(x, y)
    if y < 0 or y >= self.Height or x < 0 or x >= self.Width then
        return Color3.new(0, 0, 0), 0
    end
    
    local pixel = self.pixels[y] and self.pixels[y][x]
    if pixel then
        return Color3.new(pixel.r, pixel.g, pixel.b), pixel.a
    end
    
    return Color3.new(1, 1, 1), 255
end

return EnderHubPngLibrary
