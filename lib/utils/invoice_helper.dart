import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// 🔹 OCR
Future<String> extractTextFromImage(File imageFile) async {
  final inputImage = InputImage.fromFile(imageFile);
  final textRecognizer = TextRecognizer();

  final RecognizedText recognizedText = await textRecognizer.processImage(
    inputImage,
  );

  await textRecognizer.close();

  return recognizedText.text;
}

String detectOtherDocumentType(String text) {
  final Map<String, List<String>> rules = {
    "VGM": ["verified gross mass", "gross mass of container", "weighbridge"],
    "ContainerLoadPlan": [
      "container load plan",
      "cargo description",
      "stuffed weight",
    ],
    "RequestLetter": ["dear sir", "we request", "thanking you"],
    "Certificate": ["certificate", "certified", "authorization"],
    "Report": ["report", "analysis", "summary"],
  };

  String bestMatch = "Document";
  int highestScore = 0;

  rules.forEach((type, keywords) {
    int score = 0;

    for (var word in keywords) {
      if (text.contains(word)) score++;
    }

    if (score > highestScore) {
      highestScore = score;
      bestMatch = type;
    }
  });

  // minimum confidence
  if (highestScore >= 2) {
    return bestMatch;
  }

  return "Document";
}

// Detect document type
String detectDocumentType(String text) {
  text = text.toLowerCase();
  text = text.replaceAll(RegExp(r'\s+'), ' ');

  // 🔥 EXISTING LOGIC (Bills / invoices FIRST)

  if (text.contains("booking confirmation")) {
    return "BookingConfirmation";
  }

  if (text.contains("inspection report") ||
      text.contains("certification report") ||
      text.contains("lashing inspection")) {
    return "SurveyReport";
  }

  if (text.contains("tax invoice")) return "TaxBill";
  if (text.contains("proforma invoice")) return "ProformaBill";

  if (text.contains("shipping bill")) return "ShippingBill";
  if (text.contains("sea waybill")) return "SeaWayBill";
  if (text.contains("air waybill") || text.contains("awb")) return "AirWayBill";

  if (text.contains("invoice")) return "InvoiceBill";

  // 🔥 NEW PART → other documents detection
  return detectOtherDocumentType(text);
}

Future<String> generateUniqueFileName(Directory dir, String baseName) async {
  int count = 0;
  String fileName = baseName;

  while (true) {
    final filePath = "${dir.path}/$fileName.pdf";
    final file = File(filePath);

    if (!await file.exists()) {
      return fileName;
    }

    count++;
    fileName = "$baseName$count";
  }
}

/// 🔹 Extract number
String extractDocumentNumber(String text) {
  final patterns = [
    r'Invoice\s*(No|Number)?\s*[:\-]?\s*([A-Z0-9\/\-]+)',
    r'Tax\s*Invoice\s*(No|Number)?\s*[:\-]?\s*([A-Z0-9\/\-]+)',
    r'Proforma\s*(No|Number)?\s*[:\-]?\s*([A-Z0-9\/\-]+)',
    r'Shipping\s*Bill\s*No\s*[:\-]?\s*([A-Z0-9\-]+)',
    r'AWB\s*No\s*[:\-]?\s*([A-Z0-9\-]+)',
    r'Bill\s*No\s*[:\-]?\s*([A-Z0-9\-]+)',
  ];

  for (var pattern in patterns) {
    final regex = RegExp(pattern, caseSensitive: false);
    final match = regex.firstMatch(text);

    if (match != null) {
      String value = match.group(match.groupCount) ?? "";

      if (value.isNotEmpty &&
          value.length > 5 &&
          value.contains(RegExp(r'[0-9]'))) {
        return value.replaceAll(RegExp(r'[^\w\-]'), '_');
      }
    }
  }

  return "";
}

/// 🔹 Fallback (for unknown docs)
String fallbackNumber(String text) {
  final regex = RegExp(r'[A-Z0-9\/\-]{6,}');
  final match = regex.firstMatch(text);

  if (match != null) {
    return match.group(0)!.replaceAll(RegExp(r'[^\w\-]'), '_');
  }

  return "DOC_${DateTime.now().millisecondsSinceEpoch}";
}

/// 🔹 FINAL FUNCTION (IMPORTANT)
Future<String> generateSmartFileName(File imageFile) async {
  String text = await extractTextFromImage(imageFile);

  print("📄 OCR TEXT:\n$text");

  String type = detectDocumentType(text);
  String number = extractDocumentNumber(text);

  if (number.isEmpty) {
    number = fallbackNumber(text);
  }

  return "${type}_$number";
}
