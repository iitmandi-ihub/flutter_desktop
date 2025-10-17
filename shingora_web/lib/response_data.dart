class ResponseData{
  final String message;
  final int predictedClassIndex;
  final String predictedDefectName;
  final String predictedDefectType;
  final bool success;

  ResponseData({
    required this.message,
    required this.predictedClassIndex,
    required this.predictedDefectName,
    required this.predictedDefectType,
    required this.success,
  });

  factory ResponseData.fromJson(Map<String, dynamic> json) {
    return ResponseData(
      message: json['message'],
      predictedClassIndex: json['predicted_class_index'],
      predictedDefectName: json['predicted_defect_name'],
      predictedDefectType: json['predicted_defect_type'],
      success: json['success'],
    );
  }
}

/*{"message":"Prediction successful","predicted_class_index":2,"predicted_defect_name":"Low",
"predicted_defect_type":"Thick_Thin","success":true}*/
