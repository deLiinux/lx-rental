local rentalInstance
local targetDistance = Config.targetDistance
local spawnRange = Config.spawnRange
local despawnRange = Config.despawnRange
local spawnedIndexes = {}
local Rental = {}
Rental.__index = Rental

function Rental:new(config)
    local self = setmetatable({}, Rental)
    self.config = config
    self.peds = {}
    return self
end

function Rental:loadModel(model)
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(50) end
end

function Rental:loadAnimDict(dict)
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do Wait(10) end
end

function Rental:spawnBlips(locations)
    for i, loc in ipairs(locations) do
        local coords = loc.coords
        local groundZ = self:getGroundZ(coords)
        local blip = AddBlipForCoord(coords.x, coords.y, groundZ or coords.z)
        SetBlipSprite(blip, 225)
        SetBlipColour(blip, 3)
        SetBlipScale(blip, 0.8)
        SetBlipAsShortRange(blip, true)

        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString("Vehicle Rental")
        EndTextCommandSetBlipName(blip)

        self.peds[i .. "_blip"] = blip
    end
end

function Rental:spawnPeds(locations)
    for i, loc in ipairs(locations) do
        self:spawnPed(i, loc)
    end
end

local isSpawning = {}

function Rental:spawnPed(index, data)
    if isSpawning[index] then return end
    isSpawning[index] = true

    local model = joaat(data.pedModel)
    self:loadModel(model)

    local groundZ = self:getGroundZ(data.coords)
    local ped = CreatePed(4, model, data.coords.x, data.coords.y, groundZ, data.coords.w, false, true)

    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)

    self.peds[index] = ped
    isSpawning[index] = false

    self:updatePedTarget(index, data)
end

function Rental:updatePedTarget(index, data)
    exports.ox_target:removeEntity(self.peds[index])

    local targets = {{
        icon = 'fas fa-car',
        label = 'Rent a Vehicle',
        distance = targetDistance,
        onSelect = function() self:showRentalMenu(index, data.vehicles) end
    }}

    exports.ox_target:addLocalEntity(self.peds[index], targets)
end

function Rental:isSpawnPointFree(coords, radius)
    local vehicles = GetGamePool('CVehicle')
    for _, vehicle in ipairs(vehicles) do
        if #(GetEntityCoords(vehicle) - coords) < radius then
            return false
        end
    end
    return true
end

function Rental:getFreeSpawnPoint(location)
    local spawnRadius = 3.0
    for _, point in ipairs(location.spawnPoints) do
        local coords = point.xyz or point
        if self:isSpawnPointFree(coords, spawnRadius) then
            return point
        end
    end
    return nil
end

function Rental:spawnVehicle(model, coords, heading, plate)
    local vehModel = joaat(model)
    self:loadModel(vehModel)

    local vehicle = CreateVehicle(vehModel, coords.x, coords.y, coords.z, heading, true, false)
    if not DoesEntityExist(vehicle) then
        print("Failed to create vehicle.")
        return
    end

    SetVehicleNumberPlateText(vehicle, plate)
    SetVehicleOnGroundProperly(vehicle)
    SetVehicleDirtLevel(vehicle, 0.0)
    WashDecalsFromVehicle(vehicle, 1.0)

    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    SetNetworkIdCanMigrate(netId, true)

    TriggerServerEvent('rental:server:giveKeys', netId)
end

