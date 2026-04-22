import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../services/call_service.dart';
import '../../services/auth_service.dart';
import '../../models/user_model.dart';

class CallScreen extends StatefulWidget {
  final UserModel otherUser;
  final bool isIncoming;
  final String? callId;
  final int durationSeconds;

  const CallScreen({
    super.key,
    required this.otherUser,
    this.isIncoming = false,
    this.callId,
    this.durationSeconds = 300,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  int _hours = 0;
  int _minutes = 5;
  int _seconds = 0;

  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initRenderers();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    setState(() => _isInitialized = true);

    if (widget.isIncoming) {
      _acceptCall();
    } else {
      _showDurationPicker();
    }
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  void _showDurationPicker() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Длительность звонка'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Выберите длительность видеозвонка'),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildTimePicker(
                    'Ч',
                    _hours,
                    (v) => setDialogState(() => _hours = v),
                    23,
                  ),
                  const Text(':', style: TextStyle(fontSize: 24)),
                  _buildTimePicker(
                    'М',
                    _minutes,
                    (v) => setDialogState(() => _minutes = v),
                    59,
                  ),
                  const Text(':', style: TextStyle(fontSize: 24)),
                  _buildTimePicker(
                    'С',
                    _seconds,
                    (v) => setDialogState(() => _seconds = v),
                    59,
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _startCall();
              },
              child: const Text('Позвонить'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimePicker(
    String label,
    int value,
    Function(int) onChanged,
    int max,
  ) {
    return Column(
      children: [
        Text(label),
        const SizedBox(height: 4),
        SizedBox(
          width: 60,
          child: TextField(
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            controller: TextEditingController(text: value.toString()),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.all(8),
              isDense: true,
            ),
            onChanged: (v) {
              int parsed = int.tryParse(v) ?? 0;
              if (parsed >= 0 && parsed <= max) onChanged(parsed);
            },
          ),
        ),
      ],
    );
  }

  Future<void> _startCall() async {
    final callService = context.read<CallService>();
    final authService = context.read<AuthService>();

    await callService.initiateCall(
      callerId: authService.currentUser!.id,
      receiverId: widget.otherUser.id,
      isVideo: true,
      hours: _hours,
      minutes: _minutes,
      seconds: _seconds,
    );

    _attachStreams();
  }

  Future<void> _acceptCall() async {
    final callService = context.read<CallService>();

    await callService.acceptCall(
      callId: widget.callId!,
      otherUserId: widget.otherUser.id,
      isVideo: true,
      durationSeconds: widget.durationSeconds,
    );

    _attachStreams();
  }

  void _attachStreams() {
    final callService = context.read<CallService>();

    callService.addListener(() {
      if (!mounted) return;

      _localRenderer.srcObject = callService.localStream;
      _remoteRenderer.srcObject = callService.remoteStream;

      setState(() {});

      if (!callService.isInCall) {
        Navigator.of(context).pop();
      }
    });
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
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: _remoteRenderer.srcObject != null
                  ? RTCVideoView(_remoteRenderer)
                  : Container(
                      color: Colors.black,
                      child: Center(
                        child: Text(
                          widget.otherUser.username,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                          ),
                        ),
                      ),
                    ),
            ),
            Positioned(
              top: 40,
              right: 16,
              width: 120,
              height: 160,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _localRenderer.srcObject != null
                    ? RTCVideoView(_localRenderer, mirror: true)
                    : Container(color: Colors.grey),
              ),
            ),
            Positioned(
              top: 40,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  callService.formatTime(callService.remainingSeconds),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: FloatingActionButton(
                  backgroundColor: Colors.red,
                  onPressed: () async {
                    await callService.endCall();
                  },
                  child: const Icon(Icons.call_end),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}