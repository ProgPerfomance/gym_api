import 'package:shelf/shelf.dart';

import '../core/headers.dart';

Middleware corsMiddleware = (Handler handler) {
  return (Request request) async {
    if (request.method == 'OPTIONS') {
      return Response.ok('', headers: corsHeaders);
    }

    final response = await handler(request);
    return response.change(headers: {
      ...response.headers,
      ...corsHeaders,
    });
  };
};