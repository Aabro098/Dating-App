import 'package:flutter/material.dart';

import '../constants.dart';



class OutlineBtn extends StatefulWidget {
  final String btnText;
  OutlineBtn({required this.btnText});

  @override
  _OutlineBtnState createState() => _OutlineBtnState();
}

class _OutlineBtnState extends State<OutlineBtn> {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          border: Border.all(
            // color: Color(0xFFB40284A),
              color: kPrimaryColor,
              width: 2
          ),
          borderRadius: BorderRadius.circular(50)
      ),
      padding: EdgeInsets.all(15),
      child: Center(
        child: Text(
          widget.btnText,
          style: TextStyle(
            //color: Color(0xFFB40284A),
              color: kPrimaryColor,
              fontSize: 16
          ),
        ),
      ),
    );
  }
}
