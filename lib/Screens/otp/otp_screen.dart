import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:viora/Services/PhoneAuthService.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:sms_autofill/sms_autofill.dart';
import 'package:viora/constants.dart';
import 'package:viora/Services/Global.dart';
import '../../size_config.dart';

class OtpScreen extends HookWidget {
  final String phone;

  const OtpScreen({super.key, required this.phone});

  static String routeName = "/otp";
  static const Color greyText = Color(0xFF919191);
  static const int OTP_EXPIRATION_SECONDS = 15 * 60; // 15 minutes

  // Helper to format seconds into mm:ss
  String _formatTime(int totalSeconds) {
    int minutes = totalSeconds ~/ 60;
    int seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final globals = Globals.of(context);
    
    // Ensure system UI is visible on OTP screen
    useEffect(() {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
      return null;
    }, []);
    
    // OTP state
    final otpController = useTextEditingController();
    final otpFocus = useFocusNode();
    final isVerifying = useState(false);
    final otpError = useState<String?>(null);
    final otpValue = useState('');
    final isPasteProcessing = useState(false);
    final lastAutoVerifiedOtp = useState<String?>(null); // Track last auto-verified OTP

    // Resend OTP timer
    final resendEnabled = useState(false);
    final resendCountdown = useState(30);

    // Session Expiration Timer (15 minutes)
    final sessionExpirationSeconds = useState(OTP_EXPIRATION_SECONDS);
    final otpStartTime = useState<int>(0);

    // Initialize or retrieve OTP start time
    useEffect(() {
      Future<void> initializeTimer() async {
        final savedStartTime = globals.prefs.otpStartTime.value;
        final currentTime = DateTime.now().millisecondsSinceEpoch;
        
        if (savedStartTime > 0) {
          final elapsedSeconds = ((currentTime - savedStartTime) / 1000).floor();
          final remainingSeconds = OTP_EXPIRATION_SECONDS - elapsedSeconds;
          
          if (remainingSeconds <= 0) {
            if (context.mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Session expired. Please try again.")),
              );
            }
            return;
          }
          
          sessionExpirationSeconds.value = remainingSeconds;
          otpStartTime.value = savedStartTime;
        } else {
          await globals.prefs.otpStartTime.set(currentTime);
          otpStartTime.value = currentTime;
          sessionExpirationSeconds.value = OTP_EXPIRATION_SECONDS;
        }
      }
      initializeTimer();
      return null;
    }, []);

    // Clear OTP start time when screen is disposed
    useEffect(() {
      return () {
        debugPrint('🔒 OTP Screen disposed - session kept alive for reuse');
        globals.prefs.otpStartTime.set(0);
      };
    }, []);

    // App Lifecycle Observer
    useEffect(() {
      void handleAppLifecycle(AppLifecycleState state) {
        if (state == AppLifecycleState.resumed) {
          final savedStartTime = otpStartTime.value;
          if (savedStartTime > 0) {
            final currentTime = DateTime.now().millisecondsSinceEpoch;
            final elapsedSeconds = ((currentTime - savedStartTime) / 1000).floor();
            final remainingSeconds = OTP_EXPIRATION_SECONDS - elapsedSeconds;
            
            if (remainingSeconds <= 0) {
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Session expired. Please try again.")),
                );
              }
            } else {
              sessionExpirationSeconds.value = remainingSeconds;
            }
          }
        }
      }

