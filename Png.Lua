--[[
    Ender Hub Image Library
    -- chunktypes not by me by @MaximumADHD
]]

local PNG = {}

do
    local BinaryReader = {}
    BinaryReader.__index = BinaryReader

    function BinaryReader.new(Data)
        local self = setmetatable({}, BinaryReader)
        self.Data = Data
        self.Position = 1
        return self
    end

    function BinaryReader:ReadByte()
        local Byte = string.byte(self.Data, self.Position)
        self.Position = self.Position + 1
        return Byte
    end

    function BinaryReader:ReadBytes(Count)
        local Bytes = string.sub(self.Data, self.Position, self.Position + Count - 1)
        self.Position = self.Position + Count
        return Bytes
    end

    function BinaryReader:ReadUInt32()
        local Byte1, Byte2, Byte3, Byte4 = string.byte(self.Data, self.Position, self.Position + 3)
        self.Position = self.Position + 4
        return (Byte1 * 16777216) + (Byte2 * 65536) + (Byte3 * 256) + Byte4
    end

    function BinaryReader:ReadUInt16()
        local Byte1, Byte2 = string.byte(self.Data, self.Position, self.Position + 1)
        self.Position = self.Position + 2
        return (Byte1 * 256) + Byte2
    end

    function BinaryReader:Tell()
        return self.Position
    end

    function BinaryReader:Seek(Pos)
        self.Position = Pos
    end

    function BinaryReader:Size()
        return #self.Data
    end

    function BinaryReader:EOF()
        return self.Position > #self.Data
    end

    function BinaryReader:Skip(N)
        self.Position = self.Position + N
    end

    PNG.BinaryReader = BinaryReader
end

do
    local Unfilter = {}

    function Unfilter.None(Data)
        return Data
    end

    function Unfilter.Sub(Data, PrevLine, BPP)
        local Filtered = {}
        for I = 1, #Data do
            local X = string.byte(Data, I)
            local A = I > BPP and string.byte(table.concat(Filtered), I - BPP) or 0
            Filtered[I] = string.char((X + A) % 256)
        end
        return table.concat(Filtered)
    end

    function Unfilter.Up(Data, PrevLine)
        local Filtered = {}
        for I = 1, #Data do
            local X = string.byte(Data, I)
            local B = PrevLine and string.byte(PrevLine, I) or 0
            Filtered[I] = string.char((X + B) % 256)
        end
        return table.concat(Filtered)
    end

    function Unfilter.Average(Data, PrevLine, BPP)
        local Filtered = {}
        for I = 1, #Data do
            local X = string.byte(Data, I)
            local A = I > BPP and string.byte(table.concat(Filtered), I - BPP) or 0
            local B = PrevLine and string.byte(PrevLine, I) or 0
            Filtered[I] = string.char((X + math.floor((A + B) / 2)) % 256)
        end
        return table.concat(Filtered)
    end

    function Unfilter.Paeth(Data, PrevLine, BPP)
        local Filtered = {}
        for I = 1, #Data do
            local X = string.byte(Data, I)
            local A = I > BPP and string.byte(table.concat(Filtered), I - BPP) or 0
            local B = PrevLine and string.byte(PrevLine, I) or 0
            local C = (PrevLine and I > BPP) and string.byte(PrevLine, I - BPP) or 0
            local P = A + B - C
            local PA = math.abs(P - A)
            local PB = math.abs(P - B)
            local PC = math.abs(P - C)
            local Pr
            if PA <= PB and PA <= PC then
                Pr = A
            elseif PB <= PC then
                Pr = B
            else
                Pr = C
            end
            Filtered[I] = string.char((X + Pr) % 256)
        end
        return table.concat(Filtered)
    end

    PNG.Unfilter = Unfilter
end

