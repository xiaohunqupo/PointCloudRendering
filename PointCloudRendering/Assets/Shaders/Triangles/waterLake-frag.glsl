#version 450

// ********** PARAMETERS & VARIABLES ***********

// ------------ Constraints ------------
#define EPSILON 0.0000001f
#define WAVE_STRENGTH .015f
#define MIX_LIGHTING_KAD 0.3f


// ------------ Geometry ------------
in vec3 position;
in vec3 normal;
in vec2 textCoord;
in vec4 shadowCoord;
in vec2 inReflectionTextCoord;
in vec4 clipSpace;

// ------------ Lighting ------------
in vec3 lightPos;
in vec3 lightDir;
in vec3 vertexToLightDir;
in vec3 viewDir;

// ----------- Matrices ------------
uniform mat4 mModelView;

// ----------- Materials ------------
uniform sampler2D texKadSampler;
uniform sampler2D texKsSampler;
uniform float materialScattering;				// Substitutes ambient lighting
uniform float shininess;

subroutine vec4 semiTransparentType(const vec4 color);
subroutine uniform semiTransparentType semiTransparentUniform;

uniform sampler2D texSemiTransparentSampler;

subroutine vec3 displacementType(const vec2 fTextCoord);
subroutine uniform displacementType displacementUniform;

uniform sampler2D texBumpSampler;

// Water textures
uniform sampler2D texTerrain;
uniform sampler2D texReflectionNoise;

// Animation
uniform float t;

// ----------- Lighting -------------
subroutine vec3 lightType(const vec3 fragKad, const vec3 fragKs, const vec3 fragNormal, const float shadowDiffuseFactor, const float shadowSpecFactor);
subroutine uniform lightType lightUniform;

// Colors
uniform vec3 Ia;
uniform vec3 Id;
uniform vec3 Is;

// Spot light
uniform float cosUmbra, cosPenumbra;      // Ranged angle where light just fades out
uniform float exponentS;

// ----- Lighting attenuation -----
subroutine float attenuationType(const float distance);
subroutine uniform attenuationType attenuationUniform;

// Basic model
uniform float c1, c2, c3;

// Ranged distance model
uniform float minDistance, maxDistance;

// Pixar model
uniform float fMax;
uniform float distC, fC;
uniform float exponentSE;
uniform float k0, k1;

// ---------------- Shadows ---------------

subroutine void depthTextureType(out float shadowDiffuseFactor, out float shadowSpecFactor, in vec2 texNoise);
subroutine uniform depthTextureType depthTextureUniform;

uniform float shadowMaxIntensity, shadowMinIntensity;						// Color range
uniform int minNeighborhood, maxNeighborhood;								// Index where matrix starts / ends
uniform int neighborhoodSize;															
uniform sampler2DShadow texShadowMapSampler;

layout (location = 0) out vec4 fColor;


// ********* FUNCTIONS ************

// ----------- Attenuation ------------

// Computes the attenuation which must be applied to the fragment color
// Distance is the length of the vector which goes from the fragment to the
// lighting position

subroutine(attenuationType)
float basicAttenuation(const float distance)
{
	return min(1.0f / (c1 + c2 * distance + c3 * pow(distance, 2)), 1.0f);
}

subroutine(attenuationType)
float rangedAttenuation(const float distance)
{
	return clamp((maxDistance - distance) / (maxDistance - minDistance), 0.0f, 1.0f);
}

subroutine(attenuationType)
float pixarAttenuation(const float distance)
{
	float attenuation;

	if (distance <= distC)
	{
		attenuation = fMax * exp(k0 * pow(distance / distC, -k1));
	}
	else
	{
		attenuation = fC * pow(distC / distance, exponentSE);
	}

	return attenuation;
}

// ----------- Lighting ----------

// Computes the diffuse term with lighting wrapping, if active
vec3 getDiffuse(const vec3 fragKad, const float dotLN) 
{
	return Id * fragKad * max((dotLN + materialScattering) / (1 + materialScattering), 0.9f);
}

// Computes the specular term with halfway vector
vec3 getSpecular(const vec3 fragKs, const float dotHN)
{
	return Is * fragKs * pow(max(dotHN, 0.0f), shininess);
}

