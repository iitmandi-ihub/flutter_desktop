/*
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:shingora_web/response_data.dart';
import 'package:shingora_web/utils.dart';
import 'package:web/web.dart' as web;

import 'api_service.dart';

class MyCamera extends StatefulWidget {
  const MyCamera({super.key});

  @override
  State<MyCamera> createState() => _MyCameraState();
}
class _MyCameraState extends State<MyCamera> {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  XFile? _captured;
  final apiService = ApiService();

  int? predictedIndex;
  List<ResponseData> resultList=[];



  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _httpsWarning;


  CameraDescription? _selected;


  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      if (!kIsWeb) {
        setState(() {
          _error = 'This widget is intended for Flutter Web builds.';
          _loading = false;
        });
        return;
      }


// Warn if not HTTPS (camera access requires secure context on browsers)
      // Warn if not HTTPS (camera access requires secure context on browsers)
      final protocol = web.window.location.protocol; // e.g. 'https:' or 'http:'
      if (protocol != 'https:' && web.window.location.hostname != 'localhost') {
        _httpsWarning = 'Browser camera access requires HTTPS (or localhost).';
      }


// Query available cameras (triggers permission flow via camera_web)
      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() {
          _error = 'No cameras detected. Connect a USB webcam or allow permission.';
          _loading = false;
        });
        return;
      }


      _cameras = cams;
      _selected = cams.first;
      await _initController(_selected!);
    } catch (e) {
      setState(() {
        _error = 'Init failed: $e';
        _loading = false;
      });
    }
  }

  Future<void> _initController(CameraDescription desc) async {
    setState(() {
      _loading = true;
      _captured = null;
    });


// Dispose any previous controller before switching
    await _controller?.dispose();


    final controller = CameraController(
      desc,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );


    await controller.initialize();
    setState(() {
      _controller = controller;
      _loading = false;
    });
  }


  Future<void> _onSelect(CameraDescription newDesc) async {
    _selected = newDesc;
    await _initController(newDesc);
  }


  Future<void> _capture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() => _busy = true);
    try {
      final shot = await _controller!.takePicture();
      setState(() => _captured = shot);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Capture failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  void _download() {
    if (!kIsWeb || _captured == null) return;
// On web, XFile.path is a blob: URL. Trigger a download via anchor click.
    final a = web.HTMLAnchorElement()
      ..href = _captured!.path
      ..download = 'capture_${DateTime.now().millisecondsSinceEpoch}.jpg'
      ..rel = 'noopener'
      ..target = '_blank';
    web.document.body!.append(a);
    a.click();
    a.remove();
  }


  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;
    
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_error!, style: theme.textTheme.bodyLarge),
        ),
      );
    }

    if (_loading || _controller == null || !_controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      appBar: AppBar(title: const Text("Defect Detection",style: TextStyle
        (color: Colors.white,fontSize: 17),),
          backgroundColor:Colors.blue[900]),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,   // 👈 ensures top-left alignment
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex:4,
                    child: Container(color: Colors.amber,height: screenHeight,)),
                Expanded(flex:5,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 0.0,right:5.0,top: 5.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, // 👈
                      // align inner content top-left
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        if (_httpsWarning != null)
                          Container(
                            padding: const EdgeInsets.all(8),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.lock, size: 18),
                                const SizedBox(width: 8),
                                Expanded(child: Text(_httpsWarning!)),
                              ],
                            ),
                          ),

                        // Camera selector
                        */
