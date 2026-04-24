import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'socket_service.dart';

enum VideoQuality { low, medium, high }

class CallService extends ChangeNotifier {
  SocketService? _socketService;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  String? _currentCallId;
  String? _otherUserId;
  String? _currentUserId;

  bool _isInCall = false;
  bool _isCleaningUp = false;
  bool _isInitiator = false;

  Timer? _callTimer;
  int _remainingSeconds = 0;
  int _totalSeconds = 0;

  bool _isMicEnabled = true;
  bool _isCameraEnabled = true;
  bool _isFrontCamera = true;

  VideoQuality _videoQuality = VideoQuality.medium;
  int _fps = 30;
  int _audioSampleRate = 48000;

  final List<RTCIceCandidate> _remoteIceBuffer = [];
  bool _isRemoteDescriptionSet = false;

  bool get isInCall => _isInCall;
  bool get isMicEnabled => _isMicEnabled;
  bool get isCameraEnabled => _isCameraEnabled;
  bool get isFrontCamera => _isFrontCamera;

  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
  int get remainingSeconds => _remainingSeconds;
  int get totalSeconds => _totalSeconds;

  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ]
  };

  // =========================
  // INIT / RESET
  // =========================

  void init({
    required SocketService socketService,
    required String currentUserId,
  }) {
    _socketService = socketService;
    _currentUserId = currentUserId;
    _listenToCallEvents();
  }

  void reset() {
    _cleanup();
    _socketService = null;
    _currentUserId = null;
  }

  // =========================
  // FORMAT TIME
  // =========================

  String formatTime(int seconds) {
    int h = seconds ~/ 3600;
    int m = (seconds % 3600) ~/ 60;
    int s = seconds % 60;

    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // =========================
  // MEDIA
  // =========================

  Future<bool> initLocalStream({bool isVideo = true}) async {
    try {
      if (isVideo) {
        var status = await Permission.camera.request();
        if (status != PermissionStatus.granted) {
          debugPrint('Camera permission denied');
          return false;
        }
      }

      var micStatus = await Permission.microphone.request();
      if (micStatus != PermissionStatus.granted) {
        debugPrint('Microphone permission denied');
        return false;
      }

      int width;
      int height;

      switch (_videoQuality) {
        case VideoQuality.low:
          width = 640;
          height = 360;
          break;
        case VideoQuality.medium:
          width = 1280;
          height = 720;
          break;
        case VideoQuality.high:
          width = 1920;
          height = 1080;
          break;
      }

      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'sampleRate': _audioSampleRate,
          'echoCancellation': true,
          'noiseSuppression': true,
        },
        'video': isVideo
            ? {
                'width': {'ideal': width},
                'height': {'ideal': height},
                'frameRate': {'ideal': _fps},
                'facingMode': _isFrontCamera ? 'user' : 'environment',
              }
            : false,
      });

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Media error: $e');
      return false;
    }
  }

  void toggleMicrophone() {
    if (_localStream == null) return;
    for (var track in _localStream!.getAudioTracks()) {
      track.enabled = !_isMicEnabled;
    }
    _isMicEnabled = !_isMicEnabled;
    notifyListeners();
  }

  void toggleCamera() {
    if (_localStream == null) return;
    for (var track in _localStream!.getVideoTracks()) {
      track.enabled = !_isCameraEnabled;
    }
    _isCameraEnabled = !_isCameraEnabled;
    notifyListeners();
  }

  Future<void> switchCamera() async {
    _isFrontCamera = !_isFrontCamera;
    await _restartMedia();
  }

  Future<void> changeVideoQuality(VideoQuality quality, int fps) async {
    _videoQuality = quality;
    _fps = fps;
    await _restartMedia();
  }

  Future<void> changeMicrophoneQuality(int sampleRate) async {
    _audioSampleRate = sampleRate;
    await _restartMedia();
  }

  Future<void> _restartMedia() async {
    if (!_isInCall) return;

    final oldStream = _localStream;
    
    // Сначала создаем новый поток, не закрывая старый, чтобы избежать обращения к закрытому ресурсу в нативном слое
    final success = await initLocalStream(isVideo: _isCameraEnabled);
    if (!success) {
      _localStream = oldStream;
      return;
    }

    if (_peerConnection != null && _localStream != null) {
      try {
        final senders = await _peerConnection!.getSenders();

        for (var sender in senders) {
          if (sender.track?.kind == 'video') {
            final videoTracks = _localStream!.getVideoTracks();
            if (videoTracks.isNotEmpty) {
              await sender.replaceTrack(videoTracks.first);
            }
          }
          if (sender.track?.kind == 'audio') {
            final audioTracks = _localStream!.getAudioTracks();
            if (audioTracks.isNotEmpty) {
              await sender.replaceTrack(audioTracks.first);
            }
          }
        }
      } catch (e) {
        debugPrint('Error replacing tracks: $e');
      }
    }

    // Теперь можно безопасно закрыть старый поток
    try {
      await oldStream?.dispose();
    } catch (e) {
      debugPrint('Error disposing old stream: $e');
    }

    notifyListeners();
  }

  // =========================
  // TIMER
  // =========================

  void _startTimer() {
    _callTimer?.cancel();
    _remainingSeconds = _totalSeconds;

    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 0) {
        endCall();
      } else {
        _remainingSeconds--;
        notifyListeners();
      }
    });
  }

  // =========================
  // CALL
  // =========================

  Future<void> initiateCall({
    required String callerId,
    required String receiverId,
    required bool isVideo,
    required int hours,
    required int minutes,
    required int seconds,
  }) async {
    _totalSeconds = (hours * 3600) + (minutes * 60) + seconds;
    if (_totalSeconds <= 0) return;

    _otherUserId = receiverId;
    _isInitiator = true;

    final success = await initLocalStream(isVideo: isVideo);
    if (!success) return;

    _isInCall = true;
    notifyListeners();

    _socketService?.socket?.emit('call:initiate', {
      'callerId': callerId,
      'receiverId': receiverId,
      'isVideo': isVideo,
      'duration': _totalSeconds,
    });
  }

  Future<void> acceptCall({
    required String callId,
    required String otherUserId,
    required bool isVideo,
    required int durationSeconds,
  }) async {
    _currentCallId = callId;
    _otherUserId = otherUserId;
    _totalSeconds = durationSeconds;
    _remainingSeconds = durationSeconds;
    _isInitiator = false;
    _isInCall = true;

    notifyListeners();

    final success = await initLocalStream(isVideo: isVideo);
    if (!success) return;

    await _createPeerConnection();

    _socketService?.socket?.emit('call:accept', {'callId': callId});
  }

  Future<void> rejectCall(String callId) async {
    _socketService?.socket?.emit('call:reject', {
      'callId': callId,
    });
    await _cleanup();
  }

  Future<void> endCall() async {
    if (_currentCallId != null) {
      _socketService?.socket?.emit('call:end', {
        'callId': _currentCallId,
      });
    }
    await _cleanup();
  }

  // =========================
  // WEBRTC
  // =========================

  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection(_iceServers);

    if (_localStream != null) {
      for (var track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }
    }

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        notifyListeners();
      }
    };

    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        _socketService?.socket?.emit('webrtc:ice-candidate', {
          'callId': _currentCallId,
          'candidate': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
          'targetUserId': _otherUserId,
        });
      }
    };

    _peerConnection!.onConnectionState = (state) {
      debugPrint('Connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        endCall();
      }
    };
  }

  Future<void> _createAndSendOffer() async {
    if (_peerConnection == null) return;

    try {
      final offer = await _peerConnection!.createOffer({
        'offerToReceiveVideo': 1,
        'offerToReceiveAudio': 1,
      });

      await _peerConnection!.setLocalDescription(offer);

      _socketService?.socket?.emit('webrtc:offer', {
        'callId': _currentCallId,
        'sdp': offer.toMap(),
        'targetUserId': _otherUserId,
      });
    } catch (e) {
      debugPrint('Error creating offer: $e');
    }
  }

  Future<void> _handleOffer(Map<String, dynamic> data) async {
    try {
      await _createPeerConnection();

      final sdp = data['sdp'];
      final description = RTCSessionDescription(sdp['sdp'], sdp['type']);
      await _peerConnection!.setRemoteDescription(description);

      _isRemoteDescriptionSet = true;
      await _applyBufferedCandidates();

      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      _socketService?.socket?.emit('webrtc:answer', {
        'callId': _currentCallId,
        'sdp': answer.toMap(),
        'targetUserId': _otherUserId,
      });
    } catch (e) {
      debugPrint('Error handling offer: $e');
    }
  }

  Future<void> _handleAnswer(Map<String, dynamic> data) async {
    try {
      final sdp = data['sdp'];
      final description = RTCSessionDescription(sdp['sdp'], sdp['type']);
      await _peerConnection!.setRemoteDescription(description);

      _isRemoteDescriptionSet = true;
      await _applyBufferedCandidates();
    } catch (e) {
      debugPrint('Error handling answer: $e');
    }
  }

  Future<void> _handleIceCandidate(Map<String, dynamic> data) async {
    try {
      final candidateData = data['candidate'];
      final candidate = RTCIceCandidate(
        candidateData['candidate'],
        candidateData['sdpMid'],
        candidateData['sdpMLineIndex'],
      );

      if (_isRemoteDescriptionSet && _peerConnection != null) {
        await _peerConnection!.addCandidate(candidate);
      } else {
        _remoteIceBuffer.add(candidate);
      }
    } catch (e) {
      debugPrint('Error handling ICE candidate: $e');
    }
  }

  Future<void> _applyBufferedCandidates() async {
    if (_peerConnection == null) return;

    for (var candidate in _remoteIceBuffer) {
      try {
        await _peerConnection!.addCandidate(candidate);
      } catch (e) {
        debugPrint('Error applying buffered candidate: $e');
      }
    }
    _remoteIceBuffer.clear();
  }

  // =========================
  // SOCKET EVENTS
  // =========================

  void _listenToCallEvents() {
    final socket = _socketService?.socket;
    if (socket == null) return;

    socket.on('call:ended', (_) => _cleanup());
    socket.on('call:rejected', (_) => _cleanup());

    // Инициатор получает подтверждение принятия звонка
    socket.on('call:accepted', (data) async {
      if (data is! Map<String, dynamic>) return;

      _currentCallId = data['callId']?.toString();
      _remainingSeconds = _totalSeconds;

      await _createPeerConnection();
      await _createAndSendOffer();
      _startTimer();
    });

    // Получатель получает offer
    socket.on('webrtc:offer', (data) async {
      if (data is! Map<String, dynamic>) return;
      await _handleOffer(data);
      _startTimer();
    });

    // Инициатор получает answer
    socket.on('webrtc:answer', (data) async {
      if (data is! Map<String, dynamic>) return;
      await _handleAnswer(data);
    });

    // Оба получают ICE-кандидаты
    socket.on('webrtc:ice-candidate', (data) async {
      if (data is! Map<String, dynamic>) return;
      await _handleIceCandidate(data);
    });
  }

  // =========================
  // CLEANUP
  // =========================

  Future<void> _cleanup() async {
    if (_isCleaningUp) return;
    _isCleaningUp = true;
    debugPrint('🧹 Очистка CallService...');

    _callTimer?.cancel();
    _callTimer = null;

    _isRemoteDescriptionSet = false;
    _remoteIceBuffer.clear();

    final pc = _peerConnection;
    _peerConnection = null;

    final local = _localStream;
    _localStream = null;

    final remote = _remoteStream;
    _remoteStream = null;

    try {
      if (pc != null) {
        await pc.close();
        await pc.dispose();
      }
    } catch (e) {
      debugPrint('Error closing peer connection: $e');
    }

    try {
      if (local != null) {
        for (var track in local.getTracks()) {
          track.stop();
        }
        await local.dispose();
      }
    } catch (e) {
      debugPrint('Error disposing local stream: $e');
    }

    try {
      if (remote != null) {
        for (var track in remote.getTracks()) {
          track.stop();
        }
        await remote.dispose();
      }
    } catch (e) {
      debugPrint('Error disposing remote stream: $e');
    }

    _isInCall = false;
    _isInitiator = false;
    _currentCallId = null;
    _otherUserId = null;
    _remainingSeconds = 0;
    _totalSeconds = 0;
    _isMicEnabled = true;
    _isCameraEnabled = true;

    notifyListeners();
    _isCleaningUp = false;
  }

  @override
  void dispose() {
    _cleanup().then((_) => super.dispose());
  }
}