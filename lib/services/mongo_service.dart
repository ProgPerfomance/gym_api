
import 'package:mongo_dart/mongo_dart.dart';
MongoService mongoService = MongoService();
class MongoService {
  Db? db;
  initMongo() async {
    db = Db("mongodb://localhost:27017/profi");
    await db?.open();
  }
  get mongoDb => db!;

}

