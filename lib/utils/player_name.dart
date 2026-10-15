/// Numele de afișat al unui jucător: username, altfel prenume + nume, altfel partea dinaintea @ din email.
String playerDisplayName(Map<String, dynamic> data, {String? email, required String fallback}) {
  final String u = (data['username'] ?? '').toString().trim();
  if (u.isNotEmpty) return u;
  final String full = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
  if (full.isNotEmpty) return full;
  final String mail = (email ?? data['email'] ?? '').toString();
  if (mail.contains('@')) return mail.split('@').first;
  return fallback;
}
