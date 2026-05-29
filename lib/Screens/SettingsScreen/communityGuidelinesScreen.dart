import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:viora/constants.dart';

/// Community Guidelines Screen
/// Data is BE configurable - fetches HTML content from Firestore
/// Firestore path: Admins/admins field: 'communityGuidelines'
class CommunityGuidelinesScreen extends StatefulWidget {
  @override
  _CommunityGuidelinesScreenState createState() =>
      _CommunityGuidelinesScreenState();
}

class _CommunityGuidelinesScreenState extends State<CommunityGuidelinesScreen> {
  bool isLoading = true;
  String? contentHtml;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchContent();
  }

  Future<void> _fetchContent() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection("Admins")
          .doc('admins')
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        if (data.containsKey('communityGuidelines') &&
            data['communityGuidelines'] != null &&
            (data['communityGuidelines'] as String).isNotEmpty) {
          contentHtml = data['communityGuidelines'];
        } else {
          contentHtml = _defaultCommunityGuidelinesHtml;
        }
      } else {
        contentHtml = _defaultCommunityGuidelinesHtml;
      }
    } catch (e) {
      debugPrint('Error fetching community guidelines: $e');
      errorMessage = 'Unable to load content. Please try again.';
    }

    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: kPrimaryPurple),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Community Guidelines",
          style: TextStyle(
            color: kPrimaryPurple,
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator(color: kPrimaryPurple))
          : errorMessage != null
              ? _buildErrorState()
              : SingleChildScrollView(
                  physics: BouncingScrollPhysics(),
                  padding: EdgeInsets.all(16),
                  child: Html(data: contentHtml ?? ''),
                ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: kSecondaryColor),
            SizedBox(height: 16),
            Text(
              errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 16,
                color: kSecondaryColor,
              ),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  isLoading = true;
                  errorMessage = null;
                });
                _fetchContent();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryPurple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                "Retry",
                style: TextStyle(
                  fontFamily: 'Nunito',
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const String _defaultCommunityGuidelinesHtml = """
<div style="font-family: Nunito; padding: 8px;">
  <h3 style="color: #3E1E68;">Viora Community Guidelines</h3>
  
  <p>At Viora, we are committed to creating a safe, respectful, and inclusive community for everyone. By using our platform, you agree to follow these guidelines.</p>
  
  <p><strong>1. Be Respectful</strong></p>
  <p>Treat everyone with kindness and respect. Harassment, hate speech, discrimination, or bullying of any kind will not be tolerated.</p>
  
  <p><strong>2. Be Authentic</strong></p>
  <p>Use real photos and accurate information on your profile. Impersonation, catfishing, or using fake identities is strictly prohibited.</p>
  
  <p><strong>3. Keep It Clean</strong></p>
  <p>Do not share explicit, vulgar, or inappropriate content. This includes nudity, sexual content, or graphic imagery.</p>
  
  <p><strong>4. No Spam or Scams</strong></p>
  <p>Do not use Viora for promotional purposes, spamming, or any form of fraud or scam. Commercial solicitation is not allowed.</p>
  
  <p><strong>5. Respect Privacy</strong></p>
  <p>Do not share others' personal information without their consent. Screenshots, recordings, or sharing private conversations is prohibited.</p>
  
  <p><strong>6. No Violence or Threats</strong></p>
  <p>Any form of violence, threats, or intimidation — whether direct or implied — will result in immediate account suspension.</p>
  
  <p><strong>7. Report Violations</strong></p>
  <p>If you encounter behavior that violates these guidelines, please report it immediately. Our team reviews all reports and takes appropriate action.</p>
  
  <p><strong>8. Age Requirement</strong></p>
  <p>You must be at least 18 years old to use Viora. Underage users will be removed immediately.</p>
  
  <p style="color: #E45A92; font-weight: bold;">Violation of these guidelines may result in warnings, temporary suspensions, or permanent bans. Let's keep Viora a safe and welcoming space for all!</p>
</div>
""";
