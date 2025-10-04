--!strict

--Shape Key type for QoL
export type ShapeKey = {
	vertices: {[number]: Vector3},
	alpha: number
}

--Animated Mesh type for QoL
export type AnimatedMesh = {
	-- Properties
	meshPart: MeshPart,
	editableMesh: EditableMesh,
	shapeKeys: {[string]: ShapeKey},
	meshId: number,
	
	replicating: boolean,
	
	-- Functions
	CreateNewShapeKey: (self: AnimatedMesh, shapeKeyName: string, shapeKeyData: string) -> (),
	SetShapeKeyValue: (self: AnimatedMesh, shapeKeyName: string, alpha: number) -> (),
	AnimateShapeKey: (self: AnimatedMesh, shapeKeyName: string, animationFunction: (time: number) -> ()) -> (),
	
	_ClientCreateNewShapeKey: (self: AnimatedMesh, shapeKeyName: string, shapeKeyData: string) -> (),
	_ClientSetShapeKeyValue: (self: AnimatedMesh, shapeKeyName: string, alpha: number) -> (),
	_ClientAnimateShapeKey: (self: AnimatedMesh, shapeKeyName: string, animationFunction: (time: number) -> ()) -> (),
}

--Services
local AssetService = game:GetService("AssetService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

--RemoteEvent
local RemoteEvent = script.RemoteEvent

--Constants
local VERTEX_TOLERANCE = 0.01

--Server side meshes
local meshes = {}

--Mesh setup
local AnimatedMeshService = {}
AnimatedMeshService.__index = AnimatedMeshService

--Stop mesh replication checks
if RunService:IsServer() then
	RemoteEvent.OnServerEvent:Connect(function(_, meshId)
		meshes[meshId].replicating = false
	end)
end

--Create new animated mesh
function AnimatedMeshService.CreateAnimatedMesh(assetId: number): AnimatedMesh
	local self = setmetatable({}, AnimatedMeshService) :: any
	
	--Create editable mesh
	self.editableMesh = AssetService:CreateEditableMeshAsync(Content.fromAssetId(assetId))
	self.shapeKeys = {}

	--Setup mesh part
	self.meshId = math.random(-math.huge, math.huge)
	self.meshPart = Instance.new("MeshPart")
	self.meshPart.Anchored = true
	self.meshPart.Size = Vector3.one
	self.meshPart.Position = Vector3.new(0,6,0)
	self.meshPart.Parent = workspace
	
	self.replicating = false
	
	--Add mesh to list of server side meshes
	meshes[self.meshId] = self
	self.meshPart:SetAttribute("Id", self.meshId)

	--Tell client to change client side meshes on property change
	self.changedConnection = self.meshPart.Changed:Connect(function(property)
		RemoteEvent:FireAllClients("PropertyChanged", self.meshId, property, self.meshPart[property])
	end)
	
	--Tell client to destroy client side meshes on destroy
	self.meshPart.Destroying:Connect(function()
		RemoteEvent:FireAllClients("Destroy", self.meshId)
		
		--Cleanup
		self.meshPart:Destroy()
		self.editableMesh:Destroy()
		self.changedConnection:Disconnect()
		self = nil
	end)
	
	self.replicating = true
	
	--Wait for client to replicate mesh
	RemoteEvent:FireAllClients("WaitForReplication", self.meshId)
	while self.replicating do
		task.wait()
	end
	
	self.replicating = true
	
	--Create client sided mesh
	RemoteEvent:FireAllClients("Create", assetId, self.meshId, self.meshPart)
	while self.replicating do
		task.wait()
	end

	return self
end

--Wait for replication and tell client to change client sided mesh shape keys
function AnimatedMeshService.SetShapeKeyValue(self: AnimatedMesh, shapeKeyName: string, alpha: number)
	while self.replicating do--Replication check
		task.wait()
	end
	
	RemoteEvent:FireAllClients("SetShapeKey", self.meshId, shapeKeyName, alpha)
end

--Change shape key values on client side mesh
function AnimatedMeshService._ClientSetShapeKeyValue(self: AnimatedMesh, shapeKeyName: string, alpha: number)
	self.shapeKeys[shapeKeyName].alpha = alpha --Set to new alpha
	local vertices = self.editableMesh:GetVertices() --Get list of vertex Ids

	for _, vertexId in vertices do --Loop through all vertices
		local vertexPosition = self.shapeKeys.Basis.vertices[tostring(vertexId)] --Get base vertex position

		for shapeKeyName, shapeKey in self.shapeKeys do --Loop through all shape keys except basis
			if shapeKeyName == "basis" then continue end
			vertexPosition += shapeKey.vertices[tostring(vertexId)] * shapeKey.alpha --Add shape key delta to vertex position
		end

		self.editableMesh:SetPosition(vertexId, vertexPosition)--Set vertex position
	end
end

--Perform animation func and tell client to animate client sided mesh
function AnimatedMeshService.AnimateShapeKey(self: AnimatedMesh, shapeKeyName: string, animationFunction)
	while self.replicating do--Replication check
		task.wait()
	end
	
	RunService.Heartbeat:Connect(function()
		if self.replicating then return end--Replication check
		
		local alpha = animationFunction(time())--Perform animation func
		RemoteEvent:FireAllClients("AnimateShapeKey", self.meshId, shapeKeyName, alpha)--Animate client sided mesh
	end)
end

--Animate client sided mesh
function AnimatedMeshService._ClientAnimateShapeKey(self: AnimatedMesh, shapeKeyName: string, alpha: number)
	self:_ClientSetShapeKeyValue(shapeKeyName, alpha)--Set mesh shapekeys
end

--Create server sided shapekeys
function AnimatedMeshService.CreateShapeKeys(self: AnimatedMesh, shapeKeyData: string)
	while self.replicating do--Replication check
		task.wait()
	end
	
	self.replicating = true

	--Parse json data into readable luau table
	local success, shapeKeysData = pcall(HttpService.JSONDecode, HttpService, shapeKeyData)
	if not success then --Error check
		print("JSON Error:", shapeKeysData)
		error("Failed to parse JSON")
	end

	--Shape key tables
	local shapeKeys: {ShapeKey} = {}
	local shapeKeyVerts: {{}} = {}

	--Loop through 
	for i, shapeKey in shapeKeysData do
		local newShapeKeyVerts: {} = {}
		local newShapeKey: ShapeKey = {alpha = 0, vertices = {}}
		for _, vector in shapeKey do
			table.insert(newShapeKeyVerts, Vector3.new(vector[1], vector[2], vector[3])) --Convert list of strings into vec3
		end

		shapeKeys[i] = newShapeKey --Setup ShapeKey list
		shapeKeyVerts[i] = newShapeKeyVerts --Insert into ShapeKeyVert list
	end

	--Convert blender vert Ids to editable mesh vert Ids

	for i, meshVertId in self.editableMesh:GetVertices() do --Loop through all vertices in editable mesh
		for j, vert in shapeKeyVerts["Basis"] do --Loop through all vec3s in basis shapekey list
			--Check if vertex is within tolerance range
			if (vert - self.editableMesh:GetPosition(meshVertId)).Magnitude <= VERTEX_TOLERANCE then
				for k, shapeKey in shapeKeyVerts do --Loop through all shapekeys
					shapeKeys[k].vertices[meshVertId] = shapeKeyVerts[k][j] --Set vertex position with correct editable mesh Id
				end
			end
		end
	end

	--Tell client to replicate shapekeys
	RemoteEvent:FireAllClients("UpdateShapeKeys", self.meshId, shapeKeys)

	while self.replicating do --Replication check
		task.wait()
	end

	self.shapeKeys = shapeKeys
end

--Client sided stuff
if RunService:IsClient() then
	local meshes = {} --Initialize meshes list
	
	--Add a client sided mesh
	local function addMesh(assetId: number, meshId: number, serverMesh: MeshPart)
		serverMesh:Destroy() --Destroy server sided mesh
		
		local animatedMesh: AnimatedMesh = setmetatable({}, AnimatedMeshService) :: any --Create new client animated mesh
		
		--Setup editable mesh
		animatedMesh.editableMesh = AssetService:CreateEditableMeshAsync(Content.fromAssetId(assetId))
		animatedMesh.shapeKeys = {}

		--Setup mesh part
		animatedMesh.meshPart = AssetService:CreateMeshPartAsync(Content.fromObject(animatedMesh.editableMesh))
		animatedMesh.meshPart.Anchored = true
		animatedMesh.meshPart.Size = Vector3.one
		animatedMesh.meshPart.Position = Vector3.new(0,6,0)
		animatedMesh.meshPart.Parent = workspace
		
		meshes[meshId] = animatedMesh --Add mesh to mesh list
		
		RemoteEvent:FireServer(meshId) --Tell server mesh finished replicating
	end
	
	RemoteEvent.OnClientEvent:Connect(function(info: string, ...)
		if info == "Create" then --Create client sided mesh
			local assetId, meshId, serverMesh = ...
			addMesh(assetId, meshId, serverMesh)
			
		elseif info == "SetShapeKey" then --Set shapekey values
			local args = {...}
			local meshId = args[1]
			local shapeKey = args[2]
			local alpha = args[3]	
			
			repeat task.wait() until meshes[meshId] ~= nil --Wait until mesh exists on client
			
			meshes[meshId]:_ClientSetShapeKeyValue(shapeKey, alpha)
			
		elseif info == "AnimateShapeKey" then --Animate client sided mesh
			local meshId, shapeKey, alpha = ...
			
			repeat task.wait() until meshes[meshId] ~= nil --Wait until mesh exists on client
			
			meshes[meshId]:_ClientAnimateShapeKey(shapeKey, alpha)
			
		elseif info == "UpdateShapeKeys" then --Update shapekey lists
			local meshId, shapeKeys = ...
			
			repeat task.wait() until meshes[meshId] ~= nil --Wait until mesh exists on client
			
			meshes[meshId].shapeKeys = shapeKeys
			RemoteEvent:FireServer(meshId) --Tell server mesh finished replicating
			
		elseif info == "PropertyChanged" then --Change mesh part property
			local meshId, property, value = ...
			
			repeat task.wait() until meshes[meshId] ~= nil --Wait until mesh exists on client
			
			local success, err = pcall(function() --Error check to remove read-only errors
				meshes[meshId].meshPart[property] = value
			end)
			
		elseif info == "WaitForReplication" then --Wait until mesh replicates on client
			local meshId = ...
			local connection
			local found = false
			connection = workspace.ChildAdded:Connect(function(instance) --Check for instance added
				if instance:GetAttribute("Id") == meshId then --Check for mesh id
					RemoteEvent:FireServer(meshId) --Tell server mesh finished replicating
					
					--Cleanup
					connection:Disconnect()
					found = true
				end
			end)
			
			--Just incase attribute was not replicated before we checked
			while not found do
				for _, instance in workspace:GetChildren() do
					if instance:GetAttribute("Id") == meshId then --Check for mesh id
						RemoteEvent:FireServer(meshId) --Tell server mesh finished replicating
						
						--Cleanup
						connection:Disconnect()
						found = true
					end
				end
			end
		elseif info == "Destroy" then --Destroy client sided mesh
			local meshId = ...
			
			repeat task.wait() until meshes[meshId] ~= nil --Wait until mesh exists on client
			
			--Cleanup
			meshes[meshId].meshPart:Destroy()
			meshes[meshId].editableMesh:Destroy()
			meshes[meshId] = nil
		end
	end)
end

return AnimatedMeshService
