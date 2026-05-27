import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/material.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'neurovoice_channel',
      initialNotificationTitle: 'NeuroVoice',
      initialNotificationContent: 'Assistant actif en arrière-plan',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
    ),
  );

  await service.startService();
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Correction : Utiliser WidgetsFlutterBinding au lieu de DartPluginRegistrant
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final assistantName = prefs.getString('assistantName') ?? 'Pulvio';
  final userTitle = prefs.getString('userTitle') ?? 'Monsieur';
  final userName = prefs.getString('userName') ?? '';

  final SpeechToText speech = SpeechToText();
  final FlutterTts tts = FlutterTts();

  await speech.initialize();
  await tts.setLanguage('fr-FR');
  await tts.setSpeechRate(0.5);
  await tts.setVolume(1.0);

  bool isAwake = false;

  void speak(String message) async {
    await tts.speak(message);
  }

  void startListening() {
    speech.listen(
      onResult: (result) {
        final command = result.recognizedWords.toLowerCase();
        if (!isAwake && command.contains(assistantName.toLowerCase())) {
          isAwake = true;
          speak('Oui $userTitle ${userName.isNotEmpty ? userName : ''} ?');
          Timer(const Duration(seconds: 5), () => isAwake = false);
        } else if (isAwake && command.contains('appelle')) {
          speak("J'appelle, $userTitle");
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      localeId: 'fr_FR',
    );
  }

  startListening();

  if (service is AndroidServiceInstance) {
    service.on('stopService').listen((event) {
      service.stopSelf();
    });
  }
}