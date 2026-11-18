import 'dart:typed_data';

/// Reads text from a photo. The real engine runs on the phone (no photo leaves the device).
abstract interface class OcrEngine {
  /// Text found in [image]. [languages] are Tesseract language codes such as `eng`, `ben`.
  Future<String> recognize(Uint8List image, {List<String> languages = const ['eng', 'ben']});
}

/// OCR could not run (missing language data or engine error).
class OcrUnavailableException implements Exception {
  /// Creates the exception.
  const OcrUnavailableException([this.detail]);

  /// Short detail for the log (never shown to people).
  final String? detail;

  @override
  String toString() => 'OcrUnavailableException($detail)';
}
