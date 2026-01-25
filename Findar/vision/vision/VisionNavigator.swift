//
//  VisionNavigator.swift
//  vision
//
//  Created by Sweety on 1/24/26.
//

import UIKit
import ARKit
import Vision
import CoreML
import RealityKit
import Combine

// the COCO class names for YOLOv8
private let cocoClasses = [
    "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat",
    "traffic light", "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat",
    "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "backpack",
    "umbrella", "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard", "sports ball",
    "kite", "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket",
    "bottle", "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple",
    "sandwich", "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair",
    "couch", "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse",
    "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "sink",
    "refrigerator", "book", "clock", "vase", "scissors", "teddy bear", "hair drier", "toothbrush"
]

struct Detection {
    let label: String
    let confidence: Float
    let boundingBox: CGRect
}

@MainActor
class VisionNavManager: NSObject, ObservableObject {
    let arSession = ARSession()
    var arView: ARView?

    //object label for the spatial memory
    @Published var spatialIndex: [String: (transform: simd_float4x4, timestamp: Date)] = [:]
    @Published var currentStatus: String = "Initializing..."
    @Published var isOnTarget: Bool = false
    @Published var lastDetectedObject: String? = nil

    // the actual search
    @Published var searchTarget: String? = nil
    @Published var searchResult: simd_float4x4? = nil
    @Published var searchResultTime: Date? = nil
    @Published var directionHint: String? = nil


    @Published var debugInfo: String = ""

    private var mlModel: VNCoreMLModel?
    private var isProcessing = false
    private let hapticSuccess = UINotificationFeedbackGenerator()
    private var navigationAnchor: AnchorEntity?
    private var frameCount = 0

    override init() {
        super.init()
        setupModel()
        arSession.delegate = self
        runSession()
    }

