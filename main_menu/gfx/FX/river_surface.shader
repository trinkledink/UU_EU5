// Quick edit guide:
// - Colors are set near the bottom: search for `BaseRiverColor` and `FlowHighlight`.
//   `BaseRiverColor` = gaps, `FlowHighlight` = pulses.
//   You can also tweak `FlowSpeed`, `GradientRepeat`, and `PulseWidth`.
// - Sentinel detection uses `GB_GradientWidth` from map modes:
//     0.111 = rivers only, 0.333 = roads + rivers

Includes = {
	"river_surface.fxh"
	"standardfuncsgfx.fxh"
	"fog_of_war.fxh"
	"gbuffer.fxh"
	"winter.fxh"
	"flatmap_lerp.fxh"
	"jomini/gradient_border_constants.fxh"
	"river_vertex_shader.fxh"
	"terrain.fxh"
}


VertexShader = 
{
	MainCode CaesarRiverVertexShader
	{
		Input = "VS_INPUT_RIVER"
		Output = "VS_OUTPUT_RIVER"
		Code
		[[		
			PDX_MAIN
			{
				return CaesarRiverVertexShader( Input );
			}		
		]]
	}
}

PixelShader =
{
	TextureSampler ClimateMap
	{
		Ref = ClimateMap
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}
	TextureSampler EnvironmentMap
	{
		Ref = JominiEnvironmentMap
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
		Type = "Cube"
	}
	TextureSampler FlatMapTexture
	{
		Ref = FlatMap0
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
	}
	TextureSampler FlatMapDetail
	{
		Ref = FlatMap1
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}
	TextureSampler PaperMapSdf
	{
		Ref = PdxTexture10
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
		File = "gfx/map/rivers/river_sdf.dds"
	}
	TextureSampler PencilNoiseMap
	{
		Ref = PdxTexture11
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
		File = "gfx/map/rivers/charcoal_noise.dds"
	}

	TextureSampler DetailDiffuseIce
	{
		Ref = DynamicTerrainMask7
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
		File = "gfx/terrain2/terrain_textures/unmasked/ice_diffuse.dds"
	}

	TextureSampler DetailNormalIce
	{
		Ref = DynamicTerrainMask8
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
		File = "gfx/terrain2/terrain_textures/unmasked/ice_normal.dds"
	}

	TextureSampler DetailPropertiesIce
	{
		Ref = DynamicTerrainMask9
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
		File = "gfx/terrain2/terrain_textures/unmasked/ice_properties.dds"
	}

	MainCode PS_surface
	{
		Input = "VS_OUTPUT_RIVER"
		Output = "PS_OUTPUT"
		Code
		[[	
			float CalcNoise( float Pos )
			{
				float i = floor( Pos );
				float f = frac( Pos );

				float a = CalcRandom(i);
				float b = CalcRandom(i + 1.0);
				
				float u = f*f*(3.0-2.0*f);
				return lerp(a, b, u);
			}
			void ApplySnow( inout SWaterOutput Water, in VS_OUTPUT_RIVER Input)
			{
				#ifndef TERRAIN_DISABLED
				float Winterness = GetSnowAmountForTerrain( Water._Normal, Input.WorldSpacePos, ClimateMap );
				if( Winterness > 0.0f )
				{
					static const float DepthNoiseScale = 123.0f;
					static const float DepthNoiseLower = 0.25f;
					static const float DepthNoiseUpper = 1.0f;
					static const float DepthNoiseStrength = 0.35f;
				
					float2 UV = Input.WorldSpacePos.xz * _InvMaterialTileSize ;
					float4 DiffuseIce = PdxTex2D( DetailDiffuseIce, UV );
					float MaxDepthNoise = PdxTex2D( ClimateMap, Input.WorldSpacePos.xz * DepthNoiseScale / GetMapSize() ).g;
					MaxDepthNoise = smoothstep( DepthNoiseLower, DepthNoiseUpper, MaxDepthNoise );
					MaxDepthNoise *= DepthNoiseStrength;
					
					float RiverIceWaterDepthMin = RiverIceWaterDepthMinFlat + RiverIceWaterDepthMinByWidth * Input.Width;
					float RiverIceWaterDepthMax = RiverIceWaterDepthMaxFlat + MaxDepthNoise + RiverIceWaterDepthMaxByWidth * Input.Width;
					float RiverIceBaseFadeRange = RiverIceBaseFadeRangeFlat + RiverIceBaseFadeRangeByWidth * Input.Width;
					
					float BaseBlend = RemapClamped( Winterness, RiverIceWinternessMin, RiverIceWinternessMax, 0.0f, 1.0f );
					BaseBlend *= RemapClamped( Water._Depth, RiverIceWaterDepthMin, RiverIceWaterDepthMax, 1.0f, 0.0f );
					
					float IceBaseBlend = smoothstep( 0.0f, RiverIceBaseFadeRange, BaseBlend );
					float WaterBaseBlend = 1.0f - BaseBlend;// smoothstep( 1.0f, 0.5, BaseBlend );
					
					float2 Weights = float2( IceBaseBlend + DiffuseIce.a, WaterBaseBlend * 2.0f );
					
					float BlendStart = max( Weights.x, Weights.y ) - RiverIceDetailFadeRange;
					
					float2 Blend = max( Weights - vec2( BlendStart ), vec2( 0.0f ) );
					float2 Normalized = Blend / ( dot(Blend, vec2(1.0f) ) + 0.0000001f );
					
					if( Normalized.x > 0.0f )
					{
						float EdgeFade1 = smoothstep( 0.3f, 0.4, Input.UV.y );
						float EdgeFade2 = smoothstep( 0.3f, 0.4, 1.0f - Input.UV.y );
						float LerpSnow =  1-EdgeFade1 * EdgeFade2;
						float4 DiffuseSnow = PdxTex2D( DetailDiffuseSnow, UV );
						float3 NormalIce = UnpackRRxGNormal( PdxTex2D( DetailNormalIce, UV ) ).xzy;
						float4 PropertiesIce = PdxTex2D( DetailPropertiesIce, UV );
						
	

						float3 NormalSnow = UnpackRRxGNormal( PdxTex2D( DetailNormalSnow, UV ) ).xzy;
						float4 PropertiesSnow = PdxTex2D( DetailPropertiesSnow, UV );

						float3 Normal = lerp(NormalIce, NormalSnow, LerpSnow);
						float4 Properties = lerp(PropertiesIce, PropertiesSnow, LerpSnow);

						SMaterialProperties MaterialProps = GetMaterialProperties( lerp(DiffuseIce.rgb, DiffuseSnow.rgb, LerpSnow), Normal, Properties.a, Properties.g, Properties.b );
						SLightingProperties LightingProps = GetSunLightingProperties( Input.WorldSpacePos, 1.0f );

						float3 Color = CalculateSunLighting( MaterialProps, LightingProps, EnvironmentMap );
						
						float3 SnowedColor = (Color * Normalized.x + Water._Color.rgb * Normalized.y );
						Water._Color.rgb  = lerp(Water._Color.rgb, SnowedColor , LerpSnow * 0.5+0.5);
						
						
						float SnowReflectionAmount = Water._ReflectionAmount * ( 1.0f - Normalized.x ); //hack for SSR
						Water._ReflectionAmount = SnowReflectionAmount * Normalized.x + Water._ReflectionAmount * Normalized.y;
					}
				}
				#endif
			}		
			PDX_MAIN
			{		
				SMaterialProperties Material;
				Material._PerceptualRoughness = 0.0f;
				Material._Roughness = 0.0f;
				Material._Metalness = 0.0f;				
				Material._DiffuseColor = vec3(0.0f);
				Material._SpecularColor = vec3(0.0f);
				Material._Normal = float3(0,1,0);
				float4 FinalColor = vec4(0.0f);
				
				float2 FlatMapBlend = GetNoisyFlatMapLerp( Input.WorldSpacePos, GetFlatMapLerp() );
				#ifndef TERRAIN_DISABLED
				if( FlatMapBlend.x < 1.0f )
				{
					SWaterOutput Water = CalcRiverAdvanced( Input );					
					ApplySnow( Water, Input );
					Material._PerceptualRoughness = 0.0f;
					Material._Roughness = 0.0f;
					Material._Metalness = 0.0f;				
					Material._DiffuseColor = Water._Color.rgb;
					Material._SpecularColor = saturate( vec3( Water._ReflectionAmount ) * 7.5f );
					Material._Normal = Water._Normal;
					FinalColor = Water._Color;
					#ifndef JOMINI_REFRACTION_ENABLED
						//FinalColor.a *=4.0f;
						FinalColor.a = lerp(FinalColor.a, 1.0f, saturate ((FinalColor.a-0.05f)* 6.0f)); //Add extra opacity if refraction is disabled to compensate
					#endif
				}
				#endif
				
				if( FlatMapBlend.x > 0.0f )
				{
					float InvWidth = 1.0f;// 1.0f / Input.Width;
					float2  UV = Input.UV * float2( InvWidth * _TextureUvScale, 1 );
					float2 DistanceRaw = PdxTex2D( PaperMapSdf, UV ).rg * 2.0f - 1.0f;
					float Distance = DistanceRaw.r * Input.Width;
					
					float2 FlatMapCoords = Input.WorldSpacePos.xz * _WorldSpaceToTerrain0To1;
					float2 ColorMapCoords = float2( FlatMapCoords.x, 1.0f - FlatMapCoords.y );
					
					SFlatMapBase FlatMap = CalcFlatMapBase( Input.WorldSpacePos, FlatMapCoords, FlatMapTexture, FlatMapDetail );
					float PaperNoise = PdxTex2D( FlatMapDetail, FlatMap._FlatMapUV * float2(2.0, 1.0) * FlatMapDetailTiles ).r;
					PaperNoise = Remap( PaperNoise, FlatMapDetailRemap.x, FlatMapDetailRemap.y, FlatMapDetailRemap.z, FlatMapDetailRemap.w );
					float4 RiverColor = float4( FlatMapColorLand * PaperNoise, 1.0 );
					RiverColor.a *= FlatMap._LandMask;
					
			float PencilNoise = PdxTex2D( PencilNoiseMap, Input.WorldSpacePos.xz * 0.125f ).r;

			// Detect sentinel values via gradient_width:
			// 0.111 = rivers-only, 0.333 = roads+rivers
			bool IsSentinelActive = ( GB_GradientWidth >= 0.11f && GB_GradientWidth <= 0.12f ) || ( GB_GradientWidth >= 0.33f && GB_GradientWidth <= 0.34f );
			
				// Base contour
					float Zoomish = dot( Input.WorldSpacePos - CameraPosition, CameraLookAtDir );
					float AlphaFuzz = RemapClamped( Zoomish, 130, 368, 0.5f, 1.0f );
					
					// CUSTOMIZATION: Adjust river appearance when sentinel is active
					if( IsSentinelActive )
					{
						// THICKNESS: Increase this value to make rivers thicker (default: 1.0)
						Distance += 1.0f;
					}
					
					RiverColor.a *= smoothstep( -AlphaFuzz, AlphaFuzz, Distance - 0.2f - PencilNoise * 0.2 );
					
					// Apply color with flow animation
					if( IsSentinelActive )
					{
						// Flow animation moving downstream
						float FlowSpeed = 4.5f;
						float Time = GetScaledGlobalTime() * FlowSpeed;
						float AnimatedU = Input.UV.x - Time;
						
						// Pulse spacing and width
						float GradientRepeat = 32.0f;
						float Phase = frac( AnimatedU / GradientRepeat );
						
						// Wide pulse with soft edges
						float PulseWidth = 0.44f;
						float EdgeSoft = PulseWidth * 0.25f;
						float Centered = abs( Phase - 0.5f );
						float Pulse = 1.0f - smoothstep( PulseWidth * 0.5f, PulseWidth * 0.5f + EdgeSoft, Centered );
						
						// Color ramp
						float3 BaseRiverColor = float3( 0.50, 0.85, 1.0 );  // bright cyan for gaps
						float3 FlowHighlight = float3( 0.10, 0.30, 0.60 );  // darker blue for pulses
						RiverColor.rgb = lerp( BaseRiverColor, FlowHighlight, Pulse * 1.0f );
					}
					else
					{
						RiverColor.rgb = Overlay( RiverColor.rgb, float3( 0.2, 0.3, 0.8 ) );
					}
					
					// River bank (disabled when sentinel active for cleaner look)
					if( !IsSentinelActive )
					{
						float Edge = smoothstep( AlphaFuzz, 0.0, abs( Distance - 0.2f - PencilNoise * 0.2 ) );
						RiverColor.rgb = lerp( RiverColor.rgb, RiverColor.rgb * 0.1, Edge );
					}
					
					// Waves (disabled when sentinel active for cleaner look)
					if( !IsSentinelActive )
					{
						float NoiseGap = 0.1;
						float NoiseFade = 0.1;
						float SideDistOffset = -0.1; //To compensate for poor quality SDF generated in photoshop
						float LengthwiseNoise = CalcNoise( Input.UV.x * 0.15 );
						float WaveSine = sin( Input.UV.x * 7.0f ) * 0.05f;
						float Lines = smoothstep( 0.25, 0.0, abs( Distance - 1.2 + WaveSine ) );
						Lines += smoothstep( 0.25, 0.5, abs( LengthwiseNoise - 0.5f ) ) * smoothstep( 0.25, 0.0, abs( Distance - 2.0 ) + WaveSine );
					
						float SideMask = smoothstep( 0.5-NoiseGap, 0.5-NoiseGap-NoiseFade, LengthwiseNoise ) * smoothstep( SideDistOffset, SideDistOffset+0.1, DistanceRaw.g );
						SideMask += smoothstep( 0.5+NoiseGap, 0.5+NoiseGap+NoiseFade, LengthwiseNoise ) * smoothstep( SideDistOffset, SideDistOffset-0.1, DistanceRaw.g );
						Lines *= SideMask;					
						Lines *= PencilNoise;
						RiverColor.rgb = lerp( RiverColor.rgb, RiverColor.rgb * 0.1, Lines );
					}
					
					// Finalize output
					RiverColor.rgb *= FlatMapBlend.y;
					RiverColor.a *= Input.Transparency * saturate( ( Input.DistanceToMain - 0.15f ) * 15.0f );
					
					// Keep rivers visible in sentinel mode; fade out otherwise
					if( !IsSentinelActive )
					{
						RiverColor.a *= 1.0f - GetSimulatedFlatMapLerp();
					}
					
					FinalColor = lerp( FinalColor, RiverColor, FlatMapBlend.x );
				}
				
				FinalColor.rgb = ApplyFogOfWar( FinalColor.rgb, Input.WorldSpacePos, FogOfWarAlpha );
				if( GetFlatMapLerp() < 1.0f )
				{
					float3 FoggedColor = ApplyDistanceFog( FinalColor.rgb, Input.WorldSpacePos );
					FinalColor.rgb = lerp( FoggedColor, FinalColor.rgb, GetFlatMapLerp() );
				}
				
				Material._DiffuseColor = FinalColor.rgb;				
				return PS_Return( FinalColor, Material );
			}
		]]
	}
}
RasterizerState RiverSurfaceRasterizer
{
	DepthBias = -1000
}
Effect river_surface
{
	RasterizerState = RiverSurfaceRasterizer
	VertexShader = "CaesarRiverVertexShader"
	PixelShader = "PS_surface"
	Defines = { "ENABLE_TERRAIN" "ENABLE_GAME_CONSTANTS" "RIVER" }#"WATER_LOCAL_SPACE_NORMALS"  }
}
