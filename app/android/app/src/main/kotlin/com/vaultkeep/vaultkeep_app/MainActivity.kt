package com.vaultkeep.vaultkeep_app

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.vaultkeep/passkey_provider"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPlatformCapabilities" -> {
                    val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
                    val isDeviceSecure = keyguard?.isDeviceSecure ?: false
                    val sdkInt = Build.VERSION.SDK_INT
                    val credentialManagerSupported = sdkInt >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE
                    result.success(
                        mapOf(
                            "platform" to "android",
                            "sdkInt" to sdkInt,
                            "credentialManagerSupported" to credentialManagerSupported,
                            "conditionalGetSupported" to true,
                            "hybridTransportSupported" to true,
                            "providerServiceRegistered" to credentialManagerSupported,
                            "uvSupported" to isDeviceSecure
                        )
                    )
                }
                "openPasskeySettings" -> {
                    try {
                        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            Intent("android.settings.CREDENTIAL_PROVIDER").apply {
                                data = Uri.parse("package:$packageName")
                            }
                        } else {
                            Intent(Settings.ACTION_SETTINGS)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}

