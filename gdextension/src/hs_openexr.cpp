#include "hs_openexr.h"

#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <ImfChannelList.h>
#include <ImfChromaticitiesAttribute.h>
#include <ImfCompression.h>
#include <ImfFloatAttribute.h>
#include <ImfFrameBuffer.h>
#include <ImfHeader.h>
#include <ImfIO.h>
#include <ImfInputFile.h>
#include <ImfIntAttribute.h>
#include <ImfOutputFile.h>
#include <ImfStringAttribute.h>
#include <OpenEXRConfig.h>

#include <cstring>
#include <exception>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>

using namespace godot;

namespace {

struct CodecEntry {
	const char *name;
	Imf::Compression id;
};

// Stesso ordine del menu dell'app: lossless prima, poi lossy.
const CodecEntry CODECS[] = {
	{ "PIZ", Imf::PIZ_COMPRESSION },
	{ "ZIP", Imf::ZIP_COMPRESSION },
	{ "ZIPS", Imf::ZIPS_COMPRESSION },
	{ "RLE", Imf::RLE_COMPRESSION },
	{ "PXR24", Imf::PXR24_COMPRESSION },
	{ "B44", Imf::B44_COMPRESSION },
	{ "B44A", Imf::B44A_COMPRESSION },
	{ "DWAA", Imf::DWAA_COMPRESSION },
	{ "DWAB", Imf::DWAB_COMPRESSION },
	{ "NONE", Imf::NO_COMPRESSION },
};

bool codec_from_name(const String &name, Imf::Compression &out) {
	CharString ascii = name.to_upper().ascii();
	for (const CodecEntry &c : CODECS) {
		if (std::strcmp(c.name, ascii.get_data()) == 0) {
			out = c.id;
			return true;
		}
	}
	return false;
}

String codec_name(Imf::Compression id) {
	for (const CodecEntry &c : CODECS) {
		if (c.id == id) {
			return c.name;
		}
	}
	std::string s;
	Imf::getCompressionNameFromId(id, s);
	return String(s.c_str());
}

std::string to_std(const String &s) {
	return std::string(s.utf8().get_data());
}

// Stream OpenEXR sopra FileAccess: percorsi res:// e user:// e Unicode su Windows gestiti da Godot.
class GodotOStream : public Imf::OStream {
public:
	explicit GodotOStream(const Ref<FileAccess> &f, const std::string &name) :
			Imf::OStream(name.c_str()), file(f) {}

	void write(const char c[], int n) override {
		PackedByteArray buf;
		buf.resize(n);
		std::memcpy(buf.ptrw(), c, n);
		file->store_buffer(buf);
		if (file->get_error() != OK) {
			throw std::runtime_error("scrittura fallita");
		}
	}
	uint64_t tellp() override { return file->get_position(); }
	void seekp(uint64_t pos) override { file->seek(pos); }

private:
	Ref<FileAccess> file;
};

class GodotIStream : public Imf::IStream {
public:
	explicit GodotIStream(const Ref<FileAccess> &f, const std::string &name) :
			Imf::IStream(name.c_str()), file(f), length(f->get_length()) {}