    private func runSession() {
        let configuration = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics = .smoothedSceneDepth
        }
        configuration.planeDetection = [.horizontal, .vertical]
        arSession.run(configuration)
        currentStatus = "Scanning..."
    }

    private func setupModel() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            let model = try yolov8n(configuration: config)
            mlModel = try VNCoreMLModel(for: model.model)
            currentStatus = "Model loaded"
            debugInfo = "YOLO model ready"
        } catch {
            currentStatus = "Model failed"
            debugInfo = "Model error: \(error.localizedDescription)"
            print("Failed to load YOLO model: \(error)")
        }
    }

    private func runDetection(on pixelBuffer: CVPixelBuffer) {
        guard let model = mlModel else {
            debugInfo = "No model"
            return
        }

        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.debugInfo = "Vision error: \(error.localizedDescription)"
                }
                return
            }
            self?.processModelOutput(request: request)
        }
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        do {
            try handler.perform([request])
        } catch {
            DispatchQueue.main.async {
                self.debugInfo = "Handler error: \(error.localizedDescription)"
            }
        }
    }

    private func processModelOutput(request: VNRequest) {
        guard let results = request.results else {
            DispatchQueue.main.async {
                self.debugInfo = "No results"
            }
            return
        }

        if let observations = results as? [VNRecognizedObjectObservation], !observations.isEmpty {
            DispatchQueue.main.async {
                self.debugInfo = "Found \(observations.count) objects (VN)"
                for obs in observations where obs.confidence > 0.5 {
                    let label = obs.labels.first?.identifier ?? "unknown"
                    let box = obs.boundingBox
                    // Vision coordinates: origin bottom-left
                    let screenPoint = CGPoint(x: box.midX, y: 1.0 - box.midY)
                    self.logObjectInSpace(label: label, normalizedPoint: screenPoint, confidence: obs.confidence)
                }
            }
            return
        }

        var confidenceArray: MLMultiArray?
        var coordinatesArray: MLMultiArray?

        for result in results {
            if let featureValue = result as? VNCoreMLFeatureValueObservation {
                if featureValue.featureName == "confidence" || featureValue.featureName.contains("confidence") {
                    confidenceArray = featureValue.featureValue.multiArrayValue
                } else if featureValue.featureName == "coordinates" || featureValue.featureName.contains("coordinates") {
                    coordinatesArray = featureValue.featureValue.multiArrayValue
                }
            }
        }

        guard let confidence = confidenceArray, let coordinates = coordinatesArray else {
            DispatchQueue.main.async {
                let resultTypes = results.map { String(describing: type(of: $0)) }
                self.debugInfo = "Output types: \(resultTypes.joined(separator: ", "))"
            }
            return
        }

        let detections = parseYOLOOutput(confidence: confidence, coordinates: coordinates)

        DispatchQueue.main.async {
            if detections.isEmpty {
                self.debugInfo = "No detections above threshold"
            } else {
                self.debugInfo = "Detected: \(detections.map { $0.label }.joined(separator: ", "))"
                for detection in detections {
                    self.logObjectInSpace(
                        label: detection.label,
                        normalizedPoint: CGPoint(x: detection.boundingBox.midX, y: detection.boundingBox.midY),
                        confidence: detection.confidence
                    )
                }
            }
        }
    }

    private func parseYOLOOutput(confidence: MLMultiArray, coordinates: MLMultiArray) -> [Detection] {
        var detections: [Detection] = []


        let confShape = confidence.shape.map { $0.intValue }
        _ = coordinates.shape.map { $0.intValue }  // For debugging if needed

        let numBoxes: Int
        let numClasses: Int

        if confShape.count == 3 {
            numBoxes = confShape[1]
            numClasses = confShape[2]
        } else if confShape.count == 2 {
            numBoxes = confShape[0]
            numClasses = confShape[1]
        } else {
            return detections
        }

        let confPointer = confidence.dataPointer.assumingMemoryBound(to: Float.self)
        let coordPointer = coordinates.dataPointer.assumingMemoryBound(to: Float.self)

        for i in 0..<min(numBoxes, 100) {
            var bestClassIdx = 0
            var bestConf: Float = 0

            for c in 0..<numClasses {
                let idx = i * numClasses + c
                let conf = confPointer[idx]
                if conf > bestConf {
                    bestConf = conf
                    bestClassIdx = c
                }
            }

            if bestConf > 0.4 {
                let coordIdx = i * 4
                let x = CGFloat(coordPointer[coordIdx])
                let y = CGFloat(coordPointer[coordIdx + 1])
                let w = CGFloat(coordPointer[coordIdx + 2])
                let h = CGFloat(coordPointer[coordIdx + 3])

                let label = bestClassIdx < cocoClasses.count ? cocoClasses[bestClassIdx] : "object"
                let box = CGRect(x: x - w/2, y: y - h/2, width: w, height: h)

                detections.append(Detection(label: label, confidence: bestConf, boundingBox: box))
            }
        }

        detections.sort { $0.confidence > $1.confidence }
        return Array(detections.prefix(10))
    }

    private func logObjectInSpace(label: String, normalizedPoint: CGPoint, confidence: Float) {
        guard let arView = arView else { return }

        let viewSize = arView.bounds.size
        guard viewSize.width > 0, viewSize.height > 0 else { return }

        let screenPoint = CGPoint(x: normalizedPoint.x * viewSize.width,
                                  y: normalizedPoint.y * viewSize.height)

        let raycastResults = arView.raycast(from: screenPoint, allowing: .estimatedPlane, alignment: .any)
        guard let result = raycastResults.first else {
            let fallbackResults = arView.raycast(from: screenPoint, allowing: .existingPlaneGeometry, alignment: .any)
            guard let fallbackResult = fallbackResults.first else { return }
            spatialIndex[label] = (transform: fallbackResult.worldTransform, timestamp: Date())
            lastDetectedObject = label
            return
        }

        spatialIndex[label] = (transform: result.worldTransform, timestamp: Date())
        lastDetectedObject = label

        if normalizedPoint.x > 0.35 && normalizedPoint.x < 0.65 &&
           normalizedPoint.y > 0.35 && normalizedPoint.y < 0.65 {
            isOnTarget = true
            hapticSuccess.notificationOccurred(.success)
        } else {
            isOnTarget = false
        }
    }


