# ML Kit text recognition ships optional script models (Chinese, Devanagari,
# Japanese, Korean) that we don't bundle. Their classes are referenced but
# absent, which R8 treats as errors unless told otherwise.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Flutter deferred components / Play Core (not used, referenced by the engine).
-dontwarn com.google.android.play.core.**

# RevenueCat models are serialized reflectively.
-keep class com.revenuecat.purchases.** { *; }
