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

    fun resultStatus(installed: Boolean, correlated: Boolean, resultCode: Int): String = when {
        installed -> "installed"
        !correlated -> "unknown"
        resultCode == 0 -> "cancelled" // Activity.RESULT_CANCELED
        resultCode == 1 -> "failed" // Activity.RESULT_FIRST_USER, documented install failure
        else -> "unknown" // RESULT_OK is not package identity evidence.
    }

    fun occupiesInstaller(status: String) = status !in setOf("installed", "cancelled", "failed")
}
