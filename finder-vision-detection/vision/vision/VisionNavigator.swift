//
//  VisionNavigator.swift
//  vision
//
//  Created by Sweety on 1/24/26.
//

import Foundation
import Combine
@preconcurrency import ARKit
import Vision
import CoreML
import AVFoundation
import UIKit

class VisionNavManager: NSObject, ObservableObject {
    let arSession = ARSession()
    private let synthesizer = AVSpeechSynthesizer()
    private let hapticLight = UIImpactFeedbackGenerator(style: .light)
    private let hapticMedium = UIImpactFeedbackGenerator(style: .medium)
    private let hapticSuccess = UINotificationFeedbackGenerator()
    private var bestVoice: AVSpeechSynthesisVoice?

    @Published var currentInstruction: String = ""
    @Published var isSearching: Bool = false
    @Published var lastDetections: [VNRecognizedObjectObservation] = []
    @Published var targetObject: String? = nil
    private var hasGreeted = false
    private var isSpeaking = false
    private var userIsSpeaking = false

    private var lastSafetyTime: Date = .distantPast
    private var lastNavTime: Date = .distantPast
    private var lastSpokenMessage: String = ""

    private var scanStartTime: Date? = nil
    private var hasNotifiedNotFound = false
    private var hasFoundObject = false
    private var lastDirectionZone: String = ""

    private var objectWasWithinReach = false
    private var objectGoneTime: Date? = nil      // When it disappeared from frame
    private var objectVeryCloseTime: Date? = nil  // When it's been < 0.5m (arm's reach)

    // YOLO
    private var detectionRequest: VNCoreMLRequest?
    private var isProcessingFrame = false
    private var frameSkipCount = 0

    // LiDAR depth for object distance
    private var currentDepthMap: CVPixelBuffer?

    private var arDelegate: ARSessionDelegateHandler?

    override init() {
        super.init()
        synthesizer.delegate = self
        bestVoice = Self.selectBestVoice()
        setupYOLO()

        hapticLight.prepare()
        hapticMedium.prepare()
        hapticSuccess.prepare()

        let delegate = ARSessionDelegateHandler(manager: self)
        self.arDelegate = delegate
        arSession.delegate = delegate

        let config = ARWorldTrackingConfiguration()
        // Only use LiDAR depth if supported
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics = .smoothedSceneDepth
        }
        arSession.run(config)
    }

    private static func selectBestVoice() -> AVSpeechSynthesisVoice? {
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        let englishVoices = allVoices.filter { $0.language.hasPrefix("en") }

        let preferred = ["com.apple.voice.premium.en-US.Zoe",
                         "com.apple.voice.premium.en-US.Ava",
                         "com.apple.voice.enhanced.en-US.Zoe",
                         "com.apple.voice.enhanced.en-US.Ava",
                         "com.apple.voice.enhanced.en-US.Samantha",
                         "com.apple.ttsbundle.siri_Nicky_en-US_compact",
                         "com.apple.ttsbundle.siri_Martha_en-US_compact"]

        for id in preferred {
            if let voice = AVSpeechSynthesisVoice(identifier: id) {
                return voice
            }
        }
        let ranked = englishVoices.sorted { v1, v2 in
            v1.quality.rawValue > v2.quality.rawValue
        }
        return ranked.first ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    func greetUser() {
        guard !hasGreeted else { return }
        hasGreeted = true
        currentInstruction = "What can I help you find?"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.speak("Hi! What can I help you find?")
        }
    }

    func setTarget(_ target: String?) {
        targetObject = target
        lastNavTime = .distantPast
        lastSpokenMessage = ""
        hasNotifiedNotFound = false
        hasFoundObject = false
        lastDirectionZone = ""
        objectWasWithinReach = false
        objectGoneTime = nil
        objectVeryCloseTime = nil
        scanStartTime = target != nil ? Date() : nil

        if let t = target {
            isSearching = true
            currentInstruction = "Looking for \(t)..."
            hapticLight.impactOccurred()
            speak("On it. Scan around slowly.")
        } else {
            isSearching = false
            currentInstruction = "What can I help you find?"
            speak("Okay, stopped.")
        }
    }

    func setUserSpeaking(_ speaking: Bool) {
        userIsSpeaking = speaking
    }
    
    private func setupYOLO() {
        guard let modelURL = Bundle.main.url(forResource: "yolov8n", withExtension: "mlmodelc") else {
            print("[VisionNav] YOLOv8n model not found.")
            return
        }

        do {
            let mlModel = try MLModel(contentsOf: modelURL)
            let visionModel = try VNCoreMLModel(for: mlModel)

            detectionRequest = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
                guard let self = self else { return }
                guard let results = request.results as? [VNRecognizedObjectObservation] else { return }

                DispatchQueue.main.async {
                    self.isProcessingFrame = false
                    let good = results.filter { $0.confidence > 0.50 }
                    self.lastDetections = good
                    if self.targetObject != nil {
                        self.processDetections(good)
                    }
                }
            }
            detectionRequest?.imageCropAndScaleOption = .scaleFill
            print("[VisionNav] YOLOv8n loaded.")
        } catch {
            print("[VisionNav] Model error: \(error)")
        }
    }

    func handleFrame(_ frame: ARFrame) {
        currentDepthMap = frame.smoothedSceneDepth?.depthMap
        checkSafety()

        frameSkipCount += 1
        guard frameSkipCount >= 8 else { return }
        frameSkipCount = 0

        if !isProcessingFrame, detectionRequest != nil {
            isProcessingFrame = true
            runDetection(on: frame.capturedImage)
        }
    }

    private func checkSafety() {
        guard let depthMap = currentDepthMap else { return }
        guard Date().timeIntervalSince(lastSafetyTime) > 6.0 else { return }
        guard !isSpeaking, !userIsSpeaking else { return }

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return }

        let row = height / 2
        var minDist: Float = Float.greatestFiniteMagnitude
        let scanStart = width / 4
        let scanEnd = (width * 3) / 4
        let rowPtr = baseAddress.advanced(by: row * bytesPerRow).assumingMemoryBound(to: Float32.self)

        for col in stride(from: scanStart, to: scanEnd, by: 4) {
            let d = rowPtr[col]
            if d > 0.05 && d < minDist {
                minDist = d
            }
        }

        if minDist > 0.05 && minDist < 0.30 {
            lastSafetyTime = Date()
            hapticMedium.impactOccurred()

            let obstacleName = identifyObstacle()
            if let name = obstacleName {
                speak("Careful. \(name.capitalized) ahead.")
            } else {
                speak("Careful. Obstacle ahead.")
            }
        }
    }

    private func identifyObstacle() -> String? {
        for obs in lastDetections {
            let box = obs.boundingBox
            
            if box.midX > 0.25 && box.midX < 0.75 &&
               box.midY > 0.2 && box.midY < 0.8 {
                if let label = obs.labels.first?.identifier.lowercased() {
                    return label
                }
            }
        }
        return nil
    }

