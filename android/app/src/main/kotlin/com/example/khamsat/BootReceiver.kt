package com.work.work

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action
        Log.i("BootReceiver", "onReceive: action=$action")
        if (action == Intent.ACTION_BOOT_COMPLETED || action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            Log.i("BootReceiver", "Starting headless FlutterEngine to re-schedule notifications")
            try {
                val flutterLoader = FlutterInjector.instance().flutterLoader()
                flutterLoader.startInitialization(context)
                flutterLoader.ensureInitializationComplete(context, null)

                val engine = FlutterEngine(context)
                val appBundlePath = flutterLoader.findAppBundlePath()
                val entrypoint = DartExecutor.DartEntrypoint(appBundlePath, "notificationsBootEntrypoint")
                engine.dartExecutor.executeDartEntrypoint(entrypoint)

                // let it run short time then destroy
                Thread {
                    try { Thread.sleep(5000) } catch (_: InterruptedException) {}
                    try { engine.destroy() } catch (e: Exception) { Log.e("BootReceiver", "destroy engine error", e) }
                }.start()
            } catch (e: Exception) {
                Log.e("BootReceiver", "Error launching headless engine: ${e.message}", e)
            }
        }
    }
}
