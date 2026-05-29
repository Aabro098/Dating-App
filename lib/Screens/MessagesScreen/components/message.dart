import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:viora/models/Message.dart';
import '../../../constants.dart';
import 'text_message.dart';
import 'package:viora/Services/ChatService.dart';

class Message extends StatefulWidget {
  const Message({
    super.key,
    required this.message,
    required this.picUrl,
    required this.docId,
    required this.gender,
  });

  final MessageModel message;
  final String picUrl;
  final String docId;
  final String gender;

  @override
  MessageState createState() => MessageState();
}

class MessageState extends State<Message> {
  @override
  Widget build(BuildContext context) {
    bool isSender = widget.message.uid == FirebaseAuth.instance.currentUser!.uid
        ? true
        : false;
    if (widget.message.uid != FirebaseAuth.instance.currentUser!.uid &&
        widget.message.seen == false) {
      ChatService.updateSeen(widget.docId, {"seen": true});
    }

    return widget.message.text.contains("vioraa.firebasestorage.app") &&
            DateTime.now().difference(widget.message.date) > Duration(hours: 24)
        ? SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: kDefaultPadding),
            child: Row(
              mainAxisAlignment: isSender
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              children: [
                // if (!isSender) ...[
                //   CircleAvatar(
                //     radius: 12,
                //     backgroundImage: NetworkImage(widget.picUrl),
                //   ),
                //   SizedBox(width: kDefaultPadding / 2),
                // ],
                TextMessage(
                  message: widget.message.text,
                  isSender: isSender,
                  time: widget.message.date,
                  isSeen: widget.message.seen,
                  imagePath: widget.message.imagePath,
                  gender: widget.gender,
                ),
              ],
            ),
          );
  }
}
