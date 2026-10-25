package com.github.cyrilpeng.veneranext

import java.io.File
import java.nio.file.Files

private fun rejects(action: () -> Unit) {
    var rejected = false
    try { action() } catch (_: RuntimeException) { rejected = true }
    check(rejected) { "Unsafe APK was accepted" }
}

fun main() {
    val root = Files.createTempDirectory("update-policy-").toFile().canonicalFile
    try {
        val external = File(root, "sentinel.apk").apply { writeText("kept") }
        val directory = File(root, "updates").apply { mkdir() }
        val candidate = File(directory, "update.apk").apply { writeText("apk") }
        check(ApplicationUpdatePolicy.candidateFile(root, false) == candidate)
        rejects { ApplicationUpdatePolicy.candidateFile(root, true) }
        candidate.delete()
        Files.createSymbolicLink(candidate.toPath(), external.toPath())
        rejects { ApplicationUpdatePolicy.candidateFile(root, false) }
        candidate.delete()
        directory.delete()
        Files.createSymbolicLink(directory.toPath(), root.toPath())
        rejects { ApplicationUpdatePolicy.candidateFile(root, false) }
        directory.delete()
        check(external.readText() == "kept")
        println("PASS: fixed candidate path, missing partial, file symlink and directory symlink rejected")
    } finally { root.deleteRecursively() }
    val valid = listOf("AndroidManifest.xml", "lib/arm64-v8a/libflutter.so", "lib/arm64-v8a/libapp.so")
    ApplicationUpdatePolicy.validateLibraries(valid)
    rejects { ApplicationUpdatePolicy.validateLibraries(valid + "lib/x86/libapp.so") }
    rejects { ApplicationUpdatePolicy.validateLibraries(valid - "lib/arm64-v8a/libapp.so") }
    rejects { ApplicationUpdatePolicy.validateLibraries(valid + "lib/arm64-v8a/../libother.so") }
    rejects { ApplicationUpdatePolicy.validateLibraries(valid + "lib/arm64-v8a/libapp.so") }
    println("PASS: ARM64 release libraries, mixed ABI, missing app, traversal, duplicate library")
    for (result in listOf(-1, 0, 1, 42)) {
        check(ApplicationUpdatePolicy.resultStatus(true, false, result) == "installed")
        check(ApplicationUpdatePolicy.resultStatus(false, false, result) == "unknown")
    }
    check(ApplicationUpdatePolicy.resultStatus(false, true, -1) == "unknown")
    check(ApplicationUpdatePolicy.resultStatus(false, true, 0) == "cancelled")
    check(ApplicationUpdatePolicy.resultStatus(false, true, 1) == "failed")
    check(ApplicationUpdatePolicy.resultStatus(false, true, 42) == "unknown")
    println("PASS: actual installed identity overrides callbacks; uncorrelated results never release ownership")
    check(ApplicationUpdatePolicy.occupiesInstaller("unknown"))
    check(ApplicationUpdatePolicy.occupiesInstaller("corrupt"))
    check(!ApplicationUpdatePolicy.occupiesInstaller("installed"))
    check(!ApplicationUpdatePolicy.occupiesInstaller("cancelled"))
    check(!ApplicationUpdatePolicy.occupiesInstaller("failed"))
    println("PASS: only proven terminal results release ownership")
}
