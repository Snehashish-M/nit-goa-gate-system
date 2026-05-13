import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nit_goa_gate_app/services/user_cache.dart';

class DayScholar extends StatefulWidget {
  const DayScholar({super.key});

  @override
  State<DayScholar> createState() => _DayScholarState();
}

class _DayScholarState extends State<DayScholar> {

  final placeController = TextEditingController();

  Map<String, dynamic>? userData;

  String? qrData;
  bool _isLoading = false;
  StreamSubscription? _passListener;

  // SharedPreferences keys for day scholar pass
  static const _keyPassId = 'day_scholar_pass_id';
  static const _keyCreatedAt = 'day_scholar_pass_created_at';

  @override
  void initState() {
    super.initState();
    // Use cached profile — no Firestore read
    userData = UserCache().profileData;
    if (userData == null) {
      // Fallback: load from Firestore if cache is empty
      _loadFromFirestore();
    }
    _loadPass();
  }

  @override
  void dispose() {
    _passListener?.cancel();
    placeController.dispose();
    super.dispose();
  }

  Future _loadFromFirestore() async {
    var data = await UserCache().loadProfile();
    if (mounted) {
      setState(() {
        userData = data;
      });
    }
  }

  /// Load pass — first from local cache (instant), then verify with Firebase
  Future _loadPass() async {
    // Step 1: Show QR instantly from local cache
    final prefs = await SharedPreferences.getInstance();
    String? cachedPassId = prefs.getString(_keyPassId);
    int? cachedCreatedAt = prefs.getInt(_keyCreatedAt);

    if (cachedPassId != null && cachedCreatedAt != null) {
      // Midnight check — clear expired passes locally
      var createdDate = DateTime.fromMillisecondsSinceEpoch(cachedCreatedAt);
      var now = DateTime.now();
      var todayMidnight = DateTime(now.year, now.month, now.day);

      if (createdDate.isBefore(todayMidnight)) {
        // Pass expired — clear local cache
        await _clearLocalCache();
      } else {
        // Pass is valid — show it immediately
        if (mounted) {
          setState(() {
            qrData = cachedPassId;
          });
        }
        // Start watching for Firebase deletion
        _watchPass(cachedPassId);
      }
    }

    // Step 2: Verify with Firebase in background (if internet available)
    _verifyWithFirebase();
  }

  /// Background verification with Firebase
  Future _verifyWithFirebase() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      var snapshot = await FirebaseFirestore.instance
          .collection("gate_passes")
          .where("studentId", isEqualTo: user.uid)
          .where("type", isEqualTo: "day_scholar")
          .where("status", isEqualTo: "active")
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty && mounted) {
        var doc = snapshot.docs.first;
        // Delete passes from previous days — clears at midnight
        var createdAt = doc["createdAt"] as Timestamp?;
        if (createdAt != null) {
          var now = DateTime.now();
          var todayMidnight = DateTime(now.year, now.month, now.day);
          if (createdAt.toDate().isBefore(todayMidnight)) {
            doc.reference.delete();
            await _clearLocalCache();
            return;
          }
        }
        // Firebase confirms pass exists — update local if needed
        if (qrData != doc.id) {
          await _saveToLocalCache(doc.id, doc["createdAt"] as Timestamp);
          if (mounted) {
            setState(() {
              qrData = doc.id;
            });
          }
        }
        _watchPass(doc.id);
      } else if (snapshot.docs.isEmpty && qrData != null) {
        // Firebase says no pass exists — clear local cache
        await _clearLocalCache();
        if (mounted) {
          setState(() {
            qrData = null;
          });
        }
      }
    } catch (e) {
      // Network error — local cache keeps QR visible, which is fine
      debugPrint("Firebase verify error (using local cache): $e");
    }
  }

  /// Save pass ID to local cache
  Future _saveToLocalCache(String passId, Timestamp createdAt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPassId, passId);
    await prefs.setInt(_keyCreatedAt, createdAt.toDate().millisecondsSinceEpoch);
  }

  /// Clear local cache
  Future _clearLocalCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPassId);
    await prefs.remove(_keyCreatedAt);
  }

  Future generateQR() async {

    if (userData == null) return;

    // Prevent generating a new QR if one is already active
    if (qrData != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You already have an active QR code.")),
      );
      return;
    }

    // Validate place field
    if (placeController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter where you are coming from")),
      );
      return;
    }

    User? user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      DocumentReference passRef =
          FirebaseFirestore.instance.collection("gate_passes").doc();

      Timestamp now = Timestamp.now();

      await passRef.set({

        "studentId": user.uid,

        "name": userData!["name"],
        "rollNumber": userData!["rollNumber"],
        "degree": userData!["degree"],
        "phone": userData!["phone"],

        "comingFrom": placeController.text,

        "type": "day_scholar",

        "status": "active",

        "scanCount": 0,

        "createdAt": now

      });

      // Save to local cache
      await _saveToLocalCache(passRef.id, now);

      setState(() {
        qrData = passRef.id;
        _isLoading = false;
      });

      _watchPass(passRef.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("QR Code generated successfully")),
        );
      }
    } catch (e) {
      debugPrint("Error generating QR: $e");
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${e.toString()}")),
        );
      }
    }

  }

  /// Watches the gate pass document — if it gets deleted, hide the QR
  void _watchPass(String passId) {
    _passListener?.cancel();
    _passListener = FirebaseFirestore.instance
        .collection("gate_passes")
        .doc(passId)
        .snapshots()
        .listen((snapshot) async {
      if (!snapshot.exists && mounted) {
        await _clearLocalCache();
        setState(() {
          qrData = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Gate pass used. QR code removed.")),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: const Text("Day Scholar Portal"),
      ),

      body: userData == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20),

              child: ListView(
                children: [

                  TextField(
                    controller: placeController,
                    decoration: const InputDecoration(
                      labelText: "Place you are coming from",
                      prefixIcon: Icon(Icons.place),
                    ),
                  ),

                  const SizedBox(height: 30),

                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : generateQR,
                    icon: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.qr_code),
                    label: const Text("Generate QR"),
                  ),

                  const SizedBox(height: 40),

                  if (qrData != null)
                    Center(
                      child: QrImageView(
                        data: qrData!,
                        size: 250,
                        embeddedImage: const AssetImage('assets/images/logo.png'),
                        embeddedImageStyle: const QrEmbeddedImageStyle(
                          size: Size(40, 40),
                        ),
                      ),
                    ),

                ],
              ),
            ),
    );
  }
}
