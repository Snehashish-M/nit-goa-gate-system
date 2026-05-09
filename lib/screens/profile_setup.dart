import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nit_goa_gate_app/services/user_cache.dart';
import 'student_dashboard.dart';
import 'app_info_screen.dart';

class ProfileSetup extends StatefulWidget {
  final bool isFirstTime;

  const ProfileSetup({super.key, this.isFirstTime = false});

  @override
  State<ProfileSetup> createState() => _ProfileSetupState();
}

class _ProfileSetupState extends State<ProfileSetup> {

  // Read-only fields (auto-filled from Google account + email)
  String _name = "";
  String _rollNumber = "";

  // Dropdown options
  static const List<String> _degreeOptions = ['B.Tech', 'M.Tech', 'Ph.D', 'JRF'];
  static const List<String> _hostelOptions = ['Talpona Hostel', 'Terekhol Hostel', 'Day Scholar'];

  // Editable fields
  String? _selectedDegree;
  String? _selectedHostel;
  final roomController = TextEditingController();
  final phoneController = TextEditingController();

  Uint8List? _imageBytes;
  String? existingPhotoBase64;
  String _photoStatus = "";

  final picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  @override
  void dispose() {
    roomController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  Future loadProfile() async {
    // Try cache first, fallback to Firestore
    var data = UserCache().profileData;

    if (data == null) {
      data = await UserCache().loadProfile();
    }

    if (data != null) {
      User? user = FirebaseAuth.instance.currentUser;

      _name = data["name"] ?? user?.displayName ?? "";
      _rollNumber = data["rollNumber"] ?? "";

      String degree = data["degree"] ?? "";
      String hostel = data["hostel"] ?? "";
      _selectedDegree = _degreeOptions.contains(degree) ? degree : null;
      _selectedHostel = _hostelOptions.contains(hostel) ? hostel : null;
      roomController.text = data["roomNumber"] ?? "";
      phoneController.text = data["phone"] ?? "";

      existingPhotoBase64 = data["photo"];

      setState(() {});
    }
  }

  Future pickImage() async {

    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 500,
      maxHeight: 500,
      imageQuality: 85,
    );

    if (picked != null) {
      Uint8List? bytes;

      if (kIsWeb) {
        // Web: skip cropper (not supported), read bytes directly
        try {
          bytes = await picked.readAsBytes();
        } catch (e) {
          debugPrint("Error reading image on web: $e");
          setState(() {
            _photoStatus = "Error reading image. Please try again. ✗";
          });
          return;
        }
      } else {
        // Mobile: use cropper
        final croppedFile = await ImageCropper().cropImage(
          sourcePath: picked.path,
          aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
          compressQuality: 85,
          maxWidth: 500,
          maxHeight: 500,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Crop Photo',
              toolbarColor: const Color(0xFF0D1B2A),
              toolbarWidgetColor: Colors.white,
              activeControlsWidgetColor: const Color(0xFF1976D2),
              initAspectRatio: CropAspectRatioPreset.square,
              lockAspectRatio: false,
            ),
          ],
        );

        if (croppedFile == null) return;
        bytes = await croppedFile.readAsBytes();
      }

      final sizeKB = bytes.length / 1024;

      // Web images can be larger since compression isn't applied by image_picker
      final maxSizeKB = kIsWeb ? 500.0 : 100.0;

      if (sizeKB > maxSizeKB) {
        setState(() {
          _photoStatus = kIsWeb
              ? "Photo too large (${sizeKB.toStringAsFixed(1)}KB). Max ${maxSizeKB.toInt()}KB. Try a smaller image. ✗"
              : "Photo too large (${sizeKB.toStringAsFixed(1)}KB). Max ${maxSizeKB.toInt()}KB. ✗";
        });
        return;
      }

