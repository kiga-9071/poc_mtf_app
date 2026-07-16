import Flutter
import UIKit
import Vision
import PDFKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "VisionOcrPlugin") else {
      return
    }

    // Vision OCR チャンネル
    let ocrChannel = FlutterMethodChannel(
      name: "app.tts.ocr",
      binaryMessenger: registrar.messenger()
    )
    ocrChannel.setMethodCallHandler { call, result in
      guard call.method == "recognizeText" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
            let imagePath = args["imagePath"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "imagePath is required", details: nil))
        return
      }
      AppDelegate.recognizeText(imagePath: imagePath, result: result)
    }

    // PDFKit サムネイルチャンネル（pdfrx より高速なサムネイル専用 API）
    guard let thumbRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "PdfThumbnailPlugin") else {
      return
    }
    let thumbChannel = FlutterMethodChannel(
      name: "app.pdf.thumbnail",
      binaryMessenger: thumbRegistrar.messenger()
    )
    thumbChannel.setMethodCallHandler { call, result in
      guard call.method == "getThumbnail" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
            let filePath = args["path"] as? String,
            let pageIndex = args["pageIndex"] as? Int,
            let width = args["width"] as? Double else {
        result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
        return
      }
      AppDelegate.getThumbnail(filePath: filePath, pageIndex: pageIndex, width: CGFloat(width), result: result)
    }

    // PDFKit テキスト抽出チャンネル
    let pdfChannel = FlutterMethodChannel(
      name: "app.tts.pdf",
      binaryMessenger: registrar.messenger()
    )
    pdfChannel.setMethodCallHandler { call, result in
      guard call.method == "extractText" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
            let filePath = args["filePath"] as? String,
            let pageIndex = args["pageIndex"] as? Int else {
        result(FlutterError(code: "INVALID_ARGS", message: "filePath and pageIndex are required", details: nil))
        return
      }
      AppDelegate.extractTextWithPDFKit(filePath: filePath, pageIndex: pageIndex, result: result)
    }
  }

  /// PDFKit の thumbnail API でページサムネイルを JPEG として返す。
  /// pdfrx の draw() よりも高速なサムネイル専用コードパスを使用する。
  /// 多くのプロ向け PDF（雑誌等）は内蔵サムネイルを持つためほぼ即時に返る。
  private static func getThumbnail(
    filePath: String, pageIndex: Int, width: CGFloat, result: @escaping FlutterResult
  ) {
    DispatchQueue.global(qos: .userInteractive).async {
      let url = URL(fileURLWithPath: filePath)
      guard let doc = PDFDocument(url: url),
            pageIndex >= 0 && pageIndex < doc.pageCount,
            let page = doc.page(at: pageIndex) else {
        DispatchQueue.main.async { result(nil) }
        return
      }
      let mediaBox = page.bounds(for: .mediaBox)
      guard mediaBox.width > 0 else {
        DispatchQueue.main.async { result(nil) }
        return
      }
      let height = width * mediaBox.height / mediaBox.width
      let size = CGSize(width: width, height: height)
      // PDFPage.thumbnail() は draw() より高速なサムネイル専用パス
      let thumbnail = page.thumbnail(of: size, for: .mediaBox)
      guard let data = thumbnail.jpegData(compressionQuality: 0.75) else {
        DispatchQueue.main.async { result(nil) }
        return
      }
      DispatchQueue.main.async {
        result(FlutterStandardTypedData(bytes: data))
      }
    }
  }

  /// PDFKit でPDFページのテキストを抽出する。
  /// pdfrx がToUnicode未対応フォントで失敗する場合のフォールバックに使用する。
  private static func extractTextWithPDFKit(filePath: String, pageIndex: Int, result: @escaping FlutterResult) {
    let url = URL(fileURLWithPath: filePath)
    guard let doc = PDFDocument(url: url),
          pageIndex >= 0 && pageIndex < doc.pageCount,
          let page = doc.page(at: pageIndex) else {
      result("")
      return
    }
    let text = page.string ?? ""
    result(text)
  }

  /// Vision Framework で画像からテキストを認識する。
  /// ML Kit iOS より日本語認識精度が高いため OCR フォールバックに使用する。
  private static func recognizeText(imagePath: String, result: @escaping FlutterResult) {
    guard let image = UIImage(contentsOfFile: imagePath),
          let cgImage = image.cgImage else {
      result("")
      return
    }

    let request = VNRecognizeTextRequest { req, error in
      if error != nil {
        result("")
        return
      }
      let observations = req.results as? [VNRecognizedTextObservation] ?? []
      // Vision の座標系は Y=0 が下端のため、降順ソートで上から下の読み順にする
      let sorted = observations.sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
      let text = sorted
        .compactMap { $0.topCandidates(1).first?.string }
        .joined(separator: "\n")
      result(text)
    }
    request.recognitionLanguages = ["ja-JP", "en-US"]
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    // 小さな文字も認識するため制限なし（診断用）
    request.minimumTextHeight = 0.0

    DispatchQueue.global(qos: .userInitiated).async {
      let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
      do {
        try handler.perform([request])
      } catch {
        result("")
      }
    }
  }
}
