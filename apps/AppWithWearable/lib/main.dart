import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as ble;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:friend_private/backend/mixpanel.dart';
import 'package:friend_private/pages/home/page.dart';
import 'package:friend_private/utils/notifications.dart';
import 'package:instabug_flutter/instabug_flutter.dart';
import 'backend/preferences.dart';
import 'env/env.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  ble.FlutterBluePlus.setLogLevel(ble.LogLevel.info, color: true);
  await initializeNotifications();
  await SharedPreferencesUtil.init();
  await MixpanelManager.init();
  if (Env.instabugApiKey != null) {
    await Instabug.init(
        // TODO: set new API Key to new account
        token: Env.instabugApiKey!,
        invocationEvents: [InvocationEvent.shake, InvocationEvent.screenshot]); //InvocationEvent.floatingButton
    Instabug.setColorTheme(ColorTheme.dark);
  }
  _getRunApp();
}

_getRunApp() {
  return runApp(
      MyApp(entryPage: SharedPreferencesUtil().onboardingCompleted ? const HomePageWrapper(btDevice: null) : null));
}

class MyApp extends StatefulWidget {
  final Widget? entryPage; // TODO: RESTORE ME

  const MyApp({super.key, this.entryPage});

  // This widget is the root of your application.
  @override
  State<MyApp> createState() => _MyAppState();

  static _MyAppState of(BuildContext context) => context.findAncestorStateOfType<_MyAppState>()!;
}

class _MyAppState extends State<MyApp> {
  // TODO: setup GetX Paged router + routes in here
  // TODO: navigate using that, GetMaterialApp, setup theme
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Friend',
      localizationsDelegates: const [
        // FFLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: false,
      ),
      themeMode: ThemeMode.system,
      // RESTORE ME
      // routerConfig: RouterConfig(routerDelegate: RouterDelegate.),
    );
  }
}
