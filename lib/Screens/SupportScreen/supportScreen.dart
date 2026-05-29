import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ui_firestore/firebase_ui_firestore.dart';
import 'package:iconsax/iconsax.dart';
import 'package:viora/Screens/Home/homeScreen.dart';
import 'package:viora/Screens/MessagesScreen/components/text_message.dart';
import 'package:viora/Services/ChatService.dart';
import 'package:viora/Services/ImageUploadService.dart';
import 'package:viora/Services/NotificationService.dart';
import 'package:viora/Services/UserProvider.dart';
import 'package:viora/components/title_message_list.dart';
import 'package:viora/models/ChatRoom.dart';
import 'package:viora/models/SupportModels.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:viora/utils/constatnts/colors.dart';

import '../../constants.dart';
import '../../size_config.dart';

class SupportScreen extends StatefulWidget {
  static String routeName = "/supportScreen";

  final bool canPop;

  const SupportScreen({required this.canPop, super.key});

  @override
  SupportScreenState createState() => SupportScreenState();
}

class SupportScreenState extends State<SupportScreen> {
  @override
  void initState() {
    super.initState();
    isLoading = true;
    checkRoom();
  }

  ChatRoom? chatRoom;
  late bool isLoading;
  bool hasError = false;
  TextEditingController messageCtr = TextEditingController();

  // State variables for automated support flow
  bool showCategories = true;
  bool showQuestions = false;
  bool showChat = false;
  bool showChatHistory = false;
  SupportCategory? selectedCategory;
  SupportQuestion? selectedQuestion;
  bool awaitingResolution = false;

  List<SupportCategory> categories = [];

