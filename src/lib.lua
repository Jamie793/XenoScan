ATTACHED_PROCESSES = {}
Process = {}
Process.__index = Process
function Process.new(pid)
   local this = {}
   if (not ATTACHED_PROCESSES[pid]) then
      setmetatable(this, Process)
      this._pid = pid
      this.__nativeObject = attach(this._pid)
      assert(this.__nativeObject, "Failed to attach to process '" .. tostring(pid) .. "'!")
      ATTACHED_PROCESSES[pid] = this
   else
      this = ATTACHED_PROCESSES[pid]
   end
   return this
end
setmetatable(Process, {__call = function(_, ...) return Process.new(...) end})

function Process:destroy()
   local this = type(self) == 'table' and self or Process.new(self)

   destroy(this.__nativeObject)
   ATTACHED_PROCESSES[this._pid] = nil
   self = nil
end

function Process:newScan()
   local this = type(self) == 'table' and self or Process.new(self)

   return newScan(this.__nativeObject)
end

function Process:getResultsSize()
   local this = type(self) == 'table' and self or Process.new(self)

   return getScanResultsSize(this.__nativeObject)
end

function Process:getResults(offset, count)
   local this = type(self) == 'table' and self or Process.new(self)

   count = count or this:getResultsSize()
   if (count == 0) then return false end
   offset = offset or 0

   local result, message = getScanResults(this.__nativeObject, offset, count)
   assert(result, message)
   return result
end

function Process:findDataStructures(offset, count)
   local this = type(self) == 'table' and self or Process.new(self)
   return getDataStructures(this.__nativeObject)
end

TYPE_MODE_LOOSE = 1
TYPE_MODE_TIGHT = 2
TYPE_MODE_EXACT = 3

typeModeMap =
{
   ["string"] = {
      [TYPE_MODE_LOOSE] = SCAN_INFER_TYPE_ALL_TYPES,
      [TYPE_MODE_TIGHT] = SCAN_INFER_TYPE_STRING_TYPES,
      [TYPE_MODE_EXACT] = SCAN_INFER_TYPE_STRING_TYPES
   },
   ["number"] = {
      [TYPE_MODE_LOOSE] = SCAN_INFER_TYPE_ALL_TYPES,
      [TYPE_MODE_TIGHT] = SCAN_INFER_TYPE_NUMERIC_TYPES,
      [TYPE_MODE_EXACT] = SCAN_INFER_TYPE_NUMERIC_TYPES
   }
}

function Process:scanFor(scanValue, scanComparator, typeMode)
   local this = type(self) == 'table' and self or Process.new(self)

   typeMode = typeMode or TYPE_MODE_EXACT
   scanComparator = scanComparator or SCAN_COMPARE_EQUALS

   local raw_scanValue = nil
   local raw_scanType = nil
   local raw_scanTypeMode = nil

   if (typeModeMap[type(scanValue)]) then
      -- it's a basic primitive type
      raw_scanValue = {value = tostring(scanValue)}
      raw_scanType = 0
      raw_scanTypeMode = typeModeMap[type(scanValue)][typeMode]
   elseif type(scanValue) == "table" then
      if (scanValue.__schema) then
         --[[
            It's a structure of specific primitive types.
            Only exact scans and comparisons are allowed.
         ]]
         assert(scanComparator == SCAN_COMPARE_EQUALS, "Structures can only be scanned using SCAN_COMPARE_EQUALS")

         raw_scanValue = scanValue
         raw_scanType = SCAN_VARIANT_STRUCTURE
         raw_scanTypeMode = SCAN_INFER_TYPE_EXACT
      elseif (scanValue.__name and scanValue.__type) then
         --[[
            It's a specific primitive type.
            When not used as strcture members, these types
            Will be constructed such that the name actually contains
            the value to search for. Thus __name is the value.
         ]]
         raw_scanValue = {value = tostring(scanValue.__name)}
         raw_scanType = scanValue.__type
         raw_scanTypeMode = SCAN_INFER_TYPE_EXACT
      elseif (scanValue.__min and scanValue.__max) then
         error("Cannot search for range without specific primitive type. Try range(uint32, min, max).")
      end
   end

   local message = ""
   local success = (raw_scanValue and raw_scanTypeMode)
   if (success) then
      success, message = runScan(this.__nativeObject, raw_scanValue, raw_scanType, raw_scanTypeMode, scanComparator)
   else
      message = "Unable to deduce scan details for Lua type '" .. type(scanValue) ..  "'."
   end

   assert(success, message)
   return success, message
end

