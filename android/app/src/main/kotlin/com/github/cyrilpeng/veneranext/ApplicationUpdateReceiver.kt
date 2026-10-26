package com.github.cyrilpeng.veneranext

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageInstaller
import android.os.Build
import java.util.concurrent.ConcurrentHashMap

/** Receives session results even when no Activity or Flutter engine is alive. */
class ApplicationUpdateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        ApplicationUpdateSessions.receive(context, intent)
    }
}

/** Process-wide session state shared by the receiver and the current bridge; main thread only. */
internal object ApplicationUpdateSessions {
    const val PREFERENCES = "application_update_handoff"
    const val EXTRA_ATTEMPT = "com.github.cyrilpeng.veneranext.extra.UPDATE_ATTEMPT"

    interface Listener {
        fun onConfirmation()
        fun onFinished(attemptId: String, status: String, message: String?)
    }

    /** System confirmation for an open session; kept until a terminal result to allow reopening. */
    class Confirmation(val attempt: String, val session: Int, val intent: Intent) {
        var launched = false
    }

    /** Attempt whose APK is being streamed into an uncommitted session by this process. */
    var writingAttempt: String? = null
    var listener: Listener? = null
    var confirmation: Confirmation? = null
        private set

    /** Sessions committed by this process; added before commit() on the writer thread. */
    val processSessions: MutableSet<Int> = ConcurrentHashMap.newKeySet()

    fun receive(context: Context, intent: Intent) {
        val preferences = context.getSharedPreferences(PREFERENCES, 0)
        val attempt = intent.getStringExtra(EXTRA_ATTEMPT)
        val session = intent.getIntExtra(PackageInstaller.EXTRA_SESSION_ID, -1)
        // Only the recorded attempt's own session may change the persisted result.
        if (attempt == null || attempt != preferences.getString("attemptId", null) ||
            session < 0 || session != preferences.getInt("sessionId", -1)) return
        val status = ApplicationUpdatePolicy.sessionResult(
            intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        )
        if (status != null) {
            finish(preferences, attempt, status, intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE))
            return
        }
        val confirm = if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
        } else {
            @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_INTENT)
        }
        if (confirm == null) {
            abandon(context, session)
            finish(preferences, attempt, "failed", "Installer confirmation is unavailable")
            return
        }
        // Kept until an Activity is resumed; starting UI from the background is not allowed.
        confirmation = Confirmation(attempt, session, confirm)
        listener?.onConfirmation()
    }

    fun clearConfirmation(attempt: String) {
        if (confirmation?.attempt == attempt) confirmation = null
    }

    fun clearConfirmation(session: Int) {
        if (confirmation?.session == session) confirmation = null
    }

    fun abandon(context: Context, session: Int) {
        try { context.packageManager.packageInstaller.abandonSession(session) } catch (_: Exception) {}
    }

    fun finish(preferences: SharedPreferences, attempt: String, status: String, message: String?) {
        if (confirmation?.attempt == attempt) confirmation = null
        // The session has ended either way, so a failed write cannot keep it open.
        preferences.edit().putString("status", status).putString("message", message).commit()
        listener?.onFinished(attempt, status, message)
    }
}
