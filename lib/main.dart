import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'dart:async';
import 'background_service.dart';

// ════════════════════════════════════════════════════════
// POINT D'ENTRÉE
// ════════════════════════════════════════════════════════
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  await AppState().loadFromPrefs();
  
  // Démarrer le service d'arrière-plan
  await initializeBackgroundService();
  
  runApp(const NeuroVoiceApp());
}

// ════════════════════════════════════════════════════════
// COULEURS
// ════════════════════════════════════════════════════════
class NColors {
  static const bgDark     = Color(0xFF0D1B3E);
  static const brandBlue  = Color(0xFF3B7EF6);
  static const yellow     = Color(0xFFFFE600);
  static const purple     = Color(0xFF6B2FD9);
  static const purplePink = Color(0xFFB03AF5);
  static const cyan       = Color(0xFF00E5FF);
  static const green      = Color(0xFF00FF88);
  static const white      = Color(0xFFFFFFFF);
  static const cardBlue   = Color(0xFF1E2D6B);
  static const cardLight  = Color(0xFFEEF2FF);
  static const darkNavy   = Color(0xFF0A1628);
}

// ════════════════════════════════════════════════════════
// ÉTAT GLOBAL AVEC PERSISTANCE
// ════════════════════════════════════════════════════════
class AppState {
  static final AppState _instance = AppState._internal();
  factory AppState() => _instance;
  AppState._internal();

  String phoneNumber      = '';
  String countryCode      = '+242';
  String countryFlag      = '🇨🇬';
  String assistantName    = 'Pulvio';
  String voiceType        = 'homme';
  String userTitle        = 'Monsieur';
  String userName         = '';
  String language         = 'Français';
  bool   batterySaving    = false;
  double voiceSensitivity = 5.0;
  bool   autoAnswer       = false;

  bool get isRegistered => phoneNumber.isNotEmpty;

  Future<void> loadFromPrefs() async {
    final p = await SharedPreferences.getInstance();
    phoneNumber      = p.getString('phoneNumber')      ?? '';
    countryCode      = p.getString('countryCode')      ?? '+242';
    countryFlag      = p.getString('countryFlag')      ?? '🇨🇬';
    assistantName    = p.getString('assistantName')    ?? 'Pulvio';
    voiceType        = p.getString('voiceType')        ?? 'homme';
    userTitle        = p.getString('userTitle')        ?? 'Monsieur';
    userName         = p.getString('userName')         ?? '';
    language         = p.getString('language')         ?? 'Français';
    batterySaving    = p.getBool('batterySaving')      ?? false;
    voiceSensitivity = p.getDouble('voiceSensitivity') ?? 5.0;
    autoAnswer       = p.getBool('autoAnswer')         ?? false;
  }

  Future<void> saveToPrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('phoneNumber',      phoneNumber);
    await p.setString('countryCode',      countryCode);
    await p.setString('countryFlag',      countryFlag);
    await p.setString('assistantName',    assistantName);
    await p.setString('voiceType',        voiceType);
    await p.setString('userTitle',        userTitle);
    await p.setString('userName',         userName);
    await p.setString('language',         language);
    await p.setBool('batterySaving',      batterySaving);
    await p.setDouble('voiceSensitivity', voiceSensitivity);
    await p.setBool('autoAnswer',         autoAnswer);
  }

  Future<void> logout() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('phoneNumber');
    phoneNumber = '';
  }
}

// ════════════════════════════════════════════════════════
// SERVICE VOCAL CORRIGÉ
// ════════════════════════════════════════════════════════
class VoiceService {
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;
  VoiceService._internal();

  final SpeechToText _speech = SpeechToText();
  final FlutterTts   _tts    = FlutterTts();

  bool   _isListening  = false;
  bool   _isAwake      = false;
  bool   _initialized  = false;
  String _wakeWord     = 'pulvio';
  String _userTitle    = 'Monsieur';
  String _userName     = '';
  String _language     = 'Français';

  Timer? _sleepTimer;
  Timer? _retryTimer;

  Function(String)? onMakeCall;
  Function()?       onAnswerCall;
  Function()?       onRejectCall;
  Function(String)? onStatusChanged;

  // ── Initialisation ──────────────────────────────────
  Future<void> initialize({
    required String wakeWord,
    required String userTitle,
    required String userName,
    String voiceType = 'homme',
    String language = 'Français',
    Function(String)? onMakeCall,
    Function()?       onAnswerCall,
    Function()?       onRejectCall,
    Function(String)? onStatusChanged,
  }) async {
    _wakeWord         = wakeWord.toLowerCase().trim();
    _userTitle        = userTitle;
    _userName         = userName;
    _language         = language;
    this.onMakeCall   = onMakeCall;
    this.onAnswerCall = onAnswerCall;
    this.onRejectCall = onRejectCall;
    this.onStatusChanged = onStatusChanged;

    // Demande de permissions avec vérification complète
    final micOk   = await Permission.microphone.request();
    final phoneOk = await Permission.phone.request();

    if (!micOk.isGranted || !phoneOk.isGranted) {
      onStatusChanged?.call('Permissions refusées (micro ou téléphone)');
      return;
    }

    await _initTts(voiceType);
    await _initSpeech();
    _initialized = true;
  }

