#version 450

#extension GL_ARB_compute_variable_group_size: enable
#extension GL_ARB_gpu_shader_int64: require
#extension GL_NV_shader_atomic_int64: require

#include <Assets/Shaders/Compute/Templates/modelStructs.glsl>

layout (local_size_variable) in;

layout (std430, binding = 0) buffer DepthBuffer { uint64_t		depthBuffer[]; };
layout (std430, binding = 1) buffer PointBuffer { PointModel	points[]; };

uniform mat4	cameraMatrix;
uniform uint	numPoints;
uniform uint	offset;
uniform uvec2	windowSize;


void main()
{
	const uint index = gl_GlobalInvocationID.x;
	if (index >= numPoints) return;

	// Projection: 3D to 2D
	vec4 projectedPoint	= cameraMatrix * (points[index].point);
	projectedPoint.xyz /= projectedPoint.w;

	if (projectedPoint.w <= 0.0 || projectedPoint.x < -1.0 || projectedPoint.x > 1.0 || projectedPoint.y < -1.0 || projectedPoint.y > 1.0) 
	{
		return;
	}

	ivec2 windowPosition			= ivec2((projectedPoint.xy * 0.5f + 0.5f) * windowSize);
	uint pointIndex					= windowPosition.y * windowSize.x + windowPosition.x;
	uint64_t distanceInt			= floatBitsToUint(projectedPoint.w);				// Another way: multiply distance by 10^x. It is more precise when x is larger
	const uint64_t depthDescription = uint(index +  offset) | (distanceInt << 32);		// Distance to most significant bits. w saves the point index (mainly for multiple batch methodology)

	atomicMin(depthBuffer[pointIndex], depthDescription);								// AtomicMin: inf vs distance + index for the atomicMin call in this index
}