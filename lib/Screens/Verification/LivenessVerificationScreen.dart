import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:io';
import 'dart:ui'; // Needed for ImageFilter

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

// --- YOUR APP IMPORTS ---
import 'package:viora/Screens/SupportScreen/supportScreen.dart';
import 'package:viora/Services/Global.dart';
import 'package:viora/Services/PermissionManager.dart';
import 'package:viora/Services/ProfileVerificationService.dart';
import 'package:viora/Services/AppConfigService.dart';
import 'package:viora/Services/exceptions/exceptions.dart';
import 'package:viora/Screens/Home/home.dart';
import 'package:viora/Screens/Verification/ProfileCorrectionScreen.dart';
import 'package:viora/constants.dart';
import 'package:viora/size_config.dart';

// Helper for conditional logging
void _log(String message) {
  if (kDebugMode) {
    debugPrint('[LivenessVerification] $message');
  }
}

// --- ENUMS ---

enum LivenessChallenge {
  blink,
  smile,
  turnLeft,
  turnRight,
  tiltLeft,  // Ear to left shoulder
  tiltRight, // Ear to right shoulder
 }

enum VerificationState {
  initializing,
  detectingFace,
  waitingForNeutral, // ANTI-SPOOF: Forces user to reset face
  waitingForChallenge,
  transitioning,
  verified,
  failed,
  timeout, 
}

// --- MAIN WIDGET ---

class LivenessVerificationScreen extends HookWidget {
  static String routeName = "/liveness-verification";

  const LivenessVerificationScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // --- STATE MANAGEMENT ---

    // Camera & Processing
    final cameraController = useState<CameraController?>(null);
    final isCameraInitialized = useState(false);
    final faceDetector = useState<FaceDetector?>(null);
    final isProcessingFrame = useState(false);

    // Liveness Logic
    final verificationState = useState<VerificationState>(VerificationState.initializing);
    final challengeQueue = useState<List<LivenessChallenge>>([]);
    final currentChallengeIndex = useState<int>(0);

    // Timeouts
    final challengeTimer = useState<Timer?>(null);
    final timeLeft = useState<int>(10); // 10 seconds per step
    final maxTimePerStep = 10;

    // Tracking for Gestures
    final eyesClosedDetected = useState(false);
    final holdCounter = useState(0);

    // Anti-Spoofing
    final faceWidthHistory = useState<List<double>>([]);

    // UI State
    final statusMessage = useState('Initializing camera...');
    final isVerifying = useState(false);
    final verificationError = useState<String?>(null);
    final capturedImage = useState<Uint8List?>(null);
    final showManualCapture = useState(false);

    final lifecycle = useAppLifecycleState();

    // --- TIMEOUT LOGIC ---

    void failVerification(String reason) {
      verificationState.value = VerificationState.failed;
      challengeTimer.value?.cancel();
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => WillPopScope(
          onWillPop: () async {
            // Handle back button - close both dialog and verification screen
            Navigator.of(ctx).pop();
            Navigator.of(context).pop();
            return false;
          },
          child: Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.timer_off, color: Colors.red, size: 50),
                  const SizedBox(height: 15),
                  const Text(
                    "Verification Failed",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    reason,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx); // Close dialog
                      Navigator.pop(context); // Close screen
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: kPrimaryPurple,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Text("Close", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
      );
    }

