import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:path/path.dart' as pth;
import 'package:path_provider/path_provider.dart';
import 'package:rent_solution/features/ocr/domain/ocr_engine.dart';

/// Tesseract (Apache-2.0) running on the phone. It needs `eng.traineddata` and `ben.traineddata`
/// in `assets/tessdata/` (run `tools/fetch_tessdata.sh`). Bengali accuracy on real cards is NOT
/// verified yet: that is why every result goes through a human review screen.
class TesseractOcrEngine implements OcrEngine {
  /// Creates the engine.
  const TesseractOcrEngine();

  @override
  Future<String> recognize(Uint8List image, {List<String> languages = const ['eng', 'ben']}) async {
    final dir = await getTemporaryDirectory();
    final file = File(pth.join(dir.path, 'ocr_input_${DateTime.now().microsecondsSinceEpoch}.jpg'));
    await file.writeAsBytes(image, flush: true);
    try {
      final text = await FlutterTesseractOcr.extractText(
        file.path,
        language: languages.join('+'),
        args: {'psm': '4', 'preserve_interword_spaces': '1'},
      );
      return text;
    } on Object catch (e) {
      throw OcrUnavailableException('$e');
    } finally {
      if (file.existsSync()) {
        await file.delete();
      }
    }
  }
}

/// The engine used by the app (replaced in tests).
final ocrEngineProvider = Provider<OcrEngine>((ref) => const TesseractOcrEngine());
