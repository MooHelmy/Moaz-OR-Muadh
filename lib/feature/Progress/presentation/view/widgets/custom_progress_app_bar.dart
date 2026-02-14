// widgets/maadh_progress_header.dart
import 'package:flutter/material.dart';

class CustomProgressAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const CustomProgressAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      elevation: 0,
      backgroundColor:
          Colors.transparent, // شفاف عشان نعتمد على لون خلفية الشاشة
      leading: Padding(
        padding: const EdgeInsets.all(8.0),
        child: CircleAvatar(
          backgroundColor: Colors.white,
          child: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF064E3B),
              size: 18,
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      title: const Text(
        "سجل الانتصارات",
        style: TextStyle(
          color: Color(0xFF064E3B),
          fontWeight: FontWeight.bold,
          fontSize: 18,
          fontFamily: 'Tajawal',
        ),
      ),
      centerTitle: true,
      actions: [
        IconButton(
          icon: const Icon(Icons.share_outlined, color: Color(0xFF064E3B)),
          onPressed: () {
            // هنا ممكن نضيف ميزة مشاركة الإنجاز (بشكل مستتر) لتحفيز الآخرين
          },
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
