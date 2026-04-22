import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:async';
import 'socket_service.dart';

class CallService extends ChangeNotifier {
  SocketService? _socketService;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  String? _currentCallId;
  String? _otherUserId;
  bool _isInCall = false;

  Timer? _callTimer;
  int _remainingSeconds = 0;
  int _totalSeconds = 0;

  bool get isInCall => _isInCall;
  int get remainingSeconds => _remainingSeconds;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ]
  };

  void init({required SocketService socketService}) {
    _socketService = socketService;
    _listenToCallEvents();
    debugPrint('✅ CallService инициализирован');
  }

  void reset() {
    _cleanup();
    _socketService = null;
    notifyListeners();
  }

  String formatTime(int seconds) {
    int h = seconds ~/ 3600;
    int m = (seconds % 3600) ~/ 60;
    int s = seconds % 60;

    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<bool> initLocalStream({bool isVideo = true}) async {
    try {
      debugPrint('🎥 Инициализация локального потока...');
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': isVideo
            ? {
                'facingMode': 'user',
                'width': 1280,
                'height': 720,
              }
            : false,
      });
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('❌ Ошибка получения медиа: $e');
      return false;
    }
  }

  Future<void> initiateCall({
    required String callerId,
    required String receiverId,
    required bool isVideo,
    required int hours,
    required int minutes,
    required int seconds,
  }) async {
    _totalSeconds = (hours * 3600) + (minutes * 60) + seconds;

    if (_totalSeconds <= 0) {
      debugPrint('❌ Неверная длительность звонка');
      return;
    }

    _otherUserId = receiverId;

    await initLocalStream(isVideo: isVideo);

    _socketService?.socket?.emit('call:initiate', {
      'callerId': callerId,
      'receiverId': receiverId,
      'isVideo': isVideo,
      'duration': _totalSeconds,
    });

    _isInCall = true;
    _remainingSeconds = _totalSeconds;
    notifyListeners();
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

    await initLocalStream(isVideo: isVideo);
    await _createPeerConnection();

    _socketService?.socket?.emit('call:accept', {'callId': callId});
  }

  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection(_iceServers);

    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });
    }

    _peerConnection!.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        notifyListeners();
      }
    };

    _peerConnection!.onIceCandidate = (RTCIceCandidate? candidate) {
      if (candidate != null) {
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
  }

  void _listenToCallEvents() {
    _socketService?.socket?.on('call:accepted', (data) async {
      _currentCallId = data['callId'];

      await _createPeerConnection();

      RTCSessionDescription offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      _socketService?.socket?.emit('webrtc:offer', {
        'callId': _currentCallId,
        'offer': {
          'sdp': offer.sdp,
          'type': offer.type,
        },
      });

      _remainingSeconds = _totalSeconds;
      _startTimer();
    });

    _socketService?.socket?.on('webrtc:offer', (data) async {
      try {
        RTCSessionDescription offer = RTCSessionDescription(
          data['offer']['sdp'],
          data['offer']['type'],
        );

        await _peerConnection!.setRemoteDescription(offer);

        RTCSessionDescription answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);

        _socketService?.socket?.emit('webrtc:answer', {
          'callId': data['callId'],
          'answer': {
            'sdp': answer.sdp,
            'type': answer.type,
          },
        });

        _remainingSeconds = _totalSeconds;
        _startTimer();
      } catch (e) {
        debugPrint('❌ Ошибка обработки offer: $e');
      }
    });

    _socketService?.socket?.on('webrtc:answer', (data) async {
      RTCSessionDescription answer = RTCSessionDescription(
        data['answer']['sdp'],
        data['answer']['type'],
      );
      await _peerConnection?.setRemoteDescription(answer);
    });

    _socketService?.socket?.on('webrtc:ice-candidate', (data) async {
      RTCIceCandidate candidate = RTCIceCandidate(
        data['candidate']['candidate'],
        data['candidate']['sdpMid'],
        data['candidate']['sdpMLineIndex'],
      );
      await _peerConnection?.addCandidate(candidate);
    });

    _socketService?.socket?.on('call:ended', (_) => _cleanup());
    _socketService?.socket?.on('call:rejected', (_) => _cleanup());
  }

  void _startTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        _remainingSeconds--;
        notifyListeners();
      } else {
        endCall();
      }
    });
  }

  Future<void> endCall() async {
    if (_currentCallId != null) {
      _socketService?.socket?.emit('call:end', {
        'callId': _currentCallId,
      });
    }
    _cleanup();
  }

  void rejectCall(String callId) {
    _socketService?.socket?.emit('call:reject', {
      'callId': callId,
    });
    _cleanup();
  }

  Future<void> _cleanup() async {
    _callTimer?.cancel();
    await _localStream?.dispose();
    await _remoteStream?.dispose();
    await _peerConnection?.close();

    _localStream = null;
    _remoteStream = null;
    _peerConnection = null;
    _currentCallId = null;
    _otherUserId = null;
    _isInCall = false;
    _remainingSeconds = 0;
    _totalSeconds = 0;

    notifyListeners();
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }
}