  Future<void> _initTts(String voiceType) async {
    await _tts.setLanguage(_getTtsLocale());
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(voiceType == 'femme' ? 1.4 : 0.9);
    await _tts.setVolume(1.0);
  }

  String _getTtsLocale() {
    return _language == 'English' ? 'en-US' : 'fr-FR';
  }

  String _getSpeechLocale() {
    return _language == 'English' ? 'en_US' : 'fr_FR';
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onStatus: _onSpeechStatus,
      onError:  _onSpeechError,
    );
    if (available) {
      _startListening();
    } else {
      onStatusChanged?.call('Reconnaissance vocale indisponible');
    }
  }

  void _onSpeechStatus(String status) {
    if (status == 'notListening' || status == 'done') {
      _isListening = false;
      _retryTimer?.cancel();
      _retryTimer = Timer(const Duration(milliseconds: 500), () {
        if (_initialized) _startListening();
      });
    }
  }

  void _onSpeechError(dynamic error) {
    _isListening = false;
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 2), () {
      if (_initialized) _startListening();
    });
  }

  void _startListening() {
    if (_isListening || !_speech.isAvailable) return;
    _isListening = true;
    _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          _processCommand(result.recognizedWords.toLowerCase().trim());
        }
      },
      listenFor:      const Duration(seconds: 30),
      pauseFor:       const Duration(seconds: 3),
      partialResults: false,
      localeId:       _getSpeechLocale(),
    );
  }

  void _processCommand(String command) {
    if (command.isEmpty) return;

    if (!_isAwake) {
      if (command.contains(_wakeWord)) {
        _isAwake = true;
        final greeting = _userName.isNotEmpty ? '$_userTitle $_userName' : _userTitle;
        speak('Oui $greeting ?');
        onStatusChanged?.call('En écoute...');
        _resetSleepTimer();
      }
      return;
    }

    _resetSleepTimer();

    if (_containsAny(command, ['appelle', 'téléphone à', 'contacte', 'appeler'])) {
      String contact = command
          .replaceAll(RegExp(r'appelle[r]?|téléphone à|contacte'), '')
          .trim();
      if (contact.isNotEmpty) {
        speak('J\'appelle $contact, $_userTitle');
        onMakeCall?.call(contact);
      } else {
        speak('Qui voulez-vous appeler, $_userTitle ?');
      }
    } else if (_containsAny(command, ['réponds', 'décroche', 'vas-y', 'oui'])) {
      speak('D\'accord $_userTitle, je réponds');
      onAnswerCall?.call();
    } else if (_containsAny(command, ['ne réponds pas', 'refuse', 'laisse', 'non', 'rejette'])) {
      speak('D\'accord $_userTitle, je ne réponds pas');
      onRejectCall?.call();
    } else if (_containsAny(command, ['stop', 'arrête', 'dors', 'silence'])) {
      speak('D\'accord $_userTitle, je me mets en veille');
      _isAwake = false;
      _sleepTimer?.cancel();
      onStatusChanged?.call('En veille');
    } else {
      speak('Je n\'ai pas compris $_userTitle, pouvez-vous répéter ?');
    }
  }

  bool _containsAny(String text, List<String> keywords) {
    return keywords.any((k) => text.contains(k));
  }

  void _resetSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = Timer(const Duration(seconds: 8), () {
      _isAwake = false;
      onStatusChanged?.call('En veille — dites "$_wakeWord"');
    });
  }

  Future<void> speak(String message) async {
    await _tts.stop();
    await _tts.speak(message);
  }

  void stopListening() {
    _retryTimer?.cancel();
    _sleepTimer?.cancel();
    _isListening = false;
    _isAwake     = false;
    _initialized = false;
    _speech.stop();
    _tts.stop();
  }

  static Future<void> makePhoneCall(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      print("❌ Impossible d'ouvrir le téléphone pour : $number");
    }
  }
}

// ════════════════════════════════════════════════════════
// APP ROOT
// ════════════════════════════════════════════════════════
class NeuroVoiceApp extends StatelessWidget {
  const NeuroVoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppState();
    return MaterialApp(
      title: 'NeuroVoice',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: NColors.darkNavy,
        colorScheme: const ColorScheme.dark(
          primary: NColors.brandBlue,
          secondary: NColors.yellow,
        ),
      ),
      initialRoute: state.isRegistered ? '/assistant' : '/',
      routes: {
        '/':               (ctx) => const SplashScreen(),
        '/inscription':    (ctx) => const InscriptionPage(),
        '/personnalisation':(ctx) => const PersonnalisationPage(),
        '/options':        (ctx) => const OptionsAvanceesPage(),
        '/assistant':      (ctx) => const AssistantActivePage(),
      },
    );
  }
}