      setState(() {
        _imageBytes = bytes;
        _photoStatus = "Photo selected ✓ (${sizeKB.toStringAsFixed(1)}KB)";
      });

    }
  }

  Uint8List? _getDisplayBytes() {
    if (_imageBytes != null) return _imageBytes;
    if (existingPhotoBase64 != null && existingPhotoBase64!.isNotEmpty) {
      try {
        return base64Decode(existingPhotoBase64!);
      } catch (e) {
        debugPrint("Error decoding photo: $e");
        return null;
      }
    }
    return null;
  }

  Future saveProfile() async {

    User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      debugPrint("ERROR: No user found");
      return;
    }

    bool isDayScholar = _selectedHostel == 'Day Scholar';

    if (_selectedDegree == null ||
        _selectedHostel == null ||
        (!isDayScholar && roomController.text.isEmpty) ||
        phoneController.text.isEmpty) {

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all required fields")),
      );
      return;
    }

    // Require photo on first-time setup
    if (widget.isFirstTime && _imageBytes == null && (existingPhotoBase64 == null || existingPhotoBase64!.isEmpty)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please upload your photo")),
      );
      return;
    }

    // Validate phone number is exactly 10 digits
    String phone = phoneController.text.trim();
    if (!RegExp(r'^\d{10}$').hasMatch(phone)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Phone number must be exactly 10 digits")),
      );
      return;
    }

    if (!mounted) return;

    BuildContext? dialogContext;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogContext = ctx;
        return const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text("Saving profile..."),
            ],
          ),
        );
      },
    );

    try {
      String photoBase64 = existingPhotoBase64 ?? "";

      if (_imageBytes != null) {
        photoBase64 = base64Encode(_imageBytes!);
      }

      Map<String, dynamic> profileData = {
        "degree": _selectedDegree,
        "hostel": _selectedHostel,
        "roomNumber": roomController.text,
        "phone": phoneController.text.trim(),
        "photo": photoBase64,
      };

      await FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .set(profileData, SetOptions(merge: true));

      // Update the cache so other screens see the new data immediately
      UserCache().updateCache(profileData);

      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              photoBase64.isNotEmpty
                  ? "Profile saved with photo ✓"
                  : "Profile saved (no photo)",
            ),
          ),
        );
      }

      if (widget.isFirstTime && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const AppInfoScreen(isFirstTime: true),
          ),
        );
      } else if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("Error saving profile: $e");

      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${e.toString()}")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {

    final displayBytes = _getDisplayBytes();

    return Scaffold(

      appBar: AppBar(
        title: const Text("Edit Profile"),
      ),

      body: Padding(
        padding: const EdgeInsets.all(20),

        child: ListView(
          children: [

            if (widget.isFirstTime)
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1976D2)),
                ),
                child: const Text(
                  "Complete your profile to access the student portal. Name and Roll Number are auto-filled from your college email.",
                  style: TextStyle(
                    color: Color(0xFF1976D2),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

            if (widget.isFirstTime)
              const SizedBox(height: 20),

            // Photo preview
            Center(
              child: Stack(
                children: [
                  GestureDetector(
                    onTap: displayBytes != null
                        ? () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => Scaffold(
                                  backgroundColor: Colors.black,
                                  appBar: AppBar(
                                    backgroundColor: Colors.black,
                                    foregroundColor: Colors.white,
                                    title: const Text("Profile Picture"),
                                  ),
                                  body: Center(
                                    child: InteractiveViewer(
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxHeight: MediaQuery.of(context).size.height * 0.5,
                                        ),
                                        child: Image.memory(
                                          displayBytes,
                                          fit: BoxFit.contain,
                                          width: double.infinity,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }
                        : null,
                    child: CircleAvatar(
                      radius: 55,
                      backgroundColor: Colors.grey[300],
                      backgroundImage: displayBytes != null
                          ? MemoryImage(displayBytes)
                          : null,
                      child: displayBytes == null
                          ? const Icon(Icons.person, size: 50, color: Colors.grey)
                          : null,
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: pickImage,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 30),
                child: Text(
                  "This photo will be viewed by the warden. Please upload a clear photo where your face is visible.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),

            if (_photoStatus.isNotEmpty)
              Center(
                child: Text(
                  _photoStatus,
                  style: TextStyle(
                    color: _photoStatus.contains("✗")
                        ? Colors.red
                        : Colors.green,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),

            const SizedBox(height: 20),

            // Read-only: Name (from Google account)
            TextField(
              controller: TextEditingController(text: _name),
              decoration: const InputDecoration(
                labelText: "Name",
                suffixIcon: Icon(Icons.lock_outline, size: 18),
              ),
              enabled: false,
            ),

            const SizedBox(height: 15),

            // Read-only: Roll Number (from email prefix)
            TextField(
              controller: TextEditingController(text: _rollNumber),
              decoration: const InputDecoration(
                labelText: "Roll Number",
                suffixIcon: Icon(Icons.lock_outline, size: 18),
              ),
              enabled: false,
            ),

            const SizedBox(height: 15),

            DropdownButtonFormField<String>(
              value: _selectedDegree,
              decoration: const InputDecoration(
                labelText: "Degree",
                prefixIcon: Icon(Icons.school),
              ),
              items: _degreeOptions.map((degree) {
                return DropdownMenuItem(
                  value: degree,
                  child: Text(degree),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedDegree = value;
                });
              },
            ),

            const SizedBox(height: 15),

            DropdownButtonFormField<String>(
              value: _selectedHostel,
              decoration: const InputDecoration(
                labelText: "Hostel Name",
                prefixIcon: Icon(Icons.apartment),
              ),
              items: _hostelOptions.map((hostel) {
                return DropdownMenuItem(
                  value: hostel,
                  child: Text(hostel),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedHostel = value;
                });
              },
            ),

            const SizedBox(height: 15),

            TextField(
              controller: roomController,
              decoration: const InputDecoration(
                labelText: "Room Number",
                prefixIcon: Icon(Icons.door_front_door),
              ),
            ),

            const SizedBox(height: 15),

            TextField(
              controller: phoneController,
              decoration: const InputDecoration(
                labelText: "Phone Number",
                hintText: "10-digit number",
                prefixIcon: Icon(Icons.phone),
              ),
              keyboardType: TextInputType.phone,
              maxLength: 10,
            ),

            const SizedBox(height: 30),

            ElevatedButton.icon(
              onPressed: saveProfile,
              icon: const Icon(Icons.save),
              label: const Text("Save Profile"),
            ),

          ],
        ),
      ),
    );
  }
}