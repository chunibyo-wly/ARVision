//
//  ViewController.swift
//  ARKitVisionObjectDetection
//
//  Created by Dennis Ippel on 08/07/2020.
//  Copyright © 2020 Rozengain. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import Vision

class ViewController: UIViewController, ARSCNViewDelegate {

    @IBOutlet var sceneView: ARSCNView!
    
    private var viewportSize: CGSize!
    private var detectRemoteControl: Bool = true
    
    private var detectSet = Set<String>()
    
    private var label = ""
    private var boundingBox : CGRect!
    
    @IBOutlet weak var labelLabel: UILabel!
    
    @IBOutlet weak var labelView: UIView!
    
    override var shouldAutorotate: Bool { return false }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        sceneView.delegate = self
        labelView.layer.cornerRadius = 10
        viewportSize = sceneView.frame.size
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        resetTracking()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }
    
    private func resetTracking() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = []
        sceneView.session.run(configuration, options: [.removeExistingAnchors, .resetTracking])
        detectRemoteControl = true
    }

    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard anchor.name != nil else { return }
        
        let text = SCNText(string: anchor.name, extrusionDepth: 1)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.orange
        text.materials = [material]
        
        let childNode = SCNNode()
        childNode.position = SCNVector3(x:0, y:0, z:0)
        childNode.scale = SCNVector3(x:0.01, y:0.01, z:0.01)
        childNode.geometry = text
        
        node.addChildNode(childNode)
    }
    
    func renderer(_ renderer: SCNSceneRenderer, willRenderScene scene: SCNScene, atTime time: TimeInterval) {
        guard let capturedImage = sceneView.session.currentFrame?.capturedImage
            else { return }
        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: capturedImage, orientation: .leftMirrored, options: [:])
        
        do {
            try imageRequestHandler.perform([objectDetectionRequest])
        } catch {
            print("Failed to perform image request.")
        }
    }
    
    lazy var objectDetectionRequest: VNCoreMLRequest = {
        do {
            let model = try VNCoreMLModel(for: YOLOv3().model)
            let request = VNCoreMLRequest(model: model) { [weak self] request, error in
                self?.processDetections(for: request, error: error)
            }
            return request
        } catch {
            fatalError("Failed to load Vision ML model.")
        }
    }()
    
    func processDetections(for request: VNRequest, error: Error?) {
        guard error == nil else {
            print("Object detection error: \(error!.localizedDescription)")
            return
        }
        
        guard let results = request.results else { return }
        
        for observation in results where observation is VNRecognizedObjectObservation {
            guard let objectObservation = observation as? VNRecognizedObjectObservation,
                let topLabelObservation = objectObservation.labels.first,
//                topLabelObservation.identifier == "remote",
                topLabelObservation.confidence > 0.9
                else { continue }
            
            let label = topLabelObservation.identifier
            self.boundingBox = objectObservation.boundingBox
            self.label = label
            DispatchQueue.main.async {
                self.labelLabel.text = label
            }
        }
    }
    
    @IBAction func recognize(_ sender: UITapGestureRecognizer) {
        if detectSet.contains(self.label) {return}
        detectSet.insert(self.label)
        
        guard let currentFrame = sceneView.session.currentFrame else { return }
        // 相机实际拍到的和预览的大小不一样
        // Get the affine transform to convert between normalized image coordinates and view coordinates
        let fromCameraImageToViewTransform = currentFrame.displayTransform(for: .portrait, viewportSize: viewportSize)
        // The observation's bounding box in normalized image coordinates
        let boundingBox = self.boundingBox!
        // Transform the latter into normalized view coordinates
        let viewNormalizedBoundingBox = boundingBox.applying(fromCameraImageToViewTransform)
        // The affine transform for view coordinates
        let t = CGAffineTransform(scaleX: viewportSize.width, y: viewportSize.height)
        // Scale up to view coordinates
        let viewBoundingBox = viewNormalizedBoundingBox.applying(t)

        let midPoint = CGPoint(x: viewBoundingBox.midX,
                   y: viewBoundingBox.midY)

        let results = sceneView.hitTest(midPoint, types: .featurePoint)
        guard let result = results.first else { return }
        
        let anchor = ARAnchor(name: self.label, transform: result.worldTransform)
        sceneView.session.add(anchor: anchor)
    }
}