// ════════════════════════════════════════════════════════
// PAGE 0 — SPLASH
// ════════════════════════════════════════════════════════
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _fade;
  late Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _scale = Tween<double>(begin: 0.7, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();

    Timer(const Duration(milliseconds: 2800), () {
      if (mounted) Navigator.pushReplacementNamed(context, '/inscription');
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A4BC4), Color(0xFF0E2A7A)],
          ),
        ),
        child: FadeTransition(
          opacity: _fade,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: _scale,
                child: _RobotImage('splash_image', size: 220),
              ),
              const SizedBox(height: 36),
              ScaleTransition(
                scale: _scale,
                child: const Text('NeuroVoice',
                    style: TextStyle(
                        color: NColors.white,
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5)),
              ),
              const SizedBox(height: 12),
              FadeTransition(
                opacity: _fade,
                child: Text('Votre assistant vocal intelligent',
                    style: TextStyle(
                        color: NColors.white.withOpacity(0.7),
                        fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════
// PAGE 1 — INSCRIPTION
// ════════════════════════════════════════════════════════
class InscriptionPage extends StatefulWidget {
  const InscriptionPage({super.key});
  @override State<InscriptionPage> createState() => _InscriptionPageState();
}

class _InscriptionPageState extends State<InscriptionPage> {
  final _phoneCtrl   = TextEditingController();
  String _errorMsg   = '';
  bool   _loading    = false;
  int    _selectedCountry = 0;

  final List<Map<String, String>> _countries = [
    {'flag': '🇨🇬', 'code': '+242', 'name': 'Congo Brazzaville'},
    {'flag': '🇨🇩', 'code': '+243', 'name': 'RD Congo'},
    {'flag': '🇨🇲', 'code': '+237', 'name': 'Cameroun'},
    {'flag': '🇬🇦', 'code': '+241', 'name': 'Gabon'},
    {'flag': '🇸🇳', 'code': '+221', 'name': 'Sénégal'},
  ];

  @override
  void dispose() { _phoneCtrl.dispose(); super.dispose(); }

  bool _isValidNumber(String number, String code) {
    final clean = number.replaceAll(RegExp(r'[\s\-\.]'), '');
    switch (code) {
      case '+242':
        return clean.length == 9 &&
            (clean.startsWith('05') || clean.startsWith('06'));
      case '+243':
        return clean.length == 9 &&
            (clean.startsWith('08') || clean.startsWith('09'));
      default:
        return clean.length >= 8 && clean.length <= 12;
    }
  }

  Future<void> _inscrire() async {
    final number = _phoneCtrl.text.trim();
    final code   = _countries[_selectedCountry]['code']!;

    if (number.isEmpty) {
      setState(() => _errorMsg = 'Veuillez entrer votre numéro');
      return;
    }
    if (!_isValidNumber(number, code)) {
      setState(() => _errorMsg = 'Numéro invalide pour $code (ex: 06XXXXXXX)');
      return;
    }

    setState(() { _loading = true; _errorMsg = ''; });

    final state     = AppState();
    state.phoneNumber = number;
    state.countryCode = code;
    state.countryFlag = _countries[_selectedCountry]['flag']!;
    await state.saveToPrefs();

    setState(() => _loading = false);
    if (mounted) Navigator.pushNamed(context, '/personnalisation');
  }

  void _showCountryPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111D3E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => ListView.builder(
        shrinkWrap: true,
        itemCount: _countries.length,
        itemBuilder: (_, i) => ListTile(
          leading: Text(_countries[i]['flag']!,
              style: const TextStyle(fontSize: 26)),
          title: Text(
            '${_countries[i]['name']}  (${_countries[i]['code']})',
            style: const TextStyle(
                color: NColors.white, fontWeight: FontWeight.w600),
          ),
          onTap: () {
            setState(() => _selectedCountry = i);
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _countries[_selectedCountry];
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A4BC4), Color(0xFF0E2A7A), Color(0xFF091A4A)],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A3580),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Text('NeuroVoice',
                    style: TextStyle(
                        color: NColors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 20),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  'Votre assistant vocal intelligent.\nContrôlez vos appels sans toucher l\'écran.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: NColors.white, fontSize: 16, height: 1.6),
                ),
              ),
              Expanded(
                child: Center(child: _RobotImage('home_robot', size: 240)),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                decoration: const BoxDecoration(
                  color: Color(0xFF0D1A40),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      GestureDetector(
                        onTap: _showCountryPicker,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C2D60),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(children: [
                            Text(c['flag']!,
                                style: const TextStyle(fontSize: 22)),
                            const SizedBox(width: 6),
                            Text(c['code']!,
                                style: const TextStyle(
                                    color: NColors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14)),
                            const SizedBox(width: 4),
                            const Icon(Icons.keyboard_arrow_down,
                                color: NColors.white, size: 18),
                          ]),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C2D60),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: TextField(
                            controller: _phoneCtrl,
                            keyboardType: TextInputType.phone,
                            style: const TextStyle(
                                color: NColors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[\d\s\-]')),
                            ],
                            decoration: InputDecoration(
                              hintText: '06 000 00 00',
                              hintStyle: TextStyle(
                                  color: NColors.white.withOpacity(0.4),
                                  fontSize: 14),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 16),
                            ),
                          ),
                        ),
                      ),
                    ]),
                    if (_errorMsg.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        const Icon(Icons.error_outline,
                            color: Colors.redAccent, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(_errorMsg,
                              style: const TextStyle(
                                  color: Colors.redAccent, fontSize: 12)),
                        ),
                      ]),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: _GlowButton(
                        label: _loading ? 'Vérification…' : 'S\'inscrire',
                        gradient: const LinearGradient(
                            colors: [Color(0xFFB03AF5), Color(0xFF6B2FD9)]),
                        onTap: _loading ? null : _inscrire,
                        fontSize: 17,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════
// PAGE 2 — PERSONNALISATION
// ════════════════════════════════════════════════════════
class PersonnalisationPage extends StatefulWidget {
  const PersonnalisationPage({super.key});
  @override State<PersonnalisationPage> createState() =>
      _PersonnalisationPageState();
}

class _PersonnalisationPageState extends State<PersonnalisationPage> {
  final _state = AppState();

  Future<void> _openDialog(Widget dialog) async {
    await showDialog(context: context, builder: (_) => dialog);
    await _state.saveToPrefs();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NColors.darkNavy,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: NColors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(children: [
                    _RobotImage('header_image', size: 40),
                    const SizedBox(width: 12),
                    const Text('NeuroVoice',
                        style: TextStyle(
                            color: NColors.darkNavy,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    const Spacer(),
                    if (_state.userName.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: NColors.cardLight,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(_state.userName,
                            style: const TextStyle(
                                color: NColors.darkNavy,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                      ),
                  ]),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A3EC8),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(children: [
                    Text(
                      'Bonjour ${_state.userTitle}${_state.userName.isNotEmpty ? ' ${_state.userName}' : ''} !',
                      style: const TextStyle(
                          color: NColors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Personnalisez votre assistant.\nMot de réveil actuel : "${_state.assistantName}"',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: NColors.white.withOpacity(0.85),
                          fontSize: 14,
                          height: 1.5),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(children: [
                        _PersonnalisationBtn(
                          icon: Icons.badge_outlined,
                          label: 'NOM DE L\'ASSISTANT',
                          sublabel: _state.assistantName,
                          color: NColors.brandBlue,
                          textColor: NColors.white,
                          onTap: () =>
                              _openDialog(const _NomAssistantDialog()),
                        ),
                        const SizedBox(height: 10),
                        _PersonnalisationBtn(
                          icon: Icons.record_voice_over_outlined,
                          label: 'VOIX DE L\'ASSISTANT',
                          sublabel: _state.voiceType == 'homme'
                              ? 'Robot Homme'
                              : 'Robot Femme',
                          color: NColors.darkNavy,
                          textColor: NColors.white,
                          onTap: () => _openDialog(const _VoixDialog()),
                        ),
                        const SizedBox(height: 10),
                        _PersonnalisationBtn(
                          icon: Icons.account_circle_outlined,
                          label: 'VOTRE IDENTITÉ',
                          sublabel: '${_state.userTitle} ${_state.userName}',
                          color: NColors.yellow,
                          textColor: NColors.darkNavy,
                          onTap: () => _openDialog(const _IdentiteDialog()),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 120,
                      height: 170,
                      color: const Color(0xFFFFE600),
                      child: _RobotImage('header_image', size: 100),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/options')
                      .then((_) => setState(() {})),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: NColors.yellow, width: 2),
                    ),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: NColors.yellow,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.settings,
                            color: NColors.darkNavy, size: 18),
                      ),
                      const SizedBox(width: 12),
                      const Text('OPTIONS AVANCÉES',
                          style: TextStyle(
                              color: NColors.darkNavy,
                              fontWeight: FontWeight.w800,
                              fontSize: 14)),
                      const Spacer(),
                      const Icon(Icons.chevron_right,
                          color: NColors.darkNavy),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Paramètres actifs',
                          style: TextStyle(
                              color: NColors.darkNavy,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        _InfoChip(
                            '🌍 ${_state.language}', NColors.brandBlue),
                        _InfoChip(
                            '🔋 Batterie: ${_state.batterySaving ? "Éco" : "Normal"}',
                            NColors.darkNavy),
                        _InfoChip(
                            '🎙 Sensibilité: ${_state.voiceSensitivity.toInt()}/10',
                            NColors.purple),
                        _InfoChip(
                            '📞 Auto-réponse: ${_state.autoAnswer ? "ON" : "OFF"}',
                            _state.autoAnswer
                                ? Colors.green.shade700
                                : Colors.grey.shade600),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: _GlowButton(
                    label: 'ACTIVER L\'ASSISTANT',
                    gradient: const LinearGradient(
                        colors: [Color(0xFF3B7EF6), Color(0xFF1A55D4)]),
                    onTap: () =>
                        Navigator.pushNamed(context, '/assistant'),
                    fontSize: 16,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════
// PAGE 3 — OPTIONS AVANCÉES
// ════════════════════════════════════════════════════════
class OptionsAvanceesPage extends StatefulWidget {
  const OptionsAvanceesPage({super.key});
  @override State<OptionsAvanceesPage> createState() =>
      _OptionsAvanceesPageState();
}

class _OptionsAvanceesPageState extends State<OptionsAvanceesPage> {
  final _state = AppState();

  Future<void> _save() async => await _state.saveToPrefs();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NColors.darkNavy,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: NColors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Options Avancées',
            style: TextStyle(
                color: NColors.white,
                fontWeight: FontWeight.w700,
                fontSize: 18)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: NColors.cardBlue,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: NColors.brandBlue.withOpacity(0.4)),
            ),
            child: const Row(children: [
              Icon(Icons.tune, color: NColors.cyan, size: 24),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Ajustez les réglages de NeuroVoice selon vos besoins.',
                  style: TextStyle(
                      color: NColors.white, fontSize: 13, height: 1.5),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          _OptionCard(
            icon: Icons.language,
            title: 'Langue',
            child: Row(
              children: ['Français', 'English'].map((lang) {
                final sel = _state.language == lang;
                return GestureDetector(
                  onTap: () => setState(() {
                    _state.language = lang;
                    _save();
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: sel ? NColors.brandBlue : NColors.cardBlue,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: sel
                            ? NColors.brandBlue
                            : NColors.white.withOpacity(0.2),
                      ),
                    ),
                    child: Text(lang,
                        style: TextStyle(
                            color: sel
                                ? NColors.white
                                : NColors.white.withOpacity(0.5),
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          _OptionCard(
            icon: Icons.battery_saver_outlined,
            title: 'Mode économie batterie',
            subtitle: 'Réduit la fréquence d\'écoute',
            child: Switch(
              value: _state.batterySaving,
              onChanged: (v) => setState(() {
                _state.batterySaving = v;
                _save();
              }),
              activeColor: NColors.green,
              activeTrackColor: NColors.green.withOpacity(0.3),
            ),
          ),
          const SizedBox(height: 12),
          _OptionCard(
            icon: Icons.mic_outlined,
            title: 'Sensibilité vocale',
            subtitle: 'Niveau de détection du microphone',
            child: Column(children: [
              const SizedBox(height: 4),
              Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Faible',
                        style: TextStyle(
                            color: NColors.white.withOpacity(0.5),
                            fontSize: 11)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: NColors.cyan.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: NColors.cyan.withOpacity(0.4)),
                      ),
                      child: Text(
                        '${_state.voiceSensitivity.toInt()} / 10',
                        style: const TextStyle(
                            color: NColors.cyan,
                            fontWeight: FontWeight.w800,
                            fontSize: 14),
                      ),
                    ),
                    Text('Élevée',
                        style: TextStyle(
                            color: NColors.white.withOpacity(0.5),
                            fontSize: 11)),
                  ]),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: NColors.cyan,
                  inactiveTrackColor: NColors.cardBlue,
                  thumbColor: NColors.cyan,
                  overlayColor: NColors.cyan.withOpacity(0.2),
                  trackHeight: 4,
                ),
                child: Slider(
                  value: _state.voiceSensitivity,
                  min: 1,
                  max: 10,
                  divisions: 9,
                  onChanged: (v) => setState(() {
                    _state.voiceSensitivity = v;
                    _save();
                  }),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          _OptionCard(
            icon: Icons.phone_callback_outlined,
            title: 'Réponse automatique',
            subtitle: 'Décroche automatiquement les appels entrants',
            child: Switch(
              value: _state.autoAnswer,
              onChanged: (v) => setState(() {
                _state.autoAnswer = v;
                _save();
              }),
              activeColor: NColors.green,
              activeTrackColor: NColors.green.withOpacity(0.3),
            ),
          ),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            child: _GlowButton(
              label: 'ACTIVER L\'ASSISTANT',
              gradient: const LinearGradient(
                  colors: [Color(0xFF3B7EF6), Color(0xFF1A55D4)]),
              onTap: () => Navigator.pushNamedAndRemoveUntil(
                  context, '/assistant', (r) => false),
              fontSize: 16,
              padding: const EdgeInsets.symmetric(vertical: 20),
            ),
          ),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════
// PAGE 4 — ASSISTANT ACTIF (AVEC PAUSE/DÉCONNEXION SÉPARÉES)
// ════════════════════════════════════════════════════════
class AssistantActivePage extends StatefulWidget {
  const AssistantActivePage({super.key});
  @override State<AssistantActivePage> createState() =>
      _AssistantActivePageState();
}

class _AssistantActivePageState extends State<AssistantActivePage>
    with TickerProviderStateMixin {
  late AnimationController _ledCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _waveCtrl;
  late Animation<double>   _ledAnim;
  late Animation<double>   _pulseAnim;

  final _voiceService = VoiceService();
  final _state        = AppState();

  String _statusText  = 'Initialisation...';
  bool   _isActive    = false;
  String _lastCommand = '';
  bool   _isVoiceInitialized = false;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initVoice();
  }

  void _initAnimations() {
    _ledCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _ledAnim = Tween<double>(begin: 0.3, end: 1.0).animate(_ledCtrl);

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.9, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _waveCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))
      ..repeat();
  }

  Future<void> _initVoice() async {
    if (_isVoiceInitialized) return;
    _isVoiceInitialized = true;

    await _voiceService.initialize(
      wakeWord:   _state.assistantName,
      userTitle:  _state.userTitle,
      userName:   _state.userName,
      voiceType:  _state.voiceType,
      language:   _state.language,
      onMakeCall: (contact) async {
        setState(() => _lastCommand = 'Appel : $contact');
        final digits = contact.replaceAll(RegExp(r'[^\d]'), '');
        if (digits.isNotEmpty) {
          await VoiceService.makePhoneCall(digits);
        } else {
          await VoiceService.makePhoneCall(
              '${_state.countryCode}${_state.phoneNumber}');
        }
      },
      onAnswerCall: () {
        setState(() => _lastCommand = 'Réponse à l\'appel');
      },
      onRejectCall: () {
        setState(() => _lastCommand = 'Appel rejeté');
      },
      onStatusChanged: (status) {
        if (mounted) setState(() => _statusText = status);
      },
    );
    if (mounted) {
      setState(() {
        _isActive   = true;
        _statusText = 'Dites "${_state.assistantName}"';
      });
    }
  }

  void _startBackgroundService() async {
    final service = FlutterBackgroundService();
    service.startService();
  }

  void _stopBackgroundService() async {
    final service = FlutterBackgroundService();
    service.invoke('stopService');
  }

  void _pauseAssistant() {
    _voiceService.stopListening();
    setState(() {
      _isActive = false;
      _statusText = 'Assistant en pause';
      _lastCommand = '';
    });
  }

  Future<void> _deconnexionComplete() async {
    _voiceService.stopListening();
    await _state.logout();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/inscription', (r) => false);
    }
  }

  @override
  void dispose() {
    _ledCtrl.dispose();
    _pulseCtrl.dispose();
    _waveCtrl.dispose();
    _voiceService.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name  = _state.userName.isNotEmpty ? _state.userName : '';
    final title = _state.userTitle;
    final aName = _state.assistantName;

    return Scaffold(
      backgroundColor: NColors.darkNavy,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.3,
            colors: [Color(0xFF0D2060), Color(0xFF060D20)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(children: [
              const SizedBox(height: 20),
              Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('NeuroVoice',
                        style: TextStyle(
                            color: NColors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800)),
                    Row(children: [
                      AnimatedBuilder(
                        animation: _ledAnim,
                        builder: (_, __) => Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _isActive
                                ? NColors.green.withOpacity(_ledAnim.value)
                                : Colors.orange.withOpacity(0.7),
                            shape: BoxShape.circle,
                            boxShadow: _isActive
                                ? [
                                    BoxShadow(
                                        color: NColors.green
                                            .withOpacity(
                                                _ledAnim.value * 0.8),
                                        blurRadius: 10,
                                        spreadRadius: 2)
                                  ]
                                : [],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isActive ? 'ACTIF' : 'PAUSE',
                        style: TextStyle(
                            color: _isActive
                                ? NColors.green
                                : Colors.orange,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5),
                      ),
                    ]),
                  ]),
              const SizedBox(height: 36),
              Text('En attente de vos ordres,',
                  style: TextStyle(
                      color: NColors.white.withOpacity(0.6),
                      fontSize: 15)),
              const SizedBox(height: 4),
              Text(
                '$title${name.isNotEmpty ? ' $name' : ''}',
                style: const TextStyle(
                    color: NColors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 44),
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, child) =>
                    Transform.scale(scale: _pulseAnim.value, child: child),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ...List.generate(3, (i) => AnimatedBuilder(
                          animation: _waveCtrl,
                          builder: (_, __) {
                            final t = (_waveCtrl.value + i / 3.0) % 1.0;
                            return Opacity(
                              opacity: (1.0 - t) * 0.35,
                              child: Container(
                                width:  100 + t * 130,
                                height: 100 + t * 130,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: NColors.cyan, width: 1.5),
                                ),
                              ),
                            );
                          },
                        )),
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF3B7EF6),
                            Color(0xFF1A3A8F)
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                              color: NColors.brandBlue.withOpacity(0.5),
                              blurRadius: 30,
                              spreadRadius: 5),
                        ],
                      ),
                      child: const Icon(Icons.mic,
                          color: NColors.white, size: 50),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 44),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: NColors.cardBlue.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: NColors.cyan.withOpacity(0.3)),
                ),
                child: Column(children: [
                  const Icon(Icons.record_voice_over,
                      color: NColors.cyan, size: 26),
                  const SizedBox(height: 8),
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: const TextStyle(
                          color: NColors.white, fontSize: 14),
                      children: [
                        const TextSpan(text: 'Dites '),
                        TextSpan(
                          text: '"$aName"',
                          style: const TextStyle(
                              color: NColors.cyan,
                              fontWeight: FontWeight.w800,
                              fontSize: 16),
                        ),
                        const TextSpan(text: ' pour me réveiller'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: NColors.brandBlue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_statusText,
                        style: TextStyle(
                            color: NColors.cyan.withOpacity(0.9),
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              if (_lastCommand.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: NColors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: NColors.green.withOpacity(0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.check_circle_outline,
                        color: NColors.green, size: 16),
                    const SizedBox(width: 8),
                    Text(_lastCommand,
                        style: const TextStyle(
                            color: NColors.green,
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                  ]),
                ),
              Container(
                margin: const EdgeInsets.only(top: 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: NColors.cardBlue.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Exemples de commandes :',
                        style: TextStyle(
                            color: NColors.white.withOpacity(0.5),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5)),
                    const SizedBox(height: 8),
                    _CommandChip('"$aName, appelle Marie"'),
                    _CommandChip('"$aName, réponds"'),
                    _CommandChip('"$aName, ne réponds pas"'),
                    _CommandChip('"$aName, arrête"'),
                  ],
                ),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Bouton pause/reprise
                  ElevatedButton.icon(
                    onPressed: _pauseAssistant,
                    icon: Icon(_isActive ? Icons.pause : Icons.play_arrow, size: 16),
                    label: Text(_isActive ? 'PAUSE' : 'REPRENDRE'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  // Bouton déconnexion
                  ElevatedButton.icon(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: const Color(0xFF111D3E),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        title: const Text('Déconnexion',
                            style: TextStyle(color: NColors.white)),
                        content: const Text(
                          'Voulez-vous vraiment vous déconnecter ?\nToutes vos données seront effacées.',
                          style: TextStyle(color: Colors.white60),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Annuler',
                                style: TextStyle(color: NColors.brandBlue)),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _deconnexionComplete();
                            },
                            child: const Text('Déconnecter',
                                style: TextStyle(color: Colors.redAccent)),
                          ),
                        ],
                      ),
                    ),
                    icon: const Icon(Icons.exit_to_app, color: Colors.redAccent, size: 16),
                    label: const Text('DÉCONNEXION'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent.withOpacity(0.2),
                      foregroundColor: Colors.redAccent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ]),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════
// DIALOGUES (inchangés)
// ════════════════════════════════════════════════════════
class _NomAssistantDialog extends StatefulWidget {
  const _NomAssistantDialog();
  @override State<_NomAssistantDialog> createState() =>
      _NomAssistantDialogState();
}

class _NomAssistantDialogState extends State<_NomAssistantDialog> {
  late TextEditingController _ctrl;
  final _state = AppState();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _state.assistantName);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return _BaseDialog(
      title: 'Nom de l\'assistant',
      icon: Icons.badge_outlined,
      iconColor: NColors.brandBlue,
      child: Column(children: [
        Text('Ce prénom sera votre mot de réveil.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: NColors.white.withOpacity(0.6), fontSize: 13)),
        const SizedBox(height: 16),
        _DialogTextField(
            controller: _ctrl, hint: 'Ex: Pulvio, JARVIS, Sofia…'),
        const SizedBox(height: 20),
        _DialogSaveButton(onTap: () {
          if (_ctrl.text.trim().isNotEmpty) {
            _state.assistantName = _ctrl.text.trim();
          }
          Navigator.pop(context);
        }),
      ]),
    );
  }
}

class _VoixDialog extends StatefulWidget {
  const _VoixDialog();
  @override State<_VoixDialog> createState() => _VoixDialogState();
}

class _VoixDialogState extends State<_VoixDialog> {
  final _state = AppState();
  String _selected = '';

  @override
  void initState() {
    super.initState();
    _selected = _state.voiceType;
  }

  @override
  Widget build(BuildContext context) {
    return _BaseDialog(
      title: 'Voix de l\'assistant',
      icon: Icons.record_voice_over_outlined,
      iconColor: NColors.purplePink,
      child: Column(children: [
        _VoiceOption(
          label: 'Robot Homme',
          icon: Icons.person_outline,
          selected: _selected == 'homme',
          onSelect: () => setState(() => _selected = 'homme'),
        ),
        const SizedBox(height: 12),
        _VoiceOption(
          label: 'Robot Femme',
          icon: Icons.person_2_outlined,
          selected: _selected == 'femme',
          onSelect: () => setState(() => _selected = 'femme'),
        ),
        const SizedBox(height: 20),
        _DialogSaveButton(onTap: () {
          _state.voiceType = _selected;
          Navigator.pop(context);
        }),
      ]),
    );
  }
}

class _IdentiteDialog extends StatefulWidget {
  const _IdentiteDialog();
  @override State<_IdentiteDialog> createState() => _IdentiteDialogState();
}

class _IdentiteDialogState extends State<_IdentiteDialog> {
  final _state = AppState();
  late TextEditingController _nameCtrl;
  String _title = 'Monsieur';

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: _state.userName);
    _title    = _state.userTitle;
  }

  @override
  void dispose() { _nameCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return _BaseDialog(
      title: 'Votre identité',
      icon: Icons.account_circle_outlined,
      iconColor: NColors.yellow,
      child: Column(children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: ['Monsieur', 'Madame'].map((t) {
            final sel = _title == t;
            return GestureDetector(
              onTap: () => setState(() => _title = t),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 6),
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: sel ? NColors.brandBlue : NColors.cardBlue,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: sel ? NColors.brandBlue : Colors.white24,
                  ),
                ),
                child: Text(t,
                    style: TextStyle(
                        color: sel
                            ? NColors.white
                            : NColors.white.withOpacity(0.5),
                        fontWeight: FontWeight.w600)),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        _DialogTextField(
            controller: _nameCtrl, hint: 'Votre prénom (ex: Nicolas)'),
        const SizedBox(height: 20),
        _DialogSaveButton(onTap: () {
          _state.userTitle = _title;
          _state.userName  = _nameCtrl.text.trim();
          Navigator.pop(context);
        }),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════
// WIDGETS RÉUTILISABLES (inchangés)
// ════════════════════════════════════════════════════════

class _RobotImage extends StatelessWidget {
  final String name;
  final double size;
  const _RobotImage(this.name, {required this.size});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/$name.png',
      height: size,
      width:  size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(
        Icons.smart_toy_outlined,
        size:  size * 0.6,
        color: NColors.brandBlue,
      ),
    );
  }
}

class _GlowButton extends StatelessWidget {
  final String label;
  final LinearGradient gradient;
  final VoidCallback? onTap;
  final double fontSize;
  final EdgeInsets padding;

  const _GlowButton({
    required this.label,
    required this.gradient,
    required this.onTap,
    this.fontSize = 15,
    this.padding = const EdgeInsets.symmetric(vertical: 16),
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: onTap == null ? 0.5 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: gradient.colors.first.withOpacity(0.4),
                blurRadius: 20,
                spreadRadius: 2,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                    color: NColors.white,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w800)),
          ),
        ),
      ),
    );
  }
}

class _PersonnalisationBtn extends StatelessWidget {
  final String label;
  final String sublabel;
  final IconData icon;
  final Color color;
  final Color textColor;
  final VoidCallback onTap;

  const _PersonnalisationBtn({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.color,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(icon, color: textColor.withOpacity(0.8), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 11)),
                if (sublabel.isNotEmpty)
                  Text(sublabel,
                      style: TextStyle(
                          color: textColor.withOpacity(0.7),
                          fontSize: 11,
                          fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          Icon(Icons.chevron_right,
              color: textColor.withOpacity(0.6), size: 16),
        ]),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final Color color;
  const _InfoChip(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  const _OptionCard({
    required this.icon,
    required this.title,
    this.subtitle = '',
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NColors.cardBlue,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NColors.white.withOpacity(0.08)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: NColors.cyan, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: NColors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                if (subtitle.isNotEmpty)
                  Text(subtitle,
                      style: TextStyle(
                          color: NColors.white.withOpacity(0.45),
                          fontSize: 11)),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 14),
        child,
      ]),
    );
  }
}

