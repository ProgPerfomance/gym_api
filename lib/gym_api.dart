import 'dart:convert';
import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:gym_api/services/mongo_service.dart';
import 'middleware/cors_middleware.dart';



Future<void> start() async {
  await mongoService.initMongo();
  final db = mongoService.db!;
  final collection = db.collection('activeTournament');
  final router = Router();

  router.get('/pull', (Request request) async {
    final doc = await collection.findOne();
    if (doc == null) {
      return Response.notFound(jsonEncode({'error': 'Турнир не найден'}));
    }

    return Response.ok(
      jsonEncode(doc),
      headers: {'Content-Type': 'application/json'},
    );
  });

  router.post('/start/<id>', (Request request, String id) async {
    final queue = db.collection('tournaments');
    final active = db.collection('activeTournament');

    final tournament = await queue.findOne(where.id(ObjectId.parse(id)));
    if (tournament == null) {
      return Response.notFound('Турнир не найден');
    }

    // Удаляем старый активный турнир и сохраняем новый
    await active.deleteMany({});
    tournament.remove('_id'); // удаляем старый ID
    await active.insertOne(tournament);

    return Response.ok(jsonEncode({'status': 'started'}), headers: {
      'Content-Type': 'application/json',
    });
  });


  router.get('/tournaments', (Request request) async {
    final queue = db.collection('tournaments');
    final tournaments = await queue.find().toList();

    return Response.ok(
      jsonEncode(tournaments),
      headers: {'Content-Type': 'application/json'},
    );
  });


  router.get('/current', (Request request) async {
    final doc = await collection.findOne();
    if (doc == null || doc['completed'] == true) {
      return Response.notFound('Турнир не найден или завершён');
    }

    final sets = List<Map<String, dynamic>>.from(doc['sets']);
    final setIndex = doc['activeSet'] ?? 0;
    final set = sets[setIndex];

    final itemIndex = set['activeItem'] ?? 0;
    final item = List<Map<String, dynamic>>.from(set['items'])[itemIndex];

    final childIndex = item['activeChild'] ?? 0;
    final child = List<Map<String, dynamic>>.from(item['childrens'])[childIndex];

    final result = {
      'setIndex': setIndex,
      'apparatusId': item['id'],
      'child': child,
    };

    return Response.ok(jsonEncode(result), headers: {
      'Content-Type': 'application/json',
    });
  });


  router.post('/rate', (Request request) async {
    final body = await request.readAsString();
    final data = jsonDecode(body);

    final double? rawRate = (data['rate'] as num?)?.toDouble();
    final String? masterId = data['master_id']?.toString();

    // Округление rate до 2 знаков
    final double? rate = rawRate != null ? double.parse(rawRate.toStringAsFixed(2)) : null;

    if (rate == null || masterId == null || rate < 0 || rate > 10) {
      return Response.badRequest(body: 'Неверный формат данных');
    }

    final doc = await collection.findOne();
    if (doc == null || doc['completed'] == true) {
      return Response.notFound('Турнир не найден или завершён');
    }

    final ObjectId id = doc['_id'] is ObjectId
        ? doc['_id']
        : ObjectId.fromHexString(doc['_id'].toString());

    final setIndex = doc['activeSet'] ?? 0;
    final set = doc['sets'][setIndex];
    final itemIndex = set['activeItem'] ?? 0;
    final item = set['items'][itemIndex];
    final childIndex = item['activeChild'] ?? 0;

    final ratings = item['childrens'][childIndex]['ratings'] as List<dynamic>? ?? [];

    final alreadyRated = ratings.any((r) => r['master_id'] == masterId);
    if (alreadyRated) {
      return Response.forbidden('Оценка от этого судьи уже существует');
    }

    final ratingEntry = {
      'master_id': masterId,
      'rate': rate,
    };

    final path = 'sets.$setIndex.items.$itemIndex.childrens.$childIndex.ratings';

    await collection.update(
      where.id(id),
      modify.push(path, ratingEntry),
    );

    return Response.ok('Оценка добавлена');
  });



  router.post('/tournament', (Request request) async {
    final body = await request.readAsString();
    final data = jsonDecode(body);

    if (data['title'] == null || data['sets'] == null || data['sets'] is! List) {
      return Response.badRequest(body: 'Неверный формат данных турнира');
    }

    final queue = db.collection('tournaments');
    await queue.insertOne({
      ...data,
      'createdAt': DateTime.now().toIso8601String(),
    });

    return Response.ok(jsonEncode({'status': 'ok'}), headers: {
      'Content-Type': 'application/json',
    });
  });


  // === POST /next ===
  router.post('/next', (Request request) async {
    final collection = db.collection('activeTournament');

    final data = await collection.findOne();
    if (data == null) {
      return Response.internalServerError(body: 'Турнир не найден');
    }

    final sets = data['sets'] as List;
    int setIndex = data['activeSet'] ?? 0;

    if (setIndex >= sets.length) {
      return Response.internalServerError(body: 'Нет доступных сетов');
    }

    final set = sets[setIndex] as Map;
    final items = set['items'] as List;
    int itemIndex = set['activeItem'] ?? 0;

    if (itemIndex >= items.length) {
      return Response.internalServerError(body: 'Нет доступных айтемов');
    }

    final item = items[itemIndex] as Map;
    final childrens = item['childrens'] as List;
    int childIndex = item['activeChild'] ?? 0;

    // Шаг 1: инкрементируем child
    childIndex++;

    if (childIndex >= childrens.length) {
      // Переход к следующему item
      childIndex = 0;
      itemIndex++;

      if (itemIndex >= items.length) {
        // Переход к следующему set
        itemIndex = 0;
        setIndex++;

        if (setIndex >= sets.length) {
          final result = await collection.update(
            where.id(data['_id'] as ObjectId),
            modify.set('completed', true),
          );
          return Response.ok('Турнир завершён');
        }
      }
    }
    final result = await collection.update(
      where.id(data['_id'] as ObjectId),
      modify
        ..set('activeSet', setIndex)
        ..set('sets.$setIndex.activeItem', itemIndex)
        ..set('sets.$setIndex.items.$itemIndex.activeChild', childIndex),
    );

      return Response.ok('OK: set=$setIndex item=$itemIndex child=$childIndex');

  });

  final certPath = '/etc/letsencrypt/live/mvpgarage.one/fullchain.pem';
  final keyPath = '/etc/letsencrypt/live/mvpgarage.one/privkey.pem';

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsMiddleware)
      .addHandler(router);

  final securityContext =
  SecurityContext()
    ..useCertificateChain(certPath)
    ..usePrivateKey(keyPath);

  final server = await serve(
    handler,
    '0.0.0.0',
    3890,
    securityContext: securityContext,
  );
}
