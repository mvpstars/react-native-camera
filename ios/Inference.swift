//
//  Inference.swift
//  RCTCamera
//
//  Created by Thibaut NOAH on 15/01/2018.
//

import Foundation
import CoreMedia
import VideoToolbox
import UIKit

public class Inference: NSObject, VideoCaptureDelegate {
    
    // MARK: – Variables
    
    var resizedPixelBuffer: CVPixelBuffer?
    let ciContext = CIContext()
    let yolo = YOLO()
    var request: VNCoreMLRequest!
    var startTimes: [CFTimeInterval] = []
    let semaphore = DispatchSemaphore(value: 1)
    var boundingBoxes = [BoundingBox]()
    var previousPredictionsArray = [Any]()
    var framesDone = 0
    var frameCapturingStartTime = CACurrentMediaTime()
    var bridge: RCTBridge!
    var camera: RCTCamera!
    var manager: RCTCameraManager!
    var colors: [UIColor] = []

    @objc public init(manager: RCTCameraManager, bridge: RCTBridge, camera: RCTCamera) {
//        print("\n\n\n INFERENCE IS INIT\n\n")
        super.init()
        self.manager = manager
        self.bridge = bridge
        self.camera = camera
        setUpBoundingBoxes()
        setUpCoreImage()
        setUpVision()
        self.manager.delegate = self
    }
    
    func setUpBoundingBoxes() {
        for _ in 0..<YOLO.maxBoundingBoxes {
            boundingBoxes.append(BoundingBox())
        }
        // Make colors for the bounding boxes. There is one color for each class,
        // 20 classes in total.
        for r: CGFloat in [0.2, 0.4, 0.6, 0.8, 1.0] {
            for g: CGFloat in [0.3, 0.7] {
                for b: CGFloat in [0.4, 0.8] {
                    let color = UIColor(red: r, green: g, blue: b, alpha: 1)
                    colors.append(color)
                }
            }
        }
    }
    
    func setUpCoreImage() {
        let status = CVPixelBufferCreate(nil, YOLO.inputWidth, YOLO.inputHeight,
                                         kCVPixelFormatType_32BGRA, nil,
                                         &resizedPixelBuffer)
        if status != kCVReturnSuccess {
            print("Error: could not create resized pixel buffer", status)
        }
    }
    
    func setUpVision() {
        guard let visionModel = try? VNCoreMLModel(for: yolo.model.model) else {
            print("Error: could not create Vision model")
            return
        }
        
        request = VNCoreMLRequest(model: visionModel, completionHandler: visionRequestDidComplete)
        
        // NOTE: If you choose another crop/scale option, then you must also
        // change how the BoundingBox objects get scaled when they are drawn.
        // Currently they assume the full input image is used.
        request.imageCropAndScaleOption = .scaleFill
    }
    
    // MARK: - Doing inference
    
    func predict(image: UIImage) {
        if let pixelBuffer = image.pixelBuffer(width: YOLO.inputWidth, height: YOLO.inputHeight) {
            predict(pixelBuffer: pixelBuffer)
        }
    }
    
    func predict(pixelBuffer: CVPixelBuffer) {
        // Measure how long it takes to predict a single video frame.
        let startTime = CACurrentMediaTime()
        
        // Resize the input with Core Image to 416x416.
        guard let resizedPixelBuffer = resizedPixelBuffer else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let sx = CGFloat(YOLO.inputWidth) / CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let sy = CGFloat(YOLO.inputHeight) / CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let scaleTransform = CGAffineTransform(scaleX: sx, y: sy)
        let scaledImage = ciImage.transformed(by: scaleTransform)
        ciContext.render(scaledImage, to: resizedPixelBuffer)
        // This is an alternative way to resize the image (using vImage):
        //if let resizedPixelBuffer = resizePixelBuffer(pixelBuffer,
        //                                              width: YOLO.inputWidth,
        //                                              height: YOLO.inputHeight)
        
        // Resize the input to 416x416 and give it to our model.
        if let boundingBoxes = try? yolo.predict(image: resizedPixelBuffer) {
            let elapsed = CACurrentMediaTime() - startTime
            showOnMainThread(boundingBoxes, elapsed)
        }
    }
    
    func predictUsingVision(pixelBuffer: CVPixelBuffer) {
        // Measure how long it takes to predict a single video frame. Note that
        // predict() can be called on the next frame while the previous one is
        // still being processed. Hence the need to queue up the start times.
        startTimes.append(CACurrentMediaTime())
        
        // Vision will automatically resize the input image.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
        try? handler.perform([request])
    }
    
