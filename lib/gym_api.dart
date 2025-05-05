

import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';

void start () async {


  //await

  Router router = Router();


  router.post('/tournament/create', (Request request) async {

   final Map<String,dynamic> data= jsonDecode(await request.readAsString());

   print(data);

   return Response.ok('ss');

  });

  final server = await serve(router, 'localhost', 3930);
  print(server.address);

}


class TournamentEntity {}