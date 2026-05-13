import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:nit_goa_gate_app/services/user_cache.dart';

class VehicleApplication extends StatefulWidget {
  final bool embedded;
  const VehicleApplication({super.key, this.embedded = false});

  @override
  State<VehicleApplication> createState() => _VehicleApplicationState();
}

class _VehicleApplicationState extends State<VehicleApplication> {

  Map<String, dynamic>? userData;

  final visitorNameController = TextEditingController();
  final visitorPhoneController = TextEditingController();
  final relationshipController = TextEditingController();
  final vehicleNumberController = TextEditingController();
  final membersController = TextEditingController();
  final purposeController = TextEditingController();
  final otherVehicleController = TextEditingController();

  DateTime? visitDate;
  String? _selectedVehicleType;
  bool _isSubmitting = false;

  static const List<Map<String, dynamic>> _vehicleTypes = [
    {"label": "Two Wheeler", "icon": Icons.two_wheeler},
    {"label": "Auto", "icon": Icons.electric_rickshaw},
    {"label": "Car", "icon": Icons.directions_car},
    {"label": "Van", "icon": Icons.airport_shuttle},
    {"label": "Others", "icon": Icons.local_shipping},
  ];

  @override
  void initState() {
    super.initState();
    userData = UserCache().profileData;
    if (userData == null) {
      _loadFromFirestore();
    }
  }

