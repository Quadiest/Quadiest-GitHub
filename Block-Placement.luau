local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local PlaceBlockEvent = ReplicatedStorage:WaitForChild("PlaceBlockEvent")
local Tool = script.Parent
local Player = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local Character = Player.Character or Player.CharacterAdded:Wait()
local RootPart = Character:WaitForChild("HumanoidRootPart")
local Configuration = {}
Configuration.GridSize = 3
Configuration.MaxDistance = 18
Configuration.DepthSearch = -10
Configuration.Cooldown = 0.1
Configuration.GhostAlpha = 0.6
Configuration.GhostValidColor = Color3.fromRGB(100, 255, 100)
Configuration.GhostInvalidColor = Color3.fromRGB(255, 100, 100)
Configuration.LerpSpeed = 25
local CurrentState = {}
CurrentState.LastPlaceTime = 0
CurrentState.PendingPosition = nil
CurrentState.IsPlacementValid = false
CurrentState.RotationAngle = 0
CurrentState.ActiveConnections = {}
local PlacementSound = Instance.new("Sound")
PlacementSound.SoundId = "rbxassetid://876939830"
PlacementSound.Volume = 0.5
PlacementSound.Parent = Tool
local function CreateRaycastFilter()
local filter = RaycastParams.new()
filter.FilterType = Enum.RaycastFilterType.Exclude
filter.FilterDescendantsInstances = {Character}
filter.IgnoreWater = true
return filter
end
local function CreateOverlapFilter()
local filter = OverlapParams.new()
filter.FilterType = Enum.RaycastFilterType.Exclude
filter.FilterDescendantsInstances = {Character}
filter.MaxParts = 100
return filter
end
local PrimaryRaycastFilter = CreateRaycastFilter()
local PrimaryOverlapFilter = CreateOverlapFilter()
local function GetSnappedCoordinate(value)
local scaledValue = value / Configuration.GridSize
local roundedValue = math.floor(scaledValue + 0.5)
return roundedValue * Configuration.GridSize
end
local function SnapVectorToGrid(vector)
local snapX = GetSnappedCoordinate(vector.X)
local snapY = GetSnappedCoordinate(vector.Y)
local snapZ = GetSnappedCoordinate(vector.Z)
return Vector3.new(snapX, snapY, snapZ)
end
local function ValidatePlacementArea(targetPosition)
local targetCFrame = CFrame.new(targetPosition)
local tolerance = Vector3.new(0.1, 0.1, 0.1)
local blockSize = Vector3.one * Configuration.GridSize
local searchBounds = blockSize - tolerance
local intersectingParts = workspace:GetPartBoundsInBox(targetCFrame, searchBounds, PrimaryOverlapFilter)
return #intersectingParts == 0
end
local function InitializeGhostPart()
local part = Instance.new("Part")
part.Name = "PlacementGhost"
part.Anchored = true
part.CanCollide = false
part.CanQuery = false
part.CanTouch = false
part.CastShadow = false
part.Size = Vector3.one * Configuration.GridSize
part.Material = Enum.Material.SmoothPlastic
part.Transparency = Configuration.GhostAlpha
local highlight = Instance.new("SelectionBox")
highlight.Adornee = part
highlight.LineThickness = 0.04
highlight.Color3 = Color3.new(1, 1, 1)
highlight.Parent = part
return part
end
local GhostInstance = InitializeGhostPart()
local function UpdateGhostAppearance(targetPosition, deltaTime)
if not GhostInstance.Parent then
GhostInstance.Parent = workspace
GhostInstance.Position = targetPosition
end
local rotationMatrix = CFrame.Angles(0, math.rad(CurrentState.RotationAngle), 0)
local targetCFrame = CFrame.new(targetPosition) * rotationMatrix
GhostInstance.CFrame = GhostInstance.CFrame:Lerp(targetCFrame, math.min(1, deltaTime * Configuration.LerpSpeed))
if CurrentState.IsPlacementValid then
GhostInstance.Color = Configuration.GhostValidColor
else
GhostInstance.Color = Configuration.GhostInvalidColor
end
end
local function HideGhostVisuals()
GhostInstance.Parent = nil
end
local function FindAnchorFromGround(origin)
local downwardVector = Vector3.new(0, Configuration.DepthSearch, 0)
local result = workspace:Raycast(origin, downwardVector, PrimaryRaycastFilter)
if not result then
return nil
end
local offsetNormal = result.Normal * (Configuration.GridSize * 0.5)
return SnapVectorToGrid(result.Position - offsetNormal)
end
local function FindAnchorFromEnvironment(origin)
local parts = workspace:GetPartBoundsInRadius(origin, Configuration.MaxDistance, PrimaryOverlapFilter)
local closestAnchor = nil
local minDistance = math.huge
for index, part in ipairs(parts) do
local dist = (part.Position - origin).Magnitude
if dist < minDistance then
minDistance = dist
closestAnchor = SnapVectorToGrid(part.Position)
end
end
return closestAnchor
end
local function ResolvePlacementPosition(mouseHit, mouseRay)
local rootPosition = RootPart.Position
if mouseHit then
local normalOffset = mouseHit.Normal * (Configuration.GridSize * 0.5)
return SnapVectorToGrid(mouseHit.Position + normalOffset)
end
local validAnchor = FindAnchorFromGround(rootPosition) or FindAnchorFromEnvironment(rootPosition)
if not validAnchor then
return nil
end
local rayDir = mouseRay.Direction
if math.abs(rayDir.Y) < 0.001 then
return nil
end
local planeDistance = (validAnchor.Y - mouseRay.Origin.Y) / rayDir.Y
local projectedHit = mouseRay.Origin + (rayDir * planeDistance)
local planarDifference = (projectedHit - rootPosition) * Vector3.new(1, 0, 1)
if planarDifference.Magnitude < 0.001 then
return nil
end
local placementDirection = planarDifference.Unit
local maxIterations = math.floor(Configuration.MaxDistance / Configuration.GridSize)
for stepIndex = 1, maxIterations do
local stepOffset = placementDirection * (Configuration.GridSize * stepIndex)
local candidatePosition = SnapVectorToGrid(validAnchor + stepOffset)
local distanceFromRoot = (candidatePosition - rootPosition).Magnitude
if distanceFromRoot > Configuration.MaxDistance then
break
end
if ValidatePlacementArea(candidatePosition) then
return candidatePosition
end
end
return nil
end
local function CastViewportRay()
local mousePos = UserInputService:GetMouseLocation()
local viewportRay = Camera:ViewportPointToRay(mousePos.X, mousePos.Y)
local distanceToRoot = (RootPart.Position - viewportRay.Origin).Magnitude
local rayDistance = distanceToRoot + Configuration.MaxDistance
local result = workspace:Raycast(viewportRay.Origin, viewportRay.Direction * rayDistance, PrimaryRaycastFilter)
return result, viewportRay
end
local function TriggerBlockPlacement()
if not CurrentState.PendingPosition then
return
end
if not CurrentState.IsPlacementValid then
return
end
local timeNow = os.clock()
if timeNow - CurrentState.LastPlaceTime < Configuration.Cooldown then
return
end
CurrentState.LastPlaceTime = timeNow
PlacementSound:Play()
local finalCFrame = CFrame.new(CurrentState.PendingPosition) * CFrame.Angles(0, math.rad(CurrentState.RotationAngle), 0)
PlaceBlockEvent:InvokeServer(finalCFrame)
end
local function ProcessKeyboardInput(input, processed)
if processed then
return
end
if input.UserInputState ~= Enum.UserInputState.Begin then
return
end
if input.KeyCode == Enum.KeyCode.R then
CurrentState.RotationAngle = (CurrentState.RotationAngle + 90) % 360
end
end
local function ProcessMouseInput(input, processed)
if processed then
return
end
if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
return
end
if input.UserInputState == Enum.UserInputState.Begin then
TriggerBlockPlacement()
end
end
local function ClearToolConnections()
for key, connection in pairs(CurrentState.ActiveConnections) do
if connection then
connection:Disconnect()
end
end
table.clear(CurrentState.ActiveConnections)
end
local function ExecuteRenderStep(deltaTime)
local hitResult, rayResult = CastViewportRay()
local targetPosition = ResolvePlacementPosition(hitResult, rayResult)
CurrentState.PendingPosition = targetPosition
if not targetPosition then
HideGhostVisuals()
CurrentState.IsPlacementValid = false
return
end
local visualPosition = targetPosition
if hitResult then
visualPosition = visualPosition - (hitResult.Normal * Configuration.GridSize)
end
CurrentState.IsPlacementValid = ValidatePlacementArea(targetPosition)
UpdateGhostAppearance(visualPosition, deltaTime)
end
local function HandleToolEquip()
CurrentState.ActiveConnections.RenderUpdate = RunService.RenderStepped:Connect(ExecuteRenderStep)
CurrentState.ActiveConnections.MouseClick = UserInputService.InputBegan:Connect(ProcessMouseInput)
CurrentState.ActiveConnections.KeyPress = UserInputService.InputBegan:Connect(ProcessKeyboardInput)
CurrentState.RotationAngle = 0
end
local function HandleToolUnequip()
ClearToolConnections()
CurrentState.PendingPosition = nil
CurrentState.IsPlacementValid = false
CurrentState.RotationAngle = 0
HideGhostVisuals()
end
Tool.Equipped:Connect(HandleToolEquip)
Tool.Unequipped:Connect(HandleToolUnequip)
