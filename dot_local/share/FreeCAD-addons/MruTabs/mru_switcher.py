# MRU Ctrl+Tab document switcher for FreeCAD, Windows 11 Alt+Tab style
# Memory-bounded: thumbnails only, one per open window, freed on close.
import os
import zipfile

import FreeCAD
import FreeCADGui
from PySide import QtCore, QtGui

try:
    import shiboken6 as shiboken
except ImportError:
    import shiboken2 as shiboken

try:
    from PySide6.QtOpenGLWidgets import QOpenGLWidget
except ImportError:
    try:
        from PySide2.QtWidgets import QOpenGLWidget
    except ImportError:
        QOpenGLWidget = None

Qt = QtCore.Qt
QEvent = QtCore.QEvent

# ---- look & feel ---------------------------------------------------------
THUMB_W, THUMB_H = 240, 150     # preview size (logical px)
CARD_PAD = 10
TITLE_H = 28
SPACING = 12
MARGIN = 18
MAX_COLS = 5
SHOW_DELAY_MS = 120             # quick tap = switch without popup
CAPTURE_DELAY_MS = 400          # wait for the view to paint before caching
PANEL_BG = QtGui.QColor(32, 32, 32, 235)
PANEL_BORDER = QtGui.QColor(255, 255, 255, 40)
SEL_BORDER = QtGui.QColor(255, 255, 255, 230)
TEXT = QtGui.QColor(240, 240, 240)
CLOSE_SIZE = 20                 # close ("X") button size
CLOSE_HOVER_BG = QtGui.QColor(196, 43, 28)      # Windows 11 close red
CLOSE_FG = QtGui.QColor(220, 220, 220)

_NO_THUMB = False               # cache sentinel: "looked, nothing found"


def _alive(obj):
    try:
        return obj is not None and shiboken.isValid(obj)
    except Exception:
        return False


# ---- thumbnail sources (always return a small image) ---------------------
def _shrink(img, dpr):
    if img is None or img.isNull():
        return None
    small = img.scaled(int(THUMB_W * dpr), int(THUMB_H * dpr),
                       Qt.KeepAspectRatio, Qt.SmoothTransformation)
    small.setDevicePixelRatio(dpr)
    return small                # full-size img is freed when caller returns


def _grab_live(sub, dpr):
    """Capture a *visible* window only; hidden tabs come from the cache."""
    if not _alive(sub):
        return None
    w = sub.widget()
    if w is None or not w.isVisible() or w.width() <= 0:
        return None
    try:
        gl = w.findChild(QOpenGLWidget) if QOpenGLWidget is not None else None
        img = gl.grabFramebuffer() if gl is not None else w.grab().toImage()
    except Exception:
        return None
    return _shrink(img, dpr)


def _doc_for(sub):
    label = sub.windowTitle().replace("[*]", "").split(" : ")[0].strip()
    for name, doc in FreeCAD.listDocuments().items():
        if doc.Label == label or name == label:
            return doc
    return None


def _is_modified(sub):
    """Unsaved changes? Same flag FreeCAD uses for the '*' in the tab bar."""
    try:
        if sub.isWindowModified():
            return True
        w = sub.widget()
        if w is not None and w.isWindowModified():
            return True
        doc = _doc_for(sub)
        gdoc = FreeCADGui.getDocument(doc.Name) if doc else None
        return bool(getattr(gdoc, "Modified", False))
    except Exception:
        return False


def _file_thumbnail(sub, dpr):
    doc = _doc_for(sub)
    path = getattr(doc, "FileName", "") if doc else ""
    if not path or not os.path.isfile(path):
        return None
    try:
        with zipfile.ZipFile(path) as z:
            data = z.read("thumbnails/Thumbnail.png")
        img = QtGui.QImage()
        img.loadFromData(QtCore.QByteArray(data))
        return _shrink(img, dpr)
    except Exception:
        return None


