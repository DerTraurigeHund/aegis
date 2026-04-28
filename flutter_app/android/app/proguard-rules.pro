# Flutter Engine
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Pointycastle / Bouncy Castle for E2E crypto
-keep class org.bouncycastle.** { *; }

# JSON / Serialization
-keepattributes *Annotation*
-keep class * extends java.util.Map { *; }
-keep class * extends java.util.List { *; }
