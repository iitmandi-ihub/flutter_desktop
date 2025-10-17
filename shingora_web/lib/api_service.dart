import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:shingora_web/response_data.dart';
import 'exception_handler.dart';

class ApiService {
  final String baseUrl="http://13.229.150.34//predict";
  final uri = Uri.http('13.229.150.34', '/predict');

  final Dio _dio = Dio();

  Future<String> encodeImage(File image) async {
    final bytes = await image.readAsBytes();
    return base64Encode(bytes);
  }

  // ========= send Image to model ========= //
  Future<List<ResponseData>> uploadImage(Uint8List image) async {
    try {
      final compressed = await compressImageBytes(image);
      // Compute image size in MB
      final double compressedMb = compressed!.lengthInBytes / (1024 * 1024);
      print('===== Image size =====: ${compressedMb.toStringAsFixed(2)} MB');

      FormData formData = FormData.fromMap({
        /*"image": await MultipartFile.fromFile(compressed.path, filename: fileName),*/
        "image": MultipartFile.fromBytes(compressed, filename:"image.jpg"),
      });

      _dio.interceptors.add(LogInterceptor(
        request: true,
        requestBody: true,
        responseBody: true,
        error: true,
      ));

      Response response = await _dio.post(
        uri.toString(),
        data: formData,
        options: Options(
          headers: {
            "Content-Type": "multipart/form-data",
          },
        ),
      );
      print("==Response===$response");
      List<ResponseData> data= [];
      if(response.statusCode==200){
        ResponseData responseData = ResponseData.fromJson(response.data);
        data.add(responseData);
      }
      return data;
    } on DioException catch (e) {
      if(e.response?.statusCode!=200){
        throw Exception(e.response?.data['error']);
      }else{
        final errorMsg = ExceptionHandler.handle(e);
        throw Exception(errorMsg);
      }
    } catch (e) {
      throw Exception('Error: $e');
    }
  }

  // ========== Send Image to server  ========== //

 /* Future<dynamic> sendImage(File imageFile, List<String> selectedLabels) async {
    String fileName = imageFile.path.split('/').last;
    String textValue = selectedLabels
        .map((e) => e.replaceAll(' ', ''))  // remove internal spaces if needed
        .join('_');
  try{
    FormData formData = FormData.fromMap({
      "image": await MultipartFile.fromFile(imageFile.path, filename: fileName),
      "label_name": textValue

    });

    _dio.interceptors.add(LogInterceptor(
      request: true,
      requestBody: true,
      responseBody: true,
      error: true,
    ));

    Response response = await _dio.post(
      "${imageBaseUrl}images",
      data: formData,
      options: Options(
        headers: {
          "Content-Type": "multipart/form-data",
          "singora-API-Key":"12345"
        },
      ),
    );

    return response.statusCode;
  } on DioException catch(e){
     if(e.response != null && e.response?.data != null){
       return Future.error(e.response?.data['error'] ?? 'Unknown error');
     }else{
       final errorMsg = ExceptionHandler.handle(e);
       return Future.error(errorMsg);
       //throw Exception(errorMsg);
     }
  } catch(e){
    return Future.error("Error: $e");
    //throw Exception('Error: $e');
  }
  }*/

  Future<Uint8List?> compressImageBytes(Uint8List bytes) async {
    try {
      final result = await FlutterImageCompress.compressWithList(
        bytes,
        quality: 80,
        minWidth: 1920,
        minHeight: 1080,
      );
      return result;
    } catch (e) {
      print("Compression error: $e");
      return null;
    }
  }


 /* Future<XFile?> compressImage(Uint8List file) async {
    final result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      '${file.path}_compressed.jpg',
      quality: 80,
      minWidth: 1920,     // Resize width
      minHeight:1080, // Lower quality = smaller file
    );
    return result;
  }*/

  String convertImageToBase64(File image) {
    final bytes = image.readAsBytesSync();
    return base64Encode(bytes);
  }
  
}
