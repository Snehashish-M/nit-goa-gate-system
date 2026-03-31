import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nit_goa_gate_app/services/user_cache.dart';
import 'student_dashboard.dart';

class AppInfoScreen extends StatefulWidget {
  final bool isFirstTime;

  const AppInfoScreen({super.key, this.isFirstTime = false});

  @override
  State<AppInfoScreen> createState() => _AppInfoScreenState();
}

class _AppInfoScreenState extends State<AppInfoScreen> {
  bool _hasReadInfo = false;

  Future<void> _proceedToDashboard() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .update({"infoAcknowledged": true});

      UserCache().updateCache({"infoAcknowledged": true});
    } catch (e) {
      debugPrint("Error saving info acknowledgement: $e");
    }

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const StudentDashboard()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("How to Use"),
        automaticallyImplyLeading: !widget.isFirstTime,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            const Center(
              child: Icon(Icons.info_outline, size: 60, color: Colors.blueGrey),
            ),
            const SizedBox(height: 10),
            const Center(
              child: Text(
                "App Instructions",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),

            const SizedBox(height: 25),

            _buildSection(
              icon: Icons.qr_code_2,
              title: "Hostel Entry / Exit QR",
              points: [
                "The same QR code is used for both leaving and entering the campus.",
                "Once the QR is scanned a second time (i.e., you have re-entered the campus), the QR automatically disappears.",
                "If you generate a QR by mistake, don't worry — all hostel and day scholar QR codes are automatically cleared at 12:00 AM every night.",
                "Alternatively, you can scan the QR twice at the main gate to remove an unwanted QR and generate a new one.",
              ],
            ),

            const Divider(height: 30),

            _buildSection(
              icon: Icons.description,
              title: "Leave Application",
              points: [
                "Submit a leave application through the Leave Application option. It will be sent to your hostel warden for approval.",
                "You can check the status of your leave application in the Leave Application Status section.",
                "Once your leave is approved, a QR code will be generated that you can use to leave and re-enter the campus.",
              ],
            ),

            const Divider(height: 30),

            _buildSection(
              icon: Icons.warning_amber,
              title: "Important — Leave QR",
              points: [
                "Delete an approved leave QR only if you no longer wish to go on leave despite having an approved application.",
                "Do NOT delete the QR if you have already left the campus using it — you will need it to re-enter.",
              ],
            ),

            const Divider(height: 30),

            _buildSection(
              icon: Icons.date_range,
              title: "Leave Extension",
              points: [
                "If you need to extend your leave, use the 'Apply for Extension' option available on your approved leave QR card.",
                "The extension request will be sent to the warden. You can track its status in the Leave Application Status section.",
                "If approved, the return date will be updated automatically. The same QR code remains valid.",
              ],
            ),

            const Divider(height: 30),

            _buildSection(
              icon: Icons.cancel_outlined,
              title: "Rejected Applications",
              points: [
                "If your leave application is rejected, the reason (if provided by the warden) will be displayed in the leave details.",
                "Rejected applications are automatically removed after 2 days.",
              ],
            ),

            if (widget.isFirstTime) ...[
              const SizedBox(height: 30),
              const Divider(height: 30),

              CheckboxListTile(
                value: _hasReadInfo,
                onChanged: (value) {
                  setState(() {
                    _hasReadInfo = value ?? false;
                  });
                },
                title: const Text(
                  "I have read and understood the above instructions",
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                activeColor: Colors.green,
              ),

              const SizedBox(height: 15),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _hasReadInfo ? _proceedToDashboard : null,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text(
                    "Proceed to Dashboard",
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  static Widget _buildSection({
    required IconData icon,
    required String title,
    required List<String> points,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 24, color: Colors.blueGrey),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...points.map((point) => Padding(
          padding: const EdgeInsets.only(left: 10, bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("• ", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Expanded(
                child: Text(
                  point,
                  style: const TextStyle(fontSize: 14, height: 1.4),
                ),
              ),
            ],
          ),
        )),
      ],
    );
  }
}
