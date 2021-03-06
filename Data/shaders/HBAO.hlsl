/*
Copyright(c) 2016-2020 Panos Karabelas

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and / or sell
copies of the Software, and to permit persons to whom the Software is furnished
to do so, subject to the following conditions :

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

//= INCLUDES ===========
#include "Common.hlsl"
#include "Velocity.hlsl"
//======================

#if INDIRECT_BOUNCE
static const uint ao_directions = 1;
static const uint ao_steps      = 4;
#else
static const uint ao_directions = 2;
static const uint ao_steps      = 2;
#endif
static const float ao_radius            = 0.5f;
static const float ao_intensity         = 1.0f;
static const float ao_bounce_intensity  = 1.0f;

static const float ao_samples   = (float)(ao_directions * ao_steps);
static const float ao_radius2   = ao_radius * ao_radius;
static const float2 noise_scale = float2(g_resolution.x / 256.0f, g_resolution.y / 256.0f);

static const float3 sample_kernel[64] =
{
    float3(0.04977, -0.04471, 0.04996),
    float3(0.01457, 0.01653, 0.00224),
    float3(-0.04065, -0.01937, 0.03193),
    float3(0.01378, -0.09158, 0.04092),
    float3(0.05599, 0.05979, 0.05766),
    float3(0.09227, 0.04428, 0.01545),
    float3(-0.00204, -0.0544, 0.06674),
    float3(-0.00033, -0.00019, 0.00037),
    float3(0.05004, -0.04665, 0.02538),
    float3(0.03813, 0.0314, 0.03287),
    float3(-0.03188, 0.02046, 0.02251),
    float3(0.0557, -0.03697, 0.05449),
    float3(0.05737, -0.02254, 0.07554),
    float3(-0.01609, -0.00377, 0.05547),
    float3(-0.02503, -0.02483, 0.02495),
    float3(-0.03369, 0.02139, 0.0254),
    float3(-0.01753, 0.01439, 0.00535),
    float3(0.07336, 0.11205, 0.01101),
    float3(-0.04406, -0.09028, 0.08368),
    float3(-0.08328, -0.00168, 0.08499),
    float3(-0.01041, -0.03287, 0.01927),
    float3(0.00321, -0.00488, 0.00416),
    float3(-0.00738, -0.06583, 0.0674),
    float3(0.09414, -0.008, 0.14335),
    float3(0.07683, 0.12697, 0.107),
    float3(0.00039, 0.00045, 0.0003),
    float3(-0.10479, 0.06544, 0.10174),
    float3(-0.00445, -0.11964, 0.1619),
    float3(-0.07455, 0.03445, 0.22414),
    float3(-0.00276, 0.00308, 0.00292),
    float3(-0.10851, 0.14234, 0.16644),
    float3(0.04688, 0.10364, 0.05958),
    float3(0.13457, -0.02251, 0.13051),
    float3(-0.16449, -0.15564, 0.12454),
    float3(-0.18767, -0.20883, 0.05777),
    float3(-0.04372, 0.08693, 0.0748),
    float3(-0.00256, -0.002, 0.00407),
    float3(-0.0967, -0.18226, 0.29949),
    float3(-0.22577, 0.31606, 0.08916),
    float3(-0.02751, 0.28719, 0.31718),
    float3(0.20722, -0.27084, 0.11013),
    float3(0.0549, 0.10434, 0.32311),
    float3(-0.13086, 0.11929, 0.28022),
    float3(0.15404, -0.06537, 0.22984),
    float3(0.05294, -0.22787, 0.14848),
    float3(-0.18731, -0.04022, 0.01593),
    float3(0.14184, 0.04716, 0.13485),
    float3(-0.04427, 0.05562, 0.05586),
    float3(-0.02358, -0.08097, 0.21913),
    float3(-0.14215, 0.19807, 0.00519),
    float3(0.15865, 0.23046, 0.04372),
    float3(0.03004, 0.38183, 0.16383),
    float3(0.08301, -0.30966, 0.06741),
    float3(0.22695, -0.23535, 0.19367),
    float3(0.38129, 0.33204, 0.52949),
    float3(-0.55627, 0.29472, 0.3011),
    float3(0.42449, 0.00565, 0.11758),
    float3(0.3665, 0.00359, 0.0857),
    float3(0.32902, 0.0309, 0.1785),
    float3(-0.08294, 0.51285, 0.05656),
    float3(0.86736, -0.00273, 0.10014),
    float3(0.45574, -0.77201, 0.00384),
    float3(0.41729, -0.15485, 0.46251),
    float3(-0.44272, -0.67928, 0.1865)
};

float falloff(float distance_squared)
{
    return saturate(1.0f - distance_squared / ao_radius2);
}

float compute_occlusion(float3 center_normal, float3 center_to_sample, float distance_squared, float attunate)
{
    return saturate(dot(center_normal, center_to_sample) / sqrt(distance_squared)) * attunate;
}

float3 compute_light(float3 center_normal, float3 center_to_sample, float distance_squared, float attunate, float2 sample_uv, inout uint indirect_light_samples)
{
    float3 indirect = 0.0f;
    
    // Compute falloff
    attunate = attunate * screen_fade(sample_uv);
    
	// Reproject light
	float2 velocity         = GetVelocity_DepthMin(sample_uv);
	float2 uv_reprojected   = sample_uv - velocity;
	float3 light            = tex_light_diffuse.SampleLevel(sampler_bilinear_clamp, uv_reprojected, 0).rgb * attunate;
	
	// Transport
	[branch]
	if (luminance(light) > 0.0f)
	{
		float distance      = clamp(sqrt(distance_squared), 0.1, 50);
		float attunation    = clamp(1.0 / (distance), 0, 50);
		float occlusion     = saturate(dot(center_normal, center_to_sample)) * attunation;
	
		[branch]
		if (occlusion > 0.0f)
		{
			float3 sample_normal    = get_normal_view_space(sample_uv);
			float visibility        = saturate(dot(sample_normal, -center_to_sample));
		
			indirect = light * visibility * occlusion;
			indirect_light_samples++;
		}
	}

    return indirect;
}

float4 normal_oriented_hemisphere_ambient_occlusion(float2 uv, float3 position, float3 normal)
{
    float occlusion = 0.0f;
    
    // Use temporal interleaved gradient noise to rotate the random vector (free detail with TAA on)
    float3 random_vector    = unpack(normalize(tex_normal_noise.Sample(sampler_bilinear_wrap, uv * noise_scale).xyz));
    float ign               = interleaved_gradient_noise(uv * g_resolution);
    float rotation_angle    = max(ign * PI2, FLT_MIN);
    float3 rotation         = float3(cos(rotation_angle), sin(rotation_angle), 0.0f);
    random_vector           = float3(length(random_vector.xy) * normalize(rotation.xy), random_vector.z);
    
    [unroll]
    for (uint i = 0; i < ao_directions; i++)
    {
        // Compute offset
        float3 offset   = reflect(sample_kernel[i], random_vector);
        offset          *= ao_radius;                   // Scale by radius
        offset          *= sign(dot(offset, normal));   // Flip if behind normal
        
        // Compute sample pos
        float3 sample_pos   	= position + offset;
        float2 sample_uv    	= project_uv(sample_pos, g_projection);
        sample_pos          	= get_position_view_space(sample_uv);
		float3 center_to_sample = sample_pos - position;
		float distance_squared  = dot(center_to_sample, center_to_sample);
		float attunate 			= falloff(distance_squared);

        [branch]
        if (attunate != 0.0f)
        {
            // Occlusion
            occlusion += compute_occlusion(normal, center_to_sample, distance_squared, attunate);
        }
    }

    occlusion = 1.0f - saturate(occlusion * ao_intensity / float(ao_directions));  
    return float4(occlusion, occlusion, occlusion, 1);
}

float4 horizon_based_ambient_occlusion(float2 uv, float3 position, float3 normal)
{
    float occlusion     = 0.0f;
    float3 light        = 0.0f;
    uint light_samples  = 0;
    
    float radius_pixels = max((ao_radius * g_resolution.x * 0.5f) / position.z, (float)ao_steps);
    radius_pixels       = radius_pixels / (ao_steps + 1); // divide by ao_steps + 1 so that the farthest samples are not fully attenuated
    float rotation_step = PI2 / (float)ao_directions;

    // Offsets (noise over space and time)
    float noise_gradient_temporal   = interleaved_gradient_noise(uv * g_resolution);
    float offset_spatial            = noise_spatial_offset(uv * g_resolution);
    float offset_temporal           = noise_temporal_offset();
    float offset_rotation_temporal  = noise_temporal_direction();
    float ray_offset                = frac(offset_spatial + offset_temporal) + (random(uv) * 2.0 - 1.0) * 0.25;
    
    [unroll]
    for (uint direction_index = 0; direction_index < ao_directions; direction_index++)
    {
        float rotation_angle        = (direction_index + noise_gradient_temporal + offset_rotation_temporal) * rotation_step;
        float2 rotation_direction   = float2(cos(rotation_angle), sin(rotation_angle)) * g_texel_size;

        [unroll]
        for (uint step_index = 0; step_index < ao_steps; ++step_index)
        {
            float2 uv_offset        = max(radius_pixels * (step_index + ray_offset), 1 + step_index) * rotation_direction;
            float2 sample_uv        = uv + uv_offset;
            float3 sample_position  = get_position_view_space(sample_uv);
			float3 center_to_sample = sample_position - position;
			float distance_squared  = dot(center_to_sample, center_to_sample);
            center_to_sample        = normalize(center_to_sample);
			float attunation 		= falloff(distance_squared);
			
			[branch]
            if (attunation != 0.0f)
			{
				// Occlusion
                occlusion += compute_occlusion(normal, center_to_sample, distance_squared, attunation);
                
				// Indirect bounce
				#if INDIRECT_BOUNCE
				light += compute_light(normal, center_to_sample, distance_squared, attunation, sample_uv, light_samples);
                #endif
            }
        }
    }

    occlusion = 1.0f - saturate(occlusion * ao_intensity / ao_samples);

    #if INDIRECT_BOUNCE
    light = saturate(light * ao_bounce_intensity / float(light_samples));
    #endif
    
    return float4(light, occlusion);
}

float4 mainPS(Pixel_PosUv input) : SV_TARGET
{
    float3 position = get_position_view_space(input.uv);
    float3 normal   = get_normal_view_space(input.uv);
  
    return horizon_based_ambient_occlusion(input.uv, position, normal);
}
