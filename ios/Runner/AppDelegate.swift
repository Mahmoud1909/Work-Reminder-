import UIKit
import Flutter
import UserNotifications
import BackgroundTasks

@main
@objc class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate {
  // عرف identifiers بيستخدمها BGTaskScheduler
  let appRefreshTaskId = "com.example.khamsat.refresh"
  let processingTaskId = "com.example.khamsat.processing"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 1. سجل البلجنز (Flutter)
    GeneratedPluginRegistrant.register(with: self)

    // 2. اضبط UNUserNotificationCenter delegate
    UNUserNotificationCenter.current().delegate = self

    // 3. اطلب صلاحيات الإشعارات (alerts, sound, badge)
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      if let err = error {
        print("Notifications auth error: \(err.localizedDescription)")
      } else {
        print("Notifications granted: \(granted)")
      }
    }

    // 4. سجّل للحصول على remote notifications (APNs) لو هتستخدم push (مثل FCM)
    UIApplication.shared.registerForRemoteNotifications()

    // 5. سجّل مهام الخلفية (iOS 13+)
    if #available(iOS 13.0, *) {
      BGTaskScheduler.shared.register(forTaskWithIdentifier: appRefreshTaskId, using: nil) { task in
        self.handleAppRefresh(task: task as! BGAppRefreshTask)
      }
      BGTaskScheduler.shared.register(forTaskWithIdentifier: processingTaskId, using: nil) { task in
        self.handleProcessingTask(task: task as! BGProcessingTask)
      }
      // جدولة أولية (اختياري)
      scheduleAppRefresh()
    }

    // 6. (اختياري) إعادة جدولة local notifications عند فتح التطبيق
    // مثال: لو بتعتمد على إعادة-schedule بعد reboot أو تحديث، نعملها هنا
    // call rescheduleNotificationsIfNeeded()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - APNs callbacks (optional)
  override func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
    let token = tokenParts.joined()
    print("APNs device token: \(token)")
    // لو بتستخدم Firebase Messaging: Messaging.messaging().apnsToken = deviceToken
  }

  override func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("Failed to register APNs: \(error.localizedDescription)")
  }

  // MARK: - UNUserNotificationCenterDelegate
  // لما توصّل notification وإنت في foreground
  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    // اعرض banner وصوت وباج حتى لو التطبيق foreground
    completionHandler([.alert, .sound, .badge])
  }

  // لما المستخدم يضغط على notification
  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              didReceive response: UNNotificationResponse,
                              withCompletionHandler completionHandler: @escaping () -> Void) {
    let userInfo = response.notification.request.content.userInfo
    print("Notification tapped / responded: \(userInfo)")
    // هنا تقدر تبعت event لـ Flutter عن طريق MethodChannel لو محتاج
    completionHandler()
  }

  // MARK: - BGTask handlers (iOS 13+)
  @available(iOS 13.0, *)
  func handleAppRefresh(task: BGAppRefreshTask) {
    // جدولة المرة الجاية فوراً
    scheduleAppRefresh()

    // نفّذ مهمة قصيرة (مثال: fetch من سيرفر لتحديث تذكيرات)
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1

    let operation = BlockOperation {
      // حط هنا منطق الشبكة / تحديث التذكيرات / إعادة جدولة local notifications
      // مثال تجريبي:
      sleep(2)
      // لو عايز تنفذ كود Flutter من هنا — صعب مباشرة، عادة تعمل network وتخزن
    }

    task.expirationHandler = {
      queue.cancelAllOperations()
    }

    operation.completionBlock = {
      task.setTaskCompleted(success: !operation.isCancelled)
    }

    queue.addOperation(operation)
  }

  @available(iOS 13.0, *)
  func handleProcessingTask(task: BGProcessingTask) {
    // مهام معالجة طويلة (إذا حصلت على السماحية)
    task.expirationHandler = {
      // تنظيف لو انتهى الوقت
    }

    // نفّذ العمل هنا (مثال)
    // تذكّر: يجب أن يكون الوقت محدود
    task.setTaskCompleted(success: true)
  }

  @available(iOS 13.0, *)
  func scheduleAppRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: appRefreshTaskId)
    // earliest begin after 15 minutes (قيمة توضيحية — عدلها)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
    do {
      try BGTaskScheduler.shared.submit(request)
      print("BGAppRefreshTaskRequest submitted")
    } catch {
      print("Could not schedule app refresh: \(error.localizedDescription)")
    }
  }

  // MARK: - Example: schedule a local notification
  func scheduleLocalNotification(identifier: String = "khamsat_reminder", title: String = "تذكير", body: String = "وقت المهمة دلوقتي", hour: Int = 7, minute: Int = 0) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    content.userInfo = ["source": "local"]

    var dateComponents = DateComponents()
    dateComponents.hour = hour
    dateComponents.minute = minute

    // تكرار يومي عند الساعة المحددة
    let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

    UNUserNotificationCenter.current().add(request) { error in
      if let err = error {
        print("Error scheduling local notification: \(err.localizedDescription)")
      } else {
        print("Local notification scheduled: \(identifier)")
      }
    }
  }

  // MARK: - Helpers
  // دالة اتصال Flutter method channel لو احتجت تبعت حاجة للـ Dart عند استقبال إشعار
  // مثال (ما مفعلش افتراضياً — فعلها لو محتاج)
  /*
  func sendToFlutter(method: String, arguments: Any?) {
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "com.example.khamsat/notifications", binaryMessenger: controller.binaryMessenger)
      channel.invokeMethod(method, arguments: arguments)
    }
  }
  */
}
