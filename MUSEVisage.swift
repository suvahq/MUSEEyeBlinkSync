//
//  MUSEVisage.swift
//  PEER
//
//  Created by Julian Abentheuer on 21.12.14.
//  Copyright (c) 2014 Aaron Abentheuer. All rights reserved.
//
//
//  Cribbed from https://github.com/aaronabentheuer/AAFaceDetection - MIT licensed

import UIKit
import CoreImage
import AVFoundation
import ImageIO

class MUSEVisage: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    enum DetectorAccuracy {
        case batterySaving
        case higherPerformance
    }
    
    enum CameraDevice {
        case iSightCamera
        case faceTimeCamera
    }
    
    var onlyFireNotificatonOnStatusChange : Bool = true
    
    //Private properties of the detected face that can be accessed (read-only) by other classes.
    fileprivate(set) var faceDetected = false
    fileprivate(set) var faceBounds : CGRect?
    fileprivate(set) var faceAngle : CGFloat?
    fileprivate(set) var faceAngleDifference : CGFloat?
    fileprivate(set) var leftEyePosition : CGPoint?
    fileprivate(set) var rightEyePosition : CGPoint?
    
    fileprivate(set) var mouthPosition : CGPoint?
    fileprivate(set) var hasSmile = false
    fileprivate(set) var isBlinking = false
    fileprivate(set) var isWinking = false
    fileprivate(set) var leftEyeClosed = false
    fileprivate(set) var rightEyeClosed = false
    
    //Notifications you can subscribe to for reacting to changes in the detected properties.
    public static let NoFaceDetectedNotification = Notification.Name(rawValue: "visageNoFaceDetectedNotification")
    public static let FaceDetectedNotification = Notification.Name(rawValue: "visageFaceDetectedNotification")
    public static let SmilingNotification = Notification.Name(rawValue: "visageSmilingNotification")
    public static let NotSmilingNotification = Notification.Name(rawValue: "visageNotSmilingNotification")
    public static let BlinkingNotification = Notification.Name(rawValue: "visageBlinkingNotification")
    public static let NotBlinkingNotification = Notification.Name(rawValue: "visageNotBlinkingNotification")
    public static let WinkingNotification = Notification.Name(rawValue: "visageWinkingNotification")
    public static let NotWinkingNotification = Notification.Name(rawValue: "visageNotWinkingNotification")
    public static let LeftEyeClosedNotification = Notification.Name(rawValue: "visageLeftEyeClosedNotification")
    public static let LeftEyeOpenNotification = Notification.Name(rawValue: "visageLeftEyeOpenNotification")
    public static let RightEyeClosedNotification = Notification.Name(rawValue: "visageRightEyeClosedNotification")
    public static let RightEyeOpenNotification = Notification.Name(rawValue: "visageRightEyeOpenNotification")
    
    fileprivate let visageNoFaceDetectedNotification = Notification(name: NoFaceDetectedNotification, object: nil)
    fileprivate let visageFaceDetectedNotification = Notification(name: FaceDetectedNotification, object: nil)
    fileprivate let visageSmilingNotification = Notification(name: SmilingNotification, object: nil)
    fileprivate let visageNotSmilingNotification = Notification(name: NotSmilingNotification, object: nil)
    fileprivate let visageBlinkingNotification = Notification(name: BlinkingNotification, object: nil)
    fileprivate let visageNotBlinkingNotification = Notification(name: NotBlinkingNotification, object: nil)
    fileprivate let visageWinkingNotification = Notification(name: WinkingNotification, object: nil)
    fileprivate let visageNotWinkingNotification = Notification(name: NotWinkingNotification, object: nil)
    fileprivate let visageLeftEyeClosedNotification = Notification(name: LeftEyeClosedNotification, object: nil)
    fileprivate let visageLeftEyeOpenNotification = Notification(name: LeftEyeOpenNotification, object: nil)
    fileprivate let visageRightEyeClosedNotification = Notification(name: RightEyeClosedNotification, object: nil)
    fileprivate let visageRightEyeOpenNotification = Notification(name: RightEyeOpenNotification, object: nil)
    
    //Private variables that cannot be accessed by other classes in any way.
    fileprivate var faceDetector : CIDetector?
    fileprivate var videoDataOutput : AVCaptureVideoDataOutput?
    fileprivate var videoDataOutputQueue : DispatchQueue?
    fileprivate(set) var captureSession : AVCaptureSession = AVCaptureSession()
    fileprivate let notificationCenter : NotificationCenter = NotificationCenter.default
    private (set) var captureError : NSError?
    
    init(cameraPosition : CameraDevice, optimizeFor : DetectorAccuracy) {
        super.init()
        
        switch cameraPosition {
        case .faceTimeCamera : self.captureSetup(AVCaptureDevice.Position.front)
        case .iSightCamera : self.captureSetup(AVCaptureDevice.Position.back)
        }
        
        var faceDetectorOptions : [String : Any]?
        
        switch optimizeFor {
        case .batterySaving : faceDetectorOptions = [CIDetectorAccuracy : CIDetectorAccuracyLow]
        case .higherPerformance : faceDetectorOptions = [CIDetectorAccuracy : CIDetectorAccuracyHigh]
        }
        
        self.faceDetector = CIDetector(ofType: CIDetectorTypeFace, context: nil, options: faceDetectorOptions)
    }
    
    //MARK: SETUP OF VIDEOCAPTURE
    func beginFaceDetection() {
        self.captureSession.startRunning()
    }
    
    func endFaceDetection() {
        self.captureSession.stopRunning()
    }
    
    fileprivate func captureSetup (_ position : AVCaptureDevice.Position) {
        var captureDevice : AVCaptureDevice!
        
        let deviceDescoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [AVCaptureDevice.DeviceType.builtInWideAngleCamera],
                                                                      mediaType: AVMediaType.video,
                                                                      position: position)

        for testedDevice in deviceDescoverySession.devices {
            if (testedDevice.position == position) {
                captureDevice = testedDevice
            }
        }
        
        if (captureDevice == nil) {
            captureDevice = AVCaptureDevice.default(for: AVMediaType.video)
        }
        
        var deviceInput : AVCaptureDeviceInput?
        do {
            deviceInput = try AVCaptureDeviceInput(device: captureDevice)
        } catch let error as NSError {
            captureError = error
            deviceInput = nil
        }
        captureSession.sessionPreset = AVCaptureSession.Preset.high
        
        if (captureError == nil) {
            if (captureSession.canAddInput(deviceInput!)) {
                captureSession.addInput(deviceInput!)
            }
            
            self.videoDataOutput = AVCaptureVideoDataOutput()
            self.videoDataOutput!.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            self.videoDataOutput!.alwaysDiscardsLateVideoFrames = true
            self.videoDataOutputQueue = DispatchQueue(label: "VideoDataOutputQueue", attributes: [])
            self.videoDataOutput!.setSampleBufferDelegate(self, queue: self.videoDataOutputQueue!)
            
            if (captureSession.canAddOutput(self.videoDataOutput!)) {
                captureSession.addOutput(self.videoDataOutput!)
            }
        }
    }
        
    //MARK: CAPTURE-OUTPUT/ANALYSIS OF FACIAL-FEATURES
    func captureOutput(_ captureOutput: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        let orientation = convertOrientation(UIDevice.current.orientation)
        let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        let opaqueBuffer = Unmanaged<CVImageBuffer>.passUnretained(imageBuffer!).toOpaque()
        let pixelBuffer = Unmanaged<CVPixelBuffer>.fromOpaque(opaqueBuffer).takeUnretainedValue()
        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer, options: nil)
        let options = [CIDetectorSmile : true as AnyObject, CIDetectorEyeBlink: true as AnyObject, CIDetectorImageOrientation : orientation as AnyObject]
        
        let features = self.faceDetector!.features(in: sourceImage, options: options)
        
        if (features.count > 0) {
            let faceWasDetected = self.faceDetected
            
            self.faceDetected = true
            self.faceAngle = nil
            self.faceBounds = nil
            self.mouthPosition = nil
            self.hasSmile = false
            self.isBlinking = false
            self.isWinking = false
            self.leftEyeClosed = false
            self.rightEyeClosed = false
            
            for feature in features as! [CIFaceFeature] {
                faceBounds = feature.bounds
                
                if (feature.hasFaceAngle) {
                    
                    if (faceAngle != nil) {
                        faceAngleDifference = CGFloat(feature.faceAngle) - faceAngle!
                    } else {
                        faceAngleDifference = CGFloat(feature.faceAngle)
                    }
                    
                    faceAngle = CGFloat(feature.faceAngle)
                }
                
                if (feature.hasLeftEyePosition) {
                    leftEyePosition = feature.leftEyePosition
                }
                
                if (feature.hasRightEyePosition) {
                    rightEyePosition = feature.rightEyePosition
                }
                
                if (feature.hasMouthPosition) {
                    mouthPosition = feature.mouthPosition
                }
                
                if (feature.hasSmile) {
                    if (onlyFireNotificatonOnStatusChange == true) {
                        if (self.hasSmile == false) {
                            notificationCenter.post(visageSmilingNotification)
                        }
                    } else {
                        notificationCenter.post(visageSmilingNotification)
                    }
                    
                    hasSmile = feature.hasSmile
                    
                } else {
                    if (onlyFireNotificatonOnStatusChange == true) {
                        if (self.hasSmile == true) {
                            notificationCenter.post(visageNotSmilingNotification)
                        }
                    } else {
                        notificationCenter.post(visageNotSmilingNotification)
                    }
                    
                    hasSmile = feature.hasSmile
                }
                
                if (feature.leftEyeClosed || feature.rightEyeClosed) {
                    if (onlyFireNotificatonOnStatusChange == true) {
                        if (self.isWinking == false) {
                            notificationCenter.post(visageWinkingNotification)
                        }
                    } else {
                        notificationCenter.post(visageWinkingNotification)
                    }
                    
                    isWinking = true
                    
                    if (feature.leftEyeClosed) {
                        if (onlyFireNotificatonOnStatusChange == true) {
                            if (self.leftEyeClosed == false) {
                                notificationCenter.post(visageLeftEyeClosedNotification)
                            }
                        } else {
                            notificationCenter.post(visageLeftEyeClosedNotification)
                        }
                        
                        leftEyeClosed = feature.leftEyeClosed
                    }
                    if (feature.rightEyeClosed) {
                        if (onlyFireNotificatonOnStatusChange == true) {
                            if (self.rightEyeClosed == false) {
                                notificationCenter.post(visageRightEyeClosedNotification)
                            }
                        } else {
                            notificationCenter.post(visageRightEyeClosedNotification)
                        }
                        
                        rightEyeClosed = feature.rightEyeClosed
                    }
                    if (feature.leftEyeClosed && feature.rightEyeClosed) {
                        if (onlyFireNotificatonOnStatusChange == true) {
                            if (self.isBlinking == false) {
                                notificationCenter.post(visageBlinkingNotification)
                            }
                        } else {
                            notificationCenter.post(visageBlinkingNotification)
                        }
                        
                        isBlinking = true
                    }
                } else {
                    
                    if (onlyFireNotificatonOnStatusChange == true) {
                        if (self.isBlinking == true) {
                            notificationCenter.post(visageNotBlinkingNotification)
                        }
                        if (self.isWinking == true) {
                            notificationCenter.post(visageNotWinkingNotification)
                        }
                        if (self.leftEyeClosed == true) {
                            notificationCenter.post(visageLeftEyeOpenNotification)
                        }
                        if (self.rightEyeClosed == true) {
                            notificationCenter.post(visageRightEyeOpenNotification)
                        }
                    } else {
                        notificationCenter.post(visageNotBlinkingNotification)
                        notificationCenter.post(visageNotWinkingNotification)
                        notificationCenter.post(visageLeftEyeOpenNotification)
                        notificationCenter.post(visageRightEyeOpenNotification)
                    }
                    
                    isBlinking = false
                    isWinking = false
                    leftEyeClosed = feature.leftEyeClosed
                    rightEyeClosed = feature.rightEyeClosed
                }
                
                if (onlyFireNotificatonOnStatusChange == true) {
                    if (faceWasDetected == false) {
                        notificationCenter.post(visageFaceDetectedNotification)
                    }
                } else {
                    notificationCenter.post(visageFaceDetectedNotification)
                }
            }
        } else {
            if (onlyFireNotificatonOnStatusChange == true) {
                if (self.faceDetected == true) {
                    notificationCenter.post(visageNoFaceDetectedNotification)
                }
            } else {
                notificationCenter.post(visageNoFaceDetectedNotification)
            }
            
            self.faceDetected = false
        }
    }
    
    //TODO: 🚧 HELPER TO CONVERT BETWEEN UIDEVICEORIENTATION AND CIDETECTORORIENTATION 🚧
    fileprivate func convertOrientation(_ deviceOrientation: UIDeviceOrientation) -> Int {
/*
        enum {
            PHOTOS_EXIF_0ROW_TOP_0COL_LEFT            = 1, //   1  =  0th row is at the top, and 0th column is on the left (THE DEFAULT).
            PHOTOS_EXIF_0ROW_TOP_0COL_RIGHT            = 2, //   2  =  0th row is at the top, and 0th column is on the right.
            PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT      = 3, //   3  =  0th row is at the bottom, and 0th column is on the right.
            PHOTOS_EXIF_0ROW_BOTTOM_0COL_LEFT       = 4, //   4  =  0th row is at the bottom, and 0th column is on the left.
            PHOTOS_EXIF_0ROW_LEFT_0COL_TOP          = 5, //   5  =  0th row is on the left, and 0th column is the top.
            PHOTOS_EXIF_0ROW_RIGHT_0COL_TOP         = 6, //   6  =  0th row is on the right, and 0th column is the top.
            PHOTOS_EXIF_0ROW_RIGHT_0COL_BOTTOM      = 7, //   7  =  0th row is on the right, and 0th column is the bottom.
            PHOTOS_EXIF_0ROW_LEFT_0COL_BOTTOM       = 8  //   8  =  0th row is on the left, and 0th column is the bottom.
        };
        
        switch deviceOrientation {
        case UIDeviceOrientationPortraitUpsideDown:  // Device oriented vertically, home button on the top
            exifOrientation = PHOTOS_EXIF_0ROW_LEFT_0COL_BOTTOM;
            break;
        case UIDeviceOrientationLandscapeLeft:       // Device oriented horizontally, home button on the right
            if (isUsingFrontFacingCamera)
            exifOrientation = PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT;
            else
            exifOrientation = PHOTOS_EXIF_0ROW_TOP_0COL_LEFT;
            break;
        case UIDeviceOrientationLandscapeRight:      // Device oriented horizontally, home button on the left
            if (isUsingFrontFacingCamera)
            exifOrientation = PHOTOS_EXIF_0ROW_TOP_0COL_LEFT;
            else
            exifOrientation = PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT;
            break;
        case UIDeviceOrientationPortrait:            // Device oriented vertically, home button on the bottom
        default:
            exifOrientation = PHOTOS_EXIF_0ROW_RIGHT_0COL_TOP;
            break;
*/
        
        switch deviceOrientation {
        case .portrait:
            return 6
        case .portraitUpsideDown:
            return 8
        case .landscapeLeft:
            return 3
        case .landscapeRight:
            return 1
        default:
            return 6
        }
    }
}