function range(a, b, c)
   local ALLOWED_INPUT_TYPES = {["number"] = true}
   local ALLOWED_VARIANT_TYPES =
   {
      [tostring(uint8)] = true, [tostring(int8)] = true,
      [tostring(uint16)] = true, [tostring(int16)] = true,
      [tostring(uint32)] = true, [tostring(int32)] = true,
      [tostring(uint64)] = true, [tostring(int64)] = true,
      [tostring(double)] = true, [tostring(float)] = true
   }

   local valueTransform = function(v) return v end
   if (c ~= nil) then
      assert(ALLOWED_VARIANT_TYPES[tostring(a)], "Specified type must be numeric!")
      valueTransform = a
   end

   local values = (c ~= nil) and {b, c} or {a, b}
   if (#values ~= 2) then
      error("Expected either '(type, min, max)' or '(min, max)' as arguments")
   end

   for _, v in pairs(values) do
      if (not ALLOWED_INPUT_TYPES[type(v)]) then
         error("Inputs must be numbers")
      end
   end

   return valueTransform({__min = math.min(unpack(values)), __max = math.max(unpack(values))})
end

function ascii(name) return {__name = name, __type = SCAN_VARIANT_ASCII_STRING} end
function widestring(name) return {__name = name, __type = SCAN_VARIANT_WIDE_STRING} end
function uint8(name) return {__name = name, __type = SCAN_VARIANT_UINT8} end
function int8(name) return {__name = name, __type = SCAN_VARIANT_INT8} end
function uint16(name) return {__name = name, __type = SCAN_VARIANT_UINT16} end
function int16(name) return {__name = name, __type = SCAN_VARIANT_INT16} end
function uint32(name) return {__name = name, __type = SCAN_VARIANT_UINT32} end
function int32(name) return {__name = name, __type = SCAN_VARIANT_INT32} end
function uint64(name) return {__name = name, __type = SCAN_VARIANT_UINT64} end
function int64(name) return {__name = name, __type = SCAN_VARIANT_INT64} end
function double(name) return {__name = name, __type = SCAN_VARIANT_DOUBLE} end
function float(name) return {__name = name, __type = SCAN_VARIANT_FLOAT} end

function struct(...)
   local structure = {}
   structure.__schema = {}

   for _, v in ipairs({...}) do
      if (structure[v.__name]) then
         error("Duplicate name entry '" .. v.__name .. "' in structure!")
      end

      if (v.__schema) then
         error("Nested custom types are not yet supported (you have a struct in a struct)")
      end

      if (v.__type == SCAN_VARIANT_ASCII_STRING or v.__type == SCAN_VARIANT_ASCII_STRING) then
         error("Structures containing strings are not yet supported")
      end

      structure.__schema[#structure.__schema + 1] = {__type = v.__type, __name = v.__name}
      structure[v.__name] = {}
   end

   return structure
end


function table.show(t, name, indent)
   local cart     -- a container
   local autoref  -- for self references

   --[[ counts the number of elements in a table
   local function tablecount(t)
      local n = 0
      for _, _ in pairs(t) do n = n+1 end
      return n
   end
   ]]
   -- (RiciLake) returns true if the table is empty
   local function isemptytable(t) return next(t) == nil end

   local function basicSerialize (o)
      local so = tostring(o)
      if type(o) == "function" then
         local info = debug.getinfo(o, "S")
         -- info.name is nil because o is not a calling level
         if info.what == "C" then
            return string.format("%q", so .. ", C function")
         else 
            -- the information is defined through lines
            return string.format("%q", so .. ", defined in (" ..
                info.linedefined .. "-" .. info.lastlinedefined ..
                ")" .. info.source)
         end
      elseif type(o) == "number" or type(o) == "boolean" then
         return so
      else
         return string.format("%q", so)
      end
   end

   local function addtocart (value, name, indent, saved, field)
      indent = indent or ""
      saved = saved or {}
      field = field or name

      cart = cart .. indent .. field

      if type(value) ~= "table" then
         cart = cart .. " = " .. basicSerialize(value) .. ";\n"
      else
         if saved[value] then
            cart = cart .. " = {}; -- " .. saved[value] 
                        .. " (self reference)\n"
            autoref = autoref ..  name .. " = " .. saved[value] .. ";\n"
         else
            saved[value] = name
            --if tablecount(value) == 0 then
            if isemptytable(value) then
               cart = cart .. " = {};\n"
            else
               cart = cart .. " = {\n"
               for k, v in pairs(value) do
                  k = basicSerialize(k)
                  local fname = string.format("%s[%s]", name, k)
                  field = string.format("[%s]", k)
                  -- three spaces between levels
                  addtocart(v, fname, indent .. "   ", saved, field)
               end
               cart = cart .. indent .. "};\n"
            end
         end
      end
   end

   name = name or "__unnamed__"
   if type(t) ~= "table" then
      return name .. " = " .. basicSerialize(t)
   end
   cart, autoref = "", ""
   addtocart(t, name, indent)
   return cart .. autoref
end