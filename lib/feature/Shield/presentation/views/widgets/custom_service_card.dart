import 'package:flutter/material.dart';

class CustomServiceCard extends StatelessWidget {
  final String title;
  final String desc;
  final IconData icon;
  final bool isActive;
  final bool isWarning;

  const CustomServiceCard({
    super.key,
    required this.title,
    required this.desc,
    required this.icon,
    required this.isActive,
    this.isWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isWarning && !isActive ? const Color(0xFFFFEBEE) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            // ignore: deprecated_member_use
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildIconBox(),
          const SizedBox(width: 15),
          Expanded(child: _buildTextContent()),
          Switch.adaptive(
            value: isActive,
            onChanged: (val) {},
            // ignore: deprecated_member_use
            activeColor: const Color(0xFF10B981),
          ),
        ],
      ),
    );
  }

  Widget _buildIconBox() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: (isWarning ? Colors.red : const Color(0xFF10B981)).withOpacity(
          0.1,
        ),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Icon(
        icon,
        color: isWarning ? Colors.red[700] : const Color(0xFF064E3B),
        size: 26,
      ),
    );
  }

  Widget _buildTextContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: Color(0xFF1F2937),
          ),
        ),
        const SizedBox(height: 2),
        Text(desc, style: TextStyle(color: Colors.grey[600], fontSize: 11)),
      ],
    );
  }
}
