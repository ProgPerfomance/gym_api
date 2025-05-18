import 'dart:convert';
import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'middleware/cors_middleware.dart';
import 'package:gym_api/services/mongo_service.dart';

Future<void> start() async {
  await mongoService.initMongo();
  final db = mongoService.db!;
  final router = Router();

  final tournaments = db.collection('tournaments');
  final active = db.collection('activeTournament');

  router.get('/pull', (Request request) async {
    final activeDoc = await active.findOne();
    if (activeDoc == null || activeDoc['tournamentId'] == null) {
      return Response.notFound(jsonEncode({'error': 'Активный турнир не найден'}));
    }

    final tournament = await tournaments.findOne(where.id(activeDoc['tournamentId'] as ObjectId));
    if (tournament == null) {
      return Response.notFound(jsonEncode({'error': 'Турнир не найден'}));
    }

    return Response.ok(jsonEncode(tournament), headers: {'Content-Type': 'application/json'});
  });

  router.get('/tournaments', (Request request) async {
    final result = await tournaments.find().toList();
    return Response.ok(jsonEncode(result), headers: {'Content-Type': 'application/json'});
  });

  router.post('/start/<id>', (Request request, String id) async {
    final ObjectId tid = ObjectId.parse(id);
    final tournament = await tournaments.findOne(where.id(tid));
    if (tournament == null) {
      return Response.notFound('Турнир не найден');
    }

    await tournaments.update(where.id(tid), modify.set('status', 'active'));
    await active.deleteMany({});
    await active.insertOne({'tournamentId': tid});

    return Response.ok(jsonEncode({'status': 'started'}));
  });

  router.get('/current', (Request request) async {
    final activeDoc = await active.findOne();
    if (activeDoc == null) return Response.notFound('Активный турнир не найден');

    final tournament = await tournaments.findOne(where.id(activeDoc['tournamentId'] as ObjectId));
    if (tournament == null || tournament['status'] == 'completed') {
      return Response.notFound('Турнир не найден или завершён');
    }

    final sets = List<Map<String, dynamic>>.from(tournament['sets']);
    final setIndex = tournament['activeSet'] ?? 0;
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

    return Response.ok(jsonEncode(result), headers: {'Content-Type': 'application/json'});
  });

  router.post('/rate', (Request request) async {
    final body = await request.readAsString();
    final data = jsonDecode(body);
    final double? rawRate = (data['rate'] as num?)?.toDouble();
    final String? masterId = data['master_id']?.toString();
    final double? rate = rawRate != null ? double.parse(rawRate.toStringAsFixed(2)) : null;

    if (rate == null || masterId == null || rate < 0 || rate > 10) {
      return Response.badRequest(body: 'Неверный формат данных');
    }

    final activeDoc = await active.findOne();
    if (activeDoc == null) return Response.notFound('Нет активного турнира');

    final tournament = await tournaments.findOne(where.id(activeDoc['tournamentId'] as ObjectId));
    if (tournament == null || tournament['status'] == 'completed') {
      return Response.notFound('Турнир не найден или завершён');
    }

    final ObjectId id = activeDoc['tournamentId'] as ObjectId;
    final setIndex = tournament['activeSet'] ?? 0;
    final itemIndex = tournament['sets'][setIndex]['activeItem'] ?? 0;
    final childIndex = tournament['sets'][setIndex]['items'][itemIndex]['activeChild'] ?? 0;

    final ratingsPath = 'sets.$setIndex.items.$itemIndex.childrens.$childIndex.ratings';
    final ratings = tournament['sets'][setIndex]['items'][itemIndex]['childrens'][childIndex]['ratings'] ?? [];

    if ((ratings as List).any((r) => r['master_id'] == masterId)) {
      return Response.forbidden('Оценка уже существует');
    }

    await tournaments.update(where.id(id), modify.push(ratingsPath, {
      'master_id': masterId,
      'rate': rate,
    }));

    return Response.ok('Оценка добавлена');
  });

  router.post('/tournament', (Request request) async {
    final body = await request.readAsString();
    final data = jsonDecode(body);
    if (data['title'] == null || data['sets'] == null || data['sets'] is! List) {
      return Response.badRequest(body: 'Неверный формат данных турнира');
    }

    await tournaments.insertOne({
      ...data,
      'createdAt': DateTime.now().toIso8601String(),
      'status': 'draft',
    });

    return Response.ok(jsonEncode({'status': 'ok'}), headers: {
      'Content-Type': 'application/json',
    });
  });

  router.get('/tournament/<id>', (Request request, String id) async {
    try {
      final ObjectId tid = ObjectId.parse(id);
      final tournament = await tournaments.findOne(where.id(tid));

      if (tournament == null) {
        return Response.notFound(jsonEncode({'error': 'Турнир не найден'}));
      }

      return Response.ok(jsonEncode(tournament), headers: {
        'Content-Type': 'application/json',
      });
    } catch (e) {
      return Response.badRequest(body: jsonEncode({'error': 'Некорректный ID'}));
    }
  });


  router.post('/next', (Request request) async {
    final activeDoc = await active.findOne();
    if (activeDoc == null) return Response.internalServerError(body: 'Нет активного турнира');

    final ObjectId id = activeDoc['tournamentId'] as ObjectId;
    final doc = await tournaments.findOne(where.id(id));
    if (doc == null) return Response.internalServerError(body: 'Документ не найден');

    final sets = doc['sets'] as List;
    int setIndex = doc['activeSet'] ?? 0;
    int itemIndex = sets[setIndex]['activeItem'] ?? 0;
    int childIndex = sets[setIndex]['items'][itemIndex]['activeChild'] ?? 0;

    childIndex++;

    if (childIndex >= (sets[setIndex]['items'][itemIndex]['childrens'] as List).length) {
      childIndex = 0;
      itemIndex++;

      if (itemIndex >= (sets[setIndex]['items'] as List).length) {
        itemIndex = 0;
        setIndex++;

        if (setIndex >= sets.length) {
          await tournaments.update(where.id(id), modify.set('status', 'completed'));
          await active.deleteMany({});
          return Response.ok('Турнир завершён');
        }
      }
    }

    await tournaments.update(where.id(id), modify
      ..set('activeSet', setIndex)
      ..set('sets.$setIndex.activeItem', itemIndex)
      ..set('sets.$setIndex.items.$itemIndex.activeChild', childIndex));

    return Response.ok('OK');
  });

  final certPath = '/etc/letsencrypt/live/mvpgarage.one/fullchain.pem';
  final keyPath = '/etc/letsencrypt/live/mvpgarage.one/privkey.pem';

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsMiddleware)
      .addHandler(router);

  final securityContext = SecurityContext()
    ..useCertificateChain(certPath)
    ..usePrivateKey(keyPath);

  await serve(handler, '0.0.0.0', 3890,
      securityContext: securityContext
  );
}
