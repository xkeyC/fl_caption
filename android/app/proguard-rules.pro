# shared_preferences_android is called from Dart through JNI by class,
# method name and signature: R8 must keep its classes and the Kotlin
# coroutine types they use (release builds otherwise fail with
# NoSuchMethodError / ClassNotFoundException).
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class kotlin.coroutines.** { *; }
-keep class kotlinx.coroutines.** { *; }
