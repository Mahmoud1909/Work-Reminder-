package com.work.work

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar

class MainActivity : FlutterActivity() {
    private val CHANNEL = "khamsat/native_notifications"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scheduleFallbackAlarm" -> {
                        val id = call.argument<Int>("id") ?: 0
                        val title = call.argument<String>("title") ?: "تذكير"
                        val body = call.argument<String>("body") ?: "موعد إشعار"
                        val delaySeconds = call.argument<Int>("delaySeconds") ?: 30
                        scheduleFallbackAlarm(id, title, body, delaySeconds)
                        result.success(null)
                    }
                    "requestScheduleExactAlarm" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                            if (!alarmManager.canScheduleExactAlarms()) {
                                val i = Intent(android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                                i.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                                startActivity(i)
                            }
                        }
                        result.success(null)
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val i = Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                            i.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            startActivity(i)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // register daily check alarm to ensure notifications keep getting scheduled (every day at 03:00)
        scheduleDailyCheck()
    }

    private fun scheduleFallbackAlarm(id: Int, title: String, body: String, delaySeconds: Int) {
        val intent = Intent(this, AlarmReceiver::class.java).apply {
            putExtra("id", id)
            putExtra("title", title)
            putExtra("body", body)
        }

        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)

        val pendingIntent = PendingIntent.getBroadcast(this, id, intent, flags)
        val triggerAt = System.currentTimeMillis() + delaySeconds * 1000L
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
        } else {
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
        }
    }

    /**
     * Schedule a daily inexact repeating alarm that triggers CheckScheduleReceiver.
     * This will run roughly once per day at the specified hour (03:00).
     * The receiver should check shared prefs for the last scheduled time and
     * call NotificationScheduler.scheduleNextNDays(context, 60) if needed.
     */
    private fun scheduleDailyCheck() {
        try {
            val calendar = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, 3) // 03:00
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }

            // if the time for today already passed, start tomorrow
            if (calendar.timeInMillis <= System.currentTimeMillis()) {
                calendar.add(Calendar.DAY_OF_MONTH, 1)
            }

            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(this, CheckScheduleReceiver::class.java)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                    (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)

            val pending = PendingIntent.getBroadcast(this, 1234, intent, flags)

            // Use setInexactRepeating to be battery friendly; it fires around the requested time daily.
            alarmManager.setInexactRepeating(
                AlarmManager.RTC_WAKEUP,
                calendar.timeInMillis,
                AlarmManager.INTERVAL_DAY,
                pending
            )
        } catch (e: Exception) {
            // Log or handle as needed
            e.printStackTrace()
        }
    }
}
