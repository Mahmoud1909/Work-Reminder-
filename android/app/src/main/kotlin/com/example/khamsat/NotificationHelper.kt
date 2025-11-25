package com.work.work

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log
import java.util.Calendar

object NotificationHelper {
    fun rescheduleNotifications(context: Context) {
        try {
            Log.i("NotificationHelper", "rescheduleNotifications: scheduling fallback alarm in 1 minute")
            val calendar = Calendar.getInstance().apply { add(Calendar.MINUTE, 1) }

            val intent = Intent(context, ReminderReceiver::class.java).apply {
                putExtra("payload", "fallback|${calendar.timeInMillis}")
                putExtra("title", "تذكير (fallback)")
                putExtra("body", "هذا تذكير احتياطي بعد إعادة التشغيل.")
            }

            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val requestCode = (calendar.timeInMillis % Int.MAX_VALUE).toInt()

            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0

            val pending = PendingIntent.getBroadcast(context, requestCode, intent, flags)

            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, calendar.timeInMillis, pending)
            } else {
                alarmManager.setExact(AlarmManager.RTC_WAKEUP, calendar.timeInMillis, pending)
            }

            Log.i("NotificationHelper", "Fallback alarm scheduled at ${calendar.time}")
        } catch (e: Exception) {
            Log.e("NotificationHelper", "Error scheduling fallback alarm: ${e.message}", e)
        }
    }
}
