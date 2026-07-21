import Flutter
import UIKit
import UserNotifications
import Vision
import PDFKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // flutter_local_notifications がフォアグラウンドで willPresentNotification を呼ばれるために必要。
    // FlutterAppDelegate は FlutterAppLifeCycleProvider 経由で UNUserNotificationCenterDelegate を
    // 実装しており、登録済みプラグインに通知イベントを転送する。
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }
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
  /// 返値: [[String: Any]] — 各要素に "text", "left", "top", "right", "bottom"（正規化座標 0-1、左上原点）
  private static func recognizeText(imagePath: String, result: @escaping FlutterResult) {
    guard let image = UIImage(contentsOfFile: imagePath),
          let cgImage = image.cgImage else {
      DispatchQueue.main.async { result([]) }
      return
    }

    let request = VNRecognizeTextRequest { req, error in
      if error != nil {
        DispatchQueue.main.async { result([]) }
        return
      }
      let observations = req.results as? [VNRecognizedTextObservation] ?? []
      // Vision の座標系は Y=0 が下端のため、降順ソートで上から下の読み順にする
      let sorted = observations.sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
      // バウンディングボックスを左上原点の正規化座標に変換して返す
      let blocks: [[String: Any]] = sorted.compactMap { obs in
        guard let text = obs.topCandidates(1).first?.string else { return nil }
        let box = obs.boundingBox  // Vision 座標: 左下原点、正規化 [0,1]
        return [
          "text":   text,
          "left":   box.minX,
          "top":    1.0 - box.maxY,  // Y 反転で左上原点に変換
          "right":  box.maxX,
          "bottom": 1.0 - box.minY,
        ]
      }
      DispatchQueue.main.async { result(blocks) }
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
        DispatchQueue.main.async { result([]) }
      }
    }
  }
}
