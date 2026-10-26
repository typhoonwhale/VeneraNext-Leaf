package com.github.cyrilpeng.veneranext

import java.io.File

/** Decisions shared by the bridge and its host-side regression tests. */
internal object ApplicationUpdatePolicy {
    fun candidateFile(cacheDirectory: File, partial: Boolean): File {
        val root = cacheDirectory.canonicalFile
        val directory = File(root, "updates")
        check(directory.canonicalFile == directory && directory.isDirectory) { "Unsafe or missing update directory" }
        val file = File(directory, if (partial) "update.apk.part" else "update.apk")
        check(file.canonicalFile == file && file.isFile) { "Unsafe or missing update APK" }
        return file
    }

    fun validateLibraries(entries: List<String>) {
        val libraries = entries.filter { it.startsWith("lib/") && !it.endsWith("/") }
        require(libraries.all {
            val segments = it.split('/')
            segments.size == 3 && segments[1] == "arm64-v8a" &&
                segments[2].endsWith(".so") && segments[2] != ".so"
        }) { "APK contains unsupported native libraries" }
        require(libraries.toSet().size == libraries.size) { "APK contains duplicate libraries" }
        require(libraries.containsAll(listOf("lib/arm64-v8a/libflutter.so", "lib/arm64-v8a/libapp.so"))) {
            "APK must contain ARM64 Flutter release libraries"
        }
    }

    /** Maps a PackageInstaller status; null means the session still awaits the user. */
    fun sessionResult(status: Int): String? = when (status) {
        -1 -> null // PackageInstaller.STATUS_PENDING_USER_ACTION
        0 -> "installed" // STATUS_SUCCESS
        3 -> "cancelled" // STATUS_FAILURE_ABORTED: declined or abandoned
        else -> "failed" // FAILURE, BLOCKED, INVALID, CONFLICT, STORAGE, INCOMPATIBLE, TIMEOUT
    }

    /**
     * Uncommitted sessions are leftovers of an interrupted write. A committed session this
     * process did not create has lost its confirmation intent with the old process, so it can
     * never be confirmed: report the target if it is already installed, otherwise abandon it.
     */
    fun leftoverSession(committed: Boolean, writing: Boolean, ownedByProcess: Boolean,
                        targetInstalled: Boolean): String = when {
        writing -> "keep"
        !committed -> "abandon"
        ownedByProcess -> "pending"
        targetInstalled -> "installed"
        else -> "orphaned"
    }

    /**
     * A session is this process's if it committed the session, or if the receiver stored its
     * confirmation: after the committing process was killed, the receiver starts a new process
     * whose confirmation can still be launched, so that session is not orphaned.
     */
    fun ownsSession(session: Int, committedByProcess: Boolean, confirmationSession: Int?) =
        committedByProcess || confirmationSession == session

    /** A session ended during reconciliation must not leave its confirmation to be launched. */
    fun dropsConfirmation(decision: String, session: Int, confirmationSession: Int?) =
        confirmationSession == session && decision != "keep" && decision != "pending"

    /** Result recorded for the attempt after handling an orphaned committed session. */
    fun orphanedResult(abandoned: Boolean): String = if (abandoned) "cancelled" else "pending"

    /**
     * A committed session no longer reads the local APK, so only an active write or a live
     * committed session keeps the attempt open. A vanished session without a recorded
     * callback has ended without installing the target.
     */
    fun attemptStatus(installed: Boolean, recorded: String?, writing: Boolean,
                      sessionCommitted: Boolean?): String = when {
        installed -> "installed"
        recorded == "installed" || recorded == "cancelled" || recorded == "failed" -> recorded
        writing || sessionCommitted == true -> "pending"
        else -> "failed"
    }

    /**
     * The confirmation is started once when an Activity is resumed. A later resume with the
     * session still open means the user left the system UI; Dart then offers reopen or cancel.
     */
    fun confirmationAction(waiting: Boolean, launched: Boolean, resumed: Boolean): String = when {
        !waiting || !resumed -> "none"
        launched -> "await"
        else -> "launch"
    }

    fun occupiesInstaller(status: String) = status == "pending"
}