do
    local band   = bit32.band
    local lshift = bit32.lshift
    local rshift = bit32.rshift

    local BTYPE_NO_COMPRESSION  = 0
    local BTYPE_FIXED_HUFFMAN   = 1
    local BTYPE_DYNAMIC_HUFFMAN = 2

    local lens  = {[0]=3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258}
    local lext  = {[0]=0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0}
    local dists = {[0]=1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577}
    local dext  = {[0]=0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13}
    local order = {16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15}
    local fixedLit  = {0,8,144,9,256,7,280,8,288}
    local fixedDist = {0,5,32}

    local function createState(Output)
        return {Output = Output, Window = {}, Pos = 1}
    end

    local function write(state, byte)
        local pos = state.Pos
        state.Output(byte)
        state.Window[pos] = byte
        state.Pos = pos % 32768 + 1
    end

    local function memoize(fn)
        local meta = {}
        local memoizer = setmetatable({}, meta)
        function meta:__index(k)
            local v = fn(k)
            memoizer[k] = v
            return v
        end
        return memoizer
    end

    local pow2 = memoize(function(n) return 2 ^ n end)
    local isBitStream = setmetatable({}, {__mode = 'k'})

    local function createBitStream(reader)
        local buffer   = 0
        local bitsLeft = 0
        local stream   = {}
        isBitStream[stream] = true

        function stream:GetBitsLeft()
            return bitsLeft
        end

        function stream:Read(count)
            count = count or 1
            while bitsLeft < count do
                local byte = reader:ReadByte()
                if not byte then return end
                buffer   = buffer + lshift(byte, bitsLeft)
                bitsLeft = bitsLeft + 8
            end
            local bits
            if count == 0 then
                bits = 0
            elseif count == 32 then
                bits   = buffer
                buffer = 0
            else
                bits   = band(buffer, pow2[count] - 1)
                buffer = rshift(buffer, count)
            end
            bitsLeft = bitsLeft - count
            return bits
        end

        return stream
    end

    local function getBitStream(obj)
        if isBitStream[obj] then return obj end
        return createBitStream(obj)
    end

    local function sortHuffman(a, b)
        return a.NumBits == b.NumBits and a.Value < b.Value or a.NumBits < b.NumBits
    end

    local function msb(bits, numBits)
        local res = 0
        for i = 1, numBits do
            res  = lshift(res, 1) + band(bits, 1)
            bits = rshift(bits, 1)
        end
        return res
    end

    local function createHuffmanTable(init, isFull)
        local hTable = {}

        if isFull then
            for val, numBits in pairs(init) do
                if numBits ~= 0 then
                    hTable[#hTable + 1] = {Value = val, NumBits = numBits}
                end
            end
        else
            for i = 1, #init - 2, 2 do
                local firstVal = init[i]
                local numBits  = init[i + 1]
                local nextVal  = init[i + 2]
                if numBits ~= 0 then
                    for val = firstVal, nextVal - 1 do
                        hTable[#hTable + 1] = {Value = val, NumBits = numBits}
                    end
                end
            end
        end

        table.sort(hTable, sortHuffman)

        local code    = 1
        local numBits = 0
        for _, slide in ipairs(hTable) do
            if slide.NumBits ~= numBits then
                code    = code * pow2[slide.NumBits - numBits]
                numBits = slide.NumBits
            end
            slide.Code = code
            code = code + 1
        end

        local minBits = math.huge
        local look    = {}
        for _, slide in ipairs(hTable) do
            minBits = math.min(minBits, slide.NumBits)
            look[slide.Code] = slide.Value
        end

        local firstCode = memoize(function(bits)
            return pow2[minBits] + msb(bits, minBits)
        end)

        function hTable:Read(bitStream)
            local code    = 1
            local numBits = 0
            while true do
                if numBits == 0 then
                    local index = bitStream:Read(minBits)
                    numBits = numBits + minBits
                    code    = firstCode[index]
                else
                    local bit = bitStream:Read()
                    numBits = numBits + 1
                    code    = code * 2 + bit
                end
                local val = look[code]
                if val then return val end
            end
        end

        return hTable
    end

    local function parseZlibHeader(bitStream)
        local cm     = bitStream:Read(4)
        local cinfo  = bitStream:Read(4)
        local fcheck = bitStream:Read(5)
        local fdict  = bitStream:Read(1)
        local flevel = bitStream:Read(2)
        local cmf    = cinfo * 16 + cm
        local flg    = fcheck + fdict * 32 + flevel * 64

        assert(cm == 8,                             "unrecognized zlib compression method: " .. cm)
        assert(cinfo <= 7,                          "invalid zlib window size: cinfo=" .. cinfo)
        assert((cmf * 256 + flg) % 31 == 0,        "invalid zlib header (bad fcheck sum)")
        assert(fdict == 0,                          "FDICT not supported")

        return 2 ^ (cinfo + 8)
    end

    local function parseHuffmanTables(bitStream)
        local numLits  = bitStream:Read(5)
        local numDists = bitStream:Read(5)
        local numCodes = bitStream:Read(4)

        local codeLens = {}
        for i = 1, numCodes + 4 do
            codeLens[order[i]] = bitStream:Read(3)
        end
        codeLens = createHuffmanTable(codeLens, true)

        local function decode(numCodes)
            local init    = {}
            local numBits = nil
            local val     = 0
            while val < numCodes do
                local codeLen   = codeLens:Read(bitStream)
                local numRepeats
                if codeLen <= 15 then
                    numRepeats = 1
                    numBits    = codeLen
                elseif codeLen == 16 then
                    numRepeats = 3 + bitStream:Read(2)
                elseif codeLen == 17 then
                    numRepeats = 3 + bitStream:Read(3)
                    numBits    = 0
                elseif codeLen == 18 then
                    numRepeats = 11 + bitStream:Read(7)
                    numBits    = 0
                end
                for i = 1, numRepeats do
                    init[val] = numBits
                    val       = val + 1
                end
            end
            return createHuffmanTable(init, true)
        end

        return decode(numLits + 257), decode(numDists + 1)
    end

    local function parseCompressedItem(bitStream, state, litTable, distTable)
        local val = litTable:Read(bitStream)
        if val < 256 then
            write(state, val)
        elseif val == 256 then
            return true
        else
            local len  = lens[val - 257] + bitStream:Read(lext[val - 257])
            local dv   = distTable:Read(bitStream)
            local dist = dists[dv] + bitStream:Read(dext[dv])
            for i = 1, len do
                local pos  = (state.Pos - 1 - dist) % 32768 + 1
                local byte = assert(state.Window[pos], "invalid back-reference distance")
                write(state, byte)
            end
        end
        return false
    end

    local function parseBlock(bitStream, state)
        local bFinal = bitStream:Read(1)
        local bType  = bitStream:Read(2)

        if bType == BTYPE_NO_COMPRESSION then
            bitStream:Read(bitStream:GetBitsLeft())
            local len = bitStream:Read(16)
            bitStream:Read(16)
            for i = 1, len do write(state, bitStream:Read(8)) end

        elseif bType == BTYPE_FIXED_HUFFMAN or bType == BTYPE_DYNAMIC_HUFFMAN then
            local litTable, distTable
            if bType == BTYPE_DYNAMIC_HUFFMAN then
                litTable, distTable = parseHuffmanTables(bitStream)
            else
                litTable  = createHuffmanTable(fixedLit)
                distTable = createHuffmanTable(fixedDist)
            end
            repeat until parseCompressedItem(bitStream, state, litTable, distTable)
        else
            error("unrecognized compression type")
        end

        return bFinal ~= 0
    end

    local Deflate = {}

    function Deflate:Inflate(io)
        local state     = createState(io.Output)
        local bitStream = getBitStream(io.Input)
        repeat until parseBlock(bitStream, state)
    end

    function Deflate:InflateZlib(io)
        local bitStream = getBitStream(io.Input)
        parseZlibHeader(bitStream)
        self:Inflate({Input = bitStream, Output = io.Output})
        bitStream:Read(bitStream:GetBitsLeft())
    end

    PNG.Deflate = Deflate
end

do
    function PNG.LoadChunkHandler(chunkType)
        local handler = game:HttpGet(
            "https://raw.githubusercontent.com/MaximumADHD/Roblox-PNG-Library/refs/heads/master/Chunks/" .. chunkType .. ".lua"
        )
        return loadstring(handler)()
    end
end

do
    local band   = bit32.band
    local lshift = bit32.lshift
    local rshift = bit32.rshift

    local ZigZag = {
        1,2,9,17,10,3,4,11,18,25,33,26,19,12,5,6,
        13,20,27,34,41,49,42,35,28,21,14,7,8,15,22,29,
        36,43,50,57,58,51,44,37,30,23,16,24,31,38,45,52,
        59,60,53,46,39,32,40,47,54,61,62,55,48,56,63,64
    }

    local function clamp(v)
        return math.max(0, math.min(255, math.floor(v + 0.5)))
    end

    local function idct8(block)
        local tmp = {}
        for pass = 1, 2 do
            for i = 0, 7 do
                local s = {}
                for j = 0, 7 do
                    if pass == 1 then
                        s[j + 1] = block[i * 8 + j + 1] or 0
                    else
                        s[j + 1] = block[j * 8 + i + 1] or 0
                    end
                end
                local p1 = (s[2] + s[8]) * 0.9807852804
                local p2 = (s[2] - s[8]) * 0.7730104534
                local p3 = (s[4] + s[6]) * 0.5555702330
                local p4 = (s[4] - s[6]) * 0.1950903220
                local p5 = (s[3] + s[7]) * 0.8314696123
                local p6 = (s[3] - s[7]) * 0.3826834323
                local t0 = s[1] + s[5]
                local t1 = s[1] - s[5]
                local t2 = p5 - (s[3] + s[7]) * 0.3826834323
                local t3 = p5 + t2
                local e0 = t0 + t3
                local e1 = t1 + t2
                local e2 = t1 - t2
                local e3 = t0 - t3
                local odd0 = p1 - p3 + p4 - p2
                local odd1 = p1 + p3 - p4 + p2
                local odd2 = p2 - p4 + p1 - p3
                local odd3 = p2 + p4 + p1 + p3
                local vals = {e0+odd3, e1+odd2, e2+odd1, e3+odd0, e3-odd0, e2-odd1, e1-odd2, e0-odd3}
                for j = 0, 7 do
                    local idx = pass == 1 and (i * 8 + j + 1) or (j * 8 + i + 1)
                    tmp[idx] = vals[j + 1]
                end
            end
            if pass == 1 then block = tmp; tmp = {} end
        end
        return tmp
    end

    local function readMarker(br)
        assert(br:ReadByte() == 0xFF, "Expected JPEG marker")
        local marker = br:ReadByte()
        while marker == 0xFF do marker = br:ReadByte() end
        return marker
    end

    local function readSOF(br)
        br:ReadUInt16()
        local precision = br:ReadByte()
        local height    = br:ReadUInt16()
        local width     = br:ReadUInt16()
        local nComp     = br:ReadByte()
        local comps     = {}
        for i = 1, nComp do
            local id   = br:ReadByte()
            local samp = br:ReadByte()
            local qtId = br:ReadByte()
            comps[i]   = {id = id, hSamp = rshift(samp, 4), vSamp = band(samp, 0xF), qtId = qtId}
        end
        return width, height, comps
    end

    local function readDHT(br, huffTables)
        local len = br:ReadUInt16() - 2
        local pos = 0
        while pos < len do
            local tc_th  = br:ReadByte()
            local tc     = rshift(tc_th, 4)
            local th     = band(tc_th, 0xF)
            pos          = pos + 1
            local counts = {}
            for i = 1, 16 do
                counts[i] = br:ReadByte()
                pos = pos + 1
            end
            local symbols = {}
            for i = 1, 16 do
                for j = 1, counts[i] do
                    symbols[#symbols + 1] = br:ReadByte()
                    pos = pos + 1
                end
            end
            local codes = {}
            local code  = 0
            local si    = 1
            for bits = 1, 16 do
                for j = 1, counts[bits] do
                    codes[#codes + 1] = {bits = bits, code = code, symbol = symbols[si]}
                    si   = si + 1
                    code = code + 1
                end
                code = code * 2
            end
            huffTables[tc * 4 + th] = codes
        end
    end

    local function readDQT(br, quantTables)
        local len = br:ReadUInt16() - 2
        local pos = 0
        while pos < len do
            local pq_tq = br:ReadByte()
            local tq    = band(pq_tq, 0xF)
            pos = pos + 1
            local tbl = {}
            for i = 1, 64 do
                tbl[i] = br:ReadByte()
                pos    = pos + 1
            end
            quantTables[tq] = tbl
        end
    end

    local function makeBitReader(br)
        local buf   = 0
        local nbits = 0

        local function fill()
            while nbits < 16 do
                local b = br:ReadByte()
                if b == 0xFF then
                    local next = br:ReadByte()
                    if next ~= 0x00 then
                        br:Seek(br:Tell() - 2)
                        break
                    end
                end
                buf   = lshift(buf, 8) + b
                nbits = nbits + 8
            end
        end

        local function readBits(n)
            fill()
            nbits = nbits - n
            return band(rshift(buf, nbits), lshift(1, n) - 1)
        end

        local function readHuff(table)
            local code = 0
            for bits = 1, 16 do
                fill()
                nbits = nbits - 1
                code  = lshift(code, 1) + band(rshift(buf, nbits), 1)
                for _, entry in ipairs(table) do
                    if entry.bits == bits and entry.code == code then
                        return entry.symbol
                    end
                end
            end
            error("Huffman decode failed")
        end

        return readBits, readHuff
    end

    local function decodeBlock(readBits, readHuff, dcTable, acTable, dcPred, qtable)
        local dcSym  = readHuff(dcTable)
        local dcDiff = dcSym > 0 and readBits(dcSym) or 0
        if dcSym > 0 and dcDiff < lshift(1, dcSym - 1) then
            dcDiff = dcDiff - lshift(1, dcSym) + 1
        end
        dcPred = dcPred + dcDiff

        local block = {}
        block[1] = dcPred * qtable[1]

        local k = 2
        while k <= 64 do
            local sym = readHuff(acTable)
            if sym == 0x00 then
                while k <= 64 do block[k] = 0; k = k + 1 end
                break
            end
            local run = rshift(sym, 4)
            local sz  = band(sym, 0xF)
            for i = 1, run do block[k] = 0; k = k + 1 end
            if sz > 0 then
                local val = readBits(sz)
                if val < lshift(1, sz - 1) then val = val - lshift(1, sz) + 1 end
                block[k] = val * qtable[ZigZag[k]]
            else
                block[k] = 0
            end
            k = k + 1
        end

        return idct8(block), dcPred
    end

    function PNG.DecodeJPG(data)
        local br = PNG.BinaryReader.new(data)
        assert(br:ReadByte() == 0xFF and br:ReadByte() == 0xD8, "Not a valid JPEG")

        local width, height, comps
        local huffTables  = {}
        local quantTables = {}
        local scanData

        while not br:EOF() do
            local marker = readMarker(br)

            if marker == 0xC0 then
                width, height, comps = readSOF(br)
            elseif marker == 0xC4 then
                readDHT(br, huffTables)
            elseif marker == 0xDB then
                readDQT(br, quantTables)
            elseif marker == 0xDA then
                local len    = br:ReadUInt16()
                local nComp  = br:ReadByte()
                local scanComps = {}
                for i = 1, nComp do
                    local id = br:ReadByte()
                    local tb = br:ReadByte()
                    scanComps[i] = {id = id, dcTb = rshift(tb, 4), acTb = band(tb, 0xF)}
                end
                br:Skip(3)
                local raw = {}
                while true do
                    local b = br:ReadByte()
                    if not b then break end
                    if b == 0xFF then
                        local n = br:ReadByte()
                        if n == 0x00 then
                            raw[#raw + 1] = string.char(0xFF)
                        else
                            break
                        end
                    else
                        raw[#raw + 1] = string.char(b)
                    end
                end
                scanData = {table.concat(raw), scanComps}
                break
            elseif marker == 0xD9 then
                break
            else
                local len = br:ReadUInt16()
                br:Skip(len - 2)
            end
        end

        assert(width and height and comps, "JPEG missing SOF0 segment")
        assert(scanData, "JPEG missing SOS segment")

        local rawScan, scanComps = scanData[1], scanData[2]
        local scanBr = PNG.BinaryReader.new(rawScan)
        local readBits, readHuff = makeBitReader(scanBr)

        local mcuCols = math.ceil(width  / 8)
        local mcuRows = math.ceil(height / 8)

        local channels = {}
        local dcPreds  = {}
        for i = 1, #comps do channels[i] = {}; dcPreds[i] = 0 end

        for row = 0, mcuRows - 1 do
            for col = 0, mcuCols - 1 do
                for ci, sc in ipairs(scanComps) do
                    local comp = comps[ci]
                    local qt   = quantTables[comp.qtId]
                    local dcT  = huffTables[sc.dcTb * 4 + sc.dcTb]
                    local acT  = huffTables[1 * 4 + sc.acTb]
                    assert(dcT and acT, "Missing Huffman table for component " .. ci)
                    local block, newDc = decodeBlock(readBits, readHuff, dcT, acT, dcPreds[ci], qt)
                    dcPreds[ci] = newDc
                    for by = 0, 7 do
                        for bx = 0, 7 do
                            local px = col * 8 + bx
                            local py = row * 8 + by
                            if px < width and py < height then
                                if not channels[ci][py] then channels[ci][py] = {} end
                                channels[ci][py][px] = clamp(block[by * 8 + bx + 1] + 128)
                            end
                        end
                    end
                end
            end
        end

        local pixels = {}
        for y = 0, height - 1 do
            pixels[y + 1] = {}
            for x = 0, width - 1 do
                local r, g, b
                if #comps == 1 then
                    local lum = (channels[1][y] and channels[1][y][x]) or 0
                    r, g, b = lum, lum, lum
                else
                    local Y  = (channels[1][y] and channels[1][y][x]) or 0
                    local Cb = (channels[2][y] and channels[2][y][x]) or 128
                    local Cr = (channels[3][y] and channels[3][y][x]) or 128
                    r = clamp(Y + 1.402   * (Cr - 128))
                    g = clamp(Y - 0.34414 * (Cb - 128) - 0.71414 * (Cr - 128))
                    b = clamp(Y + 1.772   * (Cb - 128))
                end
                pixels[y + 1][x + 1] = {r, g, b, 255}
            end
        end

        return pixels
    end
end

do
    function PNG.DecodePNG(data)
        local br = PNG.BinaryReader.new(data)
        assert(br:ReadBytes(8) == "\137PNG\r\n\26\n", "Not a valid PNG")

        local width, height, bitDepth, colorType = 0, 0, 0, 0
        local idatChunks = {}

        while br:Tell() <= br:Size() do
            local length    = br:ReadUInt32()
            local chunkType = br:ReadBytes(4)
            local chunkData = br:ReadBytes(length)
            br:ReadUInt32()

            if chunkType == "IHDR" then
                local cbr = PNG.BinaryReader.new(chunkData)
                width     = cbr:ReadUInt32()
                height    = cbr:ReadUInt32()
                bitDepth  = cbr:ReadByte()
                colorType = cbr:ReadByte()
            elseif chunkType == "IDAT" then
                idatChunks[#idatChunks + 1] = chunkData
            elseif chunkType == "IEND" then
                break
            end
        end

        local compressed   = table.concat(idatChunks)
        local cbr          = PNG.BinaryReader.new(compressed)
        local decompressed = {}

        PNG.Deflate:InflateZlib({
            Input  = cbr,
            Output = function(byte) decompressed[#decompressed + 1] = string.char(byte) end
        })

        decompressed = table.concat(decompressed)

        local bpp
        if     colorType == 0 then bpp = 1
        elseif colorType == 2 then bpp = 3
        elseif colorType == 3 then bpp = 1
        elseif colorType == 4 then bpp = 2
        elseif colorType == 6 then bpp = 4
        end

        local stride  = width * bpp
        local rows    = {}
        local rawBr   = PNG.BinaryReader.new(decompressed)
        local prevRow = nil

        for y = 1, height do
            local filterType = rawBr:ReadByte()
            local rowData    = rawBr:ReadBytes(stride)

            if     filterType == 0 then rowData = PNG.Unfilter.None(rowData)
            elseif filterType == 1 then rowData = PNG.Unfilter.Sub(rowData, prevRow, bpp)
            elseif filterType == 2 then rowData = PNG.Unfilter.Up(rowData, prevRow)
            elseif filterType == 3 then rowData = PNG.Unfilter.Average(rowData, prevRow, bpp)
            elseif filterType == 4 then rowData = PNG.Unfilter.Paeth(rowData, prevRow, bpp)
            end

            rows[y]  = rowData
            prevRow  = rowData
        end

        local pixels = {}
        for y = 1, height do
            pixels[y] = {}
            local row = rows[y]
            for x = 1, width do
                local base = (x - 1) * bpp + 1
                local r, g, b, a
                if colorType == 0 then
                    local v = string.byte(row, base)
                    r, g, b, a = v, v, v, 255
                elseif colorType == 2 then
                    r = string.byte(row, base)
                    g = string.byte(row, base + 1)
                    b = string.byte(row, base + 2)
                    a = 255
                elseif colorType == 4 then
                    local v = string.byte(row, base)
                    r, g, b = v, v, v
                    a = string.byte(row, base + 1)
                elseif colorType == 6 then
                    r = string.byte(row, base)
                    g = string.byte(row, base + 1)
                    b = string.byte(row, base + 2)
                    a = string.byte(row, base + 3)
                end
                pixels[y][x] = {r, g, b, a}
            end
        end

        return pixels
    end
end

do
    local function sanitiseUrl(url)
        local host = url:match("https?://([^/]+)")
        if host then
            local lower = host:lower()
            if lower:find("discordapp%.net") or lower:find("discord%.com") or lower:find("media%.discordapp") then
                url = url:match("([^?]+)") or url
            end
        end
        return url
    end

    function PNG.Fetch(url)
        url = sanitiseUrl(url)
        local ok, result = pcall(function()
            return game:HttpGet(url, true)
        end)
        assert(ok, "[ImageLib] Fetch failed: " .. tostring(url) .. "\n" .. tostring(result))
        return result
    end

    function PNG.DetectFormat(data)
        if data:sub(1, 4) == "\137PNG" then return "png" end
        if data:sub(1, 2) == "\255\216" then return "jpg" end
        error("[ImageLib] Unknown image format")
    end

    function PNG.LoadImage(url)
        local data = PNG.Fetch(url)
        local fmt  = PNG.DetectFormat(data)
        if fmt == "png" then
            return PNG.DecodePNG(data)
        elseif fmt == "jpg" then
            return PNG.DecodeJPG(data)
        end
    end
end

Deflate      = PNG.Deflate
Unfilter     = PNG.Unfilter
BinaryReader = PNG.BinaryReader

return PNG
