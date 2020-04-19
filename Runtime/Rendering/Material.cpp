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

//= INCLUDES =========================
#include "Material.h"
#include "Renderer.h"
#include "ShaderVariation.h"
#include "../Resource/ResourceCache.h"
#include "../IO/XmlDocument.h"
#include "../RHI/RHI_Texture2D.h"
#include "../RHI/RHI_TextureCube.h"
#include "../World/World.h"
//====================================

//= NAMESPACES ===============
using namespace std;
using namespace Spartan::Math;
//============================

namespace Spartan
{
	Material::Material(Context* context) : IResource(context, Resource_Material)
	{
		m_rhi_device = context->GetSubsystem<Renderer>()->GetRhiDevice();

		// Initialize multipliers
		SetMultiplier(Texture_Roughness, 0.9f);
		SetMultiplier(Texture_Metallic, 0.0f);
		SetMultiplier(Texture_Normal, 0.0f);
		SetMultiplier(Texture_Height, 0.0f);

        // Acquire shader
        m_shader = GetOrCreateShader(m_texture_flags);
	}

	bool Material::LoadFromFile(const string& file_path)
	{
		auto xml = make_unique<XmlDocument>();
		if (!xml->Load(file_path))
			return false;

		SetResourceFilePath(file_path);

        xml->GetAttribute("Material", "Color",                  &m_color_albedo);
		xml->GetAttribute("Material", "Roughness_Multiplier",	&GetMultiplier(Texture_Roughness));
		xml->GetAttribute("Material", "Metallic_Multiplier",	&GetMultiplier(Texture_Metallic));
		xml->GetAttribute("Material", "Normal_Multiplier",		&GetMultiplier(Texture_Normal));
		xml->GetAttribute("Material", "Height_Multiplier",		&GetMultiplier(Texture_Height));
		xml->GetAttribute("Material", "IsEditable",				&m_is_editable);
		xml->GetAttribute("Material", "UV_Tiling",				&m_uv_tiling);
		xml->GetAttribute("Material", "UV_Offset",				&m_uv_offset);

		const auto texture_count = xml->GetAttributeAs<int>("Textures", "Count");
		for (auto i = 0; i < texture_count; i++)
		{
			auto node_name		= "Texture_" + to_string(i);
			const auto tex_type	= static_cast<Texture_Type>(xml->GetAttributeAs<uint32_t>(node_name, "Texture_Type"));
			auto tex_name		= xml->GetAttributeAs<string>(node_name, "Texture_Name");
			auto tex_path		= xml->GetAttributeAs<string>(node_name, "Texture_Path");

			// If the texture happens to be loaded, get a reference to it
			auto texture = m_context->GetSubsystem<ResourceCache>()->GetByName<RHI_Texture2D>(tex_name);
			// If there is not texture (it's not loaded yet), load it
			if (!texture)
			{
				texture = m_context->GetSubsystem<ResourceCache>()->Load<RHI_Texture2D>(tex_path);
			}
			SetTextureSlot(tex_type, texture);
		}

        // Acquire shader
        m_shader = GetOrCreateShader(m_texture_flags);

        m_size_cpu = sizeof(*this);

		return true;
	}

	bool Material::SaveToFile(const string& file_path)
	{
        SetResourceFilePath(file_path);

		auto xml = make_unique<XmlDocument>();
		xml->AddNode("Material");
		xml->AddAttribute("Material", "Color",					m_color_albedo);
		xml->AddAttribute("Material", "Roughness_Multiplier",	GetMultiplier(Texture_Roughness));
		xml->AddAttribute("Material", "Metallic_Multiplier",	GetMultiplier(Texture_Metallic));
		xml->AddAttribute("Material", "Normal_Multiplier",		GetMultiplier(Texture_Normal));
		xml->AddAttribute("Material", "Height_Multiplier",		GetMultiplier(Texture_Height));
		xml->AddAttribute("Material", "UV_Tiling",				m_uv_tiling);
		xml->AddAttribute("Material", "UV_Offset",				m_uv_offset);
		xml->AddAttribute("Material", "IsEditable",				m_is_editable);

		xml->AddChildNode("Material", "Textures");
		xml->AddAttribute("Textures", "Count", static_cast<uint32_t>(m_textures.size()));
		auto i = 0;
		for (const auto& texture : m_textures)
		{
			auto tex_node = "Texture_" + to_string(i);
			xml->AddChildNode("Textures", tex_node);
			xml->AddAttribute(tex_node, "Texture_Type", static_cast<uint32_t>(texture.first));
			xml->AddAttribute(tex_node, "Texture_Name", texture.second ? texture.second->GetResourceName() : "");
			xml->AddAttribute(tex_node, "Texture_Path", texture.second ? texture.second->GetResourceFilePathNative() : "");
			i++;
		}

		return xml->Save(GetResourceFilePathNative());
	}

