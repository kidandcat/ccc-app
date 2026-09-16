package dev.ccc.app

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache

class MainActivity : FlutterActivity() {
    companion object {
        private const val ENGINE_ID = "ccc"
    }

    // Cache the engine so the hub socket (and local notifications) survive the
    // activity going away. Do NOT run the Dart entrypoint here: FlutterActivity
    // registers plugins first, then starts Dart. Running Dart first made
    // flutter_local_notifications miss its registrar, so pushes never showed.
    override fun provideFlutterEngine(context: Context): FlutterEngine {
        val cache = FlutterEngineCache.getInstance()
        cache.get(ENGINE_ID)?.let { return it }
        val engine = FlutterEngine(context.applicationContext)
        cache.put(ENGINE_ID, engine)
        return engine
    }

    override fun shouldDestroyEngineWithHost(): Boolean = false
}
