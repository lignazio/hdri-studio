class_name UiStyle
extends RefCounted
## Sistema visivo dell'app in un posto solo: tema globale, scala tipografica, scala di spaziatura.
##
## Tutti i valori sono in pixel **logici**: la densità dello schermo (Retina, Windows al 150%) la
## applica main.gd con `content_scale_factor`, qui non se ne tiene conto. Prima di questo file ogni
## pannello aveva i suoi numeri (sei dimensioni di font, nove separazioni): la revisione UX del
## 2026-09-23 li ha ridotti a tre livelli di testo e quattro di spazio.

## Tipografia: tre livelli e basta. Il titolo è il testo più grande del suo pannello.
const FONT_TITLE := 15
const FONT_BODY := 13
const FONT_SMALL := 11

## Spaziatura: 4 fra righe, 8 fra controlli affiancati, 16 sopra un sottotitolo, 24 fra pannelli.
## La distanza fra gruppi deve essere molto più grande di quella dentro un gruppo, altrimenti i
## gruppi non si leggono come tali.
const SPACE_ROW := 4
const SPACE_INLINE := 8
const SPACE_GROUP := 16
const SPACE_PANEL := 24
## Margine fra il bordo di un pannello laterale (o la sua barra di scorrimento) e tutto quello che
## contiene: a 12 px i testi sembravano attaccati al bordo.
const MARGIN := 16

## Colonna delle etichette dei parametri: a 13 px la più lunga, "Risoluzione live", misura ~98 px.
const LABEL_W := 104

## Testo: le etichette sono un gradino sotto i valori, così in una colonna di numeri l'occhio
## atterra sul numero; i titoli sono bianco pieno.
const C_TITLE := Color(1, 1, 1)
const C_LABEL := Color(0.78, 0.78, 0.8)
const C_VALUE := Color(0.96, 0.96, 0.96)
const C_SECTION := Color(0.56, 0.56, 0.6)
const C_HINT := Color(0.62, 0.62, 0.65)
const C_DIM := Color(0.66, 0.66, 0.69)
## Accento: solo selezione e azione principale (export). Mai per decorare.
const C_ACCENT := Color(1.0, 0.8, 0.2)
## Fondi: la cornice è più scura dei pannelli (è lo stesso colore del boot splash).
const C_FRAME := Color(0.094, 0.094, 0.102)
const C_PANEL := Color(0.15, 0.15, 0.16)

static var _theme: Theme


