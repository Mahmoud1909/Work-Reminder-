package com.work.work

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

class CheckScheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        Log.i("CheckScheduleReceiver", "onReceive called -> starting headless engine to run checkScheduleEntrypoint")
        try {
            val flutterLoader = FlutterInjector.instance().flutterLoader()
            flutterLoader.startInitialization(context)
            flutterLoader.ensureInitializationComplete(context, null)

            val engine = FlutterEngine(context)
            val appBundlePath = flutterLoader.findAppBundlePath()
            val entrypoint = DartExecutor.DartEntrypoint(appBundlePath, "checkScheduleEntrypoint")
            engine.dartExecutor.executeDartEntrypoint(entrypoint)

            // allow a short grace period for Dart code to run, then destroy engine
            Thread {
                try { Thread.sleep(7000) } catch (_: InterruptedException) {}
                try { engine.destroy() } catch (e: Exception) { Log.e("CheckScheduleReceiver","destroy engine error", e) }
            }.start()
        } catch (e: Exception) {
            Log.e("CheckScheduleReceiver", "Error launching headless engine: ${e.message}", e)
        }
    }
}
