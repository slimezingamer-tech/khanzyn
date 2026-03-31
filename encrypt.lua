local require = modules._G.require;
local function encrypt_optimized(data, password, decrypt)
    -- Handle string input more efficiently
    if type(data) == "string" then
        -- Pre-allocate result table with known size
        local len = #data
        local result = {}
        local password_bytes = {password:byte(1, -1)}
        local plen = #password_bytes
        local j = 1
        
        -- Process string directly without intermediate buffer conversion
        for i = 1, len do
            local byte = data:byte(i)
            
            -- Inline the byte transformation (removed function call overhead)
            if decrypt then
                if i % 2 == 0 then
                    byte = (byte - password_bytes[j] + i) % 256
                else
                    byte = (byte + password_bytes[j] - i) % 256
                end
            else
                if i % 2 == 0 then
                    byte = (byte + password_bytes[j] - i) % 256
                else
                    byte = (byte - password_bytes[j] + i) % 256
                end
            end
            
            result[i] = string.char(byte)
            
            -- Increment password index
            j = j + 1
            if j > plen then
                j = 1
            end
        end
        
        return table.concat(result)
    else
        -- Handle table input (your original buffer logic, but optimized)
        local len = #data
        local password_bytes = {password:byte(1, -1)}
        local plen = #password_bytes
        local j = 1
        
        for i = 1, len do
            local byte = data[i]
            
            if decrypt then
                if i % 2 == 0 then
                    byte = (byte - password_bytes[j] + i) % 256
                else
                    byte = (byte + password_bytes[j] - i) % 256
                end
            else
                if i % 2 == 0 then
                    byte = (byte + password_bytes[j] - i) % 256
                else
                    byte = (byte - password_bytes[j] + i) % 256
                end
            end
            
            data[i] = byte
            j = j + 1
            if j > plen then
                j = 1
            end
        end
        
        -- Optimized bufferToString
        return bufferToString_optimized(data)
    end
end

-- Optimized bufferToString - eliminates unnecessary nested loop
local function bufferToString_optimized(buffer)
    local maxLength = 7997
    local length = #buffer
    
    if length <= maxLength then
        return string.char(unpack(buffer))
    end
    
    local result = {}
    local result_index = 1
    
    for index = 1, math.ceil(length / maxLength) do
        local startRange = (index - 1) * maxLength + 1
        local endRange = math.min(index * maxLength, length)
        
        -- Direct assignment instead of nested loop
        result[result_index] = string.char(unpack(buffer, startRange, endRange))
        result_index = result_index + 1
    end
    
    return table.concat(result)
end

-- LuaJIT FFI version for maximum performance (if using LuaJIT)
local ffi = require("ffi")

local function encrypt_ffi(data, password, decrypt)
    local len = #data
    local password_bytes = {password:byte(1, -1)}
    local plen = #password_bytes
    local j = 1
    
    -- Create FFI buffer
    local buffer = ffi.new("char[?]", len)
    ffi.copy(buffer, data, len)
    
    for i = 0, len - 1 do
        local byte = buffer[i]
        local lua_index = i + 1  -- Convert to 1-based index for calculations
        
        if decrypt then
            if lua_index % 2 == 0 then
                byte = (byte - password_bytes[j] + lua_index) % 256
            else
                byte = (byte + password_bytes[j] - lua_index) % 256
            end
        else
            if lua_index % 2 == 0 then
                byte = (byte + password_bytes[j] - lua_index) % 256
            else
                byte = (byte - password_bytes[j] + lua_index) % 256
            end
        end
        
        buffer[i] = byte
        j = j + 1
        if j > plen then
            j = 1
        end
    end
    
    return ffi.string(buffer, len)
end

-- Bitwise optimization version (if bit operations available)
local bit = require("bit")

local function encrypt_bitwise(data, password, decrypt)
    local len = #data
    local password_bytes = {password:byte(1, -1)}
    local plen = #password_bytes
    local j = 1
    local result = {}
    
    for i = 1, len do
        local byte = data:byte(i)
        
        -- Use bitwise AND instead of modulo for even/odd check (faster)
        if decrypt then
            if bit.band(i, 1) == 0 then  -- even
                byte = bit.band(byte - password_bytes[j] + i, 0xFF)
            else  -- odd
                byte = bit.band(byte + password_bytes[j] - i, 0xFF)
            end
        else
            if bit.band(i, 1) == 0 then  -- even
                byte = bit.band(byte + password_bytes[j] - i, 0xFF)
            else  -- odd
                byte = bit.band(byte - password_bytes[j] + i, 0xFF)
            end
        end
        
        result[i] = string.char(byte)
        j = j + 1
        if j > plen then
            j = 1
        end
    end
    
    return table.concat(result)
end
-- Return the best available version
if pcall(require, "ffi") then
    return encrypt_ffi
elseif pcall(require, "bit") then
    return encrypt_bitwise
else
    return encrypt_optimized
end
