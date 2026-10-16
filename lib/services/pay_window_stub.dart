/// Varianta pentru platformele fără browser: nu deschide nimic.
class PayWindow {
  PayWindow._();

  /// Deschide o fereastră goală (pe web, înainte de orice `await`, ca să nu fie blocată ca pop-up).
  static PayWindow? openBlank() => null;

  /// Deschide adresa într-o fereastră nouă (de apelat dintr-un click).
  static PayWindow? open(String url) => null;

  void go(String url) {}

  void close() {}
}
