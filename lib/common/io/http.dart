import 'package:dio/dio.dart';
import 'package:dio_compatibility_layer/dio_compatibility_layer.dart';
import 'package:rhttp/rhttp.dart';

class RDio {
  static Future<Dio> createRDioClient() async {
    final dio = Dio();
    final compatibleClient = await RhttpCompatibleClient.create();
    dio.httpClientAdapter = ConversionLayerAdapter(compatibleClient);
    return dio;
  }
}