	bool read(char c[], int n) override {
		PackedByteArray buf = file->get_buffer(n);
		if (buf.size() != n) {
			throw std::runtime_error("lettura oltre la fine del file");
		}
		std::memcpy(c, buf.ptr(), n);
		return file->get_position() < length;
	}
	uint64_t tellg() override { return file->get_position(); }
	void seekg(uint64_t pos) override { file->seek(pos); }
	int64_t size() override { return int64_t(length); }

private:
	Ref<FileAccess> file;
	uint64_t length;
};

struct Layout {
	Imf::PixelType type;
	int channels; // 3 o 4
	size_t pixel_bytes;
};

bool layout_of(Image::Format f, Layout &out) {
	switch (f) {
		case Image::FORMAT_RGBAF: out = { Imf::FLOAT, 4, 16 }; return true;
		case Image::FORMAT_RGBF: out = { Imf::FLOAT, 3, 12 }; return true;
		case Image::FORMAT_RGBAH: out = { Imf::HALF, 4, 8 }; return true;
		case Image::FORMAT_RGBH: out = { Imf::HALF, 3, 6 }; return true;
		default: return false;
	}
}

void add_attributes(Imf::Header &header, const Dictionary &attributes) {
	Array keys = attributes.keys();
	for (int i = 0; i < keys.size(); i++) {
		std::string name = to_std(keys[i]);
		Variant v = attributes[keys[i]];
		switch (v.get_type()) {
			case Variant::STRING:
			case Variant::STRING_NAME:
				header.insert(name, Imf::StringAttribute(to_std(v)));
				break;
			case Variant::FLOAT:
				header.insert(name, Imf::FloatAttribute(float(double(v))));
				break;
			case Variant::INT:
				header.insert(name, Imf::IntAttribute(int(int64_t(v))));
				break;
			case Variant::PACKED_FLOAT32_ARRAY: {
				PackedFloat32Array a = v;
				if (a.size() == 8) {
					Imf::Chromaticities c(
							Imath::V2f(a[0], a[1]), Imath::V2f(a[2], a[3]),
							Imath::V2f(a[4], a[5]), Imath::V2f(a[6], a[7]));
					header.insert(name, Imf::ChromaticitiesAttribute(c));
				} else {
					UtilityFunctions::push_warning("HsOpenEXR: attributo ", keys[i], " ignorato (chromaticities = 8 float)");
				}
				break;
			}
			default:
				UtilityFunctions::push_warning("HsOpenEXR: attributo ", keys[i], " di tipo non gestito, ignorato");
		}
	}
}

// Nomi dei canali R, G, B, A da usare: piatti se ci sono, altrimenti il primo layer ("beauty.R"…),
// altrimenti Y (monocromatico, replicato). Restituisce false se non c'è nulla di utilizzabile.
bool pick_channels(const Imf::ChannelList &cl, std::string names[4], bool &mono) {
	mono = false;
	if (cl.findChannel("R") && cl.findChannel("G") && cl.findChannel("B")) {
		names[0] = "R"; names[1] = "G"; names[2] = "B";
		names[3] = cl.findChannel("A") ? "A" : "";
		return true;
	}
	std::set<std::string> layers;
	cl.layers(layers);
	for (const std::string &layer : layers) {
		std::string r = layer + ".R", g = layer + ".G", b = layer + ".B", a = layer + ".A";
		if (cl.findChannel(r) && cl.findChannel(g) && cl.findChannel(b)) {
			names[0] = r; names[1] = g; names[2] = b;
			names[3] = cl.findChannel(a) ? a : "";
			return true;
		}
	}
	if (cl.findChannel("Y")) {
		names[0] = "Y"; names[1] = ""; names[2] = ""; names[3] = "";
		mono = true;
		return true;
	}
	return false;
}

} // namespace

void HsOpenEXR::_bind_methods() {
	ClassDB::bind_static_method("HsOpenEXR", D_METHOD("codecs"), &HsOpenEXR::codecs);
	ClassDB::bind_static_method("HsOpenEXR", D_METHOD("version"), &HsOpenEXR::version);
	ClassDB::bind_static_method("HsOpenEXR", D_METHOD("save", "image", "path", "codec", "half", "attributes", "dwa_level"),
			&HsOpenEXR::save, DEFVAL("PIZ"), DEFVAL(true), DEFVAL(Dictionary()), DEFVAL(45.0f));
	ClassDB::bind_static_method("HsOpenEXR", D_METHOD("load", "path"), &HsOpenEXR::load);
	ClassDB::bind_static_method("HsOpenEXR", D_METHOD("info", "path"), &HsOpenEXR::info);
}