function Rental:showRentalMenu(locationIndex, vehicles)
    local ped = self.peds[locationIndex]
    if DoesEntityExist(ped) then
        PlayAmbientSpeech1(ped, 'GENERIC_HI', 'SPEECH_PARAMS_FORCE_NORMAL')
    end

    local vehicleOptions = {}
    for _, v in pairs(vehicles) do
        table.insert(vehicleOptions, { label = string.format("%s ($%d)", v.label, v.price), value = v.model })
    end

    local input = lib.inputDialog('Select a vehicle to rent', {
        {
            type = 'select',
            label = 'Vehicle',
            options = vehicleOptions,
            required = true
        }
    })

    if not input or not input[1] then
        if DoesEntityExist(ped) then
            Wait(100)
            PlayAmbientSpeech1(ped, 'GENERIC_FUCK_YOU', 'SPEECH_PARAMS_FORCE')
        end
        return
    end

    local paymentInput = lib.inputDialog('Choose Payment Method', {
        {
            type = 'select',
            label = 'Payment',
            options = {
                { label = 'Bank', value = 'bank' },
                { label = 'Cash', value = 'cash' }
            },
            required = true
        }
    })

    if not paymentInput or not paymentInput[1] then
        return
    end

    local selectedVehicle
    for _, v in pairs(vehicles) do
        if v.model == input[1] then
            selectedVehicle = v
            break
        end
    end

    local location = Config.RentalLocations[locationIndex]
    local spawnPoint = self:getFreeSpawnPoint(location)

    if selectedVehicle and spawnPoint then
        self:playInteractionAnimation(ped)
        local success = lib.progressBar({
            duration = 3000,
            label = 'Closing deal...',
            useWhileDead = false,
            canCancel = false,
            disable = { move = true, car = true, combat = true }
        })

        self:clearAnimations(ped)

        if success then
            if DoesEntityExist(ped) then
                PlayAmbientSpeech1(ped, 'GENERIC_THANKS', 'SPEECH_PARAMS_FORCE_SHOUTED_CRITICAL')
            end

            TriggerServerEvent('rental:server:rentVehicle', {
                location = locationIndex,
                vehicle = selectedVehicle,
                paymentType = paymentInput[1]
            })
        end
    else
        lib.notify({ title = 'Rental', description = 'All parking spots are occupied.', type = 'error' })
    end
end


RegisterNetEvent('rental:client:requestSpawnPoint', function(model, plate, locationIndex)
    if not rentalInstance then return end
    local location = Config.RentalLocations[locationIndex]
    if not location then return end

    local spawnPoint = rentalInstance:getFreeSpawnPoint(location)
    if spawnPoint then
        local heading = spawnPoint.w or 0.0
        rentalInstance:spawnVehicle(model, spawnPoint, heading, plate)
    end
end)


function Rental:playInteractionAnimation(ped)
    local animDict = 'amb@world_human_hang_out_street@male_a@idle_a'
    local animName = 'idle_a'
    self:loadAnimDict(animDict)

    local playerPed = PlayerPedId()
    if DoesEntityExist(ped) then TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, -1, 1, 0, false, false, false) end
    TaskPlayAnim(playerPed, animDict, animName, 8.0, -8.0, -1, 1, 0, false, false, false)
end

function Rental:clearAnimations(ped)
    local playerPed = PlayerPedId()
    ClearPedTasks(playerPed)
    if DoesEntityExist(ped) then ClearPedTasks(ped) end
end

function Rental:getGroundZ(coords)
    local foundGround, z = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 10.0, 0)
    return foundGround and z or coords.z
end


local function isNear(coords)
    local playerCoords = GetEntityCoords(PlayerPedId())
    return #(playerCoords - vector3(coords.x, coords.y, coords.z)) < spawnRange
end

local function isTooFar(coords)
    local playerCoords = GetEntityCoords(PlayerPedId())
    return #(playerCoords - vector3(coords.x, coords.y, coords.z)) > despawnRange
end

local function handlePedSpawning()
    if not rentalInstance then return end

    for i, loc in ipairs(Config.RentalLocations) do
        if isNear(loc.coords) and not spawnedIndexes[i] then
            rentalInstance:spawnPed(i, loc)
            spawnedIndexes[i] = true
        elseif spawnedIndexes[i] and isTooFar(loc.coords) then
            local ped = rentalInstance.peds[i]
            if DoesEntityExist(ped) then DeleteEntity(ped) end
            exports.ox_target:removeEntity(ped)
            rentalInstance.peds[i] = nil
            spawnedIndexes[i] = false
        end
    end
end

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        rentalInstance = Rental:new(Config)

        local locations = Config.RentalLocations
        rentalInstance:spawnBlips(locations)

        CreateThread(function()
            while true do
                handlePedSpawning()
                Wait(2000)
            end
        end)
    end
end)

