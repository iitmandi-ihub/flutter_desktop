// main.dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';


class ExternalOnlyCameraPage extends StatefulWidget {
  const ExternalOnlyCameraPage({super.key});
  @override
  State<ExternalOnlyCameraPage> createState() => _ExternalOnlyCameraPageState();
}

class _ExternalOnlyCameraPageState extends State<ExternalOnlyCameraPage> {
  final _renderer = RTCVideoRenderer();
  final _previewKey = GlobalKey(); // wraps RTCVideoView for snapshot

  MediaStream? _stream;
  List<MediaDeviceInfo> _externals = [];
  String? _selectedExternalId;

  // UI state
  bool _opening = false; // spinner flag
  String? _lastError;

  // Captured still image replaces live preview when non-null
  Uint8List? _capturedPng;

  @override
  void initState() {
    super.initState();
    _init();
  }

  // -------------------- Init & lifecycle --------------------
  Future<void> _init() async {
    await _renderer.initialize();
    await _primePermission();
    await _refreshExternalList(keepSelection: false);

    if (_selectedExternalId != null) {
      _openSelectedCamera(); // NOTE: non-awaited => spinner can animate
    } else {
      _setError('No external camera detected.\nPlug in a USB camera.');
    }

    // Hot-plug handling
    navigator.mediaDevices.ondevicechange = (event) async {
      await _refreshExternalList(keepSelection: true);
      if (_selectedExternalId != null) {
        _openSelectedCamera(); // non-awaited
      } else {
        await _stopStream();
        _setError('No external camera detected after change.');
      }
    };
  }

  Future<void> _primePermission() async {
    try {
      final s = await navigator.mediaDevices.getUserMedia({'audio': false, 'video': true});
      s.getTracks().forEach((t) => t.stop());
      await s.dispose();
      _setError(null);
    } catch (e) {
      _setError('Camera permission/open failed: $e');
    }
  }

  @override
  void dispose() {
    try {
      _renderer.srcObject?.getTracks().forEach((t) => t.stop());
      _renderer.dispose();
      _stream?.getTracks().forEach((t) => t.stop());
    } catch (_) {}
    super.dispose();
  }

