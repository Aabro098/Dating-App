import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:flutter/material.dart';
class PurchaseApi {
  // static const _apiKey = "zIjkQxKxiPEiVQwTESyczyJvdTNTEGVi";
  static const _apiKey = "goog_fJbYxKAfTbyycozJpXjBZiPsWPD";

  static Future init() async {
   await Purchases.setDebugLogsEnabled(false);
    await Purchases.setup(_apiKey,appUserId: FirebaseAuth.instance.currentUser!.uid);
  }

  static Future<List<Offering>> fetchOffersByIds(var ids) async {
    final offers = await fetchOffers();

    return offers.where((offer) => ids.contains(offer.identifier)).toList();
  }

  static Future<List<Offering>> fetchOffers() async {
    try {
      final offerings = await Purchases.getOfferings();
      return offerings.all.values.toList();
    } on PlatformException {
      return [];
    }
  }

static Future<bool> purchasePackage(Package package) async {
  try{
    await Purchases.purchasePackage(package);
      return true;
    }
    catch (e){
    print(e.toString());
    var errorCode = PurchasesErrorHelper.getErrorCode(e as PlatformException);
    if (errorCode == PurchasesErrorCode.paymentPendingError) {
      showSimpleNotification(
        Text("Your payment is pending"),
         leading: CircularProgressIndicator(backgroundColor: Colors.black,),
        background: Colors.redAccent,
        position: NotificationPosition.bottom,
        slideDismiss: true,
        duration: Duration(seconds: 10),
        subtitle: Text("If money is Deducted wait for payment to reflect to us or send us Support message\nSwipe to dismiss")
      );

    }
    return false;
    }
  }
}
