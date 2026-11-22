import 'dart:convert';

String? passwordError(String? value) {
  if (value == null || value.trim().isEmpty || value.runes.length < 8) {
    return 'Usa almeno 8 caratteri.';
  }
  if (utf8.encode(value).length > 72) {
    return 'Password troppo lunga. Scegline una più breve.';
  }
  return null;
}