/*Row(
                       children: [
                       const Text('Camera:'),
                       const SizedBox(width: 8),
                       Expanded(
                       child: DropdownButton<CameraDescription>(
                       value: _selected,
                       isExpanded: true,
                       items: _cameras.map((c) {
                       return DropdownMenuItem(
                       value: c,
                       child: Text(c.name.isNotEmpty ? c.name : c.lensDirection.name),
                       );
                       }).toList(),
                       onChanged: (val) async {
                       if (val != null) await _onSelect(val);
                       },
                       ),
                       ),
                       IconButton(
                       tooltip: 'Refresh cameras',
                       onPressed: () async {
                       setState(() => _loading = true);
                       try {
                       _cameras = await availableCameras();
                       if (_cameras.isNotEmpty) {
                       _selected ??= _cameras.first;
                       }
                       } catch (e) {
                       ScaffoldMessenger.of(context).showSnackBar(
                       SnackBar(content: Text('Refresh failed: $e')),
                       );
                       } finally {
                       setState(() => _loading = false);
                       }
                       },
                       icon: const Icon(Icons.refresh),
                       ),
                       ],
                       ),*//*

                        const SizedBox(height:2),
                        // Live preview
                        Row(
                          children: [
                            SizedBox(
                              width:300, // custom width
                              height: 200, // custom height
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(0),
                                child:_captured!=null?ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(
                                    _captured!.path, // blob: URL
                                    fit: BoxFit.contain,
                                    height: 280,
                                  ),
                                ): CameraPreview
                                  (_controller!),
                              ),
                            ),
                            //CircularProgressIndicator(),
                            Padding(
                              padding: const EdgeInsets.only(left: 20,top: 20),
                              child: Column(
                                children: [
                                  SizedBox(height: 20,),
                                   Text("Result"),
                                  Row(
                                    children: [
                                      Text("Defect Name:"),
                                      Text("thick this")
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      Text("Defect Type:"),
                                      Text("Low")
                                    ],
                                  ),
                                ],
                              ),
                            )

                          ],
                        ) ,
                        */
/*AspectRatio(
                       aspectRatio: _controller!.value.previewSize != null
                       ? _controller!.value.previewSize!.width /
                       _controller!.value.previewSize!.height : 16 / 9,
                       child: ClipRRect(
                       borderRadius: BorderRadius.circular(12),
                       child: CameraPreview(_controller!),
                       ),
                       ),
                       *//*

                        // Controls
                        Padding(
                          padding: const EdgeInsets.only(left: 10,top: 10),
                          child: Row(
                            children: [
                              ElevatedButton.icon(
                                onPressed: _busy ? null : _capture,
                                icon: const Icon(Icons.camera),
                                label: const Text('Capture Image',style:
                                TextStyle(color: Colors.white),),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:Colors.blueAccent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                              ),

                              ),
                              const SizedBox(width: 15),
                              ElevatedButton.icon(
                                onPressed: _download,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Retake',style: TextStyle
                                  (color: Colors.white),),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:Colors.blueAccent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                              const SizedBox(width:50),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  if(_captured == null || _captured!.path.isEmpty){
                                    */
/*showSnakebar("No Selection","Please add the Image First!","error");*//*

                                  }else{
                                    if(await isInternet()){
                                    print("===========jhvjh");
                                  try {
                                    final bytes = await _captured!.readAsBytes();
                                  resultList = await apiService.uploadImage(bytes);
                                  */
/*if(resultList.isNotEmpty){
                                  setState(() {
                                  predictedIndex = resultList[0].predictedClassIndex;
                                  });
                                  }else{
                                    print("====no Result---");
                                  *//*
*/
/*showSnakebar("No Result","No Result Found"
                                  ".","error");*//*
*/
/*
                                  }*//*


                                  } catch (e) {
                                    print("====Exception---"+e.toString());
                                 // loading.hideLoading();
                                  */
/*showSnakebar("Server Issue",e.toString().replaceFirst
                                  ("Exception: ", ""), "error");*//*

                                  }finally{
                                 // loading.hideLoading();
                                  }
                                  }else{
                                      print("====no Internet---");
                                 */
/* showSnakebar("No Internet","No Internet "
                                  "Available","error");*//*

                                  }
                                }

                                  //setState(() => _captured = null);
                                },
                                icon: const Icon(Icons.data_object),
                                label: const Text('Get Result',style:
                                TextStyle(color: Colors.black),),
                                style:OutlinedButton.styleFrom(
                                  backgroundColor:Colors.transparent,
                                  side: BorderSide(
                                      color: Colors.blueAccent, // Your desired border
                                    // color
                                      width: 2.0,       // Optional: border thickness
                                    ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),

                              */
/*if (_captured != null) ...[
                                                ElevatedButton.icon(
                          onPressed: _download,
                          icon: const Icon(Icons.download),
                          label: const Text('Download'),
                                                ),
                                              ],*//*

                            ],
                          ),
                        ),

                      ],
                    ),
                  ),
                ),

              ],
            ),
          ],
        ),

      ),
      bottomNavigationBar: Container(
        height:20,
        color: Colors.blue[900],
        child: Center(
          child: Text('@iHub 2025',style: TextStyle(color: Colors.white,
              fontSize:12),),
      ),
      )
    );
  }
}*/
