# ML Kit text recognition — Latin-only OCR.
# google_mlkit_text_recognition references optional Chinese/Japanese/Korean/
# Devanagari recognizer classes that are NOT on the classpath: Vamo uses
# TextRecognitionScript.latin only and deliberately does not bundle the extra
# language models (keeps the binary lean; receipts are Latin-script IT/EN/DE/ES).
# These -dontwarn rules tell R8 the absent optional classes are intentional.
# Source: build/app/outputs/mapping/release/missing_rules.txt (AGP-generated).
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