  Future<void> checkRoom() async {
    try {
      String uid = FirebaseAuth.instance.currentUser!.uid;

      var user2 = uid;
      var user1 = "support";
      var path = user1.codeUnitAt(0) < user2.codeUnitAt(0)
          ? "${user1}_$user2"
          : "${user2}_$user1";

      CollectionReference collectionReference = FirebaseFirestore.instance
          .collection("SupportChatRooms");

      var docSnapshot = await collectionReference.doc(path).get();
      final doc = await FirebaseFirestore.instance
          .collection('AppConfig')
          .doc('SupportConfig')
          .get();

      categories = SupportFaqModel.fromFirestore(doc).categories;

      if (docSnapshot.exists) {
        chatRoom = ChatRoom.fromJson(
          docSnapshot.data() as Map<String, dynamic>,
        );
        if (mounted) {
          setState(() {
            isLoading = false;
            hasError = false;
          });
        }
      } else {
        ChatRoom newChatRoom = ChatRoom(
          blockedBy: '',
          isBlocked: false,
          lastMessage: "",
          lastMessageDate: DateTime.now(),
          users: ["support"],
        );
        await ChatService.addSupportChatRoom(newChatRoom, context);
        if (mounted) {
          await checkRoom();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
          hasError = true;
        });
      }
    }
  }

  void _selectCategory(SupportCategory category) {
    if (mounted) {
      setState(() {
        selectedCategory = category;
        showCategories = false;
        showQuestions = true;
        showChat = false;
      });
    }
  }

  Future<void> updateChatRoomStatus(String status) async {
    if (chatRoom != null) {
      if (chatRoom?.status == 'in-progress' ||
          chatRoom?.status == 'auto-replied') {
        return;
      }
      await FirebaseFirestore.instance
          .collection('SupportChatRooms')
          .doc(chatRoom!.roomId)
          .update({'status': status});
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _selectQuestion(SupportQuestion question) async {
    if (chatRoom == null) return;
    if (chatRoom?.status == 'resolved' || chatRoom?.status == null) {
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(left: 16, right: 16, bottom: 24),
          backgroundColor: Colors.orange,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.white, width: 1),
          ),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "You already have an unresolved issue. The new issue will be merged with the previous one.",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (mounted) {
      setState(() {
        selectedQuestion = question;
        showQuestions = false;
        showChat = true;
      });
    }
    try {
      // Step 1: Send user's selected question as a user message
      await _sendUserQuestion(question);
      await updateChatRoomStatus('new');
      // Small delay so Firestore timestamps are distinct & messages appear in order
      await Future.delayed(Duration(milliseconds: 300));

      // Step 2: Send auto-reply mapped to this question
      await _sendAutoReply(question);
      await updateChatRoomStatus('auto-replied');

      // Step 3: Ask for resolution after a short delay
      await Future.delayed(Duration(seconds: 1));
      if (mounted) {
        await _askForResolution();
      }
    } catch (e) {
      debugPrint("Error in _selectQuestion flow: $e");
    }
  }

  Future<void> _sendUserQuestion(SupportQuestion question) async {
    if (chatRoom == null) return;
    try {
      SupportMessageModel titleMessage = SupportMessageModel(
        seen: false,
        date: DateTime.now(),
        uid: FirebaseAuth.instance.currentUser!.uid,
        text: "New Issue Reported",
        roomId: chatRoom!.roomId,
        messageType: 'title',
      );
      await ChatService.sendSupportMessageEnhanced(titleMessage, context);

      SupportMessageModel userMsg = SupportMessageModel(
        seen: false,
        date: DateTime.now(),
        uid: FirebaseAuth.instance.currentUser!.uid,
        text: question.question,
        roomId: chatRoom!.roomId,
        categoryId: selectedCategory?.id,
        questionId: question.id,
        messageType: 'user',
      );
      await ChatService.sendSupportMessageEnhanced(userMsg, context);

      // Update chatRoom with categoryId if not already present
      if (selectedCategory?.id != null) {
        List<String> updatedCategoryIds = chatRoom!.categoryId ?? [];
        if (!updatedCategoryIds.contains(selectedCategory!.id)) {
          updatedCategoryIds.add(selectedCategory!.id);
          chatRoom!.categoryId = updatedCategoryIds;

          // Update in Firestore
          await FirebaseFirestore.instance
              .collection('SupportChatRooms')
              .doc(chatRoom!.roomId)
              .update({'categoryId': updatedCategoryIds});
        }
      }
    } catch (e) {
      debugPrint("Error sending user question: $e");
    }
  }

  Future<void> _sendAutoReply(SupportQuestion question) async {
    if (chatRoom == null) return;
    try {
      SupportMessageModel autoMessage = SupportMessageModel(
        seen: false,
        date: DateTime.now(),
        uid: 'support',
        text: question.answer,
        roomId: chatRoom!.roomId,
        isAutoReply: true,
        categoryId: selectedCategory?.id,
        questionId: question.id,
        messageType: 'auto',
      );
      await ChatService.sendSupportMessageEnhanced(autoMessage, context);
    } catch (e) {
      debugPrint("Error sending auto-reply: $e");
    }
  }

  Future<void> _askForResolution() async {
    if (chatRoom == null) return;
    try {
      if (mounted) {
        setState(() {
          awaitingResolution = true;
        });
      }

      SupportMessageModel resolutionMessage = SupportMessageModel(
        seen: false,
        date: DateTime.now(),
        uid: 'support',
        text: 'Was your query resolved?',
        roomId: chatRoom!.roomId,
        messageType: 'resolution',
      );
      await ChatService.sendSupportMessageEnhanced(resolutionMessage, context);
    } catch (e) {
      debugPrint("Error sending resolution prompt: $e");
    }
  }

  void _handleResolutionResponse(bool isResolved) async {
    if (chatRoom == null) return;
    setState(() {
      awaitingResolution = false;
    });

    try {
      String responseText = isResolved
          ? 'Yes, my query is resolved. Thank you!'
          : 'No, I need more help.';

      SupportMessageModel userResponse = SupportMessageModel(
        seen: false,
        date: DateTime.now(),
        uid: FirebaseAuth.instance.currentUser!.uid,
        text: responseText,
        roomId: chatRoom!.roomId,
        isResolved: isResolved,
        messageType: 'user',
      );
      await ChatService.sendSupportMessageEnhanced(userResponse, context);
      await Future.delayed(Duration(milliseconds: 300));
      if (isResolved) {
        SupportMessageModel thankYouMessage = SupportMessageModel(
          seen: false,
          date: DateTime.now(),
          uid: 'support',
          text:
              'Thank you for your feedback! If you need any further assistance, feel free to start a new support request.',
          roomId: chatRoom!.roomId,
          messageType: 'auto',
          isAutoReply: true,
        );
        await ChatService.sendSupportMessageEnhanced(thankYouMessage, context);
        await updateChatRoomStatus('resolved');

        SupportMessageModel titleMessage = SupportMessageModel(
          seen: false,
          date: DateTime.now(),
          uid: FirebaseAuth.instance.currentUser!.uid,
          text: "Issue ${selectedQuestion?.question} resolved",
          roomId: chatRoom!.roomId,
          categoryId: selectedCategory?.id,
          questionId: selectedQuestion?.id,
          messageType: 'title',
        );
        await ChatService.sendSupportMessageEnhanced(titleMessage, context);
        if (mounted) _resetToCategories();
      } else {
        SupportMessageModel customMessagePrompt = SupportMessageModel(
          seen: false,
          date: DateTime.now(),
          uid: 'support',
          text:
              'Please describe your issue in detail, and our support team will assist you as soon as possible.',
          roomId: chatRoom!.roomId,
          messageType: 'auto',
          isAutoReply: true,
        );
        await ChatService.sendSupportMessageEnhanced(
          customMessagePrompt,
          context,
        );
      }
    } catch (e) {
      debugPrint("Error handling resolution response: $e");
    }
  }

  void _resetToCategories() {
    setState(() {
      showCategories = true;
      showQuestions = false;
      showChat = false;
      showChatHistory = false;
      selectedCategory = null;
      selectedQuestion = null;
      awaitingResolution = false;
    });
  }

  void _openChatHistory() {
    setState(() {
      showCategories = false;
      showQuestions = false;
      showChat = false;
      showChatHistory = true;
      awaitingResolution = false;
    });
  }

  /// Handles image upload logic - delegates to business logic and repository
  void _handleImageUpload(BuildContext context, ChatRoom chatRoom) {
    ImageUploadService.sendMultipleSupportImages(
      context,
      chatRoom.roomId,
      Provider.of<UserProvider>(context, listen: false).userDetails,
      selectedCategory?.id,
      selectedQuestion?.id,
    );
    return;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (showQuestions) {
          if (mounted) {
            _resetToCategories();
          }
          return;
        } else if (showChat || showChatHistory) {
          _resetToCategories();
          return;
        } else {
          if (widget.canPop == true) {
            Navigator.of(context).pop();
          }
          showSupportScreenValue.value = false;
        }
      },
      child: Scaffold(
        backgroundColor: kBackgroundBG,
        // appBar: PreferredSize(
        //   preferredSize: Size.fromHeight(getProportionateScreenHeight(70)),
        //   child: CustomAppBar(title: "Support"),
        // ),
        body: isLoading
            ? Center(child: CircularProgressIndicator())
            : hasError
            ? _buildErrorView()
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: getProportionateScreenHeight(44)),
                  // Title
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: getProportionateScreenWidth(8),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () {
                            if (showQuestions) {
                              if (mounted) {
                                _resetToCategories();
                              }
                              return;
                            } else if (showChat || showChatHistory) {
                              _resetToCategories();
                              return;
                            } else {
                              if (widget.canPop == true) {
                                Navigator.of(context).pop();
                              }
                              showSupportScreenValue.value = false;
                            }
                          },
                          icon: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: kPrimaryColor,
                            size: 24,
                          ),
                        ),
                        SizedBox(width: getProportionateScreenWidth(4)),
                        Text(
                          'Support',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: getProportionateScreenWidth(34),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: getProportionateScreenHeight(4)),
                  if (showCategories) _buildCategoriesView(),
                  if (showQuestions) _buildQuestionsView(),
                  if (showChat) _buildChatView(),
                  if (showChatHistory) _buildChatHistoryView(),
                ],
              ),
      ),
    );
  }

  // ─── Error / Retry view ───
  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(getProportionateScreenWidth(24)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded, color: Colors.grey[400], size: 64),
            SizedBox(height: getProportionateScreenHeight(16)),
            Text(
              "Unable to connect to support.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: getProportionateScreenWidth(16),
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: getProportionateScreenHeight(8)),
            Text(
              "Please check your connection and try again.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: getProportionateScreenWidth(14),
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: getProportionateScreenHeight(24)),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  isLoading = true;
                  hasError = false;
                });
                checkRoom();
              },
              icon: Icon(Icons.refresh, color: Colors.white),
              label: Text("Retry", style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                padding: EdgeInsets.symmetric(
                  horizontal: getProportionateScreenWidth(32),
                  vertical: getProportionateScreenHeight(12),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Categories (home) view ───
  Widget _buildCategoriesView() {
    return Expanded(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(getProportionateScreenWidth(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Welcome header
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: getProportionateScreenWidth(16),
                  vertical: getProportionateScreenHeight(12),
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      kPrimaryColor.withAlpha(30),
                      kPrimaryColor.withAlpha(10),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Need help?',
                      style: TextStyle(
                        fontSize: getProportionateScreenWidth(24),
                        fontWeight: FontWeight.bold,
                        color: kPrimaryColor,
                      ),
                    ),
                    SizedBox(height: getProportionateScreenHeight(6)),
                    Text(
                      'Choose a topic or start a chat',
                      style: TextStyle(
                        fontSize: getProportionateScreenWidth(14),
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: getProportionateScreenHeight(12)),
              // Section title
              Text(
                'How can we help you?',
                style: TextStyle(
                  fontSize: getProportionateScreenWidth(17),
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: getProportionateScreenHeight(12)),
              // Category grid — 3 rows x 2 columns
              GridView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: getProportionateScreenWidth(12),
                  mainAxisSpacing: getProportionateScreenHeight(12),
                  childAspectRatio: 1.3,
                ),
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  return _buildCategoryCard(categories[index]);
                },
              ),
              SizedBox(height: getProportionateScreenHeight(12)),
              // View Chat History button
              GestureDetector(
                onTap: _openChatHistory,
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                    horizontal: getProportionateScreenWidth(16),
                    vertical: getProportionateScreenHeight(12),
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: kPrimaryColor.withAlpha(51),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(16),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: kPrimaryColor.withAlpha(25),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.history_rounded,
                          color: kPrimaryColor,
                          size: 22,
                        ),
                      ),
                      SizedBox(width: getProportionateScreenWidth(14)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Chat History',
                              style: TextStyle(
                                fontSize: getProportionateScreenWidth(15),
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'View your previous conversations with support',
                              style: TextStyle(
                                fontSize: getProportionateScreenWidth(12),
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: kPrimaryColor,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),

              SizedBox(height: getProportionateScreenHeight(16)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryCard(SupportCategory category) {
    return GestureDetector(
      onTap: () => _selectCategory(category),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kPrimaryColor.withOpacity(0.15), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              category.icon,
              style: TextStyle(fontSize: getProportionateScreenWidth(34)),
            ),
            SizedBox(height: getProportionateScreenHeight(8)),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: getProportionateScreenWidth(8),
              ),
              child: Text(
                category.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: getProportionateScreenWidth(12),
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Sub-questions list ───
  Widget _buildQuestionsView() {
    return Expanded(
      child: Column(
        children: [
          // Header with back button
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: getProportionateScreenWidth(8),
              vertical: getProportionateScreenHeight(12),
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // IconButton(
                //   icon: Icon(
                //     Icons.arrow_back_ios_new_rounded,
                //     color: kPrimaryColor,
                //     size: 20,
                //   ),
                //   onPressed: _resetToCategories,
                // ),
                SizedBox(width: getProportionateScreenWidth(16)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectedCategory?.title ?? '',
                        style: TextStyle(
                          fontSize: getProportionateScreenWidth(17),
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Select your question',
                        style: TextStyle(
                          fontSize: getProportionateScreenWidth(13),
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Questions list
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.all(getProportionateScreenWidth(16)),
              itemCount: selectedCategory?.questions.length ?? 0,
              itemBuilder: (context, index) {
                final question = selectedCategory!.questions[index];
                return _buildQuestionCard(question);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(SupportQuestion question) {
    return GestureDetector(
      onTap: () => _selectQuestion(question),
      child: Container(
        margin: EdgeInsets.only(bottom: getProportionateScreenHeight(10)),
        padding: EdgeInsets.all(getProportionateScreenWidth(16)),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kPrimaryColor.withOpacity(0.15), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                question.question,
                style: TextStyle(
                  fontSize: getProportionateScreenWidth(14),
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ),
            SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: getProportionateScreenWidth(14),
              color: kPrimaryColor,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Chat view (after selecting a question) ───
  Widget _buildChatView() {
    return Expanded(
      child: Column(
        children: [
          // Header
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: getProportionateScreenWidth(8),
              vertical: getProportionateScreenHeight(12),
            ),
            decoration: BoxDecoration(
              color: kBackgroundBG,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // IconButton(
                //   icon: Icon(
                //     Icons.arrow_back_ios_new_rounded,
                //     color: kPrimaryColor,
                //     size: 20,
                //   ),
                //   onPressed: () {
                //     setState(() {
                //       showChat = false;
                //       showQuestions = true;
                //       awaitingResolution = false;
                //     });
                //   },
                // ),
                SizedBox(width: getProportionateScreenWidth(16)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectedCategory?.title ?? 'Support',
                        style: TextStyle(
                          fontSize: getProportionateScreenWidth(15),
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        selectedQuestion?.question ?? '',
                        style: TextStyle(
                          fontSize: getProportionateScreenWidth(11),
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Home button to go back to categories
                // IconButton(
                //   icon: Icon(
                //     Icons.home_outlined,
                //     color: kPrimaryColor,
                //     size: 22,
                //   ),
                //   onPressed: _resetToCategories,
                //   tooltip: 'Back to topics',
                // ),
              ],
            ),
          ),

          // Chat messages
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: kDefaultPadding),
              child: GestureDetector(
                onTap: () => FocusScope.of(context).requestFocus(FocusNode()),
                child: FirestoreListView(
                  itemBuilder: (context, documentSnapshots) {
                    final data = documentSnapshots.data();
                    final message = SupportMessageModel.fromJson(data);

                    if (message.messageType.toLowerCase() == 'title') {
                      if (message.text == "New Issue Reported") {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(height: getProportionateScreenHeight(36)),
                            TitleMessageList(message: message.text),
                          ],
                        );
                      }
                      return TitleMessageList(message: message.text);
                    }

                    // Show resolution buttons for the latest resolution message
                    if (message.messageType == 'resolution' &&
                        awaitingResolution) {
                      return Column(
                        children: [
                          SupportMessageWidget(
                            docId: documentSnapshots.id,
                            message: message,
                          ),
                          SizedBox(height: getProportionateScreenHeight(12)),
                          _buildResolutionButtons(),
                        ],
                      );
                    }

                    return SupportMessageWidget(
                      docId: documentSnapshots.id,
                      message: message,
                    );
                  },
                  query: FirebaseFirestore.instance
                      .collection('SupportMessages')
                      .where("roomId", isEqualTo: chatRoom!.roomId)
                      .orderBy('date', descending: true),
                  reverse: true,
                  emptyBuilder: (context) {
                    return Center(child: Text("Send a message for support"));
                  },
                  errorBuilder: (context, error, stackTrace) {
                    debugPrint("FirestoreListView error: $error");
                    return Center(
                      child: Padding(
                        padding: EdgeInsets.all(
                          getProportionateScreenWidth(20),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: Colors.red,
                              size: 40,
                            ),
                            SizedBox(height: 12),
                            Text(
                              "Unable to load messages.\nPlease try again.",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  padding: EdgeInsets.all(getProportionateScreenWidth(5)),
                  shrinkWrap: true,
                  pageSize: 10,
                  loadingBuilder: (context) {
                    return Center(child: CircularProgressIndicator());
                  },
                ),
              ),
            ),
          ),

          // Input area (hide while awaiting resolution)
          if (!awaitingResolution) _buildMessageInput(),
        ],
      ),
    );
  }

  // ─── Chat History view ───
  Widget _buildChatHistoryView() {
    return Expanded(
      child: Column(
        children: [
          // Header
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: getProportionateScreenWidth(8),
              vertical: getProportionateScreenHeight(12),
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // IconButton(
                //   icon: Icon(
                //     Icons.arrow_back_ios_new_rounded,
                //     color: kPrimaryColor,
                //     size: 20,
                //   ),
                //   onPressed: _resetToCategories,
                // ),
                SizedBox(width: getProportionateScreenWidth(16)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chat History',
                        style: TextStyle(
                          fontSize: getProportionateScreenWidth(16),
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        'Your previous support conversations',
                        style: TextStyle(
                          fontSize: getProportionateScreenWidth(11),
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // All messages
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: kDefaultPadding),
              child: GestureDetector(
                onTap: () => FocusScope.of(context).requestFocus(FocusNode()),
                child: FirestoreListView(
                  itemBuilder: (context, documentSnapshots) {
                    final data = documentSnapshots.data();
                    final message = SupportMessageModel.fromJson(data);

                    if (message.messageType.toLowerCase() == 'title') {
                      if (message.text == "New Issue Reported") {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(height: getProportionateScreenHeight(42)),
                            TitleMessageList(message: message.text),
                          ],
                        );
                      }
                      return TitleMessageList(message: message.text);
                    }

                    return SupportMessageWidget(
                      docId: documentSnapshots.id,
                      message: message,
                    );
                  },
                  query: FirebaseFirestore.instance
                      .collection('SupportMessages')
                      .where("roomId", isEqualTo: chatRoom!.roomId)
                      .orderBy('date', descending: true),
                  reverse: true,
                  emptyBuilder: (context) {
                    return Center(
                      child: Padding(
                        padding: EdgeInsets.all(
                          getProportionateScreenWidth(24),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              color: Colors.grey[300],
                              size: 56,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'No conversations yet',
                              style: TextStyle(
                                fontSize: getProportionateScreenWidth(16),
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[500],
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Your support chat history will appear here once you start a conversation.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: getProportionateScreenWidth(13),
                                color: Colors.grey[400],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    debugPrint("Chat history error: $error");
                    return Center(
                      child: Padding(
                        padding: EdgeInsets.all(
                          getProportionateScreenWidth(20),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: Colors.red,
                              size: 40,
                            ),
                            SizedBox(height: 12),
                            Text(
                              "Unable to load chat history.\nPlease try again.",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  padding: EdgeInsets.all(getProportionateScreenWidth(5)),
                  shrinkWrap: true,
                  pageSize: 20,
                  loadingBuilder: (context) {
                    return Center(child: CircularProgressIndicator());
                  },
                ),
              ),
            ),
          ),

          // Message input for continuing the conversation
          _buildMessageInput(),
        ],
      ),
    );
  }

  // ─── Resolution Yes / No buttons ───
  Widget _buildResolutionButtons() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: kDefaultPadding),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: () => _handleResolutionResponse(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: EdgeInsets.symmetric(
                  vertical: getProportionateScreenHeight(12),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Yes, Resolved',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: getProportionateScreenWidth(14),
                ),
              ),
            ),
          ),
          SizedBox(width: getProportionateScreenWidth(12)),
          Expanded(
            child: ElevatedButton(
              onPressed: () => _handleResolutionResponse(false),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                padding: EdgeInsets.symmetric(
                  vertical: getProportionateScreenHeight(12),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'No, Need Help',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: getProportionateScreenWidth(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Message input bar ───
  Widget _buildMessageInput() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        kDefaultPadding,
        kDefaultPadding / 2,
        kDefaultPadding,
        kDefaultPadding + getProportionateScreenHeight(6),
      ),
      decoration: BoxDecoration(
        // color: Theme.of(context).scaffoldBackgroundColor,
        // color: kBackgroundBG,
        boxShadow: [
          BoxShadow(
            offset: Offset(0, -2),
            blurRadius: 12,
            color: Colors.black.withAlpha(16),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: getProportionateScreenHeight(52),
              padding: EdgeInsets.fromLTRB(kDefaultPadding * 0.75, 0, 6, 0),
              decoration: BoxDecoration(
                color: kPrimaryColor.withAlpha(20),
                borderRadius: BorderRadius.circular(40),
              ),
              child: Row(
                children: [
                  SizedBox(width: kDefaultPadding / 4),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: messageCtr,
                            keyboardType: TextInputType.multiline,
                            minLines: 1,
                            maxLines: 5,
                            decoration: InputDecoration(
                              hintText: "Type your message…",
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        _buildImageButton(context, chatRoom!),
                      ],
                    ),
                  ),
                  SizedBox(width: kDefaultPadding / 4),
                ],
              ),
            ),
          ),
          SizedBox(width: 8),
          GestureDetector(
            onTap: () async {
              String messageText = messageCtr.text.trim();
              if (messageText.isEmpty || chatRoom == null) return;
              messageCtr.clear();

              SupportMessageModel message = SupportMessageModel(
                seen: false,
                date: DateTime.now(),
                uid: FirebaseAuth.instance.currentUser!.uid,
                text: messageText,
                roomId: chatRoom!.roomId,
                categoryId: selectedCategory?.id,
                questionId: selectedQuestion?.id,
                messageType: 'user',
                imageUrls: null,
              );

              await ChatService.sendSupportMessageEnhanced(message, context);

              NotificationService.sendAdminNotification(
                "Support Message from ${Provider.of<UserProvider>(context, listen: false).userDetails.name}",
                messageText,
                FirebaseAuth.instance.currentUser!.uid,
              );
            },
            child: Container(
              padding: EdgeInsets.all(getProportionateScreenWidth(12)),
              height: getProportionateScreenWidth(46),
              width: getProportionateScreenWidth(46),
              decoration: BoxDecoration(
                color: kPrimaryColor,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.send, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageButton(BuildContext context, ChatRoom chatRoom) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: () => _handleImageUpload(context, chatRoom),
          child: Container(
            height: getProportionateScreenWidth(40),
            width: getProportionateScreenWidth(40),
            decoration: BoxDecoration(
              color: kPrimaryColor.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: const Icon(Iconsax.gallery5, color: AppColors.purple),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Individual support message bubble ───
class SupportMessageWidget extends StatefulWidget {
  const SupportMessageWidget({
    required this.message,
    this.docId,
    this.isAdmin = false,
  });

  final SupportMessageModel message;
  final String? docId;
  final bool isAdmin;

  @override
  _SupportMessageWidgetState createState() => _SupportMessageWidgetState();
}

class _SupportMessageWidgetState extends State<SupportMessageWidget> {
  @override
  Widget build(BuildContext context) {
    bool isSender =
        widget.message.uid == FirebaseAuth.instance.currentUser!.uid;

    if (!isSender && widget.message.seen == false && widget.docId != null) {
      ChatService.updateSupportSeen(widget.docId!, {"seen": true});
    }

    bool isImageMessage =
        widget.message.text.contains("vioraa.firebasestorage.app") &&
        widget.message.imageUrls != null;

    return Padding(
      padding: EdgeInsets.only(top: kDefaultPadding),
      child: Column(
        crossAxisAlignment: isSender
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isSender
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isSender) ...[
                CircleAvatar(
                  radius: 12,
                  backgroundColor: kPrimaryColor,
                  child: Icon(
                    widget.message.isAutoReply
                        ? Icons.smart_toy
                        : Icons.support_agent,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: kDefaultPadding / 2),
              ],
              Flexible(
                child: Column(
                  crossAxisAlignment: isSender
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: isImageMessage
                          ? null
                          : EdgeInsets.symmetric(
                              horizontal: getProportionateScreenWidth(14),
                              vertical: getProportionateScreenHeight(10),
                            ),
                      decoration: isImageMessage
                          ? null
                          : BoxDecoration(
                              color: isSender
                                  ? kPrimaryColor
                                  : widget.message.isAutoReply
                                  ? Colors.blue.shade50
                                  : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(12),
                              border: widget.message.isAutoReply && !isSender
                                  ? Border.all(color: Colors.blue.shade200)
                                  : null,
                            ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.message.isAutoReply && !isSender) ...[
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.auto_awesome,
                                  size: 12,
                                  color: Colors.blue.shade700,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Auto Reply',
                                  style: TextStyle(
                                    fontSize: getProportionateScreenWidth(10),
                                    color: Colors.blue.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 4),
                          ],
                          if (isImageMessage) ...[
                            BuildImages(
                              images: widget.message.imageUrls ?? [],
                              isSender: isSender,
                              canViewImages: true,
                            ),
                          ] else ...[
                            Text(
                              widget.message.text,
                              style: TextStyle(
                                color: isSender ? Colors.white : Colors.black87,
                                fontSize: getProportionateScreenWidth(13.5),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatTime(widget.message.date),
                          style: TextStyle(
                            fontSize: getProportionateScreenWidth(10),
                            color: Colors.grey,
                          ),
                        ),
                        if (isSender) ...[
                          SizedBox(width: 4),
                          Icon(
                            widget.message.seen ? Icons.done_all : Icons.done,
                            size: 12,
                            color: widget.message.seen
                                ? Colors.blue
                                : Colors.grey,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (isSender) SizedBox(width: kDefaultPadding / 2),
            ],
          ),

          // Admin-only metadata
          if (widget.isAdmin && !isSender) ...[
            Padding(
              padding: EdgeInsets.only(
                left: getProportionateScreenWidth(40),
                top: 4,
              ),
              child: Text(
                'Category: ${widget.message.categoryId ?? "N/A"} | Question: ${widget.message.questionId ?? "N/A"}',
                style: TextStyle(
                  fontSize: getProportionateScreenWidth(10),
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

// class BuildImages extends HookWidget {
//   final List<String> images;
//   final bool isSender;

//   const BuildImages({super.key, required this.images, required this.isSender});

//   @override
//   Widget build(BuildContext context) {
//     if (images.isEmpty) return SizedBox.shrink();
//     final expanded = useState<bool>(false);
//     final displayImages = expanded.value ? images : images.take(4).toList();
//     final remainingCount = expanded.value ? 0 : images.length - 4;

//     return images.length > 1
//         ? SizedBox(
//             width: getProportionateScreenWidth(196),
//             child: GridView.count(
//               crossAxisCount: 2,
//               shrinkWrap: true,
//               physics: NeverScrollableScrollPhysics(),
//               mainAxisSpacing: 4,
//               crossAxisSpacing: 4,
//               childAspectRatio: 1.0,
//               children: List.generate(displayImages.length, (index) {
//                 final imagePath = displayImages[index];
//                 final isLastVisible = index == 3 && remainingCount > 0;
//                 return Stack(
//                   alignment: Alignment.center,
//                   children: [
//                     GestureDetector(
//                       onTap: isLastVisible
//                           ? null
//                           : () {
//                               PersistentNavBarNavigator.pushNewScreen(
//                                 context,
//                                 screen: PhotoView(image: imagePath),
//                                 withNavBar: false,
//                                 pageTransitionAnimation:
//                                     PageTransitionAnimation.cupertino,
//                               );
//                             },
//                       child: ClipRRect(
//                         borderRadius: BorderRadius.circular(12),
//                         child: CachedNetworkImage(
//                           imageUrl: imagePath,
//                           fit: BoxFit.cover,
//                           height: getProportionateScreenHeight(90),
//                           width: getProportionateScreenWidth(90),
//                         ),
//                       ),
//                     ),
//                     if (isLastVisible)
//                       GestureDetector(
//                         onTap: () {
//                           expanded.value = !expanded.value;
//                         },
//                         child: Container(
//                           height: getProportionateScreenHeight(24),
//                           width: getProportionateScreenWidth(72),
//                           decoration: BoxDecoration(
//                             color: Color(0xFF686868).withAlpha(60),
//                             border: Border.all(
//                               color: Colors.white.withAlpha(100),
//                             ),
//                             borderRadius: BorderRadius.circular(6),
//                           ),
//                           alignment: Alignment.center,
//                           clipBehavior: Clip.antiAlias,
//                           child: Text(
//                             '+$remainingCount Images',
//                             style: const TextStyle(
//                               color: Colors.white,
//                               fontSize: 12,
//                               fontWeight: FontWeight.bold,
//                             ),
//                           ),
//                         ),
//                       ),
//                   ],
//                 );
//               }),
//             ),
//           )
//         : GestureDetector(
//             onTap: () {
//               PersistentNavBarNavigator.pushNewScreen(
//                 context,
//                 screen: PhotoView(image: images[0]),
//                 withNavBar: false,
//                 pageTransitionAnimation: PageTransitionAnimation.cupertino,
//               );
//             },
//             child: ClipRRect(
//               borderRadius: BorderRadius.circular(12),
//               child: CachedNetworkImage(
//                 imageUrl: images[0],
//                 width: getProportionateScreenHeight(184),
//                 height: getProportionateScreenHeight(184),
//                 fit: BoxFit.cover,
//                 placeholder: (context, url) => Container(
//                   width: getProportionateScreenHeight(184),
//                   height: getProportionateScreenHeight(184),
//                   color: Colors.grey[300],
//                   child: Center(child: CircularProgressIndicator()),
//                 ),
//                 errorWidget: (context, url, error) => Container(
//                   width: getProportionateScreenHeight(184),
//                   height: getProportionateScreenHeight(184),
//                   color: Colors.grey[300],
//                   child: Icon(Icons.image_not_supported),
//                 ),
//               ),
//             ),
//           );
//   }
// }
