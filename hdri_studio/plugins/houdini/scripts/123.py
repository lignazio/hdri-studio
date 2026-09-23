# Avvio di Houdini senza scena: attacca il live link di HDRI Studio.
try:
    import hdri_studio_link
    hdri_studio_link.start()
except Exception as e:
    print("[hdri-studio] start failed: %r" % e)
