import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Background alerting (beta.1): the app uses the UIScene lifecycle
    // (see Info.plist UIApplicationSceneManifest), so BGTaskScheduler launch
    // handlers must be re-registered before launch finishes — the plugin's
    // own application callback runs too late for that.
    WorkmanagerPlugin.registerLaunchHandlers()

    // Background-isolate plugin registrant (SharedPreferences,
    // flutter_secure_storage, flutter_local_notifications, path_provider…).
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }

    // ~15 min scheduling hint for the periodic alerts task. The identifier
    // MUST match BackgroundAlerts.taskName (Dart) and
    // BGTaskSchedulerPermittedIdentifiers (Info.plist), or iOS throws
    // BGTaskSchedulerErrorDomain Code=3. Optional: the plugin re-registers
    // handlers for already-scheduled tasks on launch without this call.
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "com.mycontrolpanel.my_control_panel.backgroundAlerts",
      frequency: NSNumber(value: 15 * 60)
    )

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
