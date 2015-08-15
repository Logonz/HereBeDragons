-- HereBeDragons is a data API for the World of Warcraft mapping system

local MAJOR, MINOR = "HereBeDragons-1.0", 1
assert(LibStub, MAJOR .. " requires LibStub")

local HereBeDragons = LibStub:NewLibrary(MAJOR, MINOR)
if not HereBeDragons then return end

HereBeDragons.eventFrame = HereBeDragons.eventFrame or CreateFrame("Frame")

local PI2 = math.pi * 2

-- gather map info
local getMapDataTable
do
    local mapData = {} -- table { width, height, left, top, right, bottom }
    local mapToId, idToMap = {}, {}
    local mapLocalized = {}

    -- gather the data of one zone (by mapId)
    local function processZone(id)
        if not id or mapData[id] then return end

        SetMapByID(id)
        local mapFile = GetMapInfo()
        local numFloors = GetNumDungeonMapLevels()
        idToMap[id] = mapFile

        if not mapToId[mapFile] then mapToId[mapFile] = id end
        mapLocalized[id] = GetMapNameByID(id)

        local _, left, top, right, bottom = GetCurrentMapZone()
        if (left and top and right and bottom and (left ~= 0 or top ~= 0 or right ~= 0 or bottom ~= 0)) then
            mapData[id] = { left - right, top - bottom, left, top, right, bottom }
        else
            mapData[id] = { 0, 0, 0, 0, 0, 0}
        end

        mapData[id].instance = GetAreaMapInfo(id)

        if numFloors == 0 and GetCurrentMapDungeonLevel() == 1 then
            numFloors = 1
            mapData[id].fakefloor = true
        end

        if DungeonUsesTerrainMap() then
            numFloors = numFloors - 1
        end

        mapData[id].floors = {}
        if numFloors > 0 then
            for f = 1, numFloors do
                SetDungeonMapLevel(f)
                local _, right, bottom, left, top = GetCurrentMapDungeonLevel()
                if left and top and right and bottom then
                    mapData[id].floors[f] = { left - right, top - bottom, left, top, right, bottom }
                    mapData[id].floors[f].instance = mapData[id].instance
                end
            end
        end
    end

    function getMapDataTable(mapId, level)
        if mapId == WORLDMAP_COSMIC_ID then return nil end
        if type(mapId) == "string" then
            mapId = mapToId[mapId]
        end
        local data = mapData[mapId]
        if not data then return nil end

        if (level == nil or level == 0) and data.fakefloor then
            level = 1
        end

        if level and level > 0 and data.floors[level] then
            return data.floors[level]
        else
            return data
        end
    end

    local function gatherMapData()
        local continents = {GetMapContinents()}
        for i = 1, #continents, 2 do
            processZone(continents[i])
            local zones = {GetMapZones((i + 1) / 2)}
            for z = 1, #zones, 2 do
                processZone(zones[z])
            end
        end

        local areas = GetAreaMaps()
        for idx, zoneId in pairs(areas) do
            processZone(zoneId)
        end
    end

    gatherMapData()
    HereBeDragons.gatherMapData = gatherMapData
    HereBeDragons.getMapDataTable = getMapDataTable
end

--- Return the localized zone name for a given mapId or mapFile
-- @param mapId numeric mapId or mapFile
function HereBeDragons:GetLocalizedMap(mapId)
    if mapId == WORLDMAP_COSMIC_ID then return WORLD_MAP end
    if type(mapId) == "string" then
        mapId = mapToId[mapId]
    end
    assert(mapLocalized[mapId])
    return mapLocalized[mapId]
end

--- Return the map id to a mapFile
-- @param mapFile Map File
function HereBeDragons:GetMapIdFromFile(mapFile)
    assert(mapToId[mapFile])
    return mapToId[mapFile]
end

--- Return the mapFile to a map id
-- @param mapId Map Id
function HereBeDragons:GetMapFileFromId(mapId)
    return idToMap[mapId]
end

--- Get the size of the zone
-- @param mapId Map Id or MapFile of the zone
-- @param level Optional map level
-- @return width, height of the zone, in yards
function HereBeDragons:GetZoneSize(mapId, level)
    local data = getMapDataTable(mapId, level)
    if not data then return 0, 0 end

    return data[1], data[2]
end

--- Convert local/point coordinates to world coordinates in yards
-- @param x X position on 0-1 point coordinates
-- @param y Y position in 0-1 point coordinates
-- @param zone MapId or MapFile of the zone
-- @param level Optional level of the zone
function HereBeDragons:GetWorldCoordinatesFromZone(x, y, zone, level)
    local data = getMapDataTable(zone, level)
    if not data then return 0, 0 end

    local width, height, left, top = data[1], data[2], data[3], data[4]
    x, y = left - width * x, top - height * y

    return x, y
end

--- Convert world coordinates to local/point zone coordinates
-- @param x Global X position
-- @param y Global Y position
-- @param zone MapId or MapFile of the zone
-- @param level Optiona level of the zone
function HereBeDragons:GetZoneCoordinatesFromWorld(x, y, zone, level)
    local data = getMapDataTable(zone, level)
    if not data then return 0, 0 end

    local width, height, left, top = data[1], data[2], data[3], data[4]
    x, y = (left - x) / width, (top - y) / height

    -- verify the coordinates fall into the zone
    if x < 0 or x > 1 or y < 0 or y > 1 then return 0, 0 end

    return x, y
end

--- Return the distance from an origin position to a destination position in the same instance/continent.
-- @param oInstance origin instance id
-- @param oX origin X
-- @param oY origin Y
-- @param dInstance destination instance id
-- @param dX destination X
-- @param dY destination Y
-- @return distance, deltaX, deltaY
function HereBeDragons:GetWorldDistance(oInstance, oX, oY, dInstance, dX, dY)
    local deltaX, deltaY = dX - oX, dY - oY
    return (deltaX * deltaX + deltaY * deltaY)^0.5, deltaX, deltaY
end

--- Return the angle and distance from an origin position to a destination position in the same instance/continent.
-- @param oInstance origin instance id
-- @param oX origin X
-- @param oY origin Y
-- @param dInstance destination instance id
-- @param dX destination X
-- @param dY destination Y
-- @return angle, distance where angle is in radians and distance in yards
function HereBeDragons:GetWorldVector(oInstance, oX, oY, dInstance, dX, dY)
    local distance, deltaX, deltaY = self:GetWorldDistance(oInstance, oX, oY, dInstance, dX, dY)

    -- calculate the angle from deltaY and deltaX
    local angle = math.atan2(deltaX, -deltaY)

    -- normalize the angle
    if angle > 0 then
        angle = PI2 - angle
    else
        angle = -angle
    end

    return angle, distance
end
