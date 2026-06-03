--!strict

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- References
local PlaceBlockEvent = ReplicatedStorage:WaitForChild("PlaceBlockEvent")
local Tool = script.Parent

local Player = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- Constants
local GRID_SIZE = 3
local MAX_PLACE_DISTANCE = 18
local GROUND_SEARCH_DEPTH = -10
local PLACE_COOLDOWN = 0.05

local BLOCK_SIZE = Vector3.one * GRID_SIZE
local PLANAR_MASK = Vector3.new(1, 0, 1)

local Character = Player.Character or Player.CharacterAdded:Wait()
local RootPart = Character:WaitForChild("HumanoidRootPart") :: BasePart

local LastPlacementTime = 0
local PendingPlacement: Vector3?

local Connections: {[string]: RBXScriptConnection} = {}

local RaycastParams = RaycastParams.new()
RaycastParams.FilterType = Enum.RaycastFilterType.Exclude
RaycastParams.FilterDescendantsInstances = {Character}

local OverlapParams = OverlapParams.new()
OverlapParams.FilterType = Enum.RaycastFilterType.Exclude
OverlapParams.FilterDescendantsInstances = {Character}

local function roundToGrid(value: number): number
	return math.floor(value / GRID_SIZE + 0.5) * GRID_SIZE
end

local function snapToGrid(position: Vector3): Vector3
	return Vector3.new(
		roundToGrid(position.X),
		roundToGrid(position.Y),
		roundToGrid(position.Z)
	)
end

local function isPlacementAreaEmpty(position: Vector3): boolean
	local parts = workspace:GetPartBoundsInBox(
		CFrame.new(position),
		BLOCK_SIZE - Vector3.new(0.1, 0.1, 0.1),
		OverlapParams
	)

	return #parts == 0
end

local function createGhost(): Part
	local ghost = Instance.new("Part")

	ghost.Name = "PlacementGhost"
	ghost.Anchored = true
	ghost.CanCollide = false
	ghost.CanQuery = false
	ghost.CanTouch = false

	ghost.Size = BLOCK_SIZE
	ghost.Material = Enum.Material.ForceField
	ghost.Color = Color3.fromRGB(240, 240, 240)
	ghost.Transparency = 1

	local selectionBox = Instance.new("SelectionBox")
	selectionBox.Adornee = ghost
	selectionBox.LineThickness = 0.03
	selectionBox.Color3 = Color3.new()
	selectionBox.SurfaceTransparency = 1
	selectionBox.Parent = ghost

	return ghost
end

local Ghost = createGhost()

local function showGhost(position: Vector3)
	Ghost.Position = position

	if not Ghost.Parent then
		Ghost.Parent = workspace
	end
end

local function hideGhost()
	Ghost.Parent = nil
end

local function findGroundAnchor(position: Vector3): Vector3?
	local result = workspace:Raycast(
		position,
		Vector3.new(0, GROUND_SEARCH_DEPTH, 0),
		RaycastParams
	)

	if not result then
		return nil
	end

	return snapToGrid(
		result.Position - result.Normal * (GRID_SIZE * 0.5)
	)
end

local function findNearbyAnchor(position: Vector3): Vector3?
	local nearbyParts = workspace:GetPartBoundsInRadius(
		position,
		MAX_PLACE_DISTANCE,
		OverlapParams
	)

	local nearestAnchor: Vector3?
	local nearestDistance: number?

	for _, part in nearbyParts do
		local distance = (part.Position - position).Magnitude

		if not nearestDistance or distance < nearestDistance then
			nearestDistance = distance
			nearestAnchor = snapToGrid(part.Position)
		end
	end

	return nearestAnchor
end

local function calculatePlacementPosition(
	mouseHit: RaycastResult?,
	mouseRay: Ray
): Vector3?

	local origin = RootPart.Position

	if mouseHit then
		return snapToGrid(
			mouseHit.Position + mouseHit.Normal * (GRID_SIZE * 0.5)
		)
	end

	local anchor =
		findGroundAnchor(origin)
		or findNearbyAnchor(origin)

	if not anchor then
		return nil
	end

	local rayOrigin = mouseRay.Origin
	local rayDirection = mouseRay.Direction

	if math.abs(rayDirection.Y) < 0.001 then
		return nil
	end

	local planeDistance =
		(anchor.Y - rayOrigin.Y) / rayDirection.Y

	local projectedPoint =
		rayOrigin + rayDirection * planeDistance

	local planarOffset =
		(projectedPoint - origin) * PLANAR_MASK

	if planarOffset.Magnitude < 0.001 then
		return nil
	end

	local placementDirection = planarOffset.Unit

	for step = 1, math.floor(MAX_PLACE_DISTANCE / GRID_SIZE) do
		local candidatePosition = snapToGrid(
			anchor + placementDirection * GRID_SIZE * step
		)

		if (candidatePosition - origin).Magnitude > MAX_PLACE_DISTANCE then
			break
		end

		if isPlacementAreaEmpty(candidatePosition) then
			return candidatePosition
		end
	end

	return nil
end

local function getMouseRaycast(): (RaycastResult?, Ray)
	local mousePosition = UserInputService:GetMouseLocation()

	local mouseRay = Camera:ViewportPointToRay(
		mousePosition.X,
		mousePosition.Y
	)

	local characterDistance =
		(RootPart.Position - mouseRay.Origin).Magnitude

	local result = workspace:Raycast(
		mouseRay.Origin,
		mouseRay.Direction * (characterDistance + MAX_PLACE_DISTANCE),
		RaycastParams
	)

	return result, mouseRay
end

local function placeBlock()
	if not PendingPlacement then
		return
	end

	local currentTime = os.clock()

	if currentTime - LastPlacementTime < PLACE_COOLDOWN then
		return
	end

	LastPlacementTime = currentTime

	PlaceBlockEvent:InvokeServer(PendingPlacement)
end

local function disconnectAll()
	for _, connection in Connections do
		connection:Disconnect()
	end

	table.clear(Connections)
end

local function onEquipped()
	Connections.UpdateLoop = RunService.PostSimulation:Connect(function()
		local mouseHit, mouseRay = getMouseRaycast()

		local placementPosition =
			calculatePlacementPosition(mouseHit, mouseRay)

		PendingPlacement = placementPosition

		if not placementPosition then
			hideGhost()
			return
		end

		local previewPosition = placementPosition

		if mouseHit then
			previewPosition -= mouseHit.Normal * GRID_SIZE
		end

		showGhost(previewPosition)
	end)

	Connections.InputBegan = UserInputService.InputBegan:Connect(function(
		input: InputObject,
		gameProcessed: boolean
	)
		if gameProcessed then
			return
		end

		local inputType = input.UserInputType

		if inputType ~= Enum.UserInputType.MouseButton1
			and inputType ~= Enum.UserInputType.Touch
		then
			return
		end

		placeBlock()
	end)
end

local function onUnequipped()
	disconnectAll()
	PendingPlacement = nil
	hideGhost()
end

Tool.Equipped:Connect(onEquipped)
Tool.Unequipped:Connect(onUnequipped)