  @override
  void dispose() {
    visitorNameController.dispose();
    visitorPhoneController.dispose();
    relationshipController.dispose();
    vehicleNumberController.dispose();
    membersController.dispose();
    purposeController.dispose();
    otherVehicleController.dispose();
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

  Future pickVisitDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        visitDate = picked;
      });
    }
  }

  Future submitApplication() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Validate required fields
    if (visitorNameController.text.isEmpty ||
        visitorPhoneController.text.isEmpty ||
        relationshipController.text.isEmpty ||
        vehicleNumberController.text.isEmpty ||
        membersController.text.isEmpty ||
        _selectedVehicleType == null ||
        visitDate == null ||
        purposeController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all required fields")),
      );
      return;
    }

    // If "Others" is selected, require specification
    if (_selectedVehicleType == "Others" && otherVehicleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please specify the vehicle type")),
      );
      return;
    }

    // Validate visitor phone
    String visitorPhone = visitorPhoneController.text.trim();
    if (!RegExp(r'^\d{10}$').hasMatch(visitorPhone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Visitor phone must be exactly 10 digits")),
      );
      return;
    }

    // Validate members count
    int? members = int.tryParse(membersController.text.trim());
    if (members == null || members < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter a valid number of members")),
      );
      return;
    }

    // Check for existing active request
    var existingRequest = await FirebaseFirestore.instance
        .collection("vehicle_requests")
        .where("studentId", isEqualTo: user.uid)
        .where("status", whereIn: ["pending", "approved"])
        .limit(1)
        .get();

    if (existingRequest.docs.isNotEmpty) {
      if (!mounted) return;
      String existingStatus = existingRequest.docs.first["status"];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          existingStatus == "pending"
              ? "You already have a pending vehicle request."
              : "You already have an approved vehicle entry. Cancel it before applying again."
        )),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      String vehicleType = _selectedVehicleType!;
      if (vehicleType == "Others") {
        vehicleType = "Others (${otherVehicleController.text.trim()})";
      }

      await FirebaseFirestore.instance.collection("vehicle_requests").add({
        "studentId": user.uid,
        "name": userData?["name"],
        "rollNumber": userData?["rollNumber"],
        "degree": userData?["degree"],
        "hostel": userData?["hostel"],
        "phone": userData?["phone"],

        "visitorName": visitorNameController.text.trim(),
        "visitorPhone": visitorPhoneController.text.trim(),
        "relationship": relationshipController.text.trim(),

        "vehicleNumber": vehicleNumberController.text.trim().toUpperCase(),
        "vehicleType": vehicleType,
        "numberOfMembers": members,

        "visitDate": Timestamp.fromDate(visitDate!),
        "purpose": purposeController.text.trim(),

        "status": "pending",
        "createdAt": Timestamp.now(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Vehicle entry request submitted")),
      );
      Navigator.pop(context);
    } catch (e) {
      debugPrint("Error submitting vehicle request: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${e.toString()}")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void showSubmitConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Submission"),
        content: const Text("Are you sure you want to submit this vehicle entry request?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
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

  // ─── UI HELPERS ───────────────────────────────────────────

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: Color(0xFF0A192F),
        ),
      ),
    );
  }

  Widget _buildDateTile() {
    bool isSelected = visitDate != null;
    return InkWell(
      onTap: pickVisitDate,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0A192F).withValues(alpha: 0.05) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF0A192F).withValues(alpha: 0.3) : Colors.grey.shade300,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Date of Visit",
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isSelected ? DateFormat('EEE, dd MMM yyyy').format(visitDate!) : "Tap to select",
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected ? const Color(0xFF0A192F) : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body = userData == null
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
            children: [

              // ─── VISITOR DETAILS ──────────────────────
              _buildSectionHeader("Visitor Details"),

              TextField(
                controller: visitorNameController,
                decoration: const InputDecoration(
                  labelText: "Visitor Name",
                ),
                textCapitalization: TextCapitalization.words,
              ),

              const SizedBox(height: 12),

              TextField(
                controller: visitorPhoneController,
                decoration: const InputDecoration(
                  labelText: "Visitor Phone Number",
                  hintText: "10-digit number",
                ),
                keyboardType: TextInputType.phone,
                maxLength: 10,
              ),

              const SizedBox(height: 4),

              TextField(
                controller: relationshipController,
                decoration: const InputDecoration(
                  labelText: "Relationship with Student",
                  hintText: "e.g., Father, Uncle, Friend",
                ),
                textCapitalization: TextCapitalization.words,
              ),

              // ─── VEHICLE DETAILS ──────────────────────
              _buildSectionHeader("Vehicle Details"),

              DropdownButtonFormField<String>(
                value: _selectedVehicleType,
                decoration: const InputDecoration(
                  labelText: "Type of Vehicle",
                ),
                items: _vehicleTypes.map((type) {
                  return DropdownMenuItem<String>(
                    value: type["label"] as String,
                    child: Row(
                      children: [
                        Icon(type["icon"] as IconData, size: 20, color: const Color(0xFF0A192F)),
                        const SizedBox(width: 12),
                        Text(type["label"] as String),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedVehicleType = value;
                  });
                },
              ),

              if (_selectedVehicleType == "Others") ...[
                const SizedBox(height: 12),
                TextField(
                  controller: otherVehicleController,
                  decoration: const InputDecoration(
                    labelText: "Specify Vehicle Type",
                    hintText: "e.g., Truck, Tractor",
                  ),
                ),
              ],

              const SizedBox(height: 12),

              TextField(
                controller: vehicleNumberController,
                decoration: const InputDecoration(
                  labelText: "Vehicle Number",
                  hintText: "e.g., GA-01-AB-1234",
                ),
                textCapitalization: TextCapitalization.characters,
              ),

              const SizedBox(height: 12),

              TextField(
                controller: membersController,
                decoration: const InputDecoration(
                  labelText: "Number of Members",
                  hintText: "Including driver",
                ),
                keyboardType: TextInputType.number,
              ),

              // ─── VISIT DETAILS ────────────────────────
              _buildSectionHeader("Visit Details"),

              _buildDateTile(),

              const SizedBox(height: 12),

              TextField(
                controller: purposeController,
                decoration: const InputDecoration(
                  labelText: "Purpose of Visit",
                  hintText: "e.g., Dropping off luggage, Family visit",
                ),
                maxLines: 2,
                minLines: 1,
              ),

              // ─── SUBMIT ──────────────────────────────
              const SizedBox(height: 30),

              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : showSubmitConfirmation,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          "Submit Request",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
              ),

              const SizedBox(height: 10),
            ],
          );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Vehicle Entry Request"),
      ),
      body: body,
    );
  }
}
