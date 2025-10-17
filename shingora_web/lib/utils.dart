import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:image/image.dart' as img;




//check internet
Future<bool> isInternet() async {
  final bool isConnected = await InternetConnectionChecker.instance.hasConnection;
  if(isConnected){
    return true;
  }else{
    return false;
  }

}

Future<File> compressImage(File file) async {
  final bytes = await file.readAsBytes(); // Read image bytes
  final img.Image? originalImage = img.decodeImage(Uint8List.fromList(bytes)); // Decode the image

  if (originalImage == null) {
    throw Exception("Failed to decode image.");
  }

  // Compress the image by resizing it
  final img.Image resizedImage = img.copyResize(originalImage, width:600); // Resize to width of 600px

  // Encode the resized image to a byte array
  final List<int> compressedBytes = img.encodeJpg(resizedImage, quality: 85); // Set quality (85)

  // Return the compressed image file
  final File compressedFile = await file.writeAsBytes(compressedBytes);
  return compressedFile;
}

void showSnakebar(String title, String message, String type) {
  Color bgColor;
  IconData iconData;

  switch (type) {
    case 'success':
      bgColor = Colors.green;
      iconData = Icons.check_circle;
      break;
    case 'error':
      bgColor = Colors.red;
      iconData = Icons.error;
      break;
    case 'warning':
      bgColor = Colors.orange;
      iconData = Icons.warning;
      break;
    default:
      bgColor = Colors.grey;
      iconData = Icons.info;
  }

  Get.snackbar(
    '',
    "",
    titleText: Text(title,style: TextStyle(fontSize:16,color: Colors.white,)),
    messageText: Text(message,style: TextStyle(fontSize:14,color: Colors
        .white)),
    icon: Icon(iconData, color: Colors.white),
    backgroundColor: bgColor,
    colorText: Colors.white,
    snackPosition: SnackPosition.BOTTOM,
    margin: const EdgeInsets.all(12),
    borderRadius: 6,
    duration: const Duration(seconds: 2),
  );
}