    void startStepTimer() {
      challengeTimer.value?.cancel();
      timeLeft.value = maxTimePerStep;
      
      challengeTimer.value = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (timeLeft.value > 0) {
          timeLeft.value--;
        } else {
          timer.cancel();
          if (verificationState.value != VerificationState.verified && 
              verificationState.value != VerificationState.failed) {
            failVerification("You ran out of time. Please try again.");
          }
        }
      });
    }

    // --- CAMERA INITIALIZATION ---
    
    Future<void> initializeCamera() async {
      try {
        // 1. Permissions - Check current status
        var status = await Permission.camera.status;
        _log('Initial camera permission status: $status');
        
        // If permanently denied, show custom dialog and exit
        if (status.isPermanentlyDenied) {
          _log('Camera permission permanently denied');
          if (context.mounted) {
            final shouldOpenSettings = await _showCameraPermissionDialog(context, isPermanentlyDenied: true);
            if (shouldOpenSettings) {
              await openAppSettings();
            }
          }
          if (context.mounted) Navigator.pop(context);
          return;
        }
        
        // If denied (not permanently), request permission (shows system dialog)
        if (status.isDenied) {
          _log('Camera permission denied, requesting...');
          
          try {
            // Request permission directly without PermissionManager to avoid conflicts
            status = await Permission.camera.request();
            debugPrint('✅ [CAMERA] Permission request result: $status');
          } catch (e) {
            // WORKAROUND: another_telephony plugin may throw "Reply already submitted" error
            // even though camera permission was processed correctly. Check actual status.
            debugPrint('⚠️ [CAMERA] Permission request threw error (possibly telephony plugin conflict): $e');
            
            // Re-check actual permission status after the error
            await Future.delayed(const Duration(milliseconds: 200));
            status = await Permission.camera.status;
            debugPrint('🔍 [CAMERA] Re-checked permission status after error: $status');
            
            // If still not granted after re-check, show dialog and exit
            if (!status.isGranted) {
              debugPrint('❌ [CAMERA] Permission still not granted after error handling');
              if (context.mounted) {
                await _showCameraPermissionDialog(context, isPermanentlyDenied: status.isPermanentlyDenied);
                Navigator.pop(context);
              }
              return;
            }
            
            // If granted despite error, continue normally
            debugPrint('✅ [CAMERA] Permission granted despite error - continuing...');
          }
        }
        
        // If still not granted after request, show custom dialog and exit
        if (!status.isGranted) {
          _log('Camera permission not granted after request: $status');
          
          if (context.mounted) {
            // Small delay to ensure system dialog is fully dismissed
            await Future.delayed(const Duration(milliseconds: 500));
            
            // Check if it's now permanently denied
            final isPermanent = status.isPermanentlyDenied;
            debugPrint('🔍 [CAMERA] Is permanently denied: $isPermanent');
            
            if (isPermanent) {
              final shouldOpenSettings = await _showCameraPermissionDialog(context, isPermanentlyDenied: true);
              if (shouldOpenSettings) {
                await openAppSettings();
              }
            } else {
              // User just denied it, show informative dialog
          //    await _showCameraPermissionDialog(context, isPermanentlyDenied: false);
            }
            
            Navigator.pop(context);
          }
          return;
        }
        
        _log('Camera permission granted, initializing camera...');

        // 2. Setup Challenges (Pool of 6, Pick 4)
        var allChallenges = [
          LivenessChallenge.smile,
          LivenessChallenge.blink,
          LivenessChallenge.turnLeft,
          LivenessChallenge.turnRight,
          // LivenessChallenge.tiltLeft,
          // LivenessChallenge.tiltRight, 
        ];
        allChallenges.shuffle();
        challengeQueue.value = allChallenges.take(4).toList();
        currentChallengeIndex.value = 0;

        // 3. Setup Camera
        final cameras = await availableCameras();
        if (cameras.isEmpty) return;

        final frontCamera = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => cameras.first,
        );

        final controller = CameraController(
          frontCamera,
          ResolutionPreset.high,
          enableAudio: false,
          imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
        );

        await controller.initialize();

        // 4. Face Detector
        final detector = FaceDetector(
          options: FaceDetectorOptions(
            enableClassification: true,
            enableLandmarks: true,
            enableTracking: true,
            performanceMode: FaceDetectorMode.fast,
            minFaceSize: 0.15,
          ),
        );

        cameraController.value = controller;
        faceDetector.value = detector;
        isCameraInitialized.value = true;
        verificationState.value = VerificationState.detectingFace;
        statusMessage.value = "Position face in circle";
        
        // Start the image stream
        controller.startImageStream((image) {
          if (!isProcessingFrame.value &&
              verificationState.value != VerificationState.verified &&
              verificationState.value != VerificationState.failed) {
            _processFrame(
              image,
              detector,
              verificationState,
              challengeQueue,
              currentChallengeIndex,
              eyesClosedDetected,
              holdCounter,
              statusMessage,
              isProcessingFrame,
              controller,
              capturedImage,
              isVerifying,
              verificationError,
              context,
              faceWidthHistory,
              cameraController,
              showManualCapture,
              faceDetector,
              startStepTimer, 
              challengeTimer,
              isCameraInitialized,
            );
          }
        });

      } catch (e, stackTrace) {
        _log('Camera initialization error: $e');
        final appException = ErrorHandler.convert(e, stackTrace);
        statusMessage.value = appException.userMessage;
      }
    }

    // --- EFFECTS ---

    useEffect(() {
      initializeCamera();
      return () async {
        challengeTimer.value?.cancel();
        final controller = cameraController.value;
        if (controller != null && controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
        await controller?.dispose();
        await faceDetector.value?.close();
      };
    }, []);

    // --- UI BUILD ---
    final totalSteps = challengeQueue.value.length;
    final currentStep = currentChallengeIndex.value + 1;
    final activeChallenge = challengeQueue.value.isNotEmpty
        ? challengeQueue.value[currentChallengeIndex.value]
        : LivenessChallenge.smile;

    final size = MediaQuery.of(context).size;

    return WillPopScope(
      onWillPop: () async => true,
      child: Scaffold(
        backgroundColor: kBlack,
        body: Stack(
          children: [
            // 1. Camera Preview (always visible - never hidden)
            if (isCameraInitialized.value && cameraController.value != null)
              Positioned.fill(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: cameraController.value!.value.previewSize?.height ?? 0,
                    height: cameraController.value!.value.previewSize?.width ?? 0,
                    child: CameraPreview(cameraController.value!),
                  ),
                ),
              )
            else
              const Center(child: CircularProgressIndicator(color: kTertiaryPink)),

            // 2. Face Guide Overlay
            Positioned.fill(
              child: CustomPaint(
                painter: FaceGuidePainter(state: verificationState.value),
              ),
            ),

            // 3. UI Layer
            SafeArea(
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const CircleAvatar(
                            backgroundColor: Colors.black45,
                            child: Icon(Icons.close, color: kWhite),
                          ),
                        ),
                        // Step Indicator with Timer
                        if (verificationState.value == VerificationState.waitingForChallenge ||
                            verificationState.value == VerificationState.waitingForNeutral)
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 50, height: 50,
                                child: CircularProgressIndicator(
                                  value: timeLeft.value / maxTimePerStep,
                                  color: timeLeft.value < 3 ? Colors.red : kTertiaryPink,
                                  backgroundColor: Colors.grey.withOpacity(0.3),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: kWhite.withOpacity(0.3))),
                                child: Text(
                                  "$currentStep / $totalSteps",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, color: kTertiaryPink),
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(width: 40),
                      ],
                    ),
                  ),

                  // Spacer to push content below the circular camera guide
                  // Circle is at center-50px with radius ~42% of screen width
                  // So we need to position below: (height/2 - 50) + radius + spacing
                  SizedBox(height: size.height * 0.5 + size.width * 0.20), 

                  // Instructions - NOW POSITIONED BELOW THE CIRCLE
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        if (verificationState.value == VerificationState.waitingForChallenge ||
                            verificationState.value == VerificationState.waitingForNeutral ||
                            verificationState.value == VerificationState.transitioning)
                          _buildChallengeInstruction(activeChallenge, verificationState.value),

                        // Initial Text
                        if (verificationState.value == VerificationState.detectingFace)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Text(
                              statusMessage.value,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: kWhite,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  shadows: [Shadow(blurRadius: 10, color: Colors.black)]),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Loader - positioned at bottom when verifying
                  if (isVerifying.value)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 40),
                      child: Column(
                        children: const [
                          CircularProgressIndicator(color: kTertiaryPink),
                          SizedBox(height: 10),
                          Text("Verifying Identity...",
                              style: TextStyle(
                                  color: kWhite, fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),

                  // Error Display
                  if (verificationError.value != null)
                    Container(
                      margin: const EdgeInsets.all(20),
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: GestureDetector(
                        onTap: () async {
                          // Reset all error states
                          verificationError.value = null;
                          verificationState.value = VerificationState.detectingFace;
                          statusMessage.value = "Position face in circle";
                          currentChallengeIndex.value = 0;
                          challengeQueue.value.shuffle();
                          challengeTimer.value?.cancel();
                          timeLeft.value = 10;
                          holdCounter.value = 0;
                          eyesClosedDetected.value = false;
                          capturedImage.value = null;
                          isProcessingFrame.value = false;
                          isVerifying.value = false;
                          faceWidthHistory.value.clear();

                          // Restart image stream using existing camera (never disposed)
                          await Future.delayed(const Duration(milliseconds: 300));
                          final controller = cameraController.value;
                          final detector = faceDetector.value;
                          if (controller != null && detector != null) {
                            debugPrint('🔄 [RETRY] Restarting image stream using existing camera...');
                            
                            // Start image stream on existing camera controller
                            try {
                              controller.startImageStream((image) {
                                if (!isProcessingFrame.value &&
                                    verificationState.value != VerificationState.verified &&
                                    verificationState.value != VerificationState.failed) {
                                  _processFrame(
                                    image,
                                    detector,
                                    verificationState,
                                    challengeQueue,
                                    currentChallengeIndex,
                                    eyesClosedDetected,
                                    holdCounter,
                                    statusMessage,
                                    isProcessingFrame,
                                    controller,
                                    capturedImage,
                                    isVerifying,
                                    verificationError,
                                    context,
                                    faceWidthHistory,
                                    cameraController,
                                    showManualCapture,
                                    faceDetector,
                                    startStepTimer,
                                    challengeTimer,
                                    isCameraInitialized,
                                  );
                                }
                              });
                              debugPrint('✅ [RETRY] Image stream restarted successfully');
                            } catch (e) {
                              debugPrint('❌ [RETRY] Error restarting stream: $e');
                            }
                          }
                        },
                        child: Text("${verificationError.value!}\n(Tap to retry)",
                            textAlign: TextAlign.center, style: const TextStyle(color: kWhite)),
                      ),
                    ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- HELPER WIDGETS ---

  Widget _buildChallengeInstruction(LivenessChallenge challenge, VerificationState state) {
    if (state == VerificationState.transitioning) {
      return const Icon(Icons.check_circle, color: Colors.green, size: 80);
    }

    if (state == VerificationState.waitingForNeutral) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.face, color: kWhite, size: 60),
          SizedBox(height: 10),
          Text("Relax your face", style: TextStyle(color: kWhite, fontSize: 24, fontWeight: FontWeight.bold)),
          Text("Show a neutral expression", style: TextStyle(color: Colors.white70)),
        ],
      );
    }

    IconData iconData;
    String text;
    String subText = "";

    switch (challenge) {
      case LivenessChallenge.blink:
        iconData = Icons.visibility;
        text = "Blink Eyes";
        break;
      case LivenessChallenge.smile:
        iconData = Icons.sentiment_satisfied_alt;
        text = "Smile!";
        break;
      case LivenessChallenge.turnLeft:
        iconData = Icons.turn_left;
        text = "Turn Left";
        break;
      case LivenessChallenge.turnRight:
        iconData = Icons.turn_right;
        text = "Turn Right";
        break;
      case LivenessChallenge.tiltLeft:
        iconData = Icons.rotate_left;
        text = "Tilt Head Left";
        subText = "(Ear to Shoulder)";
        break;
      case LivenessChallenge.tiltRight:
        iconData = Icons.rotate_right;
        text = "Tilt Head Right";
        subText = "(Ear to Shoulder)";
        break;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(iconData, color: kTertiaryPink, size: 80,
            shadows: const [Shadow(blurRadius: 10, color: Colors.black)]),
        const SizedBox(height: 10),
        Text(text,
            style: TextStyle(
                color: kWhite,
                fontSize: 32,
                fontWeight: FontWeight.w900,
                shadows: const [Shadow(blurRadius: 10, color: Colors.black)])),
        if (subText.isNotEmpty)
           Text(subText,
            style: TextStyle(
                color: Colors.white70,
                fontSize: 18,
                fontWeight: FontWeight.w500,
                shadows: const [Shadow(blurRadius: 10, color: Colors.black)])),
      ],
    );
  }

  // --- CORE LOGIC ---

  void _processFrame(
    CameraImage image,
    FaceDetector detector,
    ValueNotifier<VerificationState> verificationState,
    ValueNotifier<List<LivenessChallenge>> challengeQueue,
    ValueNotifier<int> currentChallengeIndex,
    ValueNotifier<bool> eyesClosedDetected,
    ValueNotifier<int> holdCounter,
    ValueNotifier<String> statusMessage,
    ValueNotifier<bool> isProcessingFrame,
    CameraController controller,
    ValueNotifier<Uint8List?> capturedImage,
    ValueNotifier<bool> isVerifying,
    ValueNotifier<String?> verificationError,
    BuildContext context,
    ValueNotifier<List<double>> faceWidthHistory,
    ValueNotifier<CameraController?> cameraController,
    ValueNotifier<bool> showManualCapture,
    ValueNotifier<FaceDetector?> faceDetector,
    Function startStepTimer,
    ValueNotifier<Timer?> challengeTimer,
    ValueNotifier<bool> isCameraInitialized,
  ) async {
    if (isProcessingFrame.value) return;
    isProcessingFrame.value = true;

    try {
      final inputImage = _convertCameraImage(image, controller);
      if (inputImage == null) {
        isProcessingFrame.value = false;
        return;
      }

      final faces = await detector.processImage(inputImage);
      final imageSize = inputImage.metadata?.size;

      if (faces.isEmpty) {
        if (verificationState.value != VerificationState.initializing &&
            verificationState.value != VerificationState.failed) {
          holdCounter.value = 0;
          statusMessage.value = "Face lost";
        }
      } else {
        final face = faces.first;

        // --- STEP 1: CENTERING (REMOVED STRICT MATH) ---
        if (verificationState.value == VerificationState.detectingFace) {
          if (imageSize != null) {
            // Only check if face is big enough
            final faceWidthProp = face.boundingBox.width / imageSize.width;
            
            if (faceWidthProp < 0.10) { // Reduced to 10% - very forgiving
              statusMessage.value = "Move closer";
            } else if (_isFaceNeutral(face)) {
              // If it's detected and decent size, proceed.
              // We removed the X/Y strict check.
              verificationState.value = VerificationState.waitingForChallenge;
              startStepTimer();
            } else {
              statusMessage.value = "Show a neutral face";
            }
          }
        }

        // --- STEP 2: STATE MACHINE ---
        
        // Waiting for Neutral (Reset)
        else if (verificationState.value == VerificationState.waitingForNeutral) {
          if (_isFaceNeutral(face)) {
            holdCounter.value++;
            if (holdCounter.value > 5) { 
              holdCounter.value = 0;
              verificationState.value = VerificationState.waitingForChallenge;
              startStepTimer();
            }
          } else {
            holdCounter.value = max(0, holdCounter.value - 1);
          }
        }

        // Active Challenge
        else if (verificationState.value == VerificationState.waitingForChallenge) {
          final currentChallenge = challengeQueue.value[currentChallengeIndex.value];
          bool challengeMet = false;

          switch (currentChallenge) {
            case LivenessChallenge.blink:
              final leftOpen = (face.leftEyeOpenProbability ?? 1.0);
              final rightOpen = (face.rightEyeOpenProbability ?? 1.0);
              if (leftOpen < 0.3 && rightOpen < 0.3) eyesClosedDetected.value = true;
              if (eyesClosedDetected.value && leftOpen > 0.6 && rightOpen > 0.6) challengeMet = true;
              break;

            case LivenessChallenge.smile:
              if ((face.smilingProbability ?? 0.0) > 0.6) challengeMet = true;
              break;

            case LivenessChallenge.turnLeft:
              // Lowered to 20 degrees
              if ((face.headEulerAngleY ?? 0.0) > 20) challengeMet = true;
              break;

            case LivenessChallenge.turnRight:
              if ((face.headEulerAngleY ?? 0.0) < -20) challengeMet = true;
              break;

            case LivenessChallenge.tiltLeft:
              // FIXED: Front camera is mirrored, so when user tilts LEFT (ear to left shoulder),
              // camera sees it as NEGATIVE Z angle
              if ((face.headEulerAngleZ ?? 0.0) < -10) challengeMet = true;
              break;

            case LivenessChallenge.tiltRight:
              // FIXED: When user tilts RIGHT (ear to right shoulder),
              // camera sees it as POSITIVE Z angle due to mirroring
              if ((face.headEulerAngleZ ?? 0.0) > 10) challengeMet = true;
              break;
          }

          if (challengeMet) {
            holdCounter.value++;
            if (holdCounter.value >= 2) {
              holdCounter.value = 0;
              eyesClosedDetected.value = false;
              
              challengeTimer.value?.cancel();

              if (currentChallengeIndex.value < challengeQueue.value.length - 1) {
                verificationState.value = VerificationState.transitioning;
                await Future.delayed(const Duration(milliseconds: 1000));
                currentChallengeIndex.value++;
                verificationState.value = VerificationState.waitingForNeutral;
                startStepTimer();
              } else {
                verificationState.value = VerificationState.verified;
                await _captureAndVerify(
                  controller, 
                  capturedImage, 
                  isVerifying, 
                  verificationError, 
                  context,
                  verificationState,
                  challengeQueue,
                  currentChallengeIndex,
                  eyesClosedDetected,
                  holdCounter,
                  statusMessage,
                  faceWidthHistory,
                  showManualCapture,
                  cameraController,
                  faceDetector,
                  isProcessingFrame,
                  isCameraInitialized,
                  startStepTimer,
                  challengeTimer,
                );
              }
            }
          } else {
             if (currentChallenge != LivenessChallenge.blink) holdCounter.value = 0;
          }
        }
      }
    } catch (e, stackTrace) {
      _log('ML processing error: $e');
      final appException = ErrorHandler.convert(e, stackTrace);
      _log('Converted to: ${appException.runtimeType}');
    } finally {
      isProcessingFrame.value = false;
    }
  }

  // --- BUSINESS LOGIC & NETWORK ---

  Future<void> _captureAndVerify(
    CameraController controller,
    ValueNotifier<Uint8List?> capturedImage,
    ValueNotifier<bool> isVerifying,
    ValueNotifier<String?> verificationError,
    BuildContext context,
    ValueNotifier<VerificationState> verificationState,
    ValueNotifier<List<LivenessChallenge>> challengeQueue,
    ValueNotifier<int> currentChallengeIndex,
    ValueNotifier<bool> eyesClosedDetected,
    ValueNotifier<int> holdCounter,
    ValueNotifier<String> statusMessage,
    ValueNotifier<List<double>> faceWidthHistory,
    ValueNotifier<bool> showManualCapture,
    ValueNotifier<CameraController?> cameraController,
    ValueNotifier<FaceDetector?> faceDetector,
    ValueNotifier<bool> isProcessingFrame,
    ValueNotifier<bool> isCameraInitialized,
    Function startStepTimer,
    ValueNotifier<Timer?> challengeTimer,
  ) async {
    isVerifying.value = true;
    try {
      // Stop camera stream and take picture (but DON'T dispose or hide - we'll reuse it)
      await controller.stopImageStream();
      final XFile photo = await controller.takePicture();
      final bytes = await photo.readAsBytes();
      capturedImage.value = bytes;
      
      _log('Camera stream stopped for verification, camera kept alive for retries');

      final globals = Globals.of(context);
      final profileGender = globals.prefs.userDetails.value?.gender ?? 'Male';

      final result = await ProfileVerificationService.verifyProfile(
        imageBytes: bytes,
        profileGender: profileGender,
        context: context,
      );

      isVerifying.value = false;
      
      // Log detailed verification result
      _log('VERIFICATION RESULT');
      _log('Success: ${result.isSuccess}');
      _log('Status: ${result.status}');
      _log('Message: ${result.message}');
      _log('Detected Gender: ${result.detectedGender}');
      _log('Coins Awarded: ${result.coinsAwarded}');

      if (result.isSuccess) {
        _showSuccessDialog(context, result.coinsAwarded ?? 0, profileGender);
      } else if (result.status == ProfileVerificationService.resultGenderMismatch) {
        await _handleGenderMismatch(
          context, 
          result.detectedGender, 
          verificationState,
          challengeQueue,
          currentChallengeIndex,
          eyesClosedDetected,
          holdCounter,
          statusMessage,
          faceWidthHistory,
          showManualCapture,
          verificationError,
          capturedImage,
          isVerifying,
          isProcessingFrame,
          cameraController,
          faceDetector,
          isCameraInitialized,
          startStepTimer,
          challengeTimer,
        );
      } else {
        // Show user-friendly error message with retry functionality
        _log('Verification failed - Status: ${result.status}, Message: ${result.message}');
        _showErrorDialog(
          context, 
          _getUserFriendlyMessage(result.status, result.message),
          verificationState: verificationState,
          challengeQueue: challengeQueue,
          currentChallengeIndex: currentChallengeIndex,
          eyesClosedDetected: eyesClosedDetected,
          holdCounter: holdCounter,
          statusMessage: statusMessage,
          faceWidthHistory: faceWidthHistory,
          showManualCapture: showManualCapture,
          verificationError: verificationError,
          capturedImage: capturedImage,
          isVerifying: isVerifying,
          isProcessingFrame: isProcessingFrame,
          cameraController: cameraController,
          faceDetector: faceDetector,
          isCameraInitialized: isCameraInitialized,
          startStepTimer: startStepTimer,
          challengeTimer: challengeTimer,
        );
      }
    } catch (e, stackTrace) {
      isVerifying.value = false;
      _log('Capture error: $e');
      final appException = ErrorHandler.convert(e, stackTrace);
      _showErrorDialog(
        context, 
        appException.userMessage,
        verificationState: verificationState,
        challengeQueue: challengeQueue,
        currentChallengeIndex: currentChallengeIndex,
        eyesClosedDetected: eyesClosedDetected,
        holdCounter: holdCounter,
        statusMessage: statusMessage,
        faceWidthHistory: faceWidthHistory,
        showManualCapture: showManualCapture,
        verificationError: verificationError,
        capturedImage: capturedImage,
        isVerifying: isVerifying,
        isProcessingFrame: isProcessingFrame,
        cameraController: cameraController,
        faceDetector: faceDetector,
        isCameraInitialized: isCameraInitialized,
        startStepTimer: startStepTimer,
        challengeTimer: challengeTimer,
      );
    }
  }
  
  /// Convert technical error messages to user-friendly ones
  String _getUserFriendlyMessage(String status, String technicalMessage) {
    switch (status) {
      case ProfileVerificationService.resultNoFaceDetected:
        return 'We couldn\'t detect your face clearly. Please ensure good lighting and try again.';
      case ProfileVerificationService.resultBlurry:
        return 'Your photo is too blurry. Please hold your device steady and ensure good lighting.';
      case ProfileVerificationService.resultLowQuality:
        return 'Photo quality is too low. Please try again in better lighting.';
      default:
        // For any other unexpected errors, show a generic friendly message
        return 'Verification failed. Please try again or contact support if the issue persists.';
    }
  }
  
  /// Show error dialog with user-friendly message and retry functionality
  void _showErrorDialog(
    BuildContext context, 
    String message, {
    ValueNotifier<VerificationState>? verificationState,
    ValueNotifier<List<LivenessChallenge>>? challengeQueue,
    ValueNotifier<int>? currentChallengeIndex,
    ValueNotifier<bool>? eyesClosedDetected,
    ValueNotifier<int>? holdCounter,
    ValueNotifier<String>? statusMessage,
    ValueNotifier<List<double>>? faceWidthHistory,
    ValueNotifier<bool>? showManualCapture,
    ValueNotifier<String?>? verificationError,
    ValueNotifier<Uint8List?>? capturedImage,
    ValueNotifier<bool>? isVerifying,
    ValueNotifier<bool>? isProcessingFrame,
    ValueNotifier<CameraController?>? cameraController,
    ValueNotifier<FaceDetector?>? faceDetector,
    ValueNotifier<bool>? isCameraInitialized,
    Function? startStepTimer,
    ValueNotifier<Timer?>? challengeTimer,
  }) {
    final displayMessage = message.isEmpty 
      ? 'Verification failed. Please try again or contact support if the issue persists.' 
      : message;
    
    _log('Showing error dialog: $displayMessage');
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => WillPopScope(
        onWillPop: () async {
          Navigator.of(ctx).pop();
          Navigator.of(context).pop(); // Also close verification screen
          return false;
        },
        child: Dialog(
          backgroundColor: kBackgroundBG,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: EdgeInsets.all(getProportionateScreenWidth(24)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: getProportionateScreenWidth(80),
                  height: getProportionateScreenWidth(80),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.error_outline,
                    color: Colors.redAccent,
                    size: getProportionateScreenWidth(50),
                  ),
                ),
                SizedBox(height: getProportionateScreenHeight(20)),
                Text(
                  'Verification Failed',
                  style: TextStyle(
                    fontSize: getProportionateScreenWidth(24),
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                SizedBox(height: getProportionateScreenHeight(16)),
                Container(
                  padding: EdgeInsets.all(getProportionateScreenWidth(14)),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.redAccent.withOpacity(0.4), width: 1.5),
                  ),
                  child: Text(
                    displayMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: getProportionateScreenWidth(16),
                      color: Colors.grey[600],
                      height: 1.6,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(height: getProportionateScreenHeight(24)),
                // Retry Button
                GestureDetector(
                  onTap: () async {
                    Navigator.of(ctx).pop(); // Close dialog
                    debugPrint('🔄 [RETRY] Starting verification retry from error dialog...');
                    
                    // Reset all error states for retry
                    if (verificationState != null) verificationState.value = VerificationState.detectingFace;
                    if (statusMessage != null) statusMessage.value = "Position face in circle";
                    if (currentChallengeIndex != null) currentChallengeIndex.value = 0;
                    if (challengeQueue != null) challengeQueue.value.shuffle();
                    if (faceWidthHistory != null) faceWidthHistory.value.clear();
                    if (holdCounter != null) holdCounter.value = 0;
                    if (eyesClosedDetected != null) eyesClosedDetected.value = false;
                    if (showManualCapture != null) showManualCapture.value = false;
                    if (verificationError != null) verificationError.value = null;
                    if (capturedImage != null) capturedImage.value = null;
                    if (isVerifying != null) isVerifying.value = false;
                    if (isProcessingFrame != null) isProcessingFrame.value = false;
                    if (challengeTimer != null) challengeTimer.value?.cancel();

                    await Future.delayed(const Duration(milliseconds: 300));
                    
                    // Restart image stream on existing camera
                    final controller = cameraController?.value;
                    final detector = faceDetector?.value;
                    if (controller != null && detector != null) {
                      try {
                        debugPrint('📷 [RETRY] Restarting image stream on existing camera...');
                        controller.startImageStream((image) {
                          if (isProcessingFrame != null && !isProcessingFrame.value &&
                              verificationState != null &&
                              verificationState.value != VerificationState.verified &&
                              verificationState.value != VerificationState.failed) {
                            _processFrame(
                              image,
                              detector,
                              verificationState,
                              challengeQueue!,
                              currentChallengeIndex!,
                              eyesClosedDetected!,
                              holdCounter!,
                              statusMessage!,
                              isProcessingFrame,
                              controller,
                              capturedImage!,
                              isVerifying!,
                              verificationError!,
                              context,
                              faceWidthHistory!,
                              cameraController!,
                              showManualCapture!,
                              faceDetector!,
                              startStepTimer ?? () {},
                              challengeTimer!,
                              isCameraInitialized!,
                            );
                          }
                        });
                        debugPrint('✅ [RETRY] Image stream restarted successfully');
                      } catch (e) {
                        debugPrint('❌ [RETRY] Error restarting stream: $e');
                      }
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                      vertical: getProportionateScreenHeight(14),
                    ),
                    decoration: BoxDecoration(
                      gradient: kPrimaryGradient,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        'Try Again',
                        style: TextStyle(
                          fontSize: getProportionateScreenWidth(16),
                          fontWeight: FontWeight.bold,
                          color: kWhite,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: getProportionateScreenHeight(12)),
                // Close Button
                GestureDetector(
                  onTap: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                      vertical: getProportionateScreenHeight(14),
                    ),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      border: Border.all(color: Colors.grey.withOpacity(0.3), width: 1.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        'Close',
                        style: TextStyle(
                          fontSize: getProportionateScreenWidth(16),
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleGenderMismatch(
    BuildContext context,
    String? detectedGender,
    ValueNotifier<VerificationState> verificationState,
    ValueNotifier<List<LivenessChallenge>> challengeQueue,
    ValueNotifier<int> currentChallengeIndex,
    ValueNotifier<bool> eyesClosedDetected,
    ValueNotifier<int> holdCounter,
    ValueNotifier<String> statusMessage,
    ValueNotifier<List<double>> faceWidthHistory,
    ValueNotifier<bool> showManualCapture,
    ValueNotifier<String?> verificationError,
    ValueNotifier<Uint8List?> capturedImage,
    ValueNotifier<bool> isVerifying,
    ValueNotifier<bool> isProcessingFrame,
    ValueNotifier<CameraController?> cameraController,
    ValueNotifier<FaceDetector?> faceDetector,
    ValueNotifier<bool> isCameraInitialized,
    Function startStepTimer,
    ValueNotifier<Timer?> challengeTimer,
  ) async {
    final globals = Globals.of(context);
    final userDetails = globals.prefs.userDetails.value;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null || userDetails == null) {
      Navigator.of(context).pop();
      return;
    }

    int currentRetries = userDetails.verificationRetries ?? 0;
    currentRetries++;

    await FirebaseFirestore.instance.collection('Users').doc(uid).update({
      'verificationRetries': currentRetries,
    });

    userDetails.verificationRetries = currentRetries;
    await globals.prefs.userDetails.set(userDetails);

    if (!context.mounted) return;

    if (currentRetries >= 3) {
      _showContactSupportDialog(context);
    } else {
      _showGenderMismatchDialog(
        context, 
        detectedGender,
        verificationState,
        challengeQueue,
        currentChallengeIndex,
        eyesClosedDetected,
        holdCounter,
        statusMessage,
        faceWidthHistory,
        showManualCapture,
        verificationError,
        capturedImage,
        isVerifying,
        isProcessingFrame,
        cameraController,
        faceDetector,
        isCameraInitialized,
        startStepTimer,
        challengeTimer,
      );
    }
  }

  // --- DIALOGS ---

  void _showGenderMismatchDialog(
    BuildContext context,
    String? detectedGender,
    ValueNotifier<VerificationState> verificationState,
    ValueNotifier<List<LivenessChallenge>> challengeQueue,
    ValueNotifier<int> currentChallengeIndex,
    ValueNotifier<bool> eyesClosedDetected,
    ValueNotifier<int> holdCounter,
    ValueNotifier<String> statusMessage,
    ValueNotifier<List<double>> faceWidthHistory,
    ValueNotifier<bool> showManualCapture,
    ValueNotifier<String?> verificationError,
    ValueNotifier<Uint8List?> capturedImage,
    ValueNotifier<bool> isVerifying,
    ValueNotifier<bool> isProcessingFrame,
    ValueNotifier<CameraController?> cameraController,
    ValueNotifier<FaceDetector?> faceDetector,
    ValueNotifier<bool> isCameraInitialized,
    Function startStepTimer,
    ValueNotifier<Timer?> challengeTimer,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => WillPopScope(
        onWillPop: () async {
          // Handle back button - close dialog and verification screen
          Navigator.of(ctx).pop();
          Navigator.of(context).pop();
          return false;
        },
        child: Dialog(
          backgroundColor: kBackgroundBG,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: EdgeInsets.all(getProportionateScreenWidth(24)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 48),
                ),
              const SizedBox(height: 20),
              Text('Gender Mismatch',
                  style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700, fontSize: 22, color: kPrimaryPurple)),
              const SizedBox(height: 12),
              Text(
                  detectedGender != null
                      ? 'The photo shows a "$detectedGender" face, which doesn\'t match your profile.'
                      : 'The detected gender doesn\'t match your profile.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w500, fontSize: 14, color: Colors.grey[600])),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () async {
                  Navigator.of(ctx).pop();
                  verificationState.value = VerificationState.detectingFace;
                  statusMessage.value = "Position your face in the circle";
                  currentChallengeIndex.value = 0;
                  challengeQueue.value.shuffle();
                  faceWidthHistory.value.clear();
                  holdCounter.value = 0;
                  eyesClosedDetected.value = false;
                  showManualCapture.value = false;
                  verificationError.value = null;
                  capturedImage.value = null;
                  isVerifying.value = false;
                  isProcessingFrame.value = false;

                  await Future.delayed(const Duration(milliseconds: 300));
                  final controller = cameraController.value;
                  final detector = faceDetector.value;
                  if (controller != null && detector != null) {
                    debugPrint('🔄 [GENDER MISMATCH RETRY] Restarting stream on existing camera...');
                    // Start image stream on existing camera (never disposed)
                    controller.startImageStream((image) {
                      if (!isProcessingFrame.value &&
                          verificationState.value != VerificationState.verified &&
                          verificationState.value != VerificationState.failed) {
                        _processFrame(
                          image,
                          detector,
                          verificationState,
                          challengeQueue,
                          currentChallengeIndex,
                          eyesClosedDetected,
                          holdCounter,
                          statusMessage,
                          isProcessingFrame,
                          controller,
                          capturedImage,
                          isVerifying,
                          verificationError,
                          context,
                          faceWidthHistory,
                          cameraController,
                          showManualCapture,
                          faceDetector,
                          startStepTimer,
                          challengeTimer,
                          isCameraInitialized,
                        );
                      }
                    });
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: getProportionateScreenHeight(14)),
                  decoration: BoxDecoration(gradient: kPrimaryGradient, borderRadius: BorderRadius.circular(14)),
                  child: Center(child: Text('Retry Verification', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: kWhite))),
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pushReplacementNamed(
                    ProfileCorrectionScreen.routeName,
                    arguments: detectedGender,
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: getProportionateScreenHeight(14)),
                  decoration: BoxDecoration(
                      color: kSecondaryPurple.withOpacity(0.2),
                      border: Border.all(color: kPrimaryPurple, width: 1.5),
                      borderRadius: BorderRadius.circular(14)),
                  child: Center(child: Text('Update My Profile', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: kPrimaryPurple))),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  void _showContactSupportDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => WillPopScope(
        onWillPop: () async {
          // Handle back button - close both dialogs
          Navigator.of(ctx).pop();
          Navigator.of(context).pop();
          return false;
        },
        child: Dialog(
          backgroundColor: kBackgroundBG,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: EdgeInsets.all(getProportionateScreenWidth(24)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(color: kTertiaryPink.withOpacity(0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.support_agent, color: kTertiaryPink, size: 48),
                ),
                const SizedBox(height: 20),
                Text('Verification Issue',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 22, color: kPrimaryPurple)),
              const SizedBox(height: 12),
              Text('You\'ve reached the maximum verification attempts (3). Our support team can help resolve this issue.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: Colors.grey[600])),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop();
                  Navigator.of(context).pushNamed(SupportScreen.routeName);
                },
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: getProportionateScreenHeight(14)),
                  decoration: BoxDecoration(gradient: kPrimaryGradient, borderRadius: BorderRadius.circular(14)),
                  child: Center(child: Text('Contact Support', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: kWhite))),
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () { Navigator.of(ctx).pop(); Navigator.of(context).pop(); },
                child: Text('Skip for now', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: kSecondaryPurple.withOpacity(0.7), decoration: TextDecoration.underline)),
              ),
            ],
          ),),
        ),
      ),
    );
  }

  void _showSuccessDialog(BuildContext context, int rewardValue, String userGender) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => WillPopScope(
        onWillPop: () async {
          // Handle back button press - close dialog and verification screen
          Navigator.of(ctx).pop();
          Navigator.of(context).popUntil((route) => route.settings.name == Home.routeName || route.isFirst);
          return false;
        },
        child: Dialog(
          backgroundColor: kBackgroundBG,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: EdgeInsets.all(getProportionateScreenWidth(24)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Verified Badge
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: kQuaternaryPink.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.verified,
                    color: kPrimaryPurple,
                  size: 48,
                ),
              ),
              SizedBox(height: getProportionateScreenHeight(20)),
              
              // Title
              Text(
                'Verification Successful!',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w700,
                  fontSize: getProportionateScreenWidth(22),
                  color: kPrimaryPurple,
                ),
              ),
              SizedBox(height: getProportionateScreenHeight(12)),
              
              // Configurable Message with Gender-Specific Rewards
              Text(
                AppConfigService.getSuccessMessage(gender: userGender, rewardValue: rewardValue),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w500,
                  fontSize: getProportionateScreenWidth(14),
                  color: Colors.grey[600],
                ),
              ),
              SizedBox(height: getProportionateScreenHeight(16)),
              
              // Gender-Specific Reward Display
              if (rewardValue > 0)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: getProportionateScreenWidth(20),
                    vertical: getProportionateScreenHeight(12),
                  ),
                  decoration: BoxDecoration(
                    color: kQuaternaryPink.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Dynamic icon based on reward type
                      Icon(
                        _getRewardIcon(userGender),
                        color: _getRewardColor(userGender),
                        size: 28,
                      ),
                      SizedBox(width: getProportionateScreenWidth(8)),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '+${rewardValue} ${AppConfigService.getRewardType(userGender)}',
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontWeight: FontWeight.w700,
                              fontSize: getProportionateScreenWidth(18),
                              color: kPrimaryPurple,
                            ),
                          ),
                          Text(
                            'Reward for verification',
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontWeight: FontWeight.w400,
                              fontSize: getProportionateScreenWidth(12),
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              
              if (rewardValue > 0)
                SizedBox(height: getProportionateScreenHeight(24)),
              
              // Continue Button
              GestureDetector(
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pushNamedAndRemoveUntil(Home.routeName, (route) => false);
                },
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                    vertical: getProportionateScreenHeight(14),
                  ),
                  decoration: BoxDecoration(
                    gradient: kPrimaryGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      AppConfigService.successButtonText,
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w600,
                        fontSize: getProportionateScreenWidth(18),
                        color: kWhite,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }
  
  /// Helper method to get reward icon based on gender/reward type
  IconData _getRewardIcon(String userGender) {
    final rewardType = AppConfigService.getRewardType(userGender).toLowerCase();
    if (rewardType.contains('coin')) return Icons.monetization_on;
    if (rewardType.contains('gem')) return Icons.diamond;
    if (rewardType.contains('premium')) return Icons.card_giftcard;
    return Icons.card_giftcard;
  }
  
  /// Helper method to get reward color based on gender/reward type
  Color _getRewardColor(String userGender) {
    final rewardType = AppConfigService.getRewardType(userGender).toLowerCase();
    if (rewardType.contains('coin')) return Colors.amber;
    if (rewardType.contains('gem')) return const Color(0xFF00CED1);
    if (rewardType.contains('premium')) return kTertiaryPink;
    return kTertiaryPink;
  }

  // --- MATH & UTILS ---

  bool _isFaceNeutral(Face face) {
    // Relaxed thresholds
    final isSmiling = (face.smilingProbability ?? 0) > 0.6;
    final isRotated = (face.headEulerAngleY ?? 0).abs() > 20;
    return !isSmiling && !isRotated;
  }

  // double _calculateStdDev(List<double> values) {
  //   if (values.isEmpty) return 0.0;
  //   final mean = values.reduce((a, b) => a + b) / values.length;
  //   final variance = values.map((v) => pow(v - mean, 2)).reduce((a, b) => a + b) / values.length;
  //   return sqrt(variance);
  // }

  InputImage? _convertCameraImage(CameraImage image, CameraController controller) {
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      if (Platform.isAndroid && format != InputImageFormat.nv21) return null;
    }

    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: _concatenatePlanes(image.planes),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: _getRotation(controller.description.sensorOrientation),
        format: format ?? InputImageFormat.nv21,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Uint8List _concatenatePlanes(List<Plane> planes) {
    final WriteBuffer allBytes = WriteBuffer();
    for (var plane in planes) {
      allBytes.putUint8List(plane.bytes);
    }
    return allBytes.done().buffer.asUint8List();
  }

  InputImageRotation _getRotation(int sensorOrientation) {
    switch (sensorOrientation) {
      case 0: return InputImageRotation.rotation0deg;
      case 90: return InputImageRotation.rotation90deg;
      case 180: return InputImageRotation.rotation180deg;
      case 270: return InputImageRotation.rotation270deg;
      default: return InputImageRotation.rotation0deg;
    }
  }

  // --- CAMERA PERMISSION DIALOG ---
  
  Future<bool> _showCameraPermissionDialog(BuildContext context, {required bool isPermanentlyDenied}) async {
    // Prevent multiple dialogs from showing simultaneously
    if (!context.mounted) return false;
    
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => WillPopScope(
        onWillPop: () async => false, // Prevent back button from dismissing
        child: Dialog(
          backgroundColor: kBackgroundBG,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: EdgeInsets.all(getProportionateScreenWidth(24)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(color: kTertiaryPink.withOpacity(0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.camera_alt, color: kTertiaryPink, size: 32),
                ),
                const SizedBox(height: 20),
                Text(
                  'Camera Access Required',
                  style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700, fontSize: 22, color: kPrimaryPurple),
                ),
                const SizedBox(height: 12),
                Text(
                  isPermanentlyDenied
                      ? 'Camera access is required for face verification. Please enable it in your device settings to continue.'
                      : 'Viora needs camera access to verify your profile with face liveness detection. This ensures the security and authenticity of all profiles.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w500, fontSize: 14, color: Colors.grey[600]),
                ),
                const SizedBox(height: 24),
                if (isPermanentlyDenied) ...[
                  GestureDetector(
                    onTap: () => Navigator.of(ctx).pop(true),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [kPrimaryPurple, kTertiaryPink]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Open Settings',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w600, fontSize: 16, color: kWhite),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(false),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      border: Border.all(color: kPrimaryPurple.withOpacity(0.3), width: 1.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isPermanentlyDenied ? 'Cancel' : 'Not Now',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: kPrimaryPurple,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ) ?? false;
  }
}

// --- PAINTER ---

class FaceGuidePainter extends CustomPainter {
  final VerificationState state;
  FaceGuidePainter({required this.state});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0;

    if (state == VerificationState.verified || state == VerificationState.transitioning) {
      paint.color = Colors.green;
    } else if (state == VerificationState.waitingForChallenge || state == VerificationState.waitingForNeutral) {
      paint.color = kTertiaryPink;
    } else {
      paint.color = Colors.white54;
    }

    final center = Offset(size.width / 2, size.height / 2 - 50);
    final radius = size.width * 0.42;

    canvas.drawCircle(center, radius, paint);
    
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromCircle(center: center, radius: radius))
      ..fillType = PathFillType.evenOdd;
      
    canvas.drawPath(path, Paint()..color = const Color(0xFFE8DCC8).withOpacity(0.4));
  }

  @override
  bool shouldRepaint(FaceGuidePainter oldDelegate) => oldDelegate.state != state;
}