PackedStringArray HsOpenEXR::codecs() {
	PackedStringArray out;
	for (const CodecEntry &c : CODECS) {
		out.push_back(c.name);
	}
	return out;
}

String HsOpenEXR::version() {
	return OPENEXR_VERSION_STRING;
}

Error HsOpenEXR::save(const Ref<Image> &image, const String &path, const String &codec, bool half, const Dictionary &attributes, float dwa_level) {
	ERR_FAIL_COND_V_MSG(image.is_null() || image->is_empty(), ERR_INVALID_PARAMETER, "HsOpenEXR.save: immagine vuota");
	Imf::Compression compression;
	ERR_FAIL_COND_V_MSG(!codec_from_name(codec, compression), ERR_INVALID_PARAMETER, String("HsOpenEXR.save: codec sconosciuto ") + codec);

	// OpenEXR non converte i tipi in scrittura: i dati in memoria devono già essere half o float
	// come i canali del file. Si scrivono solo R, G, B (l'alfa di un HDRI è sempre 1).
	Ref<Image> src = image;
	Layout layout;
	const Imf::PixelType file_type = half ? Imf::HALF : Imf::FLOAT;
	if (!layout_of(src->get_format(), layout) || layout.type != file_type) {
		src = image->duplicate();
		src->convert(half ? Image::FORMAT_RGBH : Image::FORMAT_RGBF);
		layout_of(src->get_format(), layout);
	}
	const int w = src->get_width();
	const int h = src->get_height();
	PackedByteArray data = src->get_data();
	ERR_FAIL_COND_V(data.size() != int64_t(w) * h * int64_t(layout.pixel_bytes), ERR_INVALID_DATA);

	const String dest = ProjectSettings::get_singleton()->globalize_path(path);
	const String tmp = dest + String(".tmp.exr");
	Ref<FileAccess> f = FileAccess::open(tmp, FileAccess::WRITE_READ);
	if (f.is_null()) {
		return FileAccess::get_open_error();
	}

	try {
		Imf::Header header(w, h, 1.0f, Imath::V2f(0, 0), 1.0f, Imf::INCREASING_Y, compression);
		if (compression == Imf::DWAA_COMPRESSION || compression == Imf::DWAB_COMPRESSION) {
			header.dwaCompressionLevel() = dwa_level;
		}
		add_attributes(header, attributes);
		const char *names[3] = { "R", "G", "B" };
		Imf::FrameBuffer fb;
		const size_t comp = layout.type == Imf::HALF ? 2 : 4;
		const char *base = reinterpret_cast<const char *>(data.ptr());
		for (int c = 0; c < 3; c++) {
			header.channels().insert(names[c], Imf::Channel(file_type));
			fb.insert(names[c], Imf::Slice(layout.type, const_cast<char *>(base + c * comp), layout.pixel_bytes, layout.pixel_bytes * w));
		}
		GodotOStream os(f, to_std(tmp));
		Imf::OutputFile out(os, header);
		out.setFrameBuffer(fb);
		out.writePixels(h);
	} catch (const std::exception &e) {
		f->close();
		DirAccess::remove_absolute(tmp);
		UtilityFunctions::push_error("HsOpenEXR.save: ", path, ": ", e.what());
		return ERR_FILE_CANT_WRITE;
	}
	f->close();
	if (FileAccess::file_exists(dest)) {
		DirAccess::remove_absolute(dest);
	}
	Error err = DirAccess::rename_absolute(tmp, dest);
	if (err != OK) {
		DirAccess::remove_absolute(tmp);
	}
	return err;
}

