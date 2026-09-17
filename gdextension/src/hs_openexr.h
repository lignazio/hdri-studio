// HsOpenEXR — scrittura e lettura di OpenEXR con tutti i codec, dentro Godot (GDExtension).
// Sostituisce la riconversione via Blender: Godot di suo (TinyEXR) scrive solo PIZ e non legge DWA/B44/PXR24.
#pragma once

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>

namespace godot {

class HsOpenEXR : public RefCounted {
	GDCLASS(HsOpenEXR, RefCounted)

protected:
	static void _bind_methods();

public:
	/// Nomi dei codec accettati da save(), nell'ordine dell'interfaccia.
	static PackedStringArray codecs();
	/// Versione della libreria OpenEXR compilata dentro.
	static String version();
	/// Scrive image (RGB/RGBA, half o float) in path con il codec scelto. half = canali a 16 bit.
	/// attributes: String → attributo string, PackedFloat32Array di 8 → chromaticities, float → float, int → int.
	/// dwa_level: qualità DWAA/DWAB (default OpenEXR 45; più basso = più fedele). Scrittura atomica (temporaneo + rinomina).
	static Error save(const Ref<Image> &image, const String &path, const String &codec, bool half, const Dictionary &attributes, float dwa_level);
	/// Legge un EXR (scanline, tiled o prima parte di un multipart) in un'Image RGBAF. null se non leggibile.
	static Ref<Image> load(const String &path);
	/// Header senza decodificare i pixel: width, height, compression (nome), channels, half (bool), più gli attributi string.
	static Dictionary info(const String &path);
};

} // namespace godot