//search and find feature
    func searchForObject(named query: String) {
        let normalized = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        searchTarget = normalized

        if let entry = spatialIndex.first(where: { $0.key.lowercased().contains(normalized) }) {
            searchResult = entry.value.transform
            searchResultTime = entry.value.timestamp
            showNavigationArrow(to: entry.value.transform)
            updateDirectionHint(to: entry.value.transform, objectName: entry.key)
        } else {
            searchResult = nil
            searchResultTime = nil
            directionHint = "Not seen yet. Keep scanning."
        }
    }

    func clearSearch() {
        searchTarget = nil
        searchResult = nil
        searchResultTime = nil
        directionHint = nil
        removeNavigationArrow()
    }

    private func showNavigationArrow(to transform: simd_float4x4) {
        guard let arView = arView else { return }

        removeNavigationArrow()

        let anchor = AnchorEntity(world: transform)

        let mesh = MeshResource.generateSphere(radius: 0.08)
        var material = SimpleMaterial()
        material.color = .init(tint: .green.withAlphaComponent(0.9))
        material.metallic = 0.0
        material.roughness = 1.0
        let sphere = ModelEntity(mesh: mesh, materials: [material])

        let ringMesh = MeshResource.generateBox(width: 0.25, height: 0.01, depth: 0.25, cornerRadius: 0.12)
        var ringMaterial = SimpleMaterial()
        ringMaterial.color = .init(tint: .green.withAlphaComponent(0.5))
        let ring = ModelEntity(mesh: ringMesh, materials: [ringMaterial])
        ring.position.y = -0.05

        anchor.addChild(sphere)
        anchor.addChild(ring)
        arView.scene.addAnchor(anchor)
        navigationAnchor = anchor
    }

    private func removeNavigationArrow() {
        if let anchor = navigationAnchor {
            anchor.removeFromParent()
            navigationAnchor = nil
        }
    }

    private func updateDirectionHint(to transform: simd_float4x4, objectName: String? = nil) {
        guard let frame = arSession.currentFrame else {
            directionHint = "Locating..."
            return
        }

        let cameraTransform = frame.camera.transform
        let cameraPos = simd_float3(cameraTransform.columns.3.x,
                                     cameraTransform.columns.3.y,
                                     cameraTransform.columns.3.z)
        let objectPos = simd_float3(transform.columns.3.x,
                                     transform.columns.3.y,
                                     transform.columns.3.z)

        let distance = simd_distance(cameraPos, objectPos)
        let distanceStr = String(format: "%.1f", distance)

        let relativeHint = findRelativePosition(of: objectPos, excluding: objectName)

        let cameraForward = simd_float3(-cameraTransform.columns.2.x,
                                         -cameraTransform.columns.2.y,
                                         -cameraTransform.columns.2.z)
        let toObject = simd_normalize(objectPos - cameraPos)

        let cameraRight = simd_float3(cameraTransform.columns.0.x,
                                       cameraTransform.columns.0.y,
                                       cameraTransform.columns.0.z)

        let forwardDot = simd_dot(cameraForward, toObject)
        let rightDot = simd_dot(cameraRight, toObject)

        var direction = ""
        if forwardDot > 0.7 {
            direction = "Ahead"
        } else if forwardDot < -0.3 {
            direction = "Behind you"
        } else if rightDot > 0.3 {
            direction = "To your right"
        } else {
            direction = "To your left"
        }

        if let relativeHint = relativeHint {
            directionHint = "is \(relativeHint.lowercased())\n\(direction) • \(distanceStr)m from you"
        } else {
            directionHint = "is \(direction.lowercased())\n\(distanceStr)m away"
        }
    }

    private let goodReferenceObjects: Set<String> = [
        "laptop", "tv", "couch", "chair", "bed", "dining table", "desk", "toilet",
        "refrigerator", "microwave", "oven", "sink", "book", "keyboard", "monitor",
        "bottle", "cup", "bowl", "vase", "clock", "lamp", "potted plant", "backpack",
        "suitcase", "handbag", "umbrella"
    ]

    private let poorReferenceObjects: Set<String> = [
        "person", "cat", "dog", "bird", "horse", "sheep", "cow", "elephant",
        "bear", "zebra", "giraffe", "sports ball", "frisbee", "kite"
    ]

    private func findRelativePosition(of targetPos: simd_float3, excluding: String?) -> String? {
        var bestObject: (name: String, relation: String, distance: Float, priority: Int)?
        let minDistanceThreshold: Float = 1.5  // Only consider objects within 1.5m

        for (name, entry) in spatialIndex {
            if let excluding = excluding, name.lowercased() == excluding.lowercased() {
                continue
            }

            if poorReferenceObjects.contains(name.lowercased()) {
                continue
            }

            let otherPos = simd_float3(entry.transform.columns.3.x,
                                        entry.transform.columns.3.y,
                                        entry.transform.columns.3.z)

            let distance = simd_distance(targetPos, otherPos)

            guard distance < minDistanceThreshold else { continue }

            let diff = targetPos - otherPos
            let relation: String

            if diff.y > 0.20 {
                relation = "Above the \(name)"
            } else if diff.y < -0.20 {
                relation = "On the \(name)"
            }
            else if let frame = arSession.currentFrame {
                let cameraPos = simd_float3(frame.camera.transform.columns.3.x,
                                            frame.camera.transform.columns.3.y,
                                            frame.camera.transform.columns.3.z)

                let cameraToRef = simd_float3(otherPos.x - cameraPos.x, 0, otherPos.z - cameraPos.z)
                let refToTarget = simd_float3(diff.x, 0, diff.z)

                let horizontalDist = simd_length(refToTarget)

                if horizontalDist < 0.05 {
                    relation = "Next to the \(name)"
                } else {
                    let normalizedCameraToRef = simd_normalize(cameraToRef)
                    let normalizedRefToTarget = simd_normalize(refToTarget)
                    let behindDot = simd_dot(normalizedRefToTarget, normalizedCameraToRef)

                    if behindDot > 0.3 {
                        relation = "Behind the \(name)"
                    } else if behindDot < -0.3 {
                        relation = "In front of the \(name)"
                    } else {
                        let cameraRight = simd_float3(frame.camera.transform.columns.0.x,
                                                       0,
                                                       frame.camera.transform.columns.0.z)
                        let rightDot = simd_dot(normalizedRefToTarget, simd_normalize(cameraRight))
                        if rightDot > 0.3 {
                            relation = "Right of the \(name)"
                        } else if rightDot < -0.3 {
                            relation = "Left of the \(name)"
                        } else {
                            relation = "Near the \(name)"
                        }
                    }
                }
            } else {
                relation = "Near the \(name)"
            }

            let priority = goodReferenceObjects.contains(name.lowercased()) ? 2 : 1

            if bestObject == nil ||
               priority > bestObject!.priority ||
               (priority == bestObject!.priority && distance < bestObject!.distance) {
                bestObject = (name: name, relation: relation, distance: distance, priority: priority)
            }
        }

        return bestObject?.relation
    }
}

extension VisionNavManager: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor in
            self.frameCount += 1
            guard self.frameCount % 10 == 0 else { return }
            guard !self.isProcessing else { return }

            self.isProcessing = true
            self.currentStatus = "Scanning..."

            nonisolated(unsafe) let pixelBuffer = frame.capturedImage

            Task.detached {
                await MainActor.run {
                    self.runDetection(on: pixelBuffer)
                    self.isProcessing = false
                }
            }
        }
    }
}