      final observer = _AppLifecycleObserver(handleAppLifecycle);
      WidgetsBinding.instance.addObserver(observer);
      return () => WidgetsBinding.instance.removeObserver(observer);
    }, [otpStartTime.value]);

    // SMART PASTE DETECTION - Single field approach
    final previousLength = useState(0);
    
    useEffect(() {
      void smartPasteListener() {
        final currentText = otpController.text;
        final prevLength = previousLength.value;
        
        // Extract digits only
        final digitsOnly = currentText.replaceAll(RegExp(r'[^0-9]'), '');
        final currentLength = digitsOnly.length;
        final lengthJump = currentLength - prevLength;
        
        debugPrint('📝 OTP changed: "$digitsOnly" (prev: $prevLength, now: $currentLength, jump: $lengthJump)');
        
        // PASTE DETECTED: Jump of 3+ digits (too fast to type normally)
        final isPaste = lengthJump >= 3;
        
        if (isPaste && digitsOnly.isNotEmpty) {
          debugPrint('📋 PASTE DETECTED! Extracting 6-digit OTP from: "$digitsOnly"');
          isPasteProcessing.value = true;
          
          String finalOtp = '';
          
          // Extract exactly 6 digits
          if (digitsOnly.length >= 6) {
            // For long pastes like "Your OTP is 123456", take last 6 digits
            if (digitsOnly.length >= 7) {
              finalOtp = digitsOnly.substring(digitsOnly.length - 6);
            } else {
              finalOtp = digitsOnly.substring(0, 6);
            }
          } else {
            finalOtp = digitsOnly;
          }
          
          debugPrint('✅ Extracted OTP: "$finalOtp" - Replacing field');
          
          // Replace entire field with just the 6-digit OTP
          SchedulerBinding.instance.addPostFrameCallback((_) {
            otpController.value = TextEditingValue(
              text: finalOtp,
              selection: TextSelection.collapsed(offset: finalOtp.length),
            );
            otpValue.value = finalOtp;
            previousLength.value = finalOtp.length;
            
            // Auto-verify if complete
            Future.delayed(const Duration(milliseconds: 150), () {
              isPasteProcessing.value = false;
              
              if (finalOtp.length == 6 && !isVerifying.value && lastAutoVerifiedOtp.value != finalOtp) {
                debugPrint('🚀 Auto-verifying PASTED OTP');
                lastAutoVerifiedOtp.value = finalOtp;
                if (context.mounted) {
                  _verifyOtp(context, finalOtp, isVerifying, otpError);
                }
              }
            });
          });
          return;
        }
        
        // NORMAL TYPING: Restrict display to 6 digits max
        if (digitsOnly.length > 6) {
          final limited = digitsOnly.substring(0, 6);
          otpController.value = TextEditingValue(
            text: limited,
            selection: TextSelection.collapsed(offset: limited.length),
          );
          otpValue.value = limited;
          previousLength.value = limited.length;
        } else if (currentText != digitsOnly) {
          // Filter out non-digits
          otpController.value = TextEditingValue(
            text: digitsOnly,
            selection: TextSelection.collapsed(offset: digitsOnly.length),
          );
          otpValue.value = digitsOnly;
          previousLength.value = digitsOnly.length;
        } else {
          otpValue.value = digitsOnly;
          previousLength.value = digitsOnly.length;
          
          // Auto-verify when typed to 6 digits (only if OTP changed)
          if (digitsOnly.length == 6 && !isVerifying.value && !isPasteProcessing.value && lastAutoVerifiedOtp.value != digitsOnly) {
            debugPrint('🚀 Auto-verifying TYPED OTP: $digitsOnly');
            lastAutoVerifiedOtp.value = digitsOnly;
            Future.delayed(const Duration(milliseconds: 300), () {
              if (context.mounted && !isVerifying.value) {
                _verifyOtp(context, digitsOnly, isVerifying, otpError);
              }
            });
          }
        }
      }
      
      otpController.addListener(smartPasteListener);
      return () => otpController.removeListener(smartPasteListener);
    }, []);

    // Resend Timer Logic
    useEffect(() {
      Timer? timer;
      if (!resendEnabled.value && resendCountdown.value > 0) {
        timer = Timer.periodic(const Duration(seconds: 1), (timerInstance) {
          resendCountdown.value--;
          if (resendCountdown.value <= 0) {
            resendCountdown.value = 0;
            resendEnabled.value = true;
            timerInstance.cancel();
          }
        });
      }
      return () => timer?.cancel();
    }, [resendEnabled.value]);

    // Session Timer Logic
    useEffect(() {
      final timer = Timer.periodic(const Duration(seconds: 1), (timerInstance) {
        if (sessionExpirationSeconds.value > 0) {
          final savedStartTime = otpStartTime.value;
          if (savedStartTime > 0) {
            final currentTime = DateTime.now().millisecondsSinceEpoch;
            final elapsedSeconds = ((currentTime - savedStartTime) / 1000).floor();
            final remainingSeconds = OTP_EXPIRATION_SECONDS - elapsedSeconds;
            
            if (remainingSeconds <= 0) {
              timerInstance.cancel();
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Session expired. Please try again.")),
                );
              }
            } else {
              sessionExpirationSeconds.value = remainingSeconds;
            }
          } else {
            sessionExpirationSeconds.value--;
          }
        } else {
          timerInstance.cancel();
        }
      });
      return () => timer.cancel();
    }, [otpStartTime.value]);

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          debugPrint('⬅️ User backed out - session kept alive for reuse (60s)');
        }
      },
      child: Scaffold(
        backgroundColor: kBackgroundBG,
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.translucent,
          child: SafeArea(
            child: Stack(
              children: [
                _buildBackgroundDecorations(),
                Column(
                  children: [
                    _buildBackButton(context),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            SizedBox(height: getProportionateScreenHeight(25)),
                            _buildVerifyProfileTitle(),
                            const SizedBox(height: 4),
                            _buildInstructionText(),
                            SizedBox(height: getProportionateScreenHeight(50)),
                            
                            // Input Box with smart paste detection
                            _buildOtpInputWithBoxes(
                              otpController,
                              otpFocus,
                              isVerifying.value,
                              otpValue.value,
                              context,
                              isVerifying,
                              otpError,
                              isPasteProcessing,
                            ),
                            
                            const SizedBox(height: 12),
                            
                            // Resend Link
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 26),
                              child: Row(
                                children: [
                                  _buildResendLink(
                                    context,
                                    resendEnabled.value,
                                    resendCountdown.value,
                                    () async {
                                      resendEnabled.value = false;
                                      resendCountdown.value = 30;
                                      final newStartTime = DateTime.now().millisecondsSinceEpoch;
                                      await globals.prefs.otpStartTime.set(newStartTime);
                                      otpStartTime.value = newStartTime;
                                      sessionExpirationSeconds.value = OTP_EXPIRATION_SECONDS;
                                      _handleResend(context, phone, PhoneAuth.authenticatedCountryCode ?? '+91');
                                    },
                                  ),
                                ],
                              ),
                            ),
                            
                            // Expiration Text
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0, left: 26),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  "Code expires in ${_formatTime(sessionExpirationSeconds.value)}",
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 13,
                                    fontFamily: 'Nunito',
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            
                            if (otpError.value != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Text(
                                  otpError.value!,
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    
                    // Verify Button
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: getProportionateScreenWidth(35),
                        vertical: getProportionateScreenHeight(20),
                      ),
                      child: GestureDetector(
                        onTap: isVerifying.value
                            ? null
                            : () {
                                if (otpValue.value.length == 6) {
                                  _verifyOtp(context, otpValue.value, isVerifying, otpError);
                                } else {
                                  otpError.value = 'Please enter 6-digit OTP';
                                }
                              },
                        child: Container(
                          width: double.infinity,
                          height: getProportionateScreenHeight(51),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [kPrimaryPurple, kTertiaryPink],
                              stops: [0.0312, 2.9414],
                              transform: GradientRotation(93.81 * 3.14159265 / 180),
                            ),
                            borderRadius: BorderRadius.circular(getProportionateScreenWidth(14)),
                          ),
                          child: const Center(
                            child: Text(
                              'Verify',
                              style: TextStyle(
                                fontFamily: 'Nunito',
                                fontWeight: FontWeight.w600,
                                fontSize: 20,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (isVerifying.value) _buildLoadingOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- UI Helpers ---

  Widget _buildBackgroundDecorations() {
    return Stack(
      children: [
        Positioned(
          left: -230,
          top: 40,
          child: Image.asset(
            'assets/icon/viora_transparent.png',
            width: 500,
            height: 500,
            fit: BoxFit.contain,
          ),
        ),
        Positioned(
          right: -310,
          top: -250,
          child: Transform.scale(
            scaleX: -1,
            child: Image.asset(
              'assets/icon/viora_transparent.png',
              width: 680,
              height: 650,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBackButton(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 8, top: 18),
        child: GestureDetector(
          onTap: () {
            debugPrint('⬅️ Back button pressed - session kept alive for reuse');
            Navigator.pop(context);
          },
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            child: const Icon(Icons.arrow_back, color: kPrimaryPurple, size: 24),
          ),
        ),
      ),
    );
  }

  Widget _buildVerifyProfileTitle() {
    return const Text(
      'Verify OTP',
      style: TextStyle(
        fontFamily: 'Nunito',
        fontWeight: FontWeight.w700,
        fontSize: 42,
        height: 65 / 48,
        color: Colors.black,
      ),
    );
  }

  Widget _buildInstructionText() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 55),
      child: Text(
        "Type the OTP we've sent on your mobile no.",
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Nunito',
          fontWeight: FontWeight.w500,
          fontSize: 18,
          height: 25 / 18,
          color: greyText,
        ),
      ),
    );
  }

  Widget _buildOtpInputWithBoxes(
    TextEditingController controller,
    FocusNode focusNode,
    bool isLoading,
    String currentValue,
    BuildContext context,
    ValueNotifier<bool> isVerifying,
    ValueNotifier<String?> otpError,
    ValueNotifier<bool> isPasteProcessing,
  ) {
    // Extract only digits and limit display to 6
    final displayValue = currentValue.replaceAll(RegExp(r'[^0-9]'), '');
    final displayDigits = displayValue.length > 6 ? displayValue.substring(0, 6) : displayValue;
    final cursorPosition = displayDigits.length; // Cursor is after last digit
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GestureDetector(
        onTap: () {
          // Focus the hidden field when boxes are tapped
          if (!focusNode.hasFocus) {
            focusNode.requestFocus();
          }
        },
        child: Stack(
          children: [
            // Hidden TextField that accepts up to 20 characters for paste detection
            // Positioned to show cursor in third box area
            Padding(
              padding: const EdgeInsets.only(left: 150), // Position cursor in 3rd box
              child: SizedBox(
                height: 60,
                width: 100,
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: !isLoading,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  maxLength: 20, // Allow long pastes
                  style: const TextStyle(
                    color: Colors.transparent, // Invisible text
                    fontSize: 1,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    counterText: '',
                    contentPadding: EdgeInsets.zero,
                  ),
                  cursorColor: kPrimaryPurple, // Visible cursor
                  cursorWidth: 2,
                  showCursor: true, // Show system cursor
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  onSubmitted: (code) {
                    final digits = code.replaceAll(RegExp(r'[^0-9]'), '');
                    if (digits.length >= 6 && !isVerifying.value) {
                      final otp = digits.substring(0, 6);
                      _verifyOtp(context, otp, isVerifying, otpError);
                    }
                  },
                ),
              ),
            ),
            
            // Visual OTP boxes overlay
            IgnorePointer(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (index) {
                  final hasDigit = index < displayDigits.length;
                  final digit = hasDigit ? displayDigits[index] : '';
                  final isActive = index == cursorPosition && focusNode.hasFocus;
                  
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 50,
                    height: 60,
                    decoration: BoxDecoration(
                      color: hasDigit 
                          ? kPrimaryPurple // Filled = purple
                          : kPrimaryPurple.withOpacity(0.1), // Unfilled = light
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isActive
                            ? kPrimaryPurple // Active cursor = purple border
                            : hasDigit 
                                ? kPrimaryPurple 
                                : kPrimaryPurple.withOpacity(0.3),
                        width: isActive ? 2.5 : 2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        digit,
                        style: const TextStyle(
                          fontFamily: 'Nunito',
                          fontWeight: FontWeight.w600,
                          fontSize: 32,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
  //  _ _ _ _ _ _
  //  | | | | | |
  //  _ _ _ _ _ _
  //  _ _ _ _ _ _
  //  _ _ _ _ _ _
  //  _ _ _ _ _ _
  //  _ _ _ _ _ _
  //  _ _ _ _ _ _
  Widget _buildResendLink(
    BuildContext context,
    bool enabled,
    int countdown,
    VoidCallback onResend,
  ) {
    return GestureDetector(
      onTap: enabled ? onResend : null,
      child: Text(
        enabled ? 'Resend OTP' : 'Resend OTP in ${countdown}s',
        style: TextStyle(
          fontFamily: 'Nunito',
          fontWeight: FontWeight.w600,
          fontSize: 16,
          height: 22 / 16,
          color: enabled ? kPrimaryPurple : Colors.grey,
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.3),
      child: const Center(
        child: CircularProgressIndicator(color: kPrimaryPurple),
      ),
    );
  }

  Future<void> _verifyOtp(
    BuildContext context,
    String otp,
    ValueNotifier<bool> isVerifying,
    ValueNotifier<String?> otpError,
  ) async {
    if (otp.isEmpty) {
      otpError.value = 'Please enter OTP';
      return;
    }
    if (otp.length != 6) {
      otpError.value = 'OTP must be 6 digits';
      return;
    }
    isVerifying.value = true;
    otpError.value = null;

    try {
      final success = await PhoneAuth.submitOtp(context, otp);
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("Firebase user is null after OTP");

      await user.reload();
      await user.getIdToken(true);
      if (!context.mounted) return;

      if (success) {
        debugPrint('✅ OTP verified successfully');
      } else {
        otpError.value = 'Invalid OTP. Please try again.';
      }
    } catch (e) {
      debugPrint('❌ OTP verification error: $e');
      if (context.mounted) {
        otpError.value = 'Failed to verify OTP. Please try again.';
      }
    } finally {
      if (context.mounted) isVerifying.value = false;
    }
  }

  Future<void> _handleResend(BuildContext context, String phone, String countryCode) async {
    try {
      debugPrint('📞 Resending OTP to: $countryCode $phone');
      
      final success = await PhoneAuth.verifyPhoneNumber(
        context,
        phone,
        countryCode: countryCode,
        resend: true,
      );
      if (!context.mounted) return;
      
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            content: Text('OTP resent successfully')),
        );
      } else {
        debugPrint('❌ Failed to resend OTP');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text('Failed to resend OTP')),
        );
      }
    } catch (e) {
      debugPrint('❌ Resend OTP error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }


class _AppLifecycleObserver extends WidgetsBindingObserver {
  final Function(AppLifecycleState) onStateChanged;

  _AppLifecycleObserver(this.onStateChanged);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onStateChanged(state);
  }
}