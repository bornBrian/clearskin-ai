# ML Kit text recognition ships optional script models (Chinese, Devanagari,
# Japanese, Korean) that we don't bundle. Their classes are referenced but
# absent, which R8 treats as errors unless told otherwise.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Flutter deferred components / Play Core (not used, referenced by the engine).
-dontwarn com.google.android.play.core.**

# Room builds its databases by reflection (<Name>_Impl). Without this, R8
# strips WorkManager's WorkDatabase_Impl (pulled in by the ads SDK) and the
# release build crashes on launch.
-keep class * extends androidx.room.RoomDatabase { <init>(); }

# RevenueCat models are serialized reflectively.
-keep class com.revenuecat.purchases.** { *; }