## Il tema dell'app, costruito una volta sopra quello di default di Godot: si cambia solo quello che
## serve e il resto (margini dei pulsanti, icone) resta quello di Godot.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var base := ThemeDB.get_default_theme()
	var t := Theme.new()
	t.default_font_size = FONT_BODY

	t.set_color("font_color", "Label", C_LABEL)
	t.set_color("font_color", "LineEdit", C_VALUE)
	t.set_constant("separation", "VBoxContainer", SPACE_ROW)

	# varianti di Label: titolo, sottotitolo di sezione, suggerimento, testo secondario
	t.set_type_variation("TitleLabel", "Label")
	t.set_font_size("font_size", "TitleLabel", FONT_TITLE)
	t.set_color("font_color", "TitleLabel", C_TITLE)
	t.set_type_variation("SectionLabel", "Label")
	t.set_font_size("font_size", "SectionLabel", FONT_SMALL)
	t.set_color("font_color", "SectionLabel", C_SECTION)
	t.set_type_variation("HintLabel", "Label")
	t.set_font_size("font_size", "HintLabel", FONT_SMALL)
	t.set_color("font_color", "HintLabel", C_HINT)
	t.set_type_variation("DimLabel", "Label")
	t.set_color("font_color", "DimLabel", C_DIM)

	# fondi uniformi: le due colonne laterali con lo stesso grigio, la cornice più scura
	var panel := StyleBoxFlat.new()
	panel.bg_color = C_PANEL
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "TabContainer", panel)
	var tab_sel := _flat(base, "tab_selected", "TabContainer")
	tab_sel.bg_color = C_PANEL
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)

	# caselle di spunta disegnate da noi: quella di default, vuota, ha contrasto 1,16:1 col fondo
	t.set_icon("unchecked", "CheckBox", LightIcons.check_off())
	t.set_icon("checked", "CheckBox", LightIcons.check_on())
	t.set_icon("unchecked_disabled", "CheckBox", LightIcons.check_off())
	t.set_icon("checked_disabled", "CheckBox", LightIcons.check_on())

	# schede della colonna sinistra allineate al margine del contenuto
	t.set_constant("side_margin", "TabContainer", MARGIN)

	# lista luci: più aria fra occhio, solo e lucchetto (bersagli da almeno 24 px)
	t.set_constant("button_margin", "Tree", 6)

	# campioni colore: un filo di bordo, altrimenti un colore quasi nero sparisce nel pannello
	var swatch := _flat(base, "normal", "Button")
	swatch.set_border_width_all(1)
	swatch.border_color = Color(1, 1, 1, 0.22)
	t.set_stylebox("normal", "ColorPickerButton", swatch)

	# pulsante d'accento per l'azione principale
	t.set_type_variation("AccentButton", "Button")
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := _flat(base, state if state != "focus" else "normal", "Button")
		match state:
			"normal":
				sb.bg_color = C_ACCENT.darkened(0.12)
			"hover":
				sb.bg_color = C_ACCENT
			"pressed":
				sb.bg_color = C_ACCENT.darkened(0.3)
			"focus":
				sb.draw_center = false
				sb.set_border_width_all(1)
				sb.border_color = Color(1, 1, 1, 0.7)
			"disabled":
				sb.bg_color = C_ACCENT.darkened(0.6)
		t.set_stylebox(state, "AccentButton", sb)
	var ink := Color(0.08, 0.08, 0.09)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "AccentButton", ink)
	t.set_color("font_disabled_color", "AccentButton", Color(0.08, 0.08, 0.09, 0.6))
	_theme = t
	return t


## Copia di uno stylebox del tema di default (per tenerne margini e raggi), o uno nuovo se in una
## versione futura di Godot non fosse più un StyleBoxFlat.
static func _flat(base: Theme, name: String, type: String) -> StyleBoxFlat:
	var sb := base.get_stylebox(name, type)
	if sb is StyleBoxFlat:
		return sb.duplicate() as StyleBoxFlat
	var f := StyleBoxFlat.new()
	f.set_content_margin_all(6)
	return f


## Titolo di pannello.
static func title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "TitleLabel"
	return l


## Sottotitolo di sezione: piccolo e maiuscolo, si distingue per forma e posizione invece di
## competere in luminosità con le righe che raggruppa.
static func section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.uppercase = true
	l.theme_type_variation = "SectionLabel"
	return l


## Suggerimento d'uso: va a capo invece di allargare la colonna.
static func hint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "HintLabel"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## Testo secondario su una riga (nome di file, percorso): taglia con i puntini.
static func dim(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "DimLabel"
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# riceve il mouse per mostrare il tooltip col percorso completo
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


## Stato su più righe (esiti di export, live link).
static func status() -> Label:
	var l := Label.new()
	l.theme_type_variation = "DimLabel"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## Etichetta della colonna dei parametri: larghezza unica, così i controlli partono tutti alla
## stessa x; una traduzione più lunga finisce coi puntini invece di spingere il controllo.
static func field_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = LABEL_W
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return l


## Riga "etichetta + controllo che si allarga".
static func field_row(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_child(field_label(text))
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


## Avvolge un controllo nei margini del pannello (di default MARGIN su tutti i lati).
static func pad(content: Control, left := MARGIN, top := MARGIN, right := MARGIN, bottom := MARGIN) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", left)
	m.add_theme_constant_override("margin_top", top)
	m.add_theme_constant_override("margin_right", right)
	m.add_theme_constant_override("margin_bottom", bottom)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(content)
	return m


static func spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## L'unica linea orizzontale dell'app: fra un pannello e il successivo. Dentro un pannello i gruppi
## si separano con lo spazio.
static func separator() -> HSeparator:
	var s := HSeparator.new()
	s.add_theme_constant_override("separation", SPACE_PANEL)
	return s
