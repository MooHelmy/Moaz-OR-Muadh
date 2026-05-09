package com.medi_guard

import android.os.FileObserver
import io.flutter.plugin.common.EventChannel
import java.io.File

class MultiFileObserver(
    private val paths: List<String>,
    private val eventSink: EventChannel.EventSink
) {
    private val observers = mutableListOf<FileObserver>()

    fun start() {
        paths.forEach { path ->
            val dir = File(path)
            if (!dir.exists()) return@forEach

            val observer = object : FileObserver(path, CREATE or CLOSE_WRITE) {
                override fun onEvent(event: Int, file: String?) {
                    if (file == null) return
                    val fullPath = "$path/$file"
                    if (isMediaFile(fullPath)) {
                        eventSink.success(fullPath)
                    }
                }
            }
            observer.startWatching()
            observers.add(observer)
        }
    }

    fun stop() {
        observers.forEach { it.stopWatching() }
        observers.clear()
    }

    private fun isMediaFile(path: String): Boolean {
        val ext = path.lowercase()
        return listOf(".jpg", ".jpeg", ".png", ".mp4",
                      ".mkv", ".avi", ".webp", ".3gp")
            .any { ext.endsWith(it) }
    }
}