Ref<Image> HsOpenEXR::load(const String &path) {
	const String abs = ProjectSettings::get_singleton()->globalize_path(path);
	Ref<FileAccess> f = FileAccess::open(abs, FileAccess::READ);
	if (f.is_null()) {
		return Ref<Image>();
	}
	try {
		GodotIStream is(f, to_std(abs));
		Imf::InputFile in(is);
		const Imf::Header &header = in.header();
		const Imath::Box2i dw = header.dataWindow();
		const int64_t w = int64_t(dw.max.x) - dw.min.x + 1;
		const int64_t h = int64_t(dw.max.y) - dw.min.y + 1;
		if (w <= 0 || h <= 0 || w > 32768 || h > 32768) {
			UtilityFunctions::push_error("HsOpenEXR.load: dimensioni non valide in ", path);
			return Ref<Image>();
		}
		std::string names[4];
		bool mono = false;
		if (!pick_channels(header.channels(), names, mono)) {
			UtilityFunctions::push_error("HsOpenEXR.load: nessun canale RGB in ", path);
			return Ref<Image>();
		}
		PackedByteArray data;
		data.resize(w * h * 16);
		char *base = reinterpret_cast<char *>(data.ptrw());
		const size_t xs = 16, ys = 16 * size_t(w);
		// il puntatore è riferito all'origine del dataWindow: OpenEXR indicizza con le coordinate del file
		char *origin = base - (int64_t(dw.min.x) * xs + int64_t(dw.min.y) * ys);
		Imf::FrameBuffer fb;
		for (int c = 0; c < 4; c++) {
			if (names[c].empty()) {
				continue;
			}
			fb.insert(names[c], Imf::Slice(Imf::FLOAT, origin + c * 4, xs, ys, 1, 1, c == 3 ? 1.0 : 0.0));
		}
		in.setFrameBuffer(fb);
		in.readPixels(dw.min.y, dw.max.y);
		float *px = reinterpret_cast<float *>(base);
		const int64_t n = w * h;
		if (mono) {
			for (int64_t i = 0; i < n; i++) {
				px[i * 4 + 1] = px[i * 4];
				px[i * 4 + 2] = px[i * 4];
			}
		}
		if (names[3].empty()) {
			for (int64_t i = 0; i < n; i++) {
				px[i * 4 + 3] = 1.0f;
			}
		}
		return Image::create_from_data(int(w), int(h), false, Image::FORMAT_RGBAF, data);
	} catch (const std::exception &e) {
		UtilityFunctions::push_error("HsOpenEXR.load: ", path, ": ", e.what());
		return Ref<Image>();
	}
}

Dictionary HsOpenEXR::info(const String &path) {
	Dictionary out;
	const String abs = ProjectSettings::get_singleton()->globalize_path(path);
	Ref<FileAccess> f = FileAccess::open(abs, FileAccess::READ);
	if (f.is_null()) {
		return out;
	}
	try {
		GodotIStream is(f, to_std(abs));
		Imf::InputFile in(is);
		const Imf::Header &header = in.header();
		const Imath::Box2i dw = header.dataWindow();
		out["width"] = int64_t(dw.max.x) - dw.min.x + 1;
		out["height"] = int64_t(dw.max.y) - dw.min.y + 1;
		out["compression"] = codec_name(header.compression());
		PackedStringArray channels;
		bool half = true;
		for (Imf::ChannelList::ConstIterator it = header.channels().begin(); it != header.channels().end(); ++it) {
			channels.push_back(it.name());
			if (it.channel().type != Imf::HALF) {
				half = false;
			}
		}
		out["channels"] = channels;
		out["half"] = half;
		Dictionary attrs;
		for (Imf::Header::ConstIterator it = header.begin(); it != header.end(); ++it) {
			const Imf::StringAttribute *s = dynamic_cast<const Imf::StringAttribute *>(&it.attribute());
			if (s != nullptr) {
				attrs[String(it.name())] = String::utf8(s->value().c_str());
			}
		}
		out["attributes"] = attrs;
	} catch (const std::exception &e) {
		UtilityFunctions::push_error("HsOpenEXR.info: ", path, ": ", e.what());
		return Dictionary();
	}
	return out;
}
