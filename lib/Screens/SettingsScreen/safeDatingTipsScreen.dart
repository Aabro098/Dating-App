import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:viora/constants.dart';

/// Safe Dating Tips Screen
/// Data is BE configurable - fetches HTML content from Firestore
/// Firestore path: Admins/admins field: 'safeDatingTips'
class SafeDatingTipsScreen extends StatefulWidget {
  @override
  _SafeDatingTipsScreenState createState() => _SafeDatingTipsScreenState();
}

class _SafeDatingTipsScreenState extends State<SafeDatingTipsScreen> {
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
        if (data.containsKey('safeDatingTips') &&
            data['safeDatingTips'] != null &&
            (data['safeDatingTips'] as String).isNotEmpty) {
          contentHtml = data['safeDatingTips'];
        } else {
          contentHtml = _defaultSafeDatingTipsHtml;
        }
      } else {
        contentHtml = _defaultSafeDatingTipsHtml;
      }
    } catch (e) {
      debugPrint('Error fetching safe dating tips: $e');
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
          "Safe Dating Tips",
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

const String _defaultSafeDatingTipsHtml = """
<div style="font-family: Nunito; padding: 8px;">
  <h3 style="color: #3E1E68;">Stay Safe While Dating</h3>
  
  <p><strong>1. Protect Your Personal Information</strong></p>
  <p>Never share your home address, financial details, or workplace location with someone you've just met online. Keep your personal details private until you're comfortable.</p>
  
  <p><strong>2. Meet in Public Places</strong></p>
  <p>Always meet in public places for the first few dates. Choose well-lit, populated locations like cafes or restaurants.</p>
  
  <p><strong>3. Tell Someone Your Plans</strong></p>
  <p>Inform a friend or family member about your plans. Share your live location and let them know when you expect to be back.</p>
  
  <p><strong>4. Trust Your Instincts</strong></p>
  <p>If something feels off or uncomfortable, don't hesitate to end the conversation or leave the date. Your safety always comes first.</p>
  
  <p><strong>5. Arrange Your Own Transport</strong></p>
  <p>Drive yourself, take a cab, or use public transport. Avoid getting into someone's car until you know them well.</p>
  
  <p><strong>6. Stay Sober</strong></p>
  <p>Keep your wits about you — avoid excessive drinking on early dates.</p>
  
  <p><strong>7. Video Chat First</strong></p>
  <p>Before meeting in person, try a video call to confirm the person matches their profile.</p>
  
  <p><strong>8. Report Suspicious Behavior</strong></p>
  <p>If someone is making you uncomfortable, harassing you, or behaving inappropriately, report them immediately through the app.</p>
</div>
""";
