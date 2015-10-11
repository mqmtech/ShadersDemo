Shader "SocialPoint/GrassGeneratorShader"
{
	Properties
	{
		_MainTex("Texture", 2D) = "white" {}
		_Color("Color", Color) = (1,1,1,1)
		_FresnelColor("Fresnel Color", Color) = (1,1,1,1)
		_SpecularColor("Specular Color", Color) = (1,1,1,1)
		_LightProps0("x:DiffuseIntensity y:SpecPower, z: SpecIntensity", Vector) = (1,4,1,1)
		_LightProps1("x:FresnelPower y:FresnelIntensity", Vector) = (10,1,1,1)
		_SpherifyIntensity("x:SpheriyIntensity", Float) = 0.3
		
	}

	SubShader
	{
		Tags 
		{ 
			"RenderType" = "Transparent" 
			"Queue" = "Transparent" 
		}
		
		Pass
		{
			Blend SrcAlpha OneMinusSrcAlpha
			ZWrite On Cull Off ZTest On
		
			CGPROGRAM
			
			#include "UnityCG.cginc"
			#include "Lighting.cginc"
			#include "Assets/Resources/ShaderIncludes/VertexUtils.cginc"
			
			#pragma vertex vert
			#pragma geometry geom
			#pragma fragment frag
			
			#pragma target 5.0
			
			#define GRASS_PARTS 8
			
			struct GrassData
			{
				float3 pos;
				float3 front;
				float3 right;
				float flattening;
			};
			
			sampler2D _MainTex;
			sampler2D _NoiseTex;
			fixed4 _Color;
			fixed4 _FresnelColor;
			fixed4 _SpecularColor;
			
			StructuredBuffer<GrassData> _GrassBuffer;
			half _Width;
			half _Height;
			
			half4 _LightProps0; //x:DiffuseIntensity y:SpecPower, z: SpecIntensity
			half4 _LightProps1; //x:FresnelPower y:FresnelIntensity
			half _SpherifyIntensity;
			
			struct vertexdata
			{
				float4 pos : POSITION;
			};
			
			struct v2g
			{
				float4 pos : SV_POSITION;
				float2 noise : TEXCOORD0;
				int inst : TEXCOORD1;
			};
			
			struct g2f
			{
				float4 pos : SV_POSITION;
				float3 wpos : TEXCOORD0;
				float2 uv : TEXCOORD1;
				float3 normal : NORMAL;
				float4 lightParams : TEXCOORD2;
				fixed4 color : COLOR;
			};
			
			v2g vert(uint inst : SV_InstanceID)
			{
				v2g o = (v2g) 0;
			
				float3 wpos = _GrassBuffer[inst].pos;
				o.pos = float4(wpos, 0);
				
				// Noise
				float w = (inst % _Width) / _Width;
				float h = (inst / _Width) / _Height;
				o.noise = tex2Dlod(_NoiseTex, float4(w, h, 0, 0) * 50.0).xy;
				
				o.inst = inst;
				
				return o;
			}
			
			void processVertex(v2g i, inout g2f o, int inst, float3 localPos, float4 instancePos, half3 front)
			{
				float instf = float(inst);
				float blendFactorFront = sin(instancePos.x*0 + i.noise.x*10 + _Time.x)*sin(instancePos.z*0 + i.noise.y*10 + _Time.x) * smoothstep(0, 1, localPos.y);
				float blendFactorUp = abs(blendFactorFront)*0.5;
				
				localPos += front * blendFactorFront;
				localPos.y += -blendFactorUp;
				o.wpos = instancePos.xyz + localPos.xyz;
				o.wpos.xyz = Spherify(o.wpos.xyz, _SpherifyIntensity);
				o.pos = mul(UNITY_MATRIX_VP, float4(o.wpos, 1));
				
				o.normal.y += blendFactorUp*4;
				o.normal = normalize(o.normal);
				
				o.color = fixed4(i.noise.rg, 0, 1);
			}
			
			[maxvertexcount(4*GRASS_PARTS)]
			void geom(point v2g i[1], inout TriangleStream<g2f> oStream)
			{
				half3 _Size = 0.25;
			
				g2f o = (g2f) 0;
				float4 wpos;
				float3 localpos = fixed3(0,0,0);
				
				float3 subpartSize = float3(_Size.x, 2.0*_Size.y/((float)GRASS_PARTS), _Size.z);
				float uvsize = 1.0/GRASS_PARTS;
				
				half3 front = _GrassBuffer[i[0].inst].front;
				half3 right = _GrassBuffer[i[0].inst].right;
				half3 up = half3(0, 1, 0) * max(_GrassBuffer[i[0].inst].flattening, 0.2);
				//half3x3 model = half3x3(front, right, up);
				float3 defaultNormal = front;
				
				for(int idx = 0; idx < GRASS_PARTS; ++idx)
				{
					float2 uvmin = float2(0, idx*uvsize);
					float2 uvmax = float2(1, uvmin.y+uvsize);
					float subpartPosY =  subpartSize.y*idx;
				
					//Left Bottom
					localpos.xyz = -right*subpartSize.x + up*subpartPosY;
					o.uv = half2(uvmin.x, uvmin.y);
					o.normal = defaultNormal;
					processVertex(i, o, i[0].inst, localpos, i[0].pos, front);
					oStream.Append(o);
					
					//Left Top
					localpos.xyz = -right*subpartSize.x + up*(subpartPosY+subpartSize);
					o.uv = half2(uvmin.x, uvmax.y);
					o.normal = defaultNormal;
					processVertex(i, o, i[0].inst, localpos, i[0].pos, front);
					oStream.Append(o);
					
					//Right Bottom
					localpos.xyz = right*subpartSize.x + up*(subpartPosY);
					o.uv = half2(uvmax.x, uvmin.y);
					o.normal = defaultNormal;
					processVertex(i, o, i[0].inst, localpos, i[0].pos, front);
					oStream.Append(o);
					
					//Right Top
					localpos.xyz = right*subpartSize.x + up*(subpartPosY+subpartSize);
					o.uv = half2(uvmax.x, uvmax.y);
					o.normal = defaultNormal;
					processVertex(i, o, i[0].inst, localpos, i[0].pos, front);
					oStream.Append(o);
					
					oStream.RestartStrip();
				}
			}
			
			fixed4 frag(g2f i) : COLOR
			{
				fixed4 albedo = tex2D(_MainTex, i.uv) * _Color;
				albedo.a = min(albedo.a, 1-Luminance(albedo.rgb));
				//albedo.rgb *= i.color;
				
				clip(albedo.a-0.01);
				
				float3 lightDir = _WorldSpaceLightPos0.xyz;
				float3 viewDir = normalize(_WorldSpaceCameraPos - i.wpos);
				
				// Fresnel
				half fresnelFactor = pow(abs(dot(viewDir, i.normal)), _LightProps1.x)*_LightProps1.y;
				// Diffuse
				half diffFactor = abs(dot(lightDir, i.normal)) * _LightProps0.x;
				// Specular
				half3 halfVector = (lightDir + viewDir) * 0.5;
				half specFactor = pow(abs(dot(halfVector, i.normal)), _LightProps0.x ) * _LightProps0.z;
				fixed4 finalColor =  _LightColor0 * (albedo*diffFactor + _SpecularColor*specFactor + _FresnelColor*fresnelFactor);
				finalColor.a = albedo.a * (0.8+0.2*fresnelFactor);
				
				return finalColor;
			}
			
			ENDCG
		}
	}
}