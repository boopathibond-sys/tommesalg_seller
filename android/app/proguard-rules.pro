# Release builds run R8 with `proguard-android-optimize.txt` — the Flutter
# Gradle plugin turns that on for us (`isMinifyEnabled = true`) and ships only a
# couple of `-dontwarn` rules of its own. Nothing there protects the Android
# embedding itself, and R8's optimizer rewrites `DartExecutor` badly enough that
# its `binaryMessenger` field is still null by the time `FlutterEngine`'s
# constructor builds the system channels:
#
#   java.lang.NullPointerException: Attempt to invoke virtual method
#     'void ...DefaultBinaryMessenger.setMessageHandler(String, ...)'
#     on a null object reference
#       at io.flutter.embedding.engine.dart.DartExecutor.setMessageHandler
#       at io.flutter.plugin.common.MethodChannel.setMethodCallHandler
#       at io.flutter.embedding.engine.systemchannels.NavigationChannel.<init>
#       at io.flutter.embedding.engine.FlutterEngine.<init>
#
# That kills FlutterActivity.onCreate, so the release APK dies on the splash
# screen every launch. Keeping the embedding out of R8's hands fixes it, and
# costs a rounding error of APK size next to the bundled Agora native libs.
-keep class io.flutter.** { *; }
-keep interface io.flutter.** { *; }

# Keeping all of io.flutter also keeps the deferred-component / Play Store split
# classes, which reference Play Core. We don't depend on Play Core and don't use
# deferred components, so let R8 leave those references dangling instead of
# failing the build — the code paths are unreachable at runtime.
-dontwarn com.google.android.play.core.**

# Plugins are resolved reflectively by GeneratedPluginRegistrant, and their
# method-channel handlers are only ever reached from Dart — R8 sees no callers
# and is free to strip or rewrite them.
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }

# Agora RTC/RTM call back into Java from native code, so the JNI entry points
# have no visible caller either.
-keep class io.agora.** { *; }
-dontwarn io.agora.**

# uCrop is launched by image_cropper through an explicit Intent.
-keep class com.yalantis.ucrop.** { *; }
-dontwarn com.yalantis.ucrop.**
