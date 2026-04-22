import 'package:permission_handler/permission_handler.dart';

class PermissionsHelper {
  static Future<bool> requestCallPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    return statuses[Permission.camera]!.isGranted &&
           statuses[Permission.microphone]!.isGranted;
  }

  static Future<void> openSettings() async {
    await openAppSettings();
  }
}