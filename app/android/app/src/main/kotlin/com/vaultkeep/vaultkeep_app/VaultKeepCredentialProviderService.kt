package com.vaultkeep.vaultkeep_app

import android.app.PendingIntent
import android.app.slice.Slice
import android.app.slice.SliceSpec
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.CancellationSignal
import android.os.OutcomeReceiver
import android.service.credentials.BeginCreateCredentialRequest
import android.service.credentials.BeginCreateCredentialResponse
import android.service.credentials.BeginGetCredentialRequest
import android.service.credentials.BeginGetCredentialResponse
import android.service.credentials.ClearCredentialStateRequest
import android.service.credentials.CreateEntry
import android.service.credentials.CredentialProviderService
import android.service.credentials.RemoteEntry
import androidx.annotation.RequiresApi

/**
 * Android 14+ (API 34+) native Credential Provider Service for VaultKeep Passkeys.
 *
 * Integrates with Android's system CredentialManager pipeline for:
 * - Local app and browser WebAuthn ceremonies (`internal` transport)
 * - Cross-Device Authentication (CTAP 2.2 QR/BLE `hybrid` transport)
 * - Conditional UI autofill and passkey upgrades
 *
 * Enforces `passkeys.dev` strict User Verification (`UV`): never signs or creates a passkey
 * without explicit user authentication in the unlocked VaultKeep session.
 */
@RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
class VaultKeepCredentialProviderService : CredentialProviderService() {

    override fun onBeginGetCredentialRequest(
        request: BeginGetCredentialRequest,
        cancellationSignal: CancellationSignal,
        callback: OutcomeReceiver<BeginGetCredentialResponse, android.credentials.GetCredentialException>
    ) {
        val hasPublicKeyOption = request.beginGetCredentialOptions.any { option ->
            option.type == "android.credentials.TYPE_PUBLIC_KEY_CREDENTIAL" ||
                option.type == "android.credentials.TYPE_PASSWORD_CREDENTIAL"
        }
        if (!hasPublicKeyOption) {
            callback.onResult(BeginGetCredentialResponse())
            return
        }

        val launchIntent = Intent(applicationContext, MainActivity::class.java).apply {
            action = "com.vaultkeep.action.GET_PASSKEY_CREDENTIAL"
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            applicationContext,
            1001,
            launchIntent,
            PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val slice = buildProviderSlice(
            title = "Unlock VaultKeep Passkeys",
            subtitle = "Authenticate with VaultKeep (ES256 / Strict UV)",
            pendingIntent = pendingIntent
        )
        val response = BeginGetCredentialResponse.Builder()
            .setRemoteCredentialEntry(RemoteEntry(slice))
            .build()
        callback.onResult(response)
    }

    override fun onBeginCreateCredentialRequest(
        request: BeginCreateCredentialRequest,
        cancellationSignal: CancellationSignal,
        callback: OutcomeReceiver<BeginCreateCredentialResponse, android.credentials.CreateCredentialException>
    ) {
        if (request.type != "android.credentials.TYPE_PUBLIC_KEY_CREDENTIAL" &&
            request.type != "android.credentials.TYPE_PASSWORD_CREDENTIAL"
        ) {
            callback.onResult(BeginCreateCredentialResponse())
            return
        }

        val launchIntent = Intent(applicationContext, MainActivity::class.java).apply {
            action = "com.vaultkeep.action.CREATE_PASSKEY_CREDENTIAL"
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            applicationContext,
            1002,
            launchIntent,
            PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val slice = buildProviderSlice(
            title = "VaultKeep KDBX4 Vault",
            subtitle = "Save synced passkey (ES256 P-256, BE=1, BS=1)",
            pendingIntent = pendingIntent
        )
        val response = BeginCreateCredentialResponse.Builder()
            .addCreateEntry(CreateEntry(slice))
            .build()
        callback.onResult(response)
    }

    override fun onClearCredentialStateRequest(
        request: ClearCredentialStateRequest,
        cancellationSignal: CancellationSignal,
        callback: OutcomeReceiver<Void?, android.credentials.ClearCredentialException>
    ) {
        callback.onResult(null)
    }

    private fun buildProviderSlice(
        title: String,
        subtitle: String,
        pendingIntent: PendingIntent
    ): Slice {
        val spec = SliceSpec("VaultKeepPasskeySpec", 1)
        val builder = Slice.Builder(Uri.parse("content://com.vaultkeep.vaultkeep_app/passkey"), spec)
        builder.addText(title, null, listOf("androidx.credentials.provider.credentialEntry.SLICE_HINT_TITLE"))
        builder.addText(subtitle, null, listOf("androidx.credentials.provider.credentialEntry.SLICE_HINT_SUBTITLE"))
        val actionSlice = Slice.Builder(builder).build()
        builder.addAction(
            pendingIntent,
            actionSlice,
            "androidx.credentials.provider.credentialEntry.SLICE_HINT_PENDING_INTENT"
        )
        return builder.build()
    }
}
