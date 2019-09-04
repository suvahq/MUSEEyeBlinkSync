//
//  MUSEBlinkPreviewView.swift
//  PEER
//
//  Created by Mark Alldritt on 2017-07-03.
//  Copyright 2018 SUVA Technologies, All Rights Reserved.
//  Copyright © 2017 Late Night Software Ltd. All rights reserved.
//

import UIKit
import AVFoundation

class MUSEBlinkPreviewView: UIView {
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Expected `AVCaptureVideoPreviewLayer` type for layer. Check PreviewView.layerClass implementation.")
        }
        
        return layer
    }
    
    var session: AVCaptureSession? {
        get {
            return videoPreviewLayer.session
        }
        set {
            videoPreviewLayer.session = newValue
            videoPreviewLayer.videoGravity = .resizeAspectFill
        }
    }
    
    // MARK: UIView
    
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
}
