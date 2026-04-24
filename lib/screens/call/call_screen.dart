import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../services/call_service.dart';
import '../../models/user_model.dart';

class CallScreen extends StatefulWidget {
  final UserModel otherUser;
  final bool isIncoming;
  final bool isVideo; // ✅ добавлен параметр
  final String? callId;
  final int durationSeconds;

  const CallScreen({
    super.key,
    required this.otherUser,
    this.isIncoming = false,
    this.isVideo = true, // ✅ по умолчанию видео
    this.callId,
    this.durationSeconds = 300,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  // ✅ Сохраняем сервис в поле — не используем context в dispose
  late final CallService _callService;

  bool _isInitialized = false;
  VoidCallback? _listener;

  @override
  void initState() {
    super.initState();
    // ✅ Сохраняем до первого async
    _callService = context.read<CallService>();
    _init();
  }

  Future<void> _init() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    // ✅ Проверяем mounted после await
    if (!mounted) return;

    _listener = () {
      if (!mounted) return;

      setState(() {
        _localRenderer.srcObject = _callService.localStream;
        _remoteRenderer.srcObject = _callService.remoteStream;
      });

      if (!_callService.isInCall) {
        Navigator.pop(context);
      }
    };

    _callService.addListener(_listener!);

    if (!mounted) return;
    setState(() => _isInitialized = true);

    if (widget.isIncoming) {
      // ✅ Проверяем callId перед использованием
      if (widget.callId == null) {
        debugPrint('CallScreen: callId is null for incoming call');
        if (mounted) Navigator.pop(context);
        return;
      }

      await _callService.acceptCall(
        callId: widget.callId!,
        otherUserId: widget.otherUser.id,
        isVideo: widget.isVideo, // ✅ используем параметр
        durationSeconds: widget.durationSeconds,
      );
    }
  }

  @override
  void dispose() {
    // ✅ Используем сохранённую ссылку, не context
    if (_listener != null) {
      _callService.removeListener(_listener!);
    }
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      // ✅ Используем правильный context из builder
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          const Text(
            'Качество видео',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          ListTile(
            title: const Text('360p / 15 FPS'),
            onTap: () {
              _callService.changeVideoQuality(VideoQuality.low, 15);
              Navigator.pop(sheetContext); // ✅ правильный context
            },
          ),
          ListTile(
            title: const Text('720p / 30 FPS'),
            onTap: () {
              _callService.changeVideoQuality(VideoQuality.medium, 30);
              Navigator.pop(sheetContext);
            },
          ),
          ListTile(
            title: const Text('1080p / 60 FPS'),
            onTap: () {
              _callService.changeVideoQuality(VideoQuality.high, 60);
              Navigator.pop(sheetContext);
            },
          ),
          const Divider(),
          const Text(
            'Качество микрофона',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          ListTile(
            title: const Text('16 kHz'),
            onTap: () {
              _callService.changeMicrophoneQuality(16000);
              Navigator.pop(sheetContext);
            },
          ),
          ListTile(
            title: const Text('48 kHz'),
            onTap: () {
              _callService.changeMicrophoneQuality(48000);
              Navigator.pop(sheetContext);
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final callService = context.watch<CallService>();

    if (!_isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          /// Remote video or avatar
          Positioned.fill(
            child: callService.remoteStream != null
                // ✅ Убрали isCameraEnabled — это не наша камера
                ? RTCVideoView(
                    _remoteRenderer,
                    objectFit:
                        RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  )
                : Center(
                    child: CircleAvatar(
                      radius: 60,
                      child: Text(
                        widget.otherUser.username[0].toUpperCase(),
                        style: const TextStyle(fontSize: 40),
                      ),
                    ),
                  ),
          ),

          /// Local preview — ✅ показываем только при видео звонке
          if (widget.isVideo)
            Positioned(
              top: 40,
              right: 16,
              width: 120,
              height: 160,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: callService.isCameraEnabled
                    ? RTCVideoView(
                        _localRenderer,
                        mirror: true,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      )
                    // ✅ Если камера выключена — показываем заглушку
                    : Container(
                        color: Colors.grey[900],
                        child: const Center(
                          child: Icon(
                            Icons.videocam_off,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
              ),
            ),

          /// Timer
          Positioned(
            top: 40,
            left: 16,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                callService.formatTime(callService.remainingSeconds),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),

          /// Controls
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Микрофон
                _ControlButton(
                  icon: callService.isMicEnabled
                      ? Icons.mic
                      : Icons.mic_off,
                  onPressed: callService.toggleMicrophone,
                ),
                // ✅ Кнопки камеры только для видео звонка
                if (widget.isVideo) ...[
                  _ControlButton(
                    icon: callService.isCameraEnabled
                        ? Icons.videocam
                        : Icons.videocam_off,
                    onPressed: callService.toggleCamera,
                  ),
                  _ControlButton(
                    icon: Icons.cameraswitch,
                    onPressed: callService.switchCamera,
                  ),
                ],
                _ControlButton(
                  icon: Icons.settings,
                  onPressed: _openSettings,
                ),
                // Завершить звонок
                FloatingActionButton(
                  backgroundColor: Colors.red,
                  onPressed: callService.endCall,
                  child: const Icon(Icons.call_end),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ✅ Вынесли повторяющийся виджет кнопки
class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _ControlButton({
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: Colors.white, size: 30),
      onPressed: onPressed,
    );
  }
}