import 'package:flutter/material.dart';

class CustomHomeHeader extends StatelessWidget {
  const CustomHomeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: HeaderClipper(),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.42,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF064E3B), Color(0xFF065F46)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
      ),
    );
  }
}

class HeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    // نبدأ من النقطة صفر وصفر (أعلى اليسار)
    path.lineTo(0, size.height - 80);

    // رسم المنحنى: النقطة الأولى هي "نقطة التحكم" في منتصف الشاشة، والنقطة الثانية هي نهاية المنحنى
    path.quadraticBezierTo(
      size.width / 2, // في منتصف العرض
      size.height, // أقصى الارتفاع (رأس المنحنى)
      size.width, // نهاية العرض (يمين الشاشة)
      size.height - 80,
    );

    path.lineTo(size.width, 0); // نطلع لأعلى اليمين
    path.close(); // نقفل الشكل
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
