import FreeCAD
try:
    import mru_switcher
    mru_switcher.start()
    FreeCAD.Console.PrintLog("MruTabs: loaded\n")
except Exception as e:
    FreeCAD.Console.PrintError("MruTabs failed: %s\n" % e)

