import 'dart:async';

import 'package:http/http.dart' show ClientException;

// Ripiego sulla copia locale soltanto per errori di trasporto, non per permessi o dati errati.
bool isNetworkFailure(Object error) =>
    error is ClientException || error is TimeoutException;
