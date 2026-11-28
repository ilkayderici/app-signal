import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/retry.dart';

/// Geçici ağ hatalarında isteği iki kez daha dener. Windows'ta TLS el
/// sıkışması ara ara `HandshakeException: DECODE_ERROR` ile düşüyor; tek
/// düşen istek tüm kartı hataya çeviriyordu. Jeton yenileme isteği de iç
/// istemcide olduğundan o da yeniden denenir. Yalnız okuma istekleri
/// gönderildiği için POST'u yinelemek güvenli.
http.Client retrying(http.Client inner) => RetryClient(
  inner,
  retries: 2,
  whenError: (e, _) =>
      e is TlsException ||
      e is SocketException ||
      e is HttpException ||
      e is http.ClientException,
);
