import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:nit_goa_gate_app/services/user_cache.dart';

class LeaveApplication extends StatefulWidget {
  const LeaveApplication({super.key});

  @override
  State<LeaveApplication> createState() => _LeaveApplicationState();
}

class _LeaveApplicationState extends State<LeaveApplication> {

  Map<String, dynamic>? userData;

  // Dropdown options
  static const List<String> _floorOptions = ['G Floor', '1 Floor', '2 Floor', '3 Floor', '4 Floor'];
  String? _selectedFloor;

  final transportController = TextEditingController();
  final purposeController = TextEditingController();
  final addressController = TextEditingController();
  final parentPhoneController = TextEditingController();

  DateTime? leavingDate;
  DateTime? returnDate;

  TimeOfDay? leavingTime;
  TimeOfDay? returnTime;

  int durationDays = 0;

  @override
  void initState() {
    super.initState();
    // Use cached profile — no Firestore read
    userData = UserCache().profileData;
    if (userData == null) {
      _loadFromFirestore();
    }
  }

  @override
  void dispose() {
    transportController.dispose();
    purposeController.dispose();
    addressController.dispose();
    parentPhoneController.dispose();
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

  Future pickDate(bool isLeaving) async {

    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
    );

    if (picked != null) {

      setState(() {

        if (isLeaving) {
          leavingDate = picked;
        } else {
          returnDate = picked;
        }

        calculateDuration();

      });

    }
  }

  Future pickTime(bool isLeaving) async {

    TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (picked != null) {

      setState(() {

        if (isLeaving) {
          leavingTime = picked;
        } else {
          returnTime = picked;
        }

      });

    }
  }

  void calculateDuration() {

    if (leavingDate != null && returnDate != null) {

      durationDays = returnDate!.difference(leavingDate!).inDays + 1;

    }

  }

  Future submitApplication() async {

    User? user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    // Validate required fields
    if (leavingDate == null ||
        returnDate == null ||
        purposeController.text.isEmpty ||
        transportController.text.isEmpty ||
        addressController.text.isEmpty ||
        parentPhoneController.text.isEmpty) {
      debugPrint("Validation failed");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all required fields")),
      );
      return;
    }

    // Validate parent phone is exactly 10 digits
    String parentPhone = parentPhoneController.text.trim();
    if (!RegExp(r'^\d{10}$').hasMatch(parentPhone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Parent phone number must be exactly 10 digits")),
      );
      return;
    }

    // Check if there's already a pending or approved leave request
    var existingLeave = await FirebaseFirestore.instance
        .collection("leave_requests")
        .where("studentId", isEqualTo: user.uid)
        .where("status", whereIn: ["pending", "approved"])
        .limit(1)
        .get();

    if (existingLeave.docs.isNotEmpty) {
      if (!mounted) return;
      String existingStatus = existingLeave.docs.first["status"];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          existingStatus == "pending"
              ? "You already have a pending leave request."
              : "You already have an approved leave. Use it before applying again."
        )),
      );
      return;
    }

    await FirebaseFirestore.instance.collection("leave_requests").add({

      "studentId": user.uid,

      "name": userData?["name"],
      "rollNumber": userData?["rollNumber"],
      "degree": userData?["degree"],
      "hostel": userData?["hostel"],
      "roomNumber": userData?["roomNumber"],
      "phone": userData?["phone"],
      "photo": userData?["photo"] ?? "",

      "floor": _selectedFloor ?? "",

      "leavingDate": leavingDate,
      "returnDate": returnDate,

      "leavingTime": leavingTime?.format(context),
      "returnTime": returnTime?.format(context),

      "durationDays": durationDays,

      "modeOfTransport": transportController.text,
      "purpose": purposeController.text,

      "addressDuringLeave": addressController.text,
      "parentPhone": parentPhoneController.text.trim(),

      "status": "pending",

      "createdAt": Timestamp.now()

    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Leave Application Submitted")),
    );

    Navigator.pop(context);
  }

  void showSubmitConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Submission"),
        content: const Text("Are you sure you want to submit this leave application?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              submitApplication();
            },
            child: const Text("Submit"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: const Text("Leave Application"),
      ),

      body: userData == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20),

              child: ListView(
                children: [

                  ListTile(
                    title: Text(leavingDate == null
                        ? "Select Leaving Date"
                        : DateFormat('yyyy-MM-dd').format(leavingDate!)),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () => pickDate(true),
                  ),

                  ListTile(
                    title: Text(leavingTime == null
                        ? "Select Leaving Time"
                        : leavingTime!.format(context)),
                    trailing: const Icon(Icons.access_time),
                    onTap: () => pickTime(true),
                  ),

                  const SizedBox(height: 10),

                  ListTile(
                    title: Text(returnDate == null
                        ? "Select Return Date"
                        : DateFormat('yyyy-MM-dd').format(returnDate!)),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () => pickDate(false),
                  ),

                  ListTile(
                    title: Text(returnTime == null
                        ? "Select Return Time"
                        : returnTime!.format(context)),
                    trailing: const Icon(Icons.access_time),
                    onTap: () => pickTime(false),
                  ),

                  const SizedBox(height: 10),

                  Text("Duration: $durationDays days"),

                  const SizedBox(height: 20),

                  DropdownButtonFormField<String>(
                    value: _selectedFloor,
                    decoration: const InputDecoration(labelText: "Floor"),
                    items: _floorOptions.map((floor) {
                      return DropdownMenuItem(
                        value: floor,
                        child: Text(floor),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedFloor = value;
                      });
                    },
                  ),

                  const SizedBox(height: 10),

                  TextField(
                    controller: transportController,
                    decoration: const InputDecoration(labelText: "Mode of Transport"),
                  ),

                  const SizedBox(height: 10),

                  TextField(
                    controller: purposeController,
                    decoration: const InputDecoration(labelText: "Purpose of Leave"),
                  ),

                  const SizedBox(height: 10),

                  TextField(
                    controller: addressController,
                    decoration: const InputDecoration(labelText: "Address During Leave"),
                  ),

                  const SizedBox(height: 10),

                  TextField(
                    controller: parentPhoneController,
                    decoration: const InputDecoration(
                      labelText: "Parent Phone Number",
                      hintText: "10-digit number",
                    ),
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                  ),

                  const SizedBox(height: 30),

                  ElevatedButton.icon(
                    onPressed: showSubmitConfirmation,
                    icon: const Icon(Icons.send),
                    label: const Text("Submit Application"),
                  ),

                ],
              ),
            ),
    );
  }
}