	void Material::SetTextureSlot(const Texture_Type type, const shared_ptr<RHI_Texture>& texture)
	{
		if (texture)
		{
            // In order for the material to guarantee serialization/deserialization we cache the texture
            const shared_ptr<RHI_Texture> texture_cached = m_context->GetSubsystem<ResourceCache>()->Cache(texture);
			m_textures[type] = texture_cached != nullptr ? texture_cached : texture;
            m_texture_flags |= type;

            SetMultiplier(type, 1.0f);
		}
		else
		{
			m_textures.erase(type);
            m_texture_flags &= ~type;
		}

        // Acquire shader
        m_shader = GetOrCreateShader(m_texture_flags);
	}

	void Material::SetTextureSlot(const Texture_Type type, const std::shared_ptr<RHI_Texture2D>& texture)
	{
        SetTextureSlot(type, static_pointer_cast<RHI_Texture>(texture));
	}

    void Material::SetTextureSlot(const Texture_Type type, const std::shared_ptr<RHI_TextureCube>& texture)
    {
        SetTextureSlot(type, static_pointer_cast<RHI_Texture>(texture));
    }

    bool Material::HasTexture(const string& path) const
	{
		for (const auto& texture : m_textures)
		{
			if (!texture.second)
				continue;

			if (texture.second->GetResourceFilePathNative() == path)
				return true;
		}

		return false;
	}

    string Material::GetTexturePathByType(const Texture_Type type)
	{
		if (!HasTexture(type))
			return "";

		return m_textures.at(type)->GetResourceFilePathNative();
	}

	vector<string> Material::GetTexturePaths()
	{
		vector<string> paths;
		for (const auto& texture : m_textures)
		{
			if (!texture.second)
				continue;

			paths.emplace_back(texture.second->GetResourceFilePathNative());
		}

		return paths;
	}

    shared_ptr<Spartan::RHI_Texture>& Material::GetTexture_PtrShared(const Texture_Type type)
    {
        static shared_ptr<RHI_Texture> texture_empty;
        return HasTexture(type) ? m_textures.at(type) : texture_empty;
    }

    shared_ptr<ShaderVariation> Material::GetOrCreateShader(const uint8_t shader_flags)
	{
		if (!m_context)
		{
			LOG_ERROR("Context is null, can't execute function");
			static shared_ptr<ShaderVariation> empty;
			return empty;
		}

		// If an appropriate shader already exists, return it instead
		if (const auto& existing_shader = ShaderVariation::GetMatchingShader(shader_flags))
			return existing_shader;

		// Create and compile shader
		auto shader = make_shared<ShaderVariation>(m_rhi_device, m_context);
		const auto dir_shaders = m_context->GetSubsystem<ResourceCache>()->GetDataDirectory(Asset_Shaders) + "/";
		shader->Compile(dir_shaders + "GBuffer.hlsl", shader_flags);

		return shader;
	}

    void Material::SetColorAlbedo(const Math::Vector4& color)
    {
        // If an object switches from opaque to transparent or vice versa, make the world update so that the renderer
        // goes through the entities and makes the ones that use this material, render in the correct mode.
        if ((m_color_albedo.w != 1.0f && color.w == 1.0f) || (m_color_albedo.w == 1.0f && color.w != 1.0f))
        {
            m_context->GetSubsystem<World>()->MakeDirty();
        }

        m_color_albedo = color;
    }

    Texture_Type Material::TextureTypeFromString(const string& type)
	{
		if (type == "Albedo")		return Texture_Albedo;
		if (type == "Roughness")	return Texture_Roughness;
		if (type == "Metallic")		return Texture_Metallic;
		if (type == "Normal")		return Texture_Normal;
		if (type == "Height")		return Texture_Height;
		if (type == "Occlusion")	return Texture_Occlusion;
		if (type == "Emission")		return Texture_Emission;
		if (type == "Mask")			return Texture_Mask;

		return Texture_Unknown;
	}
}