  // -------------------- Smooth open helper (non-awaited) --------------------
  void _openSelectedCamera() {
    if (_selectedExternalId == null) return;
    setState(() {
      _opening = true;
      _capturedPng = null;
      _lastError = null;
    });

    // Let the spinner frame render first, then open camera off the UI frame.
    // 1) schedule after this frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 2) then microtask to start the heavy async open
      Future.microtask(() async {
        await _startWithDevice(_selectedExternalId!, allowAnyFallback: false);
      });
    });
  }

  // -------------------- External detection --------------------
  bool _looksExternal(MediaDeviceInfo d) {
    final label = (d.label ?? '').toLowerCase();
    final id = d.deviceId.toLowerCase();
    final gid = (d.groupId ?? '').toLowerCase();

    const usbVids = ['046d','0c45','2bd9','1e4e','05a3','1bcf','2a0b']; // common USB vendors
    const white = [
      'usb','external','logitech','razer','elgato','aver','avermedia','huddly','creative',
      'microsoft lifecam','c920','c922','brio','ptz','obsbot','insta360','sony','canon','nikon'
    ];
    const black = ['integrated','internal','built-in','builtin','face time','facetime','isight'];

    final whiteHit = white.any((w) => label.contains(w) || id.contains(w) || gid.contains(w));
    final blackHit = black.any((b) => label.contains(b) || id.contains(b) || gid.contains(b));
    final vidHit   = usbVids.any((v) => label.contains(v) || id.contains(v) || gid.contains(v));
    final v4l      = id.contains('/dev/video') || id.contains('v4l');

    if (blackHit) return false;
    if (whiteHit || vidHit) return true;
    if (v4l && !blackHit) return true;
    if (label.contains('webcam')) return true;
    return false;
  }

  Future<void> _refreshExternalList({bool keepSelection = true}) async {
    final all = await navigator.mediaDevices.enumerateDevices();
    final cams = all.where((d) => d.kind == 'videoinput').toList();

    if (cams.isNotEmpty && cams.every((d) => (d.label ?? '').isEmpty)) {
      await _primePermission();
    }

    final seen = <String>{};
    final filtered = <MediaDeviceInfo>[];
    for (final d in cams) {
      if (d.deviceId.isEmpty) continue;
      if (!seen.add(d.deviceId)) continue;
      if (_looksExternal(d)) filtered.add(d);
    }

    String? next = _selectedExternalId;
    final still = next != null && filtered.any((d) => d.deviceId == next);
    if (!keepSelection || !still) {
      next = filtered.isNotEmpty ? filtered.first.deviceId : null;
    }

    setState(() {
      _externals = filtered;
      _selectedExternalId = next;
    });
  }

  // -------------------- Open / stop camera --------------------
  Future<void> _startWithDevice(String deviceId, {bool allowAnyFallback = false}) async {
    _setError(null);
    await _stopStream();

    // Yield once more right here to ensure spinner keeps animating even if
    // libwebrtc does heavy work immediately after this call starts.
    await SchedulerBinding.instance.endOfFrame;

    final attempts = <MapEntry<String, Map<String, dynamic>>>[
      // Quick open for faster time-to-first-frame
      MapEntry('quick 640x480@15 exact', {
        'audio': false,
        'video': {
          'deviceId': {'exact': deviceId},
          'width': {'ideal': 640},
          'height': {'ideal': 480},
          'frameRate': {'ideal': 15},
        }
      }),
    ];

    if (deviceId.contains('/dev/video')) {
      attempts.add(MapEntry('linux v4l2 string', {
        'audio': false,
        'video': {'deviceId': deviceId}
      }));
    }

    attempts.addAll([
      MapEntry('exact 1280x720@30', {
        'audio': false,
        'video': {
          'deviceId': {'exact': deviceId},
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
          'frameRate': {'ideal': 30},
        },
      }),
      MapEntry('exact 640x480', {
        'audio': false,
        'video': {
          'deviceId': {'exact': deviceId},
          'width': {'ideal': 640},
          'height': {'ideal': 480},
        },
      }),
      MapEntry('exact only', {'audio': false, 'video': {'deviceId': {'exact': deviceId}}}),
      MapEntry('string id',   {'audio': false, 'video': {'deviceId': deviceId}}),
      MapEntry('advanced',    {'audio': false, 'video': {'advanced': [{'deviceId': deviceId}]}}),
      MapEntry('optional',    {'audio': false, 'video': {'optional': [{'sourceId': deviceId}]}}),
    ]);

    Future<void> _openAndVerify(Map<String, dynamic> c) async {
      final s = await navigator.mediaDevices.getUserMedia(c);
      if (s.getVideoTracks().isEmpty) {
        await s.dispose();
        throw 'No video track';
      }

      // Verify correct device (best effort)
      String? openedId;
      try {
        final settings = await s.getVideoTracks().first.getSettings();
        openedId = (settings['deviceId'] ?? settings['device_id'] ?? '').toString();
      } catch (_) {}

      final askedExact = (c['video'] is Map) &&
          (c['video']['deviceId'] is Map) &&
          (c['video']['deviceId'] as Map).containsKey('exact');

      final matched = openedId != null && openedId.isNotEmpty
          ? (openedId == deviceId || openedId.contains(deviceId))
          : askedExact;

      if (!matched) {
        try { s.getTracks().forEach((t) => t.stop()); await s.dispose(); } catch (_) {}
        throw 'Wrong device opened';
      }

      _renderer.srcObject = s;
      if (!mounted) return;
      setState(() {
        _stream = s;
        _opening = false; // spinner off
      });
    }

    String lastErr = '';
    for (final a in attempts) {
      try {
        await _openAndVerify(a.value);
        _setError(null);
        return;
      } catch (e) {
        lastErr = '$e';
      }
    }

    if (allowAnyFallback) {
      try {
        await _openAndVerify({'audio': false, 'video': true});
        return;
      } catch (e) {
        lastErr = '$e';
      }
    }

    if (!mounted) return;
    setState(() => _opening = false);
    _setError('Could not lock to the selected external camera.\nLast error: $lastErr');
  }

  Future<void> _stopStream() async {
    try {
      _renderer.srcObject?.getTracks().forEach((t) => t.stop());
      await _renderer.srcObject?.dispose();
    } catch (_) {}
    _renderer.srcObject = null;
    if (mounted) setState(() => _stream = null);
  }

  void _setError(String? msg) {
    if (!mounted) return;
    setState(() => _lastError = msg);
    if (msg != null) debugPrint(msg);
  }

  // -------------------- Capture / Retake / Clear --------------------
  Future<void> _captureSnapshot() async {
    if (_stream == null) return;
    // Give a frame to render for stable capture
    await Future.delayed(const Duration(milliseconds: 16));
    final boundary = _previewKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preview not ready')));
      }
      return;
    }
    final uiImage = await boundary.toImage(pixelRatio: 1.0);
    final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;
    if (!mounted) return;
    setState(() => _capturedPng = byteData.buffer.asUint8List());
  }

  Future<void> _retakeAndCapture() async {
    setState(() => _capturedPng = null); // show live again
    await _captureSnapshot();            // capture fresh still
  }

  void _clearCapturedOnly() {
    if (_capturedPng != null) {
      setState(() => _capturedPng = null); // back to live preview (no restart)
    }
  }

  // -------------------- UI --------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('External USB Camera')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // -------- TOP: Preview (300×200) --------
            Center(
              child: SizedBox(
                width: 300,
                height: 200,
                child: _opening && _stream == null
                    ? const Center(child: CircularProgressIndicator())
                    : (_capturedPng != null
                    ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(_capturedPng!, fit: BoxFit.cover),
                )
                    : (_stream == null
                    ? Center(
                  child: Text(
                    _lastError ??
                        (_externals.isEmpty
                            ? 'No external camera detected.'
                            : 'Select camera & open'),
                    textAlign: TextAlign.center,
                  ),
                )
                    : RepaintBoundary(
                  key: _previewKey,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: RTCVideoView(
                      _renderer,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ))),
              ),
            ),

            const SizedBox(height: 12),

            // -------- BUTTON ROW --------
            Row(
              children: [
                // Capture Image
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (_stream != null && !_opening)
                        ? () async {
                      setState(() => _capturedPng = null); // ensure live visible
                      await _captureSnapshot();
                    }
                        : null,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Capture Image'),
                  ),
                ),
                const SizedBox(width: 8),

                // Retake Image
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (_stream != null && !_opening)
                        ? () async {
                      await _retakeAndCapture();
                    }
                        : null,
                    icon: const Icon(Icons.repeat),
                    label: const Text('Retake Image'),
                  ),
                ),
                const SizedBox(width: 8),

                // Get Result (clear image preview only)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (_capturedPng != null) ? _clearCapturedOnly : null,
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Get Result'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // -------- Camera chooser (optional) --------
            Row(
              children: [
                const Text('Camera:', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: (_selectedExternalId != null &&
                        _externals.any((d) => d.deviceId == _selectedExternalId))
                        ? _selectedExternalId
                        : null,
                    hint: const Text('Select external camera'),
                    items: _externals
                        .map((d) => DropdownMenuItem(
                      value: d.deviceId,
                      child: Text(d.label?.isNotEmpty == true ? d.label! : d.deviceId),
                    ))
                        .toList(),
                    onChanged: (id) async {
                      if (id == null) return;
                      setState(() {
                        _selectedExternalId = id;
                      });
                      _openSelectedCamera(); // non-awaited => smooth spinner
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: (_selectedExternalId == null) ? null : _openSelectedCamera,
                  child: const Text('Open'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


/*
class ExternalOnlyCameraPage extends StatefulWidget {
  const ExternalOnlyCameraPage({super.key});
  @override
  State<ExternalOnlyCameraPage> createState() => _ExternalOnlyCameraPageState();
}

class _ExternalOnlyCameraPageState extends State<ExternalOnlyCameraPage> {
  final _renderer = RTCVideoRenderer();
  final _previewKey = GlobalKey(); // wraps RTCVideoView to snapshot it

  MediaStream? _stream;
  List<MediaDeviceInfo> _externals = [];
  String? _selectedExternalId;

  // UI state
  bool _opening = false;         // show spinner while opening
  String? _lastError;

  // Captured still (when not null, replaces live preview)
  Uint8List? _capturedPng;

  @override
  void initState() {
    super.initState();
    _init();
  }

  // -------------------- Lifecycle & init --------------------
  Future<void> _init() async {
    await _renderer.initialize();
    await _primePermission();
    await _refreshExternalList(keepSelection: false);

    if (_selectedExternalId != null) {
      setState(() => _opening = true);
      // Let spinner render smoothly before heavy camera open:
      await Future.delayed(const Duration(milliseconds: 120));
      await _startWithDevice(_selectedExternalId!, allowAnyFallback: false);
    } else {
      _setError('No external camera detected.\nPlug in a USB camera.');
    }

    // Hot-plug handling
    navigator.mediaDevices.ondevicechange = (event) async {
      await _refreshExternalList(keepSelection: true);
      if (_selectedExternalId != null) {
        setState(() => _opening = true);
        await Future.delayed(const Duration(milliseconds: 120));
        await _startWithDevice(_selectedExternalId!, allowAnyFallback: false);
      } else {
        await _stopStream();
        _setError('No external camera detected after change.');
      }
    };
  }

  Future<void> _primePermission() async {
    try {
      final s = await navigator.mediaDevices.getUserMedia({'audio': false, 'video': true});
      s.getTracks().forEach((t) => t.stop());
      await s.dispose();
      _setError(null);
    } catch (e) {
      _setError('Camera permission/open failed: $e');
    }
  }

  @override
  void dispose() {
    try {
      _renderer.srcObject?.getTracks().forEach((t) => t.stop());
      _renderer.dispose();
      _stream?.getTracks().forEach((t) => t.stop());
    } catch (_) {}
    super.dispose();
  }

  // -------------------- External detection --------------------
  bool _looksExternal(MediaDeviceInfo d) {
    final label = (d.label ?? '').toLowerCase();
    final id = d.deviceId.toLowerCase();
    final gid = (d.groupId ?? '').toLowerCase();

    const usbVids = ['046d','0c45','2bd9','1e4e','05a3','1bcf','2a0b']; // common USB vendors
    const white = [
      'usb','external','logitech','razer','elgato','aver','avermedia','huddly','creative',
      'microsoft lifecam','c920','c922','brio','ptz','obsbot','insta360','sony','canon','nikon'
    ];
    const black = ['integrated','internal','built-in','builtin','face time','facetime','isight'];

    final whiteHit = white.any((w) => label.contains(w) || id.contains(w) || gid.contains(w));
    final blackHit = black.any((b) => label.contains(b) || id.contains(b) || gid.contains(b));
    final vidHit   = usbVids.any((v) => label.contains(v) || id.contains(v) || gid.contains(v));
    final v4l      = id.contains('/dev/video') || id.contains('v4l');

    if (blackHit) return false;
    if (whiteHit || vidHit) return true;
    if (v4l && !blackHit) return true;
    if (label.contains('webcam')) return true;
    return false;
  }

  Future<void> _refreshExternalList({bool keepSelection = true}) async {
    final all = await navigator.mediaDevices.enumerateDevices();
    final cams = all.where((d) => d.kind == 'videoinput').toList();

    if (cams.isNotEmpty && cams.every((d) => (d.label ?? '').isEmpty)) {
      await _primePermission();
    }

    final seen = <String>{};
    final filtered = <MediaDeviceInfo>[];
    for (final d in cams) {
      if (d.deviceId.isEmpty) continue;
      if (!seen.add(d.deviceId)) continue;
      if (_looksExternal(d)) filtered.add(d);
    }

    String? next = _selectedExternalId;
    final still = next != null && filtered.any((d) => d.deviceId == next);
    if (!keepSelection || !still) {
      next = filtered.isNotEmpty ? filtered.first.deviceId : null;
    }

    setState(() {
      _externals = filtered;
      _selectedExternalId = next;
    });
  }

  // -------------------- Open / stop camera --------------------
  Future<void> _startWithDevice(String deviceId, {bool allowAnyFallback = false}) async {
    _setError(null);
    await _stopStream();
    setState(() {
      _opening = true;
      _capturedPng = null; // ensure live preview shows when ready
    });

    // Try multiple constraint shapes; verify device actually matches selection
    final attempts = <MapEntry<String, Map<String, dynamic>>>[
      // Quick open → faster spinner time
      MapEntry('quick 640x480@15 exact', {
        'audio': false,
        'video': {
          'deviceId': {'exact': deviceId},
          'width': {'ideal': 640},
          'height': {'ideal': 480},
          'frameRate': {'ideal': 15},
        }
      }),
    ];

    if (deviceId.contains('/dev/video')) {
      attempts.add(MapEntry('linux v4l2 string', {
        'audio': false,
        'video': {'deviceId': deviceId}
      }));
    }

    attempts.addAll([
      MapEntry('exact 1280x720@30', {
        'audio': false,
        'video': {
          'deviceId': {'exact': deviceId},
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
          'frameRate': {'ideal': 30},
        },
      }),
      MapEntry('exact 640x480', {
        'audio': false,
        'video': {
          'deviceId': {'exact': deviceId},
          'width': {'ideal': 640},
          'height': {'ideal': 480},
        },
      }),
      MapEntry('exact only', {'audio': false, 'video': {'deviceId': {'exact': deviceId}}}),
      MapEntry('string id',   {'audio': false, 'video': {'deviceId': deviceId}}),
      MapEntry('advanced',    {'audio': false, 'video': {'advanced': [{'deviceId': deviceId}]}}),
      MapEntry('optional',    {'audio': false, 'video': {'optional': [{'sourceId': deviceId}]}}),
    ]);

    Future<void> _openAndVerify(Map<String, dynamic> c) async {
      final s = await navigator.mediaDevices.getUserMedia(c);
      if (s.getVideoTracks().isEmpty) {
        await s.dispose();
        throw 'No video track';
      }

      // Verify correct device (best-effort)
      String? openedId;
      try {
        final settings = await s.getVideoTracks().first.getSettings();
        openedId = (settings['deviceId'] ?? settings['device_id'] ?? '').toString();
      } catch (_) {}
      final askedExact = (c['video'] is Map) &&
          (c['video']['deviceId'] is Map) &&
          (c['video']['deviceId'] as Map).containsKey('exact');
      final matched = openedId != null && openedId.isNotEmpty
          ? (openedId == deviceId || openedId.contains(deviceId))
          : askedExact;

      if (!matched) {
        try { s.getTracks().forEach((t) => t.stop()); await s.dispose(); } catch (_) {}
        throw 'Wrong device opened';
      }

      _renderer.srcObject = s;
      setState(() {
        _stream = s;
        _opening = false;
      });
    }

    String lastErr = '';
    for (final a in attempts) {
      try {
        await _openAndVerify(a.value);
        _setError(null);
        return;
      } catch (e) {
        lastErr = '$e';
      }
    }

    if (allowAnyFallback) {
      try {
        await _openAndVerify({'audio': false, 'video': true});
        return;
      } catch (e) {
        lastErr = '$e';
      }
    }

    setState(() => _opening = false);
    _setError('Could not lock to the selected external camera.\nLast error: $lastErr');
  }

  Future<void> _stopStream() async {
    try {
      _renderer.srcObject?.getTracks().forEach((t) => t.stop());
      await _renderer.srcObject?.dispose();
    } catch (_) {}
    _renderer.srcObject = null;
    setState(() => _stream = null);
  }

  void _setError(String? msg) {
    setState(() => _lastError = msg);
    if (msg != null) debugPrint(msg);
  }

  // -------------------- Capture / Retake / Clear --------------------
  Future<void> _captureSnapshot() async {
    if (_stream == null) return;
    // give a frame to render for stable capture
    await Future.delayed(const Duration(milliseconds: 30));
    final boundary = _previewKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preview not ready')));
      }
      return;
    }
    final uiImage = await boundary.toImage(pixelRatio: 1.0);
    final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;
    setState(() => _capturedPng = byteData.buffer.asUint8List());
  }

  Future<void> _retakeAndCapture() async {
    // return to live, then capture fresh still
    setState(() => _capturedPng = null);
    await _captureSnapshot();
  }

  void _clearCapturedOnly() {
    // "Get Result" → just clear image, show live again (no camera restart)
    if (_capturedPng != null) {
      setState(() => _capturedPng = null);
    }
  }

  // -------------------- UI --------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('External USB Camera')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // -------- TOP: Preview (300×200) --------
            Center(
              child: SizedBox(
                width: 300,
                height: 200,
                child: _opening && _stream == null
                    ? const Center(child: CircularProgressIndicator())
                    : (_capturedPng != null
                    ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(_capturedPng!, fit: BoxFit.cover),
                )
                    : (_stream == null
                    ? Center(
                  child: Text(
                    _lastError ??
                        (_externals.isEmpty
                            ? 'No external camera detected.'
                            : 'Select camera & open'),
                    textAlign: TextAlign.center,
                  ),
                )
                    : RepaintBoundary(
                  key: _previewKey,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: RTCVideoView(
                      _renderer,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ))),
              ),
            ),

            const SizedBox(height: 12),

            // -------- BUTTON ROW --------
            Row(
              children: [
                // Capture Image
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (_stream != null && !_opening)
                        ? () async {
                      // ensure live is visible before capture
                      setState(() => _capturedPng = null);
                      await _captureSnapshot();
                    }
                        : null,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Capture Image'),
                  ),
                ),
                const SizedBox(width: 8),

                // Retake Image
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (_stream != null && !_opening)
                        ? () async {
                      await _retakeAndCapture();
                    }
                        : null,
                    icon: const Icon(Icons.repeat),
                    label: const Text('Retake Image'),
                  ),
                ),
                const SizedBox(width: 8),

                // Get Result (clear image preview only)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (_capturedPng != null) ? _clearCapturedOnly : null,
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Get Result'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // -------- Camera chooser (optional) --------
            Row(
              children: [
                const Text('Camera:', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: (_selectedExternalId != null &&
                        _externals.any((d) => d.deviceId == _selectedExternalId))
                        ? _selectedExternalId
                        : null,
                    hint: const Text('Select external camera'),
                    items: _externals
                        .map((d) => DropdownMenuItem(
                      value: d.deviceId,
                      child: Text(d.label?.isNotEmpty == true ? d.label! : d.deviceId),
                    ))
                        .toList(),
                    onChanged: (id) async {
                      if (id == null) return;
                      setState(() {
                        _selectedExternalId = id;
                        _opening = true;
                        _capturedPng = null;
                        _lastError = null;
                      });
                      await Future.delayed(const Duration(milliseconds: 120)); // smooth spinner
                      await _startWithDevice(id, allowAnyFallback: false);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: (_selectedExternalId == null)
                      ? null
                      : () async {
                    setState(() {
                      _opening = true;
                      _capturedPng = null;
                      _lastError = null;
                    });
                    await Future.delayed(const Duration(milliseconds: 120)); // smooth spinner
                    await _startWithDevice(_selectedExternalId!, allowAnyFallback: false);
                  },
                  child: const Text('Open'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
*/

