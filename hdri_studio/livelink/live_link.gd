class_name LiveLink
extends Node
## Server TCP locale per il live link con il software 3D. Protocollo JSON-lines (un oggetto per riga).
##
## app → plugin   {"type":"hdri_updated","path":"…/rig.exr","target":"Cinema 4D + Octane","seq":12}
## plugin → app   {"type":"hello","host":"c4d","version":"2026","renderer":"octane"}
## plugin → app   {"type":"lightpaint","point":[x,y,z],"normal":[x,y,z],"camera":[x,y,z]}  (Fase 3)

signal message_received(msg: Dictionary, client_id: int)
signal clients_changed(count: int)

const DEFAULT_PORT := 47820

var port := DEFAULT_PORT
var _server := TCPServer.new()
var _peers: Array[StreamPeerTCP] = []
var _buffers: Array[String] = []
var _seq := 0


func is_listening() -> bool:
	return _server.is_listening()


func start(p := DEFAULT_PORT) -> Error:
	stop()
	port = p
	var err := _server.listen(port, "127.0.0.1")
	if err != OK:
		push_warning("Live link: cannot listen on port %d (%s)" % [port, error_string(err)])
	return err


func stop() -> void:
	for peer in _peers:
		peer.disconnect_from_host()
	_peers.clear()
	_buffers.clear()
	if _server.is_listening():
		_server.stop()
	clients_changed.emit(0)


func client_count() -> int:
	return _peers.size()


func broadcast(msg: Dictionary) -> void:
	if _peers.is_empty():
		return
	_seq += 1
	msg["seq"] = _seq
	var line := (JSON.stringify(msg) + "\n").to_utf8_buffer()
	for peer in _peers:
		peer.put_data(line)


func notify_hdri(path: String, target: String) -> void:
	broadcast({"type": "hdri_updated", "path": ProjectSettings.globalize_path(path), "target": target})


func _process(_delta: float) -> void:
	if not _server.is_listening():
		return
	while _server.is_connection_available():
		var peer := _server.take_connection()
		peer.set_no_delay(true)
		_peers.append(peer)
		_buffers.append("")
		clients_changed.emit(_peers.size())
	var i := 0
	while i < _peers.size():
		var peer := _peers[i]
		peer.poll()
		var status := peer.get_status()
		if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
			_peers.remove_at(i)
			_buffers.remove_at(i)
			clients_changed.emit(_peers.size())
			continue
		var n := peer.get_available_bytes()
		if n > 0:
			_buffers[i] += peer.get_utf8_string(n)
			_drain(i)
		i += 1


func _drain(i: int) -> void:
	var buf := _buffers[i]
	while true:
		var nl := buf.find("\n")
		if nl < 0:
			break
		var line := buf.substr(0, nl).strip_edges()
		buf = buf.substr(nl + 1)
		if line.is_empty():
			continue
		var parsed = JSON.parse_string(line)
		if parsed is Dictionary:
			message_received.emit(parsed, i)
		else:
			push_warning("Live link: non-JSON line: " + line)
	_buffers[i] = buf
