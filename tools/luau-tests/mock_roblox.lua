-- Permissive Roblox mock: jedes unbekannte Feld ist ein aufrufbares Proxy-Objekt.
local handlersAll = {}
local function newProxy(label)
  local props, cache, handlers = {}, {}, {}
  local self = {}
  local mt = {}
  mt.__index = function(_, k)
    if k == "_props" then return props end
    if k == "_label" then return label end
    if k == "_handlers" then return handlers end
    local v = props[k]
    if v ~= nil then return v end
    if k == "Connect" or k == "connect" then
      return function(_, fn) table.insert(handlers, fn); return newProxy("conn") end
    end
    if k == "Visible" then return false end
    if k == "ClassName" then return label end
    local c = cache[k]
    if not c then c = newProxy(tostring(label) .. "." .. tostring(k)); cache[k] = c end
    return c
  end
  mt.__newindex = function(_, k, v) props[k] = v end
  mt.__call = function(_, ...) return newProxy("call") end
  mt.__add = function() return newProxy("op") end
  mt.__sub = mt.__add; mt.__mul = mt.__add; mt.__div = mt.__add
  mt.__lt = function() return false end; mt.__le = function() return false end
  mt.__unm = mt.__add
  return setmetatable(self, mt)
end
MockProxy = newProxy

CREATED = {}
local function instance(cls)
  local p = newProxy(cls)
  table.insert(CREATED, p)
  p.ClassName = cls
  p.Name = cls
  p.Text = ""
  p.Visible = true
  p._children = {}
  return p
end

Instance = { new = function(cls) return instance(cls) end }
Enum = newProxy("Enum")
UDim2 = newProxy("UDim2"); UDim = newProxy("UDim"); Vector2 = newProxy("Vector2"); Vector3 = newProxy("Vector3")
Color3 = newProxy("Color3"); ColorSequence = newProxy("ColorSequence"); ColorSequenceKeypoint = newProxy("CSK")
TweenInfo = newProxy("TweenInfo"); NumberRange = newProxy("NumberRange"); CFrame = newProxy("CFrame"); Rect = newProxy("Rect")
task = { delay = function() end, spawn = function(f, ...) end, wait = function() return 0 end, defer = function() end }

LOCALE_ID = "de-de"
ROBLOX_LOCALE = "en-us"
FIRED = {}   -- Protokoll der FireServer-Aufrufe

local fakePlayer = newProxy("Player")
fakePlayer.LocaleId = LOCALE_ID

local services = {}
game = {
  GetService = function(_, name)
    if name == "ReplicatedStorage" then return RS end
    if name == "Players" then
      local p = newProxy("Players"); p.LocalPlayer = fakePlayer; return p
    end
    if name == "LocalizationService" then
      local p = newProxy("LocalizationService"); p.RobloxLocaleId = ROBLOX_LOCALE; return p
    end
    if not services[name] then services[name] = newProxy(name) end
    return services[name]
  end,
}
function SetLocale(id) fakePlayer.LocaleId = id end
CLOCK = 0
local realOs = os
os = setmetatable({ clock = function() return CLOCK end, time = function() return 1000000 end }, { __index = realOs })
