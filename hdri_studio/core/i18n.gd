extends Node
## Lingue dell'app (autoload `I18n`).
##
## L'inglese è la lingua base: le stringhe nel codice sono in inglese e ogni testo senza
## traduzione resta in inglese. L'italiano è una traduzione caricata a runtime da LangIt.
##
## Politica: la lingua salvata in settings.json vince sempre; con "auto" (default) si segue
## la lingua del sistema, quindi italiano su un OS in italiano e inglese in tutti gli altri casi.

## Emesso dopo ogni cambio di lingua: i testi composti a mano vanno riscritti.
signal changed

const SETTING_KEY := "language"
const AUTO := "auto"
const FALLBACK := "en"
## Lingue con una traduzione disponibile (l'inglese è il codice stesso).
const SUPPORTED := ["en", "it"]

var _language := AUTO


func _enter_tree() -> void:
	_install_translations()
	apply(String(AppSettings.get_value(SETTING_KEY, AUTO)))


func _install_translations() -> void:
	var it := Translation.new()
	it.locale = "it"
	for key in LangIt.DATA:
		it.add_message(key, LangIt.DATA[key])
	TranslationServer.add_translation(it)


## "auto", "en" o "it": quello che l'utente ha scelto, non la lingua effettiva.
func language() -> String:
	return _language


## Lingua effettiva, con "auto" già risolto.
func locale() -> String:
	return resolve(_language)


## Solo "auto" guarda il sistema: una lingua scelta a mano vince sempre, e un codice che non
## sappiamo tradurre (settings.json modificato a mano) ricade sull'inglese.
static func resolve(code: String) -> String:
	if code in SUPPORTED:
		return code
	if code != AUTO:
		return FALLBACK
	var system := OS.get_locale_language()
	return system if system in SUPPORTED else FALLBACK


func apply(code: String) -> void:
	_language = code if (code == AUTO or code in SUPPORTED) else FALLBACK
	TranslationServer.set_locale(resolve(_language))
	changed.emit()


## Cambia lingua e la ricorda in settings.json.
func set_language(code: String) -> void:
	AppSettings.set_value(SETTING_KEY, code)
	apply(code)
