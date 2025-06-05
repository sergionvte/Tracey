//
//  CameraView.swift
//  DrawingReference
//
//  Created by Sergio Navarrete on 31/05/25.
//

// CameraView.swift - Versión mejorada con zoom, enfoque y método para enfocar al centro
import SwiftUI
import AVFoundation

struct CameraView: UIViewRepresentable {
    let viewModel: CameraViewModel
    @Binding var cameraUIView: CameraUIView?
    var isZoomEnabled: Bool // Nueva propiedad para controlar el zoom

    func makeUIView(context: Context) -> CameraUIView {
        let cameraView = CameraUIView()
        cameraView.isZoomEnabled = isZoomEnabled // Pasar el estado
        cameraView.setupCamera()
        DispatchQueue.main.async {
            cameraUIView = cameraView
            // Vincular referencia débil para setear zoom desde el ViewModel
            viewModel.cameraUIViewRef = cameraView
        }
        return cameraView
    }

    func updateUIView(_ uiView: CameraUIView, context: Context) {
        uiView.isZoomEnabled = isZoomEnabled // Actualizar si cambia
    }
}

class CameraUIView: UIView {
    private var captureSession: AVCaptureSession!
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var captureDevice: AVCaptureDevice!

    // Agregar propiedad para controlar el zoom
    var isZoomEnabled: Bool = true

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("No camera available")
            return
        }

        captureDevice = device

        do {
            let input = try AVCaptureDeviceInput(device: captureDevice)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
        } catch {
            print("Error setting up camera input: \(error)")
            return
        }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)

        // Configurar gestos
        setupGestures()

        DispatchQueue.global(qos: .background).async {
            self.captureSession.startRunning()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }

    private func setupGestures() {
        // Gesto de zoom (pinch)
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinchGesture)

        // Gesto de enfoque (tap)
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapToFocus(_:)))
        tapGesture.numberOfTapsRequired = 1
        addGestureRecognizer(tapGesture)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard isZoomEnabled else { gesture.scale = 1.0; return } // Deshabilitar zoom si no está permitido
        guard let device = captureDevice else { return }

        do {
            try device.lockForConfiguration()

            let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 10.0)
            let currentZoom = device.videoZoomFactor

            var newZoom = currentZoom * gesture.scale
            newZoom = max(1.0, min(newZoom, maxZoom))

            device.videoZoomFactor = newZoom
            device.unlockForConfiguration()

            gesture.scale = 1.0
        } catch {
            print("Error adjusting zoom: \(error)")
        }
    }

    @objc private func handleTapToFocus(_ gesture: UITapGestureRecognizer) {
        let touchPoint = gesture.location(in: self)
        focusAtPoint(touchPoint)
    }

    // Método público para enfocar al centro
    func focusAtCenter() {
        let centerPoint = CGPoint(x: bounds.midX, y: bounds.midY)
        focusAtPoint(centerPoint)
    }

    // Método privado para enfocar en un punto específico
    private func focusAtPoint(_ touchPoint: CGPoint) {
        guard let device = captureDevice else { return }

        let focusPoint = previewLayer.captureDevicePointConverted(fromLayerPoint: touchPoint)

        do {
            try device.lockForConfiguration()

            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = focusPoint
                device.focusMode = .autoFocus
            }

            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = focusPoint
                device.exposureMode = .autoExpose
            }

            device.unlockForConfiguration()

            // Mostrar indicador visual de enfoque
            showFocusIndicator(at: touchPoint)
        } catch {
            print("Error setting focus: \(error)")
        }
    }

    private func showFocusIndicator(at point: CGPoint) {
        // Crear indicador de enfoque
        let focusView = UIView(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
        focusView.center = point
        focusView.backgroundColor = UIColor.clear
        focusView.layer.borderColor = UIColor.yellow.cgColor
        focusView.layer.borderWidth = 2
        focusView.layer.cornerRadius = 40
        focusView.alpha = 0

        addSubview(focusView)

        // Animar el indicador
        UIView.animate(withDuration: 0.2, animations: {
            focusView.alpha = 1
            focusView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        }) { _ in
            UIView.animate(withDuration: 0.3, delay: 0.5, animations: {
                focusView.alpha = 0
            }) { _ in
                focusView.removeFromSuperview()
            }
        }
    }

    func setZoomFactor(_ zoom: CGFloat) {
        guard let device = captureDevice else { return }
        do {
            try device.lockForConfiguration()
            let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 10.0)
            let newZoom = max(1.0, min(zoom, maxZoom))
            device.videoZoomFactor = newZoom
            device.unlockForConfiguration()
        } catch {
            print("Error setting zoom: \(error)")
        }
    }

    // Nuevo método público para obtener el zoom actual de la cámara
    func getCurrentZoomFactor() -> CGFloat {
        return captureDevice?.videoZoomFactor ?? 1.0
    }
}

