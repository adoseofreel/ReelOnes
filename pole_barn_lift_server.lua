-- pole_barn_lift_server.lua - online physics helper for the pole_barn car lifts
-- Sent to every player by the server (csp_extra_options.ini [SCRIPT_...]). Does nothing on other tracks.
-- The track's own lifts.lua runs the lift and tells this script what to do through shared memory;
-- this script owns the physics (scripts sent by a server are allowed to touch physics online).

local okId, trackId = pcall(ac.getTrackID)
if not okId or not tostring(trackId):lower():find('pole_barn', 1, true) then return end

local ex = ac.connect({
  key = ac.StructItem.key('pole_barn.lifts.exec'),
  beat = ac.StructItem.int32(),
  hold = ac.StructItem.int32(),
  platOn = ac.StructItem.array(ac.StructItem.int32(), 2),
  platX = ac.StructItem.array(ac.StructItem.float(), 2),
  platY = ac.StructItem.array(ac.StructItem.float(), 2),
  platZ = ac.StructItem.array(ac.StructItem.float(), 2),
  surfY = ac.StructItem.array(ac.StructItem.float(), 2),
  wake = ac.StructItem.array(ac.StructItem.int32(), 2),
  liftX = ac.StructItem.array(ac.StructItem.float(), 2),
  z0 = ac.StructItem.float(), z1 = ac.StructItem.float(), xi = ac.StructItem.float(), xo = ac.StructItem.float(),
  platW = ac.StructItem.float(), platT = ac.StructItem.float(), platL = ac.StructItem.float(),
}, true, ac.SharedNamespace.Shared)

local bodies, inWorld, surf, surfAt = {}, {}, {}, {}
local held = false
local status = 'waiting for the track'

local function body(k)
  if bodies[k] == nil and ex.platW > 0 then
    local ok, b = pcall(function()
      local b = physics.RigidBody({ physics.Collider.Box(vec3(ex.platW, ex.platT, ex.platL)) }, 3000, nil, true, false)
      b:setSemiDynamic(true, false)
      return b
    end)
    bodies[k] = ok and b or false
    status = ok and 'physics ok' or ('platform not allowed: ' .. tostring(b))
    ac.log('pole_barn lift helper: ' .. status)
  end
  return bodies[k] or nil
end

local function makeSurface(k, y)
  local x, zA, zB = ex.liftX[k], ex.z0, ex.z1
  local v, idx = {}, {}
  for sgn = -1, 1, 2 do
    local xa, xb = x + sgn * (ex.xi - 0.06), x + sgn * (ex.xo + 0.06)
    local b = #v
    v[b + 1] = vec3(xa, y, zA - 0.1); v[b + 2] = vec3(xb, y, zA - 0.1); v[b + 3] = vec3(xb, y, zB + 0.3); v[b + 4] = vec3(xa, y, zB + 0.3)
    for _, t in ipairs({ 0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2 }) do idx[#idx + 1] = b + t end   -- both sides
  end
  local ok, d = pcall(physics.addTrackSurface, v, idx, 'ROAD')
  if not ok then ac.log('pole_barn lift helper: surface failed: ' .. tostring(d)) end
  return ok and d or nil
end

function script.update(dt)
  ex.beat = ex.beat + 1
  for k = 0, 1 do
    -- platform under the car
    local b = body(k)
    if b then
      local on = ex.platOn[k] == 1
      if on ~= inWorld[k] then pcall(function() b:setInWorld(on) end); inWorld[k] = on end
      if on then pcall(function() b:setTransformation(mat4x4.translation(vec3(ex.platX[k], ex.platY[k], ex.platZ[k])), true) end) end
    end
    -- solid road surface at the top
    local want = ex.surfY[k] > -100 and ex.surfY[k] or nil
    if want ~= surfAt[k] then
      if surf[k] then pcall(function() surf[k]:dispose() end); surf[k] = nil end
      if want then surf[k] = makeSurface(k, want) end
      surfAt[k] = want
    end
    if ex.wake[k] >= 0 then pcall(physics.awakeCar, ex.wake[k]) end
  end
  -- no return-to-pits while your car is up on a lift
  local hold = ex.hold == 1
  if hold or held ~= hold then
    local ok, err = pcall(ac.disableCarRecovery, hold)
    if held ~= hold then ac.log('pole_barn lift helper: recovery ' .. (hold and 'off' or 'normal') .. (ok and '' or (' (not allowed: ' .. tostring(err) .. ')'))) end
    held = hold
  end
  pcall(ac.debug, 'pole_barn lift helper', status)
end