//detection/labeling
    private func runDetection(on pixelBuffer: CVPixelBuffer) {
        guard let request = detectionRequest else {
            isProcessingFrame = false
            return
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async { self?.isProcessingFrame = false }
            }
        }
    }

    private func processDetections(_ observations: [VNRecognizedObjectObservation]) {
        guard let target = targetObject?.lowercased() else { return }

        let match = findBestMatch(for: target, in: observations)

        if match == nil {
            if objectGoneTime == nil {
                objectGoneTime = Date()
            }

            if objectWasWithinReach,
               let gone = objectGoneTime,
               Date().timeIntervalSince(gone) > 3.0 {
                objectWasWithinReach = false
                objectGoneTime = nil
                targetObject = nil
                isSearching = false
                hapticSuccess.notificationOccurred(.success)
                speak("Nice, got it!")
                DispatchQueue.main.async {
                    self.currentInstruction = "What can I help you find?"
                }
                return
            }

            guard !userIsSpeaking, !isSpeaking else { return }
            guard Date().timeIntervalSince(lastNavTime) > 6.0 else { return }

            if hasFoundObject && !hasNotifiedNotFound && !objectWasWithinReach {
                lastNavTime = Date()
                hasNotifiedNotFound = true
                speak("Lost it. Try panning back.")
                DispatchQueue.main.async {
                    self.currentInstruction = "Object out of view"
                }
            } else if !hasFoundObject, !hasNotifiedNotFound,
                      let start = scanStartTime,
                      Date().timeIntervalSince(start) > 8.0 {
                lastNavTime = Date()
                hasNotifiedNotFound = true
                speak("Haven't spotted it yet. Keep looking around.")
                DispatchQueue.main.async {
                    self.currentInstruction = "Not found yet — keep scanning"
                }
            }
            return
        }

        objectGoneTime = nil
        let found = match!
        let wasFirstFind = !hasFoundObject
        hasFoundObject = true
        hasNotifiedNotFound = false

        let box = found.boundingBox

        let distance = getDistance(box: box)
        if distance > 0 && distance < 1.0 {
            objectWasWithinReach = true
        }

        if distance > 0 && distance < 0.5 {
            if objectVeryCloseTime == nil {
                objectVeryCloseTime = Date()
            } else if let closeStart = objectVeryCloseTime,
                      Date().timeIntervalSince(closeStart) > 2.0 {
                // Been within arm's reach for 2 seconds — they got it
                objectVeryCloseTime = nil
                objectWasWithinReach = false
                targetObject = nil
                isSearching = false
                hapticSuccess.notificationOccurred(.success)
                speak("Nice, got it!")
                DispatchQueue.main.async {
                    self.currentInstruction = "What can I help you find?"
                }
                return
            }
        } else {
            objectVeryCloseTime = nil
        }

        guard !userIsSpeaking, !isSpeaking else { return }

        let direction = describeDirection(box: box)

        if !wasFirstFind {
            guard direction != lastDirectionZone else { return }
            guard Date().timeIntervalSince(lastNavTime) > 6.0 else { return }
        }
        lastDirectionZone = direction
        lastNavTime = Date()

        if wasFirstFind {
            hapticMedium.impactOccurred()
        } else {
            hapticLight.impactOccurred()
        }

        let distanceStr = getDistanceString(box: box)

        let msg: String
        if wasFirstFind {
            if distanceStr.isEmpty {
                msg = "Found it! \(direction.capitalized)."
            } else {
                msg = "Found it! \(direction.capitalized), \(distanceStr)."
            }
        } else {
            if distanceStr.isEmpty {
                msg = "Now \(direction)."
            } else {
                msg = "\(direction.capitalized), \(distanceStr)."
            }
        }

        speak(msg)
        DispatchQueue.main.async {
            self.currentInstruction = "\(direction.capitalized) — \(distanceStr.isEmpty ? "" : distanceStr)"
        }
    }

    private func findBestMatch(for target: String, in observations: [VNRecognizedObjectObservation]) -> VNRecognizedObjectObservation? {
        let primaryWord = getPrimaryWord(from: target)

        for obs in observations {
            let label = obs.labels.first?.identifier.lowercased() ?? ""
            if label == target || label == primaryWord {
                return obs
            }
            if label.contains(target) || target.contains(label) {
                return obs
            }
        }

        for obs in observations {
            let label = obs.labels.first?.identifier.lowercased() ?? ""
            let labelWords = label.components(separatedBy: " ")
            for lWord in labelWords {
                if lWord == primaryWord || (primaryWord.count >= 4 && lWord.contains(primaryWord)) {
                    return obs
                }
            }
        }

        let synonyms: [String: [String]] = [
            "phone": ["cell phone"],
            "laptop": ["computer", "notebook"],
            "couch": ["sofa"],
            "tv": ["television", "monitor"],
            "cup": ["mug"],
            "bag": ["backpack", "handbag", "suitcase"],
            "glasses": ["sunglasses"],
            "shoe": ["sneaker", "boot"],
            "remote": ["remote"],
            "bottle": ["bottle"],
        ]

        for obs in observations {
            let label = obs.labels.first?.identifier.lowercased() ?? ""
            for (key, values) in synonyms {
                if primaryWord == key && values.contains(where: { label.contains($0) }) {
                    return obs
                }
                if values.contains(primaryWord) && label.contains(key) {
                    return obs
                }
            }
        }

        return nil
    }

    private func getPrimaryWord(from target: String) -> String {
        let words = target.components(separatedBy: " ")
        let fillers: Set<String> = ["my", "the", "a", "an", "that", "this", "those"]
        let meaningful = words.filter { !fillers.contains($0) && $0.count >= 2 }
        return meaningful.max(by: { $0.count < $1.count }) ?? target
    }


    private func describeDirection(box: CGRect) -> String {
        let x = box.midX

        if x < 0.2 {
            return "far to your left"
        } else if x < 0.4 {
            return "to your left"
        } else if x < 0.6 {
            return "straight ahead"
        } else if x < 0.8 {
            return "to your right"
        } else {
            return "far to your right"
        }
    }

    private func getDistance(box: CGRect) -> Float {
        guard let depthMap = currentDepthMap else { return -1 }

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return -1 }

        let depthX = Int(box.midX * Double(width))
        let depthY = Int((1.0 - box.midY) * Double(height))

        let clampedX = max(0, min(width - 1, depthX))
        let clampedY = max(0, min(height - 1, depthY))

        let rowPtr = baseAddress.advanced(by: clampedY * bytesPerRow).assumingMemoryBound(to: Float32.self)
        return rowPtr[clampedX]
    }

    private func getDistanceString(box: CGRect) -> String {
        guard let depthMap = currentDepthMap else { return "" }

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return "" }

        let depthX = Int(box.midX * Double(width))
        let depthY = Int((1.0 - box.midY) * Double(height))

        let clampedX = max(0, min(width - 1, depthX))
        let clampedY = max(0, min(height - 1, depthY))

        let rowPtr = baseAddress.advanced(by: clampedY * bytesPerRow).assumingMemoryBound(to: Float32.self)
        let distance = rowPtr[clampedX]

        if distance < 0.1 || distance > 10.0 { return "" }

        let feet = Int(round(distance * 3.28))
        if feet <= 1 { return "right in front of you" }
        return "about \(feet) feet away"
    }

    private func speak(_ text: String) {
        guard !text.isEmpty else { return }
        guard !userIsSpeaking else { return }

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try? audioSession.setActive(true)

        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = bestVoice
        utterance.rate = 0.50
        utterance.pitchMultiplier = 1.05
        utterance.volume = 0.85
        utterance.preUtteranceDelay = 0.05
        utterance.postUtteranceDelay = 0.1
        isSpeaking = true
        synthesizer.speak(utterance)
    }
}

extension VisionNavManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
    }
}

class ARSessionDelegateHandler: NSObject, ARSessionDelegate {
    weak var manager: VisionNavManager?

    init(manager: VisionNavManager) {
        self.manager = manager
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        DispatchQueue.main.async {
            self.manager?.handleFrame(frame)
        }
    }
}
