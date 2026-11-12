import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tz.initializeTimeZones();

final timezoneInfo = await FlutterTimezone.getLocalTimezone();
tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const settings = InitializationSettings(
      android: androidSettings,
    );

    await _notifications.initialize(settings: settings);

    _initialized = true;
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    await initialize();

    const androidDetails = AndroidNotificationDetails(
      'find_my_tutor_notifications',
      'Find My Tutor Notifications',
      channelDescription: 'Tutoring applications, bookings and reminders',
      importance: Importance.high,
      priority: Priority.high,
    );

    const details = NotificationDetails(
      android: androidDetails,
    );

    await _notifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }
  Future<void> scheduleLessonReminder({
  required int id,
  required DateTime sessionDate,
}) async {
  await initialize();

  final reminderTime = sessionDate.subtract(
    const Duration(minutes: 15),
  );

  if (!reminderTime.isAfter(DateTime.now())) return;

  const androidDetails = AndroidNotificationDetails(
    'find_my_tutor_notifications',
    'Find My Tutor Notifications',
    channelDescription: 'Tutoring applications, bookings and reminders',
    importance: Importance.high,
    priority: Priority.high,
  );

  await _notifications.zonedSchedule(
    id: id,
    title: 'Upcoming Tutoring Session',
    body: 'Your tutoring session starts in 15 minutes. Get ready!',
    scheduledDate: tz.TZDateTime.from(reminderTime, tz.local),
    notificationDetails: const NotificationDetails(
      android: androidDetails,
    ),
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
  );
}
Future<void> cancelNotification(int id) async {
  await initialize();
  await _notifications.cancel(id: id);
}
Future<void> cancelAllNotifications() async {
  await initialize();
  await _notifications.cancelAll();
}
}