class _CommandChip extends StatelessWidget {
  final String text;
  const _CommandChip(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: NColors.cyan.withOpacity(0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NColors.cyan.withOpacity(0.25)),
      ),
      child: Row(children: [
        const Icon(Icons.mic_none, color: NColors.cyan, size: 13),
        const SizedBox(width: 8),
        Text(text,
            style: const TextStyle(
                color: NColors.cyan,
                fontSize: 12,
                fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

class _BaseDialog extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget child;

  const _BaseDialog({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF111D3E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(height: 14),
          Text(title,
              style: const TextStyle(
                  color: NColors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 20),
          child,
        ]),
      ),
    );
  }
}

class _DialogTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  const _DialogTextField({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NColors.cardBlue,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NColors.brandBlue.withOpacity(0.5)),
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: NColors.white, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
              color: NColors.white.withOpacity(0.35), fontSize: 13),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}

class _DialogSaveButton extends StatelessWidget {
  final VoidCallback onTap;
  const _DialogSaveButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: _GlowButton(
        label: 'Enregistrer',
        gradient: const LinearGradient(
            colors: [Color(0xFF3B7EF6), Color(0xFF1A55D4)]),
        onTap: onTap,
        fontSize: 15,
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }
}

class _VoiceOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onSelect;

  const _VoiceOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? NColors.brandBlue.withOpacity(0.2)
              : NColors.cardBlue,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? NColors.brandBlue : Colors.white12,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(children: [
          Icon(icon,
              color:
                  selected ? NColors.brandBlue : Colors.white38,
              size: 24),
          const SizedBox(width: 14),
          Text(label,
              style: TextStyle(
                  color: selected ? NColors.white : Colors.white54,
                  fontWeight: selected
                      ? FontWeight.w700
                      : FontWeight.w500,
                  fontSize: 15)),
          const Spacer(),
          Icon(
            selected
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            color:
                selected ? NColors.brandBlue : Colors.white24,
            size: 22,
          ),
        ]),
      ),
    );
  }
}