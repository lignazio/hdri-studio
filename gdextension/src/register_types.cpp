#include "hs_openexr.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include <ImfThreading.h>

#include <thread>

using namespace godot;

static void initialize_hs_openexr(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	unsigned n = std::thread::hardware_concurrency();
	Imf::setGlobalThreadCount(n > 1 ? n : 1);
	GDREGISTER_CLASS(HsOpenEXR);
}

static void uninitialize_hs_openexr(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	Imf::setGlobalThreadCount(0);
}

extern "C" {
GDExtensionBool GDE_EXPORT hs_openexr_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_hs_openexr);
	init_obj.register_terminator(uninitialize_hs_openexr);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