    func visionRequestDidComplete(request: VNRequest, error: Error?) {
        if let observations = request.results as? [VNCoreMLFeatureValueObservation],
            let features = observations.first?.featureValue.multiArrayValue, !startTimes.isEmpty {
            
            let boundingBoxes = yolo.computeBoundingBoxes(features: features)
            let elapsed = CACurrentMediaTime() - startTimes.remove(at: 0)
            showOnMainThread(boundingBoxes, elapsed)
        }
        if let error = error {
            print("Error vision predict \(error)")
        }
    }
    
    func showOnMainThread(_ boundingBoxes: [YOLO.Prediction], _ elapsed: CFTimeInterval) {
        DispatchQueue.main.async {
            // For debugging, to make sure the resized CVPixelBuffer is correct.
            //            var debugImage: CGImage?
            //            VTCreateCGImageFromCVPixelBuffer(self.resizedPixelBuffer!, nil, &debugImage)
            //            self.debugImageView.image = UIImage(cgImage: debugImage!)
            self.show(predictions: boundingBoxes)
            let fps = self.measureFPS()
           // self.timeLabel.text = String(format: "Elapsed %.5f seconds - %.2f FPS", elapsed, fps)
            self.semaphore.signal()
        }
    }
    
    func measureFPS() -> Double {
        // Measure how many frames were actually delivered per second.
        framesDone += 1
        let frameCapturingElapsed = CACurrentMediaTime() - frameCapturingStartTime
        let currentFPSDelivered = Double(framesDone) / frameCapturingElapsed
        if frameCapturingElapsed > 1 {
            framesDone = 0
            frameCapturingStartTime = CACurrentMediaTime()
        }
        return currentFPSDelivered
    }
    
    func show(predictions: [YOLO.Prediction]) {
        var predictionsArray = [Any]()
        for i in 0..<boundingBoxes.count {
            if i < predictions.count {
                let prediction = predictions[i]
                
                // The predicted bounding box is in the coordinate space of the input
                // image, which is a square image of 416x416 pixels. We want to show it
                // on the video preview, which is as wide as the screen and has a 4:3
                // aspect ratio. The video preview also may be letterboxed at the top
                // and bottom.
                let width = camera.bounds.width
                let height = width * 4 / 3
                let scaleX = width / CGFloat(YOLO.inputWidth)
                let scaleY = height / CGFloat(YOLO.inputHeight)
                let top = (camera.bounds.height - height) / 2
                
                // Translate and scale the rectangle to our own coordinate system.
                var rect = prediction.rect
                rect.origin.x *= scaleX
                rect.origin.y *= scaleY
                rect.origin.y += top
                rect.size.width *= scaleX
                rect.size.height *= scaleY
                // Show the bounding box.
                //                let label = String(format: "%@ %.1f", labels[prediction.classIndex], prediction.score * 100)
                //                let color = colors[prediction.classIndex]
                // check the prediction before appending datas for react-native boundingBox
                if labels[prediction.classIndex] == "cat" && prediction.score > 0.1 {
                    let location = ["top": rect.origin.y, "left": rect.origin.x, "right": rect.maxX, "bottom": rect.maxY]
                    let body = ["confidence": prediction.score, "location": location] as [String : Any]
                    predictionsArray.append(body)
                }
                //                boundingBoxes[i].show(frame: rect, label: label, color: color)
            } else {
                //                boundingBoxes[i].hide()
            }
            // send boundingBoxes to reactNative
            // FIXME: call react bridge
            self.bridge.eventDispatcher().sendDeviceEvent(withName: "Recognitions", body: predictionsArray)
            previousPredictionsArray = predictionsArray
        }
    }
    
    @objc public func videoCapture(_ capture: NSObject, didCaptureVideoFrame pixelBuffer: CVPixelBuffer?, timestamp: CMTime) {
        print("\n\n\n PREDICTION IS INIT\n\n")
        
        // For debugging.
        //predict(image: UIImage(named: "dog416")!); return
        semaphore.wait()
        if let pixelBuffer = pixelBuffer {
            // For better throughput, perform the prediction on a background queue
            // instead of on the VideoCapture queue. We use the semaphore to block
            // the capture queue and drop frames when Core ML can't keep up.
            DispatchQueue.global().async {
                
                //self.predict(pixelBuffer: pixelBuffer)
                self.predictUsingVision(pixelBuffer: pixelBuffer)
            }
        }
    }
}
