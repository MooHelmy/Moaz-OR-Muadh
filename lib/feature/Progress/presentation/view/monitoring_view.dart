// ignore_for_file: deprecated_member_use

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MonitoringView extends ConsumerWidget {
  const MonitoringView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: const Text(
          'مركز المراقبة',
          style: TextStyle(
            color: Color(0xFF064E3B),
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Status Card — حالة الحماية النشطة
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.shield_rounded, color: Colors.green, size: 45),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('الدرع الذكي نشط',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1F2937))),
                    Text('يتم فحص 15 مجلد بشكل فوري',
                        style:
                            TextStyle(color: Colors.grey[600], fontSize: 13)),
                  ],
                ),
              ],
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text('سجل المحذوفات التلقائي',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF374151))),
            ),
          ),

          // سجل المحذوفات المباشر من Firebase
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('deleted_files')
                  .orderBy('deletedAt', descending: true)
                  .limit(50)
                  .snapshots(),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  debugPrint('Firestore Stream Error: ${snap.error}');
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.cloud_off,
                            size: 50, color: Colors.grey),
                        const SizedBox(height: 10),
                        const Text(
                          'خطأ في الاتصال بالخادم. يرجى التحقق من اتصال الإنترنت.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                        // Note: As MonitoringView is a StatelessWidget, a retry button
                        // would require more complex state management (e.g., Riverpod provider for retry).
                      ],
                    ),
                  );
                }
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return const Center(
                    child: Text('لا يوجد محتوى محذوف حتى الآن'),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: snap.data!.docs.length,
                  itemBuilder: (_, i) {
                    final doc =
                        snap.data!.docs[i].data() as Map<String, dynamic>;
                    return Card(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15)),
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: const CircleAvatar(
                            backgroundColor: Color(0xFFFFEBEE),
                            child: Icon(Icons.delete_sweep_rounded,
                                color: Colors.redAccent)),
                        title: Text(doc['fileName'] ?? 'ملف غير معروف',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        subtitle:
                            Text('المصدر: ${doc['source'] ?? 'غير محدد'}'),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
