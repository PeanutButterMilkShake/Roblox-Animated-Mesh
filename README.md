# Roblox-Animated-Mesh
Animated mesh service to implement shape keys

# How to use:
## Create animated mesh:
```luau
local animatedMesh = AnimatedMeshService.CreateAnimatedMesh(87610914005922) -- pass the mesh Id NOT asset Id
```

## Setup shapekeys:
```luau
--Use the blender script to add shapekey data to clipboard
--I reccomend storing shapekey data in a string value instance
animatedMesh:CreateShapeKeys(script.ShapeKeyData.Value)
```

## Set shape key values
```luau
--Arg 1 is the name of the shape key MUST match shape key name inside of blender
--Arg 2 is the new value for the shape key
animatedMesh:SetShapeKeyValue("Cube", 1)
```

## Animate shape key values
```luau
--Arg 1 is the name of the shape key MUST match shape key name inside of blender
--Arg 2 is the animation function
animatedMesh:AnimateShapeKey("Cube", function(t: number)
	local frac = t * 0.5 % 1
	local value = frac < 0.5 and frac * 2 or 2 - frac * 2
	return value
end)
```

## Edit mesh properties
All mesh properties are inside animatedMesh.meshPart

## Client-Server replication
As you may know, the editable mesh does not currently replicate to clients but do not worry the module will handle this too.
