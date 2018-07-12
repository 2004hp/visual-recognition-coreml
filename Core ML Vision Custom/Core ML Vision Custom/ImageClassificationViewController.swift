/**
 * Copyright IBM Corporation 2017, 2018
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 **/

import UIKit
import AVFoundation
import VisualRecognitionV3

struct VisualRecognitionConstants {
    // Instantiation with `api_key` works only with Visual Recognition service instances created before May 23, 2018. Visual Recognition instances created after May 22 use the IAM `apikey`.
    static let apikey = ""     // The IAM apikey
    static let api_key = ""    // The apikey
    static let classifierId = ""
    static let version = "2018-03-19"
}

class ImageClassificationViewController: UIViewController {
    
    // MARK: - IBOutlets
    
    @IBOutlet weak var cameraView: UIView!
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var simulatorTextView: UITextView!
    @IBOutlet weak var captureButton: UIButton!
    @IBOutlet weak var updateModelButton: UIButton!
    @IBOutlet weak var choosePhotoButton: UIButton!
    @IBOutlet weak var closeButton: UIButton!
    
    // MARK: - Variable Declarations
    
    var cameraAvailable = true
    
    let visualRecognition: VisualRecognition = {
        if !VisualRecognitionConstants.api_key.isEmpty {
            return VisualRecognition(apiKey: VisualRecognitionConstants.api_key, version: VisualRecognitionConstants.version)
        }
        return VisualRecognition(version: VisualRecognitionConstants.version, apiKey: VisualRecognitionConstants.apikey)
    }()
    
    let photoOutput = AVCapturePhotoOutput()
    lazy var captureSession: AVCaptureSession? = {
        guard let backCamera = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: backCamera) else {
                cameraAvailable = false
                return nil
        }
        
        let captureSession = AVCaptureSession()
        captureSession.sessionPreset = .high
        captureSession.addInput(input)
        
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
            let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.frame = view.bounds
            // `.resize` allows the camera to fill the screen on the iPhone X.
            previewLayer.videoGravity = .resize
            previewLayer.connection?.videoOrientation = .portrait
            cameraView.layer.addSublayer(previewLayer)
            return captureSession
        }
        return nil
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        captureSession?.startRunning()
        resetUI()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        // Pull down model if none on device
        guard let localModels = try? visualRecognition.listLocalModels() else {
            return
        }
        
        // This only checks if the model is downloaded, we need to change this if we want to check for updates when then open the app
        if !localModels.contains(VisualRecognitionConstants.classifierId) {
            invokeModelUpdate()
        }
    }
    
    // MARK: - Model Methods
    
    func invokeModelUpdate() {
        let failure = { (error: Error) in
            DispatchQueue.main.async {
                SwiftSpinner.hide()
            }
        }
        
        let success = {
            DispatchQueue.main.async {
                SwiftSpinner.hide()
            }
        }
        
        SwiftSpinner.show("Compiling model...")
        
        visualRecognition.updateLocalModel(classifierID: VisualRecognitionConstants.classifierId, failure: failure, success: success)
    }

    func presentPhotoPicker(sourceType: UIImagePickerControllerSourceType) {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = sourceType
        present(picker, animated: true)
    }
    
    // MARK: - Image Classification
    
    func classifyImage(for image: UIImage, localThreshold: Double = 0.0) {
        showResultsUI(for: image)
        
        let failure = { (error: Error) in
            DispatchQueue.main.async {
                self.showAlert("Could not classify image", alertMessage: error.localizedDescription)
                self.resetUI()
            }
        }
        
        visualRecognition.classifyWithLocalModel(image: image, classifierIDs: [VisualRecognitionConstants.classifierId], threshold: localThreshold, failure: failure) { classifiedImages in
            
            // Make sure that an image was successfully classified.
            guard let classifiedImage = classifiedImages.images.first else {
                return
            }

            // Update UI on main thread
            DispatchQueue.main.async {
                // Push the classification results of all the provided models to the ResultsTableView.
                self.push(results: classifiedImage.classifiers)
            }
        }
    }
    
    func dismissResults() {
        push(results: [], position: .closed)
    }
    
    func push(results: [VisualRecognitionV3.ClassifierResult], position: PulleyPosition = .partiallyRevealed) {
        guard let drawer = pulleyViewController?.drawerContentViewController as? ResultsTableViewController else {
            return
        }
        drawer.classifications = results
        pulleyViewController?.setDrawerPosition(position: position, animated: true)
        drawer.tableView.reloadData()
    }
    
    func showResultsUI(for image: UIImage) {
        imageView.image = image
        simulatorTextView.isHidden = true
        closeButton.isHidden = false
    }
    
    func resetUI() {
        if (cameraAvailable) {
            simulatorTextView.isHidden = true
            imageView.isHidden = true
        } else {
            imageView.image = UIImage(named: "Background")
            simulatorTextView.isHidden = false
            imageView.isHidden = false
        }
        
        closeButton.isHidden = true
        dismissResults()
    }
    
    // MARK: - IBActions
    
    @IBAction func updateModel(_ sender: Any) {
        invokeModelUpdate()
    }
    
    @IBAction func takePicture() {
        // Show options for the source picker only if the camera is available.
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            presentPhotoPicker(sourceType: .photoLibrary)
            return
        }
        
        let photoSourcePicker = UIAlertController()
        let takePhoto = UIAlertAction(title: "Take Photo", style: .default) { [unowned self] _ in
            self.presentPhotoPicker(sourceType: .camera)
        }
        let choosePhoto = UIAlertAction(title: "Choose Photo", style: .default) { [unowned self] _ in
            self.presentPhotoPicker(sourceType: .photoLibrary)
        }
        
        photoSourcePicker.addAction(takePhoto)
        photoSourcePicker.addAction(choosePhoto)
        photoSourcePicker.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        
        present(photoSourcePicker, animated: true)
    }
    
    @IBAction func reset() {
        resetUI()
    }
}

// MARK: - Error Handling

extension ImageClassificationViewController {
    func showAlert(_ alertTitle: String, alertMessage: String) {
        let alert = UIAlertController(title: alertTitle, message: alertMessage, preferredStyle: UIAlertControllerStyle.alert)
        alert.addAction(UIAlertAction(title: "Dismiss", style: UIAlertActionStyle.default, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }
}

// MARK: - UIImagePickerControllerDelegate

extension ImageClassificationViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String: Any]) {
        picker.dismiss(animated: true)
        
        guard let image = info[UIImagePickerControllerOriginalImage] as? UIImage else {
            return
        }
        
        classifyImage(for: image)
    }
}


