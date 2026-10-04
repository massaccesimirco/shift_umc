class AccessFailure implements Exception {
  const AccessFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

String accessErrorMessage(Object error) => error is AccessFailure
    ? error.message
    : 'Servizio non raggiungibile. Controlla la connessione e riprova.';
