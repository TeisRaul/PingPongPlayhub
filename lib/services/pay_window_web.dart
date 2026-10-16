import 'dart:js_interop';

@JS('window.open')
external _JsWindow? _windowOpen(JSString url, JSString target);

extension type _JsWindow(JSObject _) implements JSObject {
  external _JsLocation get location;
  external bool get closed;
  external void close();
}

extension type _JsLocation(JSObject _) implements JSObject {
  external set href(JSString value);
}

/// Fereastra browserului în care se deschide pagina Stripe Checkout.
class PayWindow {
  PayWindow._(this._win);

  final _JsWindow _win;

  /// Deschide o fereastră goală. Se apelează imediat după click, înainte de orice `await`,
  /// altfel browserul o poate bloca drept pop-up. Întoarce null dacă a fost blocată.
  static PayWindow? openBlank() => _wrap(_windowOpen(''.toJS, '_blank'.toJS));

  /// Deschide direct adresa (de apelat dintr-un click, de ex. „Deschide din nou plata").
  static PayWindow? open(String url) => _wrap(_windowOpen(url.toJS, '_blank'.toJS));

  static PayWindow? _wrap(_JsWindow? w) {
    try {
      if (w == null || w.closed) return null;
      return PayWindow._(w);
    } catch (_) {
      return null;
    }
  }

  void go(String url) {
    try {
      _win.location.href = url.toJS;
    } catch (_) {}
  }

  void close() {
    try {
      if (!_win.closed) _win.close();
    } catch (_) {}
  }
}
