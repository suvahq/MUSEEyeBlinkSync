//
//  MUSEBlinkViewController.swift
//  PEER
//
//  Created by Mark Alldritt on 2017-07-03.
//  Copyright 2018 SUVA Technologies, All Rights Reserved.
//  Copyright © 2017 Late Night Software Ltd. All rights reserved.
//

import UIKit
import AudioToolbox
import MBProgressHUD


class MUSEBlinkViewController: MUSEOrientedViewController, IXNMuseDataListener {

    enum State {
        case idle,
        waitingForFace,
        faceDetected,
        faceLost,
        waitingForVisualBlink,
        waitingForMUSEBlink,
        blinkDetected,
        blinkTimeout,
        blinkAborted,
        blinkAbortedRestart,
        qualityHUD
    }

    let minMUSEBlinkLatency = 50 /* ms */ * 1000 // us - minimum EEG latency in ms
    let maxMUSEBlinkLatency = 180 /* ms */ * 1000 // us - maximum EEG latency in ms
    let minVisualBlinkInterval = 40 /* ms */ * 1000 // us - minimum visual blink length
    let timeoutInterval: TimeInterval = 90 /* seconds - 3 minutes*/
    let badQualityInterval: TimeInterval = 8 /* seconds */
    
    private var visualBlinks = 0
    private var museBlinks = 0
    private var museBlinksUndertime = 0
    private var museBlinksOvertime = 0
    private var timeoutTimer: Timer?
    private var badQualityStart: Date?
    private var visage: MUSEVisage?
    private let emojiLabel: UILabel = UILabel(frame: CGRect.zero)
    private var visualBlinkTimestamp: Int64?
    private var museBlinkTimestamp: Int64?
    private var blinkEEGIndex: Int?
    private var faceTimestamp: Int64?
    private var timer: Timer?
    private var museObserver : NSObjectProtocol?
    private var observers: [NSObjectProtocol] = []
    private var hud : MBProgressHUD?
    private var state : State = .idle {
        didSet {
            guard state != oldValue else { return }
            guard let visage = self.visage else { return }
            var emojiAlpha : CGFloat = 1.0
            var animateEmojiAlpha = true
            
            timer?.invalidate()
            timer = nil

            switch state {
            case .idle, .qualityHUD:
                emojiAlpha = 0.2
                museBlinks = 0
                museBlinksUndertime = 0
                museBlinksOvertime = 0
                visualBlinks = 0
                faceTimestamp = nil
                visualBlinkTimestamp = nil
                museBlinkTimestamp = nil
                emojiLabel.text = ""
                helpText = ""
                timeoutTimer?.invalidate()
                timeoutTimer = nil
                if state != .qualityHUD, let hud = self.hud {
                    hud.hide(animated: true)
                    self.hud = nil
                    self.badQualityStart = nil
                }
                break
                
            case .waitingForFace:  // waiting for a face to appear
                faceTimestamp = nil
                visualBlinkTimestamp = nil
                museBlinkTimestamp = nil
                emojiLabel.text = "👤"
                helpText = "Please center your face on the screen"
                break

            case .faceDetected: // face detected, waiting to ensure face detection is good
                if timeoutTimer == nil {
                    timeoutTimer = Timer.scheduledTimer(withTimeInterval: timeoutInterval, repeats: false, block: { [unowned self] (timer) in
                        self.state = .idle
                        self.timedOut()
                    })
                }
                emojiAlpha = 0.2
                animateEmojiAlpha = emojiLabel.text == "👤"
                visualBlinkTimestamp = nil
                museBlinkTimestamp = nil
                emojiLabel.text = "👤"//"😐"
                helpText = "Please center your face on the screen"
                timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false, block: { [unowned self] (timer) in
                    #if DEBUG
                    //print("faceDetected: visage.faceDetected: \(visage.faceDetected)")
                    #endif
                    self.state = visage.faceDetected ? .waitingForVisualBlink : .faceLost
                })
                break

            case .faceLost:
                faceTimestamp = nil
                visualBlinkTimestamp = nil
                museBlinkTimestamp = nil
                emojiLabel.text = "👤"
                helpText = "Please ensure there is good light and remove eye glasses"
                timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false, block: { [unowned self] (timer) in
                    #if DEBUG
                    //print("faceLost: visage.faceDetected: \(visage.faceDetected)")
                    #endif
                    self.state = visage.faceDetected ? .faceDetected : .waitingForFace
                })
                break

            case .waitingForVisualBlink: // face confirmed, waiting for the camera to detect a blink
                emojiAlpha = 0.2
                animateEmojiAlpha = emojiLabel.text == "👤"
                visualBlinkTimestamp = nil
                museBlinkTimestamp = nil
                emojiLabel.text = "👤"//"😐"
                helpText = "Please close both eyes and wait for a sound"
                break

            case .waitingForMUSEBlink: // camera has detected a blink, waiting for the MUSE to detect the corresponding blink artifact
                emojiAlpha = 0.2
                animateEmojiAlpha = emojiLabel.text == "👤"
                museBlinkTimestamp = nil
                emojiLabel.text = "👤"//"😑"
                helpText = "Blink detected, waiting for the MUSE headband..."
                timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false, block: { [unowned self] (timer) in
                    #if DEBUG
                    //print("waitingForMUSEBlink: visage.faceDetected: \(visage.faceDetected)")
                    #endif
                    self.state = .blinkTimeout
                })
                break

