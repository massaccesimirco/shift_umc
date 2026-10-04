import 'dart:convert';

class BackendConfig {
  const BackendConfig({required this.url, required this.publicKey});
  const BackendConfig.fromEnvironment()
    : url = const String.fromEnvironment('SUPABASE_URL'),
      publicKey = const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  final String url;
  final String publicKey;

  bool get isValid {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return false;
    }
    if (publicKey.startsWith('sb_publishable_')) {
      return publicKey.length > 'sb_publishable_'.length;
    }
    // Compatibilità con le vecchie chiavi anon. Le service_role sono vietate.
    try {
      final parts = publicKey.split('.');
      if (parts.length != 3) return false;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      return payload is Map && payload['role'] == 'anon';
    } catch (_) {
      return false;
    }
  }
}