// Computes the color related to any light source. Receives the attenuation variables from shadows
vec3 getDiffuseAndSpecular(const vec3 fragKad, const vec3 fragKs, const vec3 fragNormal, const float shadowDiffuseFactor, const float shadowSpecFactor)
{
	const vec3 n = normalize(fragNormal);
	const vec3 l = normalize(vertexToLightDir);
	const vec3 v = normalize(viewDir);
	const vec3 h = normalize(v + l);						// Halfway vector

	const float dotLN = clamp(dot(l, n), -1.0f, 1.0f);      // Prevents Nan values from acos
	const float dotHN = dot(h, n);

	const vec3 diffuse = getDiffuse(fragKad, dotLN);
	const vec3 specular = getSpecular(fragKs, dotHN);

	return shadowDiffuseFactor * (diffuse + shadowSpecFactor * specular);
}


// Computes the color from a light source, including diffuse and specular terms, as well as 
// ambient if necessary (ambient light). The result can be attenuated taking into account any
// model for such effect

subroutine(lightType)
vec3 ambientLight(const vec3 fragKad, const vec3 fragKs, const vec3 fragNormal, const float shadowDiffuseFactor, const float shadowSpecFactor)
{
	return Ia * fragKad;
}

subroutine(lightType)
vec3 pointLight(const vec3 fragKad, const vec3 fragKs, const vec3 fragNormal, const float shadowDiffuseFactor, const float shadowSpecFactor)
{
	const vec3 diffuseSpecular = getDiffuseAndSpecular(fragKad, fragKs, fragNormal, shadowDiffuseFactor, shadowSpecFactor);

	const float distance = distance(lightPos, position);
	const float attenuation = attenuationUniform(distance);

	return attenuation * diffuseSpecular;
}

subroutine(lightType)
vec3 directionalLight(const vec3 fragKad, const vec3 fragKs, const vec3 fragNormal, const float shadowDiffuseFactor, const float shadowSpecFactor)
{
	return getDiffuseAndSpecular(fragKad, fragKs, fragNormal, shadowDiffuseFactor, shadowSpecFactor);
}

subroutine(lightType)
vec3 spotLight(const vec3 fragKad, const vec3 fragKs, const vec3 fragNormal, const float shadowDiffuseFactor, const float shadowSpecFactor)
{
	const vec3 n = normalize(fragNormal);
	const vec3 l = normalize(vertexToLightDir);
	const vec3 v = normalize(viewDir);
	const vec3 d = normalize(lightDir);
	const vec3 h = normalize(v + l);						// Halfway vector

	const float dotLN = clamp(dot(l, n), -1.0f, 1.0f);      // Prevents Nan values from acos
	const float dotHN = dot(h, n);

	const vec3 diffuse = getDiffuse(fragKad, dotLN);
	const vec3 specular = getSpecular(fragKs, dotHN);

	const float distance = distance(lightPos, position);
	const float attenuation = attenuationUniform(distance);

	// Radial attenuation
	float sf = 0.0f;
	const float dotLD = dot(-l, d);

	if (dotLD >= cosPenumbra) 
	{
		sf = 1.0f;
	}
	else if (dotLD > cosUmbra) 
	{
		sf = pow((dotLD - cosUmbra) / (cosPenumbra - cosUmbra), exponentS);		
	}

	return sf * attenuation * shadowDiffuseFactor * (diffuse + shadowSpecFactor * specular);
}

subroutine(lightType)
vec3 rimLight(const vec3 fragKad, const vec3 fragKs, const vec3 fragNormal, const float shadowDiffuseFactor, const float shadowSpecFactor)
{
	const vec3 n = normalize(fragNormal);
	const vec3 v = normalize(-position);
	const float vdn = 1.0f - max(dot(v, n), 0.0f);

	return vdn * Ia;				
}


// ------------ Materials ------------

// ----- Diffuse & specular -----

// Obtains color from diffuse texture
vec4 getKad()
{
	return texture(texKadSampler, textCoord);
}

// Obtains color from specular texture
vec4 getKs()
{
	return texture(texKsSampler, textCoord);
}

// ----- Semitransparent -----

// Combines current fragment color with a semi-transparent texture, if any

subroutine(semiTransparentType)
vec4 semiTransparentTexture(const vec4 color)
{
	const vec4 semiTransparent = texture(texSemiTransparentSampler, textCoord);

	return vec4(mix(color.xyz, semiTransparent.xyz, semiTransparent.w), color.w);
}