# ---- popup ---------------------------------------------------------------
class SwitcherPopup(QtGui.QWidget):
    clicked = QtCore.Signal(int)
    close_clicked = QtCore.Signal(int)

    def __init__(self, parent):
        super().__init__(parent, Qt.ToolTip | Qt.FramelessWindowHint)
        self.setAttribute(Qt.WA_TranslucentBackground)
        self.setAttribute(Qt.WA_ShowWithoutActivating)
        self.setMouseTracking(True)
        self.items = []          # (title, QIcon, QPixmap | None, modified) - only while shown
        self.rects = []
        self.close_rects = []
        self.index = 0
        self.hover = -1
        self.hover_close = -1
        self.title_font = QtGui.QFont(self.font())
        self.title_font.setPointSizeF(self.title_font.pointSizeF() * 1.05)

    def set_items(self, items, index):
        self.items, self.index = items, index
        self.hover = self.hover_close = -1
        self._layout()
        self.update()

    def set_index(self, index):
        self.index = index
        self.update()

    def remove_item(self, i, new_index):
        if 0 <= i < len(self.items):
            del self.items[i]
        self.index = new_index
        self.hover = self.hover_close = -1
        self._layout()
        self.update()

    def clear(self):
        """Release all pixmaps/icons held by the popup."""
        self.items = []
        self.rects = []
        self.close_rects = []
        self.hover = self.hover_close = -1

    def hideEvent(self, ev):
        self.clear()
        super().hideEvent(ev)

    def _layout(self):
        n = len(self.items)
        cw = THUMB_W + 2 * CARD_PAD
        ch = THUMB_H + TITLE_H + 2 * CARD_PAD
        screen = self.parentWidget().screen().availableGeometry()
        fit = int((screen.width() - 80 - 2 * MARGIN + SPACING) // (cw + SPACING))
        cols = max(1, min(n, MAX_COLS, fit))
        rows = (n + cols - 1) // cols
        self.rects = []
        self.close_rects = []
        for i in range(n):
            r, c = divmod(i, cols)
            in_row = cols if r < rows - 1 else n - cols * (rows - 1)
            x0 = MARGIN + (cols - in_row) * (cw + SPACING) / 2.0
            rect = QtCore.QRectF(x0 + c * (cw + SPACING),
                                 MARGIN + r * (ch + SPACING), cw, ch)
            self.rects.append(rect)
            self.close_rects.append(QtCore.QRectF(
                rect.right() - CARD_PAD - CLOSE_SIZE,
                rect.top() + CARD_PAD + (TITLE_H - 4 - CLOSE_SIZE) / 2.0,
                CLOSE_SIZE, CLOSE_SIZE))
        self.resize(int(2 * MARGIN + cols * cw + (cols - 1) * SPACING),
                    int(2 * MARGIN + rows * ch + (rows - 1) * SPACING))

    def paintEvent(self, ev):
        if not self.items:
            return
        p = QtGui.QPainter(self)
        p.setRenderHint(QtGui.QPainter.Antialiasing)
        p.setRenderHint(QtGui.QPainter.SmoothPixmapTransform)

        p.setPen(QtGui.QPen(PANEL_BORDER, 1))
        p.setBrush(PANEL_BG)
        p.drawRoundedRect(QtCore.QRectF(self.rect()).adjusted(0.5, 0.5, -0.5, -0.5), 14, 14)

        p.setFont(self.title_font)
        fm = p.fontMetrics()
        for i, (title, icon, pix, modified) in enumerate(self.items):
            r = self.rects[i]
            sel, hov = i == self.index, i == self.hover
            if sel or hov:
                p.setBrush(QtGui.QColor(255, 255, 255, 28 if sel else 16))
                p.setPen(QtGui.QPen(SEL_BORDER, 2.5) if sel else Qt.NoPen)
                p.drawRoundedRect(r.adjusted(1.5, 1.5, -1.5, -1.5), 10, 10)

            tx, ty = r.left() + CARD_PAD, r.top() + CARD_PAD
            if icon is not None and not icon.isNull():
                icon.paint(p, QtCore.QRect(int(tx), int(ty + (TITLE_H - 18) / 2 - 2), 18, 18))
                tx += 24
            avail = int(r.right() - CARD_PAD - CLOSE_SIZE - 6 - tx)
            if modified:            # keep the '*' visible even when the name is elided
                text = fm.elidedText(title, Qt.ElideRight,
                                     max(0, avail - fm.horizontalAdvance("*"))) + "*"
            else:
                text = fm.elidedText(title, Qt.ElideRight, avail)
            p.setPen(TEXT)
            p.drawText(QtCore.QRectF(tx, ty, avail, TITLE_H - 4),
                       int(Qt.AlignVCenter | Qt.AlignLeft), text)

            if sel or hov:
                self._paint_close(p, self.close_rects[i], i == self.hover_close)

            tr = QtCore.QRectF(r.left() + CARD_PAD, ty + TITLE_H, THUMB_W, THUMB_H)
            clip = QtGui.QPainterPath()
            clip.addRoundedRect(tr, 6, 6)
            p.save()
            p.setClipPath(clip)
            p.fillRect(tr, QtGui.QColor(18, 18, 18))
            if pix is not None:
                dpr = pix.devicePixelRatio() or 1.0
                pr = QtCore.QRectF(0, 0, pix.width() / dpr, pix.height() / dpr)
                pr.moveCenter(tr.center())
                p.drawPixmap(pr.toRect(), pix)
            elif icon is not None and not icon.isNull():
                c = tr.center()
                icon.paint(p, QtCore.QRect(int(c.x() - 24), int(c.y() - 24), 48, 48))
            p.restore()
        p.end()

    @staticmethod
    def _paint_close(p, rect, hot):
        p.save()
        if hot:
            p.setPen(Qt.NoPen)
            p.setBrush(CLOSE_HOVER_BG)
            p.drawRoundedRect(rect, 4, 4)
        pen = QtGui.QPen(QtGui.QColor(255, 255, 255) if hot else CLOSE_FG, 1.6)
        pen.setCapStyle(Qt.RoundCap)
        p.setPen(pen)
        g = rect.adjusted(6, 6, -6, -6)
        p.drawLine(g.topLeft(), g.bottomRight())
        p.drawLine(g.topRight(), g.bottomLeft())
        p.restore()

    def _hit(self, ev):
        """Return (card index or -1, True if on that card's close button)."""
        pos = ev.position() if hasattr(ev, "position") else QtCore.QPointF(ev.pos())
        for i, r in enumerate(self.rects):
            if r.contains(pos):
                return i, self.close_rects[i].contains(pos)
        return -1, False

    def mouseMoveEvent(self, ev):
        h, on_close = self._hit(ev)
        hc = h if on_close else -1
        if h != self.hover or hc != self.hover_close:
            self.hover, self.hover_close = h, hc
            self.update()

    def leaveEvent(self, ev):
        self.hover = self.hover_close = -1
        self.update()

    def mousePressEvent(self, ev):
        h, on_close = self._hit(ev)
        if h >= 0:
            (self.close_clicked if on_close else self.clicked).emit(h)


# ---- switcher logic ------------------------------------------------------
class MruSwitcher(QtCore.QObject):
    def __init__(self, mdi):
        super().__init__(mdi)
        self.mdi = mdi
        self.dead = False
        self.mru = []            # QMdiSubWindow, most recent first
        self.cache = {}          # QMdiSubWindow -> small QImage | _NO_THUMB
        self.cycling = False
        self.snapshot = []
        self.index = 0
        self._capture_target = None

        self.popup = SwitcherPopup(mdi.window())
        self.popup.clicked.connect(self._on_click)
        self.popup.close_clicked.connect(self._on_close_clicked)

        self.show_timer = QtCore.QTimer(self)
        self.show_timer.setSingleShot(True)
        self.show_timer.timeout.connect(self._show_popup)

        self.capture_timer = QtCore.QTimer(self)      # one reusable timer
        self.capture_timer.setSingleShot(True)
        self.capture_timer.timeout.connect(self._capture_active)

        for w in reversed(mdi.subWindowList(QtGui.QMdiArea.ActivationHistoryOrder)):
            self._track(w)
            self.mru.append(w)

        mdi.subWindowActivated.connect(self._on_activated)
        QtGui.QApplication.instance().installEventFilter(self)

    # ---- lifetime --------------------------------------------------------
    def _track(self, sub):
        """Hook destroyed() once per window so its data is freed immediately."""
        if not _alive(sub) or sub.property("_mru_tracked"):
            return
        sub.setProperty("_mru_tracked", True)
        sub.destroyed.connect(lambda *_a, s=sub: self._forget(s))

    def _forget(self, sub):
        if self.dead:
            return
        self.mru = [w for w in self.mru if w is not sub]
        self.cache.pop(sub, None)
        if self._capture_target is sub:
            self._capture_target = None
        if self.cycling and any(w is sub for w in self.snapshot):
            # e.g. other views of a document that just closed: drop their cards,
            # deferred so we don't re-layout from inside destroyed()
            QtCore.QTimer.singleShot(0, lambda s=sub: self._drop_from_snapshot(s))

    def _drop_from_snapshot(self, sub):
        if self.dead or not self.cycling:
            return
        idx = next((k for k, w in enumerate(self.snapshot) if w is sub), -1)
        if idx < 0:
            return
        del self.snapshot[idx]
        if not self.snapshot:
            self._finish(commit=False)
            return
        if self.index > idx:
            self.index -= 1
        self.index = min(self.index, len(self.snapshot) - 1)
        if self.popup.isVisible():
            self.popup.remove_item(idx, self.index)
            self._center_popup()

    def _prune(self):
        live = [w for w in self.mdi.subWindowList() if _alive(w)]
        self.mru = [w for w in self.mru if _alive(w) and w in live]
        for w in live:
            if w not in self.mru:
                self._track(w)
                self.mru.append(w)
        self.cache = {w: v for w, v in self.cache.items() if _alive(w) and w in live}

    def shutdown(self):
        self.dead = True
        self._finish(commit=False)
        QtGui.QApplication.instance().removeEventFilter(self)
        self.show_timer.stop()
        self.capture_timer.stop()
        try:
            self.mdi.subWindowActivated.disconnect(self._on_activated)
        except Exception:
            pass
        self.cache.clear()
        self.mru.clear()
        self.snapshot = []
        self._capture_target = None
        self.popup.deleteLater()
        self.deleteLater()

    # ---- MRU + cache -----------------------------------------------------
    def _on_activated(self, sub):
        if sub is None or self.cycling or not _alive(sub):
            return
        self._track(sub)
        self.mru = [w for w in self.mru if w is not sub]
        self.mru.insert(0, sub)
        self._capture_target = sub                    # debounced: last one wins
        self.capture_timer.start(CAPTURE_DELAY_MS)

    def _capture_active(self):
        sub, self._capture_target = self._capture_target, None
        if _alive(sub) and sub is self.mdi.activeSubWindow():
            img = _grab_live(sub, self.popup.devicePixelRatioF())
            if img is not None:
                self.cache[sub] = img

    def _thumb_for(self, sub, dpr):
        if sub is self.mdi.activeSubWindow():         # only visible one is live
            img = _grab_live(sub, dpr)
            if img is not None:
                self.cache[sub] = img
                return img
        cached = self.cache.get(sub)
        if cached is None:                            # never looked: try file once
            cached = _file_thumbnail(sub, dpr) or _NO_THUMB
            self.cache[sub] = cached
        return cached or None

    # ---- cycling ---------------------------------------------------------
    def _step(self, delta):
        if not self.cycling:
            self._prune()
            if len(self.mru) < 2:
                return
            self.cycling = True
            self.snapshot = list(self.mru)
            self.index = 0
            self.show_timer.start(SHOW_DELAY_MS)
        self.index = (self.index + delta) % len(self.snapshot)
        if self.popup.isVisible():
            self.popup.set_index(self.index)

    def _show_popup(self):
        if not self.cycling:
            return
        dpr = self.popup.devicePixelRatioF()
        items = []
        for w in self.snapshot:
            if not _alive(w):
                self._finish(commit=False)
                return
            img = self._thumb_for(w, dpr)
            pix = QtGui.QPixmap.fromImage(img) if img is not None else None
            items.append((w.windowTitle().replace("[*]", ""), w.windowIcon(), pix,
                          _is_modified(w)))
        self.popup.set_items(items, self.index)
        self._center_popup()
        self.popup.show()
        self.popup.raise_()

    def _center_popup(self):
        geo = self.popup.frameGeometry()
        geo.moveCenter(self.mdi.mapToGlobal(self.mdi.rect().center()))
        self.popup.move(geo.topLeft())

    def _on_click(self, i):
        if self.cycling:
            self.index = i
            self._finish(commit=True)

    def _on_close_clicked(self, i):
        """Close a view from its card - same behaviour as the tab bar's X."""
        if not self.cycling or not 0 <= i < len(self.snapshot):
            return
        sub = self.snapshot[i]
        if not _alive(sub):
            self._drop_from_snapshot(sub)
            return
        if _is_modified(sub):
            # FreeCAD will ask to save: get out of the way first, so releasing
            # Ctrl while the dialog is open doesn't commit a switch.
            self._finish(commit=False)
            QtCore.QTimer.singleShot(0, lambda s=sub: _alive(s) and s.close())
            return
        if sub.close():
            self._drop_from_snapshot(sub)

    def _finish(self, commit):
        if not self.cycling:
            return
        self.cycling = False
        self.show_timer.stop()
        self.popup.hide()                             # hideEvent frees pixmaps
        target = self.snapshot[self.index] if commit and self.snapshot else None
        self.snapshot = []
        if _alive(target) and target in self.mdi.subWindowList():
            self.mdi.setActiveSubWindow(target)
            self._on_activated(target)

    # ---- keyboard --------------------------------------------------------
    def eventFilter(self, obj, ev):
        t = ev.type()

        if t == QEvent.KeyRelease:
            if self.cycling and ev.key() == Qt.Key_Control:
                self._finish(commit=True)
            return False

        if t == QEvent.ShortcutOverride or t == QEvent.KeyPress:
            key = ev.key()
            if key == Qt.Key_Tab or key == Qt.Key_Backtab:
                mods = ev.modifiers()
                if (mods & Qt.ControlModifier
                        and QtGui.QApplication.activeModalWidget() is None
                        and len(self.mdi.subWindowList()) > 1):
                    if t == QEvent.ShortcutOverride:
                        ev.accept()                   # block FreeCAD's Ctrl+Tab
                        return True
                    back = key == Qt.Key_Backtab or bool(mods & Qt.ShiftModifier)
                    self._step(-1 if back else 1)
                    return True
            if self.cycling:
                if t == QEvent.ShortcutOverride:
                    ev.accept()                       # swallow shortcuts while open
                    return True
                if key == Qt.Key_Escape:
                    self._finish(commit=False)
                    return True
                if key == Qt.Key_Return or key == Qt.Key_Enter:
                    self._finish(commit=True)
                    return True
                if key == Qt.Key_Right or key == Qt.Key_Left:
                    self._step(1 if key == Qt.Key_Right else -1)
                    return True
                if key == Qt.Key_Delete:
                    self._on_close_clicked(self.index)
                    return True
            return False

        if t == QEvent.ApplicationDeactivate and self.cycling:
            self._finish(commit=False)

        return False


# ---- startup / control ---------------------------------------------------
def _install(tries=0):
    mw = FreeCADGui.getMainWindow()
    mdi = mw.findChild(QtGui.QMdiArea) if mw else None
    if mdi is None:
        if tries < 20:
            QtCore.QTimer.singleShot(500, lambda: _install(tries + 1))
        return
    FreeCADGui._mru_switcher = MruSwitcher(mdi)


def start():
    if not hasattr(FreeCADGui, "_mru_switcher"):
        QtCore.QTimer.singleShot(0, _install)


def stop():
    sw = getattr(FreeCADGui, "_mru_switcher", None)
    if sw is not None:
        sw.shutdown()
        del FreeCADGui._mru_switcher


def restart():
    """Reload after editing this file:  import mru_switcher; mru_switcher.restart()"""
    import importlib
    import sys
    stop()
    mod = importlib.reload(sys.modules[__name__])
    mod.start()