            case .blinkAborted: // something went wrong during the waitingForMUSEBlink state (face detection lost, etc.)
                visualBlinkTimestamp = nil
                museBlinkTimestamp = nil
                helpText = "Please ensure there is good light and remove eye glasses"
                emojiLabel.text = "❌"
                AudioServicesPlaySystemSound(1053)
                timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false, block: { [unowned self] (timer) in
                    #if DEBUG
                    //print("blinkAborted: visage.faceDetected: \(visage.faceDetected)")
                    #endif
                    self.state = visage.faceDetected ? .faceDetected : .waitingForFace
                })
                break

            case .blinkAbortedRestart:
                visualBlinkTimestamp = nil
                museBlinkTimestamp = nil
                helpText = "Please try not to blink, remove eye glasses"
                emojiLabel.text = "❌"
                timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false, block: { [unowned self] (timer) in
                    #if DEBUG
                    //print("blinkAbortedRestart: visage.faceDetected: \(visage.faceDetected)")
                    #endif
                    self.state = visage.faceDetected ? .faceDetected : .waitingForFace
                })
                break

            case .blinkDetected: // MUSE has detected a blink artifact
                guard let visualBlinkTimestamp = visualBlinkTimestamp else { return }
                guard let museBlinkTimestamp = museBlinkTimestamp else { return }
                
                let deltaMS = Int((museBlinkTimestamp - visualBlinkTimestamp) / 1000)

                helpText = "MUSE Latancy: \(deltaMS)ms"
                emojiLabel.text = "✅"
                AudioServicesPlaySystemSoundWithCompletion(1054, { [weak self] in
                    if (self?.state ?? .idle) == .blinkDetected {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            #if DEBUG
                            //print("blinkDetected: visage.faceDetected: \(visage.faceDetected)")
                            #endif
                            #if true
                                self?.navigationController?.dismiss(animated: true, completion: {
                                    self?.timeoutTimer?.invalidate()
                                    self?.timeoutTimer = nil
                                    self?.completionHandler?(false, self?.visualBlinkTimestamp, self?.blinkEEGIndex, self?.museBlinkTimestamp)
                                    self?.state = .idle
                                })
                            #else
                                self?.state = visage.faceDetected ? .faceDetected : .waitingForFace
                            #endif
                        }
                    }
                })
                break

            case .blinkTimeout: // MUSE has not detected a blink artifact (time out)
                visualBlinkTimestamp = nil
                museBlinkTimestamp = nil
                helpText = "The MUSE headband failed to detect a blink"
                emojiLabel.text = "❌"
                AudioServicesPlaySystemSound(1053)
                timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false, block: { [unowned self] (timer) in
                    #if DEBUG
                    //print("blinkTimeout: visage.faceDetected: \(visage.faceDetected)")
                    #endif
                    if self.state == .blinkTimeout {
                        self.state = .waitingForVisualBlink
                    }
                    else {
                        self.state = visage.faceDetected ? .faceDetected : .waitingForFace
                    }
                })
                break
            }
            
            if emojiLabel.alpha != emojiAlpha {
                if animateEmojiAlpha {
                    UIView.animate(withDuration: 0.3, animations: { [unowned self] in
                        #if DEBUG
                        //print("emojiLabel.text = \(self.emojiLabel.text), emojiLabel.alpha = \(emojiAlpha)")
                        #endif
                        self.emojiLabel.alpha = emojiAlpha
                    })
                }
                else {
                    self.emojiLabel.alpha = emojiAlpha
                }
            }
        }
    }
    private var helpText: String {
        get {
            return helpLabel.text ?? ""
        }
        set {
            let strokeTextAttributes : [NSAttributedString.Key: Any] = [
                NSAttributedString.Key.strokeColor : UIColor.black,
                NSAttributedString.Key.foregroundColor : UIColor.white,
                NSAttributedString.Key.strokeWidth : -1.0]
            
            helpLabel.attributedText = NSAttributedString(string: newValue, attributes: strokeTextAttributes)
        }
    }
    private var help2Text: String {
        get {
            return help2Label.text ?? ""
        }
        set {
            let strokeTextAttributes : [NSAttributedString.Key: Any] = [
                NSAttributedString.Key.strokeColor : UIColor.black,
                NSAttributedString.Key.foregroundColor : UIColor.white,
                NSAttributedString.Key.strokeWidth : -1.0]
            
            help2Label.attributedText = NSAttributedString(string: newValue, attributes: strokeTextAttributes)
        }
    }

    @IBOutlet weak var previewView: MUSEBlinkPreviewView!
    @IBOutlet weak var helpLabel: UILabel!
    @IBOutlet weak var help2Label: UILabel!
    
    var muse : IXNMuse? {
        didSet {
            guard muse != oldValue else { return }
            
            oldValue?.unregisterDataListener(self, type: .artifacts)

            muse?.register(self, type: .artifacts)
            museBlinks = 0
            museBlinksUndertime = 0
            museBlinksOvertime = 0
        }
    }

    public var completionHandler: ((_ cancelled: Bool, _ blinkTimestamp: Int64?, _ blinkEEGIndex: Int?, _ blinkEEGTimestamp: Int64?) -> Void)?
    public var recorder: MUSEEEGRecorder?
    
    public static var sharedNavController : UINavigationController {
        return UIStoryboard(name: "MUSEChooser", bundle: nil).instantiateViewController(withIdentifier: "MUSEBlinkDetector") as! UINavigationController
    }
    
    deinit {
        #if DEBUG
        print("deinit MUSEBlinkViewController")
        #endif
        muse = nil
        timer?.invalidate()
        timeoutTimer?.invalidate()
        if museObserver != nil {
            NotificationCenter.default.removeObserver(museObserver!)
        }
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    @IBAction func cancelSheet(_ sender: Any) {
        navigationController?.dismiss(animated: false, completion: { [unowned self] in
            self.timeoutTimer?.invalidate()
            self.timeoutTimer = nil
            self.completionHandler?(true, nil, nil, nil)
            self.state = .idle
        })
    }
    
    private func timedOut() {
        //  It has taken too long (> timeoutInterval) to get an eye blink
        #if DEBUG
        print("MUSEBlinkViewController timeout")
        print("  visualBlinks: \(visualBlinks)")
        print("  museBlinks: \(museBlinks)")
        print("  museBlinksUndertime: \(museBlinksUndertime)")
        print("  museBlinksOvertime: \(museBlinksOvertime)")
        #endif
        
        let saveShouldReconnect = MUSEManager.shared.shouldReconnect
        
        MUSEManager.shared.shouldReconnect = false
        state = .idle
        
        //  TODO - text for Dave to work on.
        let alertController = UIAlertController(title: "Eye Blink Not Detected",
                                                message: "Eye blink synchronization is taking too long.",
                                                preferredStyle: .alert)

        alertController.addAction(UIAlertAction(title: "Try Again",
                                                style: .default,
                                                handler: { [weak self] (alert) in
                                                    guard let xself = self else { return }

                                                    MUSEManager.shared.shouldReconnect = saveShouldReconnect
                                                    xself.state = xself.visage!.faceDetected ? .faceDetected : .waitingForFace
        }))
        alertController.addAction(UIAlertAction(title: "Cancel",
                                                style: .cancel,
                                                handler: { [weak self] (alert) in
                                                    guard let xself = self else { return }

                                                    MUSEManager.shared.shouldReconnect = saveShouldReconnect
                                                    xself.cancelSheet(xself)
        }))
        
        present(alertController, animated: true, completion: nil)
    }
    
    private func qualityFailed() {
        //  EEG quality is fallen for too long (badQualityInterval)
        #if DEBUG
        print("MUSEBlinkViewController qualityFailed")
        print("  visualBlinks: \(visualBlinks)")
        print("  museBlinks: \(museBlinks)")
        print("  museBlinksUndertime: \(museBlinksUndertime)")
        print("  museBlinksOvertime: \(museBlinksOvertime)")
        #endif
        
        let saveShouldReconnect = MUSEManager.shared.shouldReconnect
        
        MUSEManager.shared.shouldReconnect = false
        state = .idle

        //  TODO - text for Dave to work on.
        let alertController = UIAlertController(title: "Eye Blink Not Detected",
                                                message: "Eye blink synchronization interrupted because MUSE signal quality has declined.",
                                                preferredStyle: .alert)
        
        alertController.addAction(UIAlertAction(title: "Recalibrate MUSE",
                                                style: .default,
                                                handler: { [unowned self] (alert) in
                                                    //  NOTE: quality duration will come from MUSEManager
                                                    MUSEManager.shared.aquireMuse(canCancel: true,
                                                                                  needsCleanData: true,
                                                                                  completionHandler: { [weak self] (muse, success) in
                                                                                    guard let xself = self else { return }
                                                                                    
                                                                                    MUSEManager.shared.shouldReconnect = saveShouldReconnect
                                                                                    if muse != nil, success {
                                                                                        xself.state = xself.visage!.faceDetected ? .faceDetected : .waitingForFace
                                                                                    }
                                                                                    else {
                                                                                        xself.cancelSheet(xself)
                                                                                    }
                                                    })
        }))
        alertController.addAction(UIAlertAction(title: "Cancel",
                                                style: .cancel,
                                                handler: { [weak self] (alert) in
                                                    guard let xself = self else { return }

                                                    MUSEManager.shared.shouldReconnect = saveShouldReconnect
                                                    xself.cancelSheet(xself)
        }))

        present(alertController, animated: true, completion: nil)

    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        //Setup "Visage" with a camera-position (iSight-Camera (Back), FaceTime-Camera (Front)) and an optimization mode for either better feature-recognition performance (HighPerformance) or better battery-life (BatteryLife)
        visage = MUSEVisage(cameraPosition: MUSEVisage.CameraDevice.faceTimeCamera, optimizeFor: MUSEVisage.DetectorAccuracy.higherPerformance)
        
        if let _ = visage!.captureError {
            helpLabel.text = ""
            help2Label.text = ""
            emojiLabel.text = ""
            let alertController = UIAlertController(title: "Cannot Use Camera",
                                                    message: "Please use the Settings app to give \(UIDevice.current.appName()) access to your camera.",
                                                    preferredStyle: .alert)
            
            alertController.addAction(UIAlertAction(title: "Cancel",
                                                    style: .cancel,
                                                    handler: { [unowned self] (action) in
                                                        self.cancelSheet(self)
            }))
            
            present(alertController, animated: true, completion: nil)
            return
        }
        
        //If you enable "onlyFireNotificationOnStatusChange" you won't get a continuous "stream" of notifications, but only one notification once the status changes.
        visage!.onlyFireNotificatonOnStatusChange = false
        
        //  Configure the preview
        previewView.session = visage?.captureSession
        if preferredInterfaceOrientationForPresentation == .unknown {
            if let newVideoOrientation = UIApplication.shared.statusBarOrientation.videoOrientation {
                previewView?.videoPreviewLayer.connection?.videoOrientation = newVideoOrientation
            }
        }
        else if !supportedInterfaceOrientations.contains(UIApplication.shared.statusBarOrientation.interfaceOrientationMask!) {
            if let newVideoOrientation = preferredInterfaceOrientationForPresentation.videoOrientation {
                previewView?.videoPreviewLayer.connection?.videoOrientation = newVideoOrientation
            }
        }
        else if let newVideoOrientation = UIApplication.shared.statusBarOrientation.videoOrientation {
            previewView?.videoPreviewLayer.connection?.videoOrientation = newVideoOrientation
        }

        //You need to call "beginFaceDetection" to start the detection, but also if you want to use the cameraView.
        visage!.beginFaceDetection()
        
        /*
         let visualEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .extraLight))
         visualEffectView.frame = self.view.bounds
         visualEffectView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
         self.view.addSubview(visualEffectView)
         */
        
        emojiLabel.frame = view.bounds
        emojiLabel.font = UIFont.systemFont(ofSize: 120)
        emojiLabel.autoresizingMask = [.flexibleHeight, .flexibleWidth]
        emojiLabel.textAlignment = .center
        emojiLabel.alpha = 0.20
        
        view.addSubview(emojiLabel)
        
        help2Text = "Synchronizing with MUSE headband..."
        
        state = .waitingForFace
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        muse = MUSEManager.shared.muse
        museObserver = NotificationCenter.default.addObserver(forName: MUSEManagerMuseChangedNotification,
                                                              object: MUSEManager.shared,
                                                              queue: nil) { [unowned self] (node) in
                                                                self.muse = MUSEManager.shared.muse
        }

        observers = [
            NotificationCenter.default.addObserver(forName: MUSEManagerMuseQualityChangedNotification,
                                                   object: MUSEManager.shared,
                                                   queue: nil) { [unowned self] (notification) in
                guard let visage = self.visage else { return }
                guard self.state != .idle else { return }
                let now = Date()

                if let hud = self.hud {
                    if self.state == .blinkDetected || MUSEManager.shared.eegQualityIsPerfect {
                        hud.hide(animated: true)
                        self.badQualityStart = nil
                        self.hud = nil
                        self.state = visage.faceDetected ? .faceDetected : .waitingForFace
                    }
                    else if now.timeIntervalSince(self.badQualityStart!) >= self.badQualityInterval {
                        self.badQualityStart = nil
                        self.hud?.hide(animated: true)
                        self.hud = nil
                        self.qualityFailed()
                    }
                }
                else if self.state != .blinkDetected && !MUSEManager.shared.eegQualityIsGood && self.badQualityStart == nil {
                    self.badQualityStart = now
                    
                    self.hud = MBProgressHUD.showAdded(to: self.view, animated: true)
                    let qualityView = MUSEQualityViewII(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
                    
                    self.hud?.minShowTime = 1.0 // seconds
                    self.hud?.customView = qualityView
                    self.hud?.mode = .customView
                    self.hud?.label.text = "Poor MUSE Signal Quality"
                    self.state = .qualityHUD
                }
            },
            NotificationCenter.default.addObserver(forName: MUSEVisage.FaceDetectedNotification,
                                                   object: nil,
                                                   queue: OperationQueue.main) { [unowned self] (notification) in
                guard let visage = self.visage else { return }
                guard self.state != .idle && self.state != .qualityHUD else { return }
                
                let now = Date.usecTimestamp
                
                if visage.isBlinking {
                    self.visualBlinks += 1
                }
                                                    
                switch self.state {
                case .waitingForFace:
                    self.faceTimestamp = now
                    self.state = .waitingForVisualBlink
                    
                case .blinkAborted:
                    if visage.isBlinking {
                        //  If the user blinks while we are waiting for the MUSE to clear its buffer, restart the delay
                        self.state = .idle
                        self.state = .blinkAbortedRestart
                    }
                    
                case .waitingForVisualBlink:
                    if visage.isBlinking {
                        self.visualBlinkTimestamp = now
                        self.state = .waitingForMUSEBlink
                    }
                    
                case .waitingForMUSEBlink:
                    guard let visualBlinkTimestamp = self.visualBlinkTimestamp else { return }
                    
                    if !visage.isBlinking &&
                        now - visualBlinkTimestamp <= self.minVisualBlinkInterval {
                        //  Visual blink was too short...
                        self.state = .blinkAborted
                    }
                    
                default:
                    break
                }
            },
                     //The same thing for the opposite, when no face is detected things are reset.
            NotificationCenter.default.addObserver(forName: MUSEVisage.NoFaceDetectedNotification,
                                                   object: nil,
                                                   queue: OperationQueue.main) { [weak self] (notification) in
                                                    guard let self = self else { return }
                                                    
                                                    switch self.state {
                                                    case .idle, .qualityHUD, .faceLost, .blinkAborted, .blinkDetected:
                                                        break
                                                        
                                                    case .waitingForMUSEBlink:
                                                        self.state = .blinkAborted
                                                        
                                                    default:
                                                        self.state = .waitingForFace
                                                    }
            }]
        
        if state != .idle && state != .qualityHUD && state != .blinkDetected && timeoutTimer == nil {
            timeoutTimer = Timer.scheduledTimer(withTimeInterval: timeoutInterval, repeats: false, block: { [unowned self] (timer) in
                self.state = .idle
                self.timedOut()
            })
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        muse = nil
        if museObserver != nil {
            NotificationCenter.default.removeObserver(museObserver!)
            museObserver = nil
        }
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        hud?.hide(animated: true)
        hud = nil
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        if let videoPreviewLayerConnection = previewView?.videoPreviewLayer.connection {
            let deviceOrientation = UIDevice.current.orientation
            
            guard let newVideoOrientation = deviceOrientation.videoOrientation, deviceOrientation.isPortrait || deviceOrientation.isLandscape else {
                return
            }
            
            videoPreviewLayerConnection.videoOrientation = newVideoOrientation
        }
    }

    //  MARK: - IXNMuseDataListener
    
    func receive(_ packet: IXNMuseDataPacket?, muse: IXNMuse?) {
    }
    
    func receive(_ packet: IXNMuseArtifactPacket, muse: IXNMuse?) {
        #if DEBUG
        //print("blink: \(packet.blink), jawClench: \(packet.jawClench), headbandOn: \(packet.headbandOn)")
        #endif
        
        if packet.blink && MUSEManager.shared.eegQualityIsGood {
            museBlinks += 1
            if state == .waitingForMUSEBlink {
                guard let visualBlinkTimestamp = visualBlinkTimestamp else { return }
                let now = Date.usecTimestamp
                let delta = Int(now - visualBlinkTimestamp)
                
                if delta >= minMUSEBlinkLatency && delta <= maxMUSEBlinkLatency {
                    self.blinkEEGIndex = recorder?.nextEEGIndex
                    self.museBlinkTimestamp = now
                    
                    DispatchQueue.main.async(execute: { [weak self] in
                        guard self != nil else { return }

                        self?.state = .blinkDetected
                    })
                }
                else {
                    if delta < minMUSEBlinkLatency { museBlinksUndertime += 1 }
                    if delta > maxMUSEBlinkLatency { museBlinksOvertime += 1 }
                    DispatchQueue.main.async(execute: { [weak self] in
                        guard self != nil else { return }

                        #if DEBUG
                        print("Blink delta out of range: \(delta / 1000), museBlinksUndertime: \(self!.museBlinksUndertime), museBlinksOvertime: \(self!.museBlinksOvertime)")
                        #endif
                        self?.state = .blinkTimeout
                    })
                }
            }
        }
    }

}