subroutine(semiTransparentType)
vec4 noSemiTransparentTexture(const vec4 color)
{
	return color;
}

// ----- Displacement -----

// Retrieves the normal from a texture or just uses the input one if no texture is
// associated

subroutine(displacementType)
vec3 bumpMappingDisplacement(const vec2 fTextCoord)
{
	return vec3((2.0f * texture(texBumpSampler, fTextCoord)) - 1.0f);
}

subroutine(displacementType)
vec3 displacementMapping(const vec2 fTextCoord)
{
	return bumpMappingDisplacement(fTextCoord);
}

subroutine(displacementType)
vec3 noDisplacement(const vec2 fTextCoord)
{
	return normal;
}

// ----- Shadows -------

// Computes the fragment attenuation related to shadowing. For that purpose we must query a depth texture

subroutine(depthTextureType)
void shadow(out float shadowDiffuseFactor, out float shadowSpecFactor, in vec2 texNoise)
{
	vec4 fShadowCoord = vec4(shadowCoord.x + texNoise.x, shadowCoord.y + texNoise.y, shadowCoord.z, shadowCoord.w);
	shadowDiffuseFactor = 0.0f;

	for (int i = minNeighborhood; i <= maxNeighborhood; ++i)					// Neighborhood average
	{
		for (int j = minNeighborhood; j <= maxNeighborhood; ++j)
		{
			shadowDiffuseFactor += textureProjOffset(texShadowMapSampler, fShadowCoord, ivec2(i, j));
		}
	}	

	shadowDiffuseFactor /= neighborhoodSize;									// Average
	shadowDiffuseFactor = shadowDiffuseFactor * (shadowMaxIntensity - shadowMinIntensity) + shadowMinIntensity;
	
	if (shadowDiffuseFactor < (1.0f - EPSILON))
	{
		shadowSpecFactor = 0.0f;
	}
	else
	{
		shadowSpecFactor = 1.0f;
	}
}

subroutine(depthTextureType)
void noShadow(out float shadowDiffuseFactor, out float shadowSpecFactor, in vec2 texNoise)
{
	shadowDiffuseFactor = 1.0f;					// Color gets no attenuation
	shadowSpecFactor = 1.0f;
}


void main()
{
	// Projection texture mapping
	vec2 ndc = (clipSpace.xy / clipSpace.w) / 2.0f + 0.5f;
	vec2 reflectionTextCoord = vec2(ndc.x, 1.0 - ndc.y);
	vec2 refractionTextCoord = vec2(ndc.x, ndc.y);

	vec2 distortedTextCoord = texture(texReflectionNoise, vec2(inReflectionTextCoord.x + t, inReflectionTextCoord.y)).rg * 0.1f;
	distortedTextCoord = inReflectionTextCoord + vec2(distortedTextCoord.x, distortedTextCoord.y + t);
	vec2 totalDistortion = (texture(texReflectionNoise, distortedTextCoord).rg * 2.0f - 1.0f) * WAVE_STRENGTH;

	refractionTextCoord += totalDistortion;
	refractionTextCoord = clamp(refractionTextCoord, EPSILON, 1.0f - EPSILON);

	reflectionTextCoord += totalDistortion;
	reflectionTextCoord = clamp(reflectionTextCoord, EPSILON, 1.0f - EPSILON);

	const vec4 fragKad = semiTransparentUniform(getKad());
	const vec4 fragKs = getKs();
	const vec3 fragNormal = displacementUniform(distortedTextCoord);

	float shadowDiffuseFactor, shadowSpecFactor;
	depthTextureUniform(shadowDiffuseFactor, shadowSpecFactor, totalDistortion);

	const float refractiveFactor = pow(dot(normalize(-position), (mModelView * vec4(vec3(.0, 1.0f, .0f), .0f)).xyz), 1.0f);
	const vec3 reflectionColor = texture(texTerrain, reflectionTextCoord).rgb;
	const vec3 refractionColor = texture(texTerrain, refractionTextCoord).rgb;
	const vec3 lightedColor = lightUniform(mix(reflectionColor, refractionColor, refractiveFactor), fragKs.rgb, fragNormal, shadowDiffuseFactor, shadowSpecFactor);

	fColor = vec4(mix(lightedColor, fragKad.rgb, MIX_LIGHTING_KAD), 1.0f);
}