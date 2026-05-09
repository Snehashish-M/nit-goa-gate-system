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
  final addressFlatController = TextEditingController();
  final addressAreaController = TextEditingController();
  final addressCityController = TextEditingController();
  final addressStateController = TextEditingController();
  final parentPhoneController = TextEditingController();

  DateTime? leavingDate;
  DateTime? returnDate;

  TimeOfDay? leavingTime;
  TimeOfDay? returnTime;

  int durationDays = 0;

  bool _isAddressSaved = false;
  bool _isEditingAddress = false;
  bool _isPhoneSaved = false;
  bool _isEditingPhone = false;

  @override
  void initState() {
    super.initState();
    userData = UserCache().profileData;
    if (userData == null) {
      _loadFromFirestore();
    } else {
      _loadSavedAddress();
      _loadSavedPhone();
    }
  }

  @override
  void dispose() {
    transportController.dispose();
    purposeController.dispose();
    addressFlatController.dispose();
    addressAreaController.dispose();
    addressCityController.dispose();
    addressStateController.dispose();
    parentPhoneController.dispose();
    super.dispose();
  }

  Future _loadFromFirestore() async {
    var data = await UserCache().loadProfile();
    if (mounted) {
      setState(() {
        userData = data;
      });
      _loadSavedAddress();
      _loadSavedPhone();
    }
  }

  void _loadSavedAddress() {
    if (userData == null) return;
    String flat = userData!["addressFlat"] ?? "";
    String area = userData!["addressArea"] ?? "";
    String city = userData!["addressCity"] ?? "";
    String state = userData!["addressState"] ?? "";

    if (flat.isNotEmpty && city.isNotEmpty && state.isNotEmpty) {
      addressFlatController.text = flat;
      addressAreaController.text = area;
      addressCityController.text = city;
      addressStateController.text = state;
      setState(() {
        _isAddressSaved = true;
        _isEditingAddress = false;
      });
    }
  }

  void _loadSavedPhone() {
    if (userData == null) return;
    String phone = userData!["parentPhone"] ?? "";
    if (phone.isNotEmpty) {
      parentPhoneController.text = phone;
      setState(() {
        _isPhoneSaved = true;
        _isEditingPhone = false;
      });
    }
  }

  Future<void> _savePhoneToProfile() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .update({"parentPhone": parentPhoneController.text.trim()});
      UserCache().updateCache({"parentPhone": parentPhoneController.text.trim()});
    } catch (e) {
      debugPrint("Error saving parent phone: $e");
    }
  }

  Future<void> _saveAddressToProfile() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    Map<String, dynamic> addressData = {
      "addressFlat": addressFlatController.text.trim(),
      "addressArea": addressAreaController.text.trim(),
      "addressCity": addressCityController.text.trim(),
      "addressState": addressStateController.text.trim(),
    };

    try {
      await FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .update(addressData);
      UserCache().updateCache(addressData);
    } catch (e) {
      debugPrint("Error saving address: $e");
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
        addressFlatController.text.isEmpty ||
        addressAreaController.text.isEmpty ||
        addressCityController.text.isEmpty ||
        addressStateController.text.isEmpty ||
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

    // Save address to profile for future use
    await _saveAddressToProfile();

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

      "addressDuringLeave": [
        addressFlatController.text.trim(),
        addressAreaController.text.trim(),
        addressCityController.text.trim(),
        addressStateController.text.trim(),
      ].join(", "),
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

  Widget _buildDateTimeTile({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    bool isSelected = value != label;
    return InkWell(
      onTap: onTap,
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
                    label,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isSelected ? value : "Tap to select",
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

  Widget _buildSavedAddressCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                "Saved Address",
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.green.shade800,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isEditingAddress = true;
                  });
                },
                child: const Text("Edit"),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF0A192F),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildAddressRow(addressFlatController.text),
          if (addressAreaController.text.isNotEmpty)
            _buildAddressRow(addressAreaController.text),
          _buildAddressRow(addressCityController.text),
          _buildAddressRow(addressStateController.text),
        ],
      ),
    );
  }

  Widget _buildAddressRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text, style: const TextStyle(fontSize: 14)),
    );
  }

  Widget _buildAddressFields() {
    return Column(
      children: [
        TextField(
          controller: addressFlatController,
          decoration: const InputDecoration(
            labelText: "Flat / House No. / Apartment",
          ),
        ),

        const SizedBox(height: 10),

        TextField(
          controller: addressAreaController,
          decoration: const InputDecoration(
            labelText: "Area / Street",
          ),
        ),

        const SizedBox(height: 10),

        TextField(
          controller: addressCityController,
          decoration: const InputDecoration(
            labelText: "City",
          ),
        ),

        const SizedBox(height: 10),

        TextField(
          controller: addressStateController,
          decoration: const InputDecoration(
            labelText: "State",
          ),
        ),

        if (_isEditingAddress && _isAddressSaved) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    _loadSavedAddress();
                  },
                  child: const Text("Cancel"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    if (addressFlatController.text.isNotEmpty &&
                        addressAreaController.text.isNotEmpty &&
                        addressCityController.text.isNotEmpty &&
                        addressStateController.text.isNotEmpty) {
                      _saveAddressToProfile();
                      setState(() {
                        _isAddressSaved = true;
                        _isEditingAddress = false;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Address updated")),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Please fill all address fields")),
                      );
                    }
                  },
                  child: const Text("Save"),
                ),
              ),
            ],
          ),
        ],

        // First time: show Save Address button
        if (!_isAddressSaved && !_isEditingAddress) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                if (addressFlatController.text.isNotEmpty &&
                    addressAreaController.text.isNotEmpty &&
                    addressCityController.text.isNotEmpty &&
                    addressStateController.text.isNotEmpty) {
                  _saveAddressToProfile();
                  setState(() {
                    _isAddressSaved = true;
                    _isEditingAddress = false;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Address saved")),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please fill all address fields")),
                  );
                }
              },
              child: const Text("Save Address"),
            ),
          ),
        ],
      ],
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
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
              children: [

                // ─── DEPARTURE ────────────────────────────
                _buildSectionHeader("Leaving"),

                _buildDateTimeTile(
                  label: "Leaving Date",
                  value: leavingDate != null ? DateFormat('EEE, dd MMM yyyy').format(leavingDate!) : "Leaving Date",
                  onTap: () => pickDate(true),
                ),

                const SizedBox(height: 8),

                _buildDateTimeTile(
                  label: "Leaving Time",
                  value: leavingTime != null ? leavingTime!.format(context) : "Leaving Time",
                  onTap: () => pickTime(true),
                ),

                // ─── RETURN ───────────────────────────────
                _buildSectionHeader("Return"),

                _buildDateTimeTile(
                  label: "Return Date",
                  value: returnDate != null ? DateFormat('EEE, dd MMM yyyy').format(returnDate!) : "Return Date",
                  onTap: () => pickDate(false),
                ),

                const SizedBox(height: 8),

                _buildDateTimeTile(
                  label: "Return Time",
                  value: returnTime != null ? returnTime!.format(context) : "Return Time",
                  onTap: () => pickTime(false),
                ),

                // ─── DURATION CHIP ────────────────────────
                if (durationDays > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A192F),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          "Duration: $durationDays day${durationDays > 1 ? 's' : ''}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),

                // ─── DETAILS ──────────────────────────────
                _buildSectionHeader("Details"),

                DropdownButtonFormField<String>(
                  value: _selectedFloor,
                  decoration: const InputDecoration(
                    labelText: "Floor",
                  ),
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

                const SizedBox(height: 12),

                TextField(
                  controller: transportController,
                  decoration: const InputDecoration(
                    labelText: "Mode of Transport",
                  ),
                ),

                const SizedBox(height: 12),

                TextField(
                  controller: purposeController,
                  decoration: const InputDecoration(
                    labelText: "Purpose of Leave",
                  ),
                  maxLines: 2,
                  minLines: 1,
                ),

                // ─── ADDRESS ──────────────────────────────
                _buildSectionHeader("Address During Leave"),

                if (_isAddressSaved && !_isEditingAddress)
                  _buildSavedAddressCard()
                else
                  _buildAddressFields(),

                // ─── CONTACT ──────────────────────────────
                _buildSectionHeader("Parent Contact"),

                if (_isPhoneSaved && !_isEditingPhone)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Parent Phone Number",
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                parentPhoneController.text,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _isEditingPhone = true;
                            });
                          },
                          child: const Text("Edit"),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF0A192F),
                            minimumSize: Size.zero,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  TextField(
                    controller: parentPhoneController,
                    decoration: InputDecoration(
                      labelText: "Parent Phone Number",
                      hintText: "10-digit number",
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isEditingPhone && _isPhoneSaved)
                            TextButton(
                              onPressed: () {
                                _loadSavedPhone();
                              },
                              child: const Text("Cancel", style: TextStyle(fontSize: 12)),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.grey,
                                minimumSize: Size.zero,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          TextButton(
                            onPressed: () {
                              String phone = parentPhoneController.text.trim();
                              if (RegExp(r'^\d{10}$').hasMatch(phone)) {
                                _savePhoneToProfile();
                                setState(() {
                                  _isPhoneSaved = true;
                                  _isEditingPhone = false;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Phone number saved")),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Enter a valid 10-digit number")),
                                );
                              }
                            },
                            child: const Text("Save", style: TextStyle(fontSize: 12)),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF0A192F),
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                  ),

                // ─── SUBMIT ──────────────────────────────
                const SizedBox(height: 24),

                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: showSubmitConfirmation,
                    child: const Text(
                      "Submit Application",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

              ],
            ),
    );
  }
}
