-- Mock von Network/Remotes: jedes Remote ist ein Proxy mit OnClientEvent / FireServer-Protokoll
local names = {}
local R = {}
local function remote(name)
  local r = MockProxy("Remote:" .. name)
  r.FireServer = function(self, ...) table.insert(FIRED, { name = name, args = { ... } }) end
  return r
end
return setmetatable({}, { __index = function(t, k)
  local r = remote(k); rawset(t, k, r); return r
end })
