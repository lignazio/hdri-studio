extends SceneTree
## Smoke test delle lingue: inglese di base, traduzione italiana, politica "auto" e cambio a caldo.
## Uso:  Godot --path hdri_studio -s res://tools/i18n_smoke.gd

var _ok := true


func _initialize() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run(main)


func _run(main: Node) -> void:
	await process_frame
	# con `-s` l'autoload non è un identificatore noto al compilatore: si prende dal /root
	var I18n: Node = root.get_node("/root/I18n")
	var before: String = I18n.language()

	# la politica: "auto" segue l'OS, le altre due vincono sempre
	_check(I18n.resolve("en") == "en" and I18n.resolve("it") == "it", "scelta esplicita rispettata")
	var system := OS.get_locale_language()
	var expected: String = system if system in I18n.SUPPORTED else I18n.FALLBACK
	_check(I18n.resolve(I18n.AUTO) == expected, "auto → %s (OS: %s)" % [expected, system])
	_check(I18n.resolve("de") == "en", "lingua non tradotta → inglese")

	# inglese: nessuna traduzione, le chiavi restano come sono
	I18n.apply("en")
	await process_frame
	_check(main.tr("Export") == "Export", "inglese: chiave invariata")
	_check(main.export_panel.get_child(0).text == "Export", "pannello export in inglese")
	_check(main.light_list.SHAPE_LABELS[0] == "Rectangle", "forme in inglese")

	# italiano: tradotto, comprese le stringhe composte a mano
	I18n.apply("it")
	await process_frame
	_check(main.tr("Export EXR…") == "Esporta EXR…", "italiano: pulsante tradotto")
	_check(main.tr("Rectangle") == "Rettangolo", "italiano: forma tradotta")
	_check(main.status.text.contains("luci"), "barra di stato ritradotta")
	_check(main.tr(main._status_bar.tooltip_text).contains("duplica"), "scorciatoie (tooltip della barra) tradotte")
	_check(main.tr("Rig saved: %s") % "a.json" == "Rig salvato: a.json", "formato con %s tradotto")

	# ogni chiave del dizionario deve esistere ed essere diversa dall'inglese
	var untranslated := 0
	for key in LangIt.DATA:
		if main.tr(key) != LangIt.DATA[key]:
			untranslated += 1
	_check(untranslated == 0, "%d voci del dizionario non applicate" % untranslated)

	I18n.apply("en")
	await process_frame
	_check(main.status.text.contains("lights"), "ritorno all'inglese")

	# il selettore in fondo alla colonna destra cambia lingua e la ricorda in settings.json
	var picker := _find_language_picker(main)
	_check(picker != null, "selettore della lingua nell'interfaccia")
	if picker != null:
		picker.item_selected.emit(2)
		await process_frame
		_check(I18n.locale() == "it" and AppSettings.get_value("language", "") == "it", "selettore → italiano, ricordato")
		picker.item_selected.emit(0)
		await process_frame
		_check(AppSettings.get_value("language", "") == I18n.AUTO, "selettore → automatico, ricordato")
	I18n.set_language(before)

	print("[i18n] ", "TUTTO OK" if _ok else "FALLITO")
	quit(0 if _ok else 1)


## L'OptionButton delle lingue: l'unico con "Italiano" tra le voci.
func _find_language_picker(node: Node) -> OptionButton:
	if node is OptionButton:
		var ob := node as OptionButton
		for i in ob.item_count:
			if ob.get_item_text(i) == "Italiano":
				return ob
	for c in node.get_children():
		var found := _find_language_picker(c)
		if found != null:
			return found
	return null


func _check(cond: bool, msg: String) -> void:
	print("[i18n] %s %s" % ["✓" if cond else "✗", msg])
	if not cond:
		_ok = false
