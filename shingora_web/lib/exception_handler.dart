import 'package:dio/dio.dart';

class ExceptionHandler {
  static String handle(DioException e) {
    if (e.response != null) {
      int? statusCode = e.response?.statusCode;
      switch (statusCode) {
        case 400:
          return "400 Bad Request - The server could not understand your request.";
        case 401:
          return "401 Unauthorized - You are not authorized to access this.";
        case 403:
          return "403 Forbidden - Access denied.";
        case 404:
          return "404 Not Found - The requested resource was not found.";
        case 500:
          return "500 Internal Server Error - Something went wrong on the server.";
        case 502:
          return "502 Bad Gateway - Server failed to fulfill a valid request.";
        case 503:
          return "503 Service Unavailable - Server temporarily unavailable.";
        default:
          return "${statusCode ?? 'Unknown'} - An unknown error occurred.";
      }
    }

    // If no response (e.g., no internet, timeout)
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return "Connection timeout. Please try again.";
      case DioExceptionType.sendTimeout:
        return "Request send timeout.";
      case DioExceptionType.receiveTimeout:
        return "Server took too long to respond.";
      case DioExceptionType.connectionError:
        return "No internet connection.";
      case DioExceptionType.cancel:
        return "Request was cancelled.";
      case DioExceptionType.badCertificate:
        return "SSL certificate error.";
      default:
        return "An unknown error occurred.";
    }
  }
}