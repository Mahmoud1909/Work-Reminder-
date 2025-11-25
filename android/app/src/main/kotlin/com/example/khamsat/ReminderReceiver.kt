package com.work.work

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import android.os.Build
import android.app.PendingIntent

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            Log.i("ReminderReceiver", "onReceive extras=${intent.extras}")

            val payload = intent.getStringExtra("payload") ?: ""
            val title = intent.getStringExtra("title") ?: "تذكير"
            val body = intent.getStringExtra("body") ?: "لديك تذكير الآن."

            val openIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("payload", payload)
            }

            val requestCode = if (payload.isNotEmpty()) (payload.hashCode() and 0x7fffffff) else (System.currentTimeMillis() % Int.MAX_VALUE).toInt()

            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            else
                PendingIntent.FLAG_UPDATE_CURRENT

            val pendingOpen = PendingIntent.getActivity(context, requestCode, openIntent, flags)

            val builder = NotificationCompat.Builder(context, "work_channel")
                .setSmallIcon(getAppIcon(context))
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .setContentIntent(pendingOpen)

            with(NotificationManagerCompat.from(context)) {
                notify(requestCode, builder.build())
                Log.i("ReminderReceiver", "notification posted id=$requestCode title=$title payload=$payload")
            }
        } catch (e: Exception) {
            Log.e("ReminderReceiver", "onReceive error: ${e.message}", e)
        }
    }

    private fun getAppIcon(context: Context): Int {
        val res = context.resources
        val packageName = context.packageName
        val id = res.getIdentifier("mipmap/ic_launcher", null, packageName)
        return if (id != 0) id else android.R.drawable.ic_dialog_info
    }
}
