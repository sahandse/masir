# Keep MapLibre / location / Flutter engines intact in release.
-keep class com.mapbox.** { *; }
-keep class org.maplibre.** { *; }
-keep class com.maplibre.** { *; }
-dontwarn com.mapbox.**
-dontwarn org.maplibre.**

-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

-keep class com.baseflow.geolocator.** { *; }
-dontwarn com.baseflow.geolocator.**

# Flutter Play Store deferred components (optional; not bundled in this APK).
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task
