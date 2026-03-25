import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';


class LeaveStatus extends StatefulWidget {
  const LeaveStatus({super.key});

  @override
  State<LeaveStatus> createState() => _LeaveStatusState();
}

class _LeaveStatusState extends State<LeaveStatus> {

  List<DocumentSnapshot> _leaveRequests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchLeaveRequests();
  }

  Future<void> _fetchLeaveRequests() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      var snapshot = await FirebaseFirestore.instance
          .collection("leave_requests")
          .where("studentId", isEqualTo: user.uid)
          .get();

      var docs = snapshot.docs;

      // Sort by createdAt descending
      docs.sort((a, b) {
        Timestamp aTime = a["createdAt"] ?? Timestamp.now();
        Timestamp bTime = b["createdAt"] ?? Timestamp.now();
        return bTime.compareTo(aTime);
      });

      if (mounted) {
        setState(() {
          _leaveRequests = docs;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching leave requests: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void showLeaveDetails(BuildContext context, DocumentSnapshot leaveRequest) {
    DateTime? leavingDate;
    DateTime? returnDate;

    bool isExtended = false;
    String? extensionStatus;

    try {
      if (leaveRequest["leavingDate"] is Timestamp) {
        leavingDate = (leaveRequest["leavingDate"] as Timestamp).toDate();
      }
      if (leaveRequest["returnDate"] is Timestamp) {
        returnDate = (leaveRequest["returnDate"] as Timestamp).toDate();
      }
    } catch (e) {
      debugPrint("Error parsing dates: $e");
    }

    try {
      isExtended = leaveRequest["extended"] == true;
    } catch (_) {}

    try {
      extensionStatus = leaveRequest["extensionStatus"];
    } catch (_) {}

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Leave Application Details"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Name: ${leaveRequest["name"]}"),
              Text("Roll Number: ${leaveRequest["rollNumber"]}"),
              Text("Degree: ${leaveRequest["degree"]}"),
              Text("Hostel: ${leaveRequest["hostel"]}"),
              Text("Room: ${leaveRequest["roomNumber"]}"),
              Text("Phone: ${leaveRequest["phone"]}"),
              const SizedBox(height: 10),

              if (leavingDate != null)
                Text("Leaving Date: ${DateFormat('yyyy-MM-dd').format(leavingDate)}"),

              if (returnDate != null)
                Row(
                  children: [
                    Flexible(
                      child: Text("Return Date: ${DateFormat('yyyy-MM-dd').format(returnDate)}"),
                    ),
                    if (isExtended)
                      const Text(
                        "  EXTENDED",
                        style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),

              Text("Duration: ${leaveRequest["durationDays"]} days"),

              const SizedBox(height: 10),
              Text("Mode of Transport: ${leaveRequest["modeOfTransport"]}"),
              Text("Purpose: ${leaveRequest["purpose"]}"),
              Text("Address During Leave: ${leaveRequest["addressDuringLeave"]}"),
              Text("Parent Phone: ${leaveRequest["parentPhone"]}"),

              // Extension status in details
              if (extensionStatus != null) ...[
                const SizedBox(height: 10),
                Text(
                  "Extension: ${extensionStatus == 'approved' ? 'Approved' : extensionStatus == 'rejected' ? 'Rejected' : 'Pending'}",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: extensionStatus == 'approved'
                        ? Colors.green
                        : extensionStatus == 'rejected'
                            ? Colors.red
                            : Colors.orange,
                  ),
                ),
              ],

              // Rejection reason in details
              Builder(
                builder: (context) {
                  String? rejectionReason;
                  try {
                    rejectionReason = leaveRequest["rejectionReason"];
                  } catch (_) {}
                  if (rejectionReason != null && rejectionReason.isNotEmpty) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        "Rejection Reason: $rejectionReason",
                        style: const TextStyle(
                          color: Colors.red,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Leave Status")),
        body: const Center(child: Text("Not logged in")),
      );
    }

    return Scaffold(

      appBar: AppBar(
        title: const Text("Leave Application Status"),
      ),

      body: RefreshIndicator(
        onRefresh: _fetchLeaveRequests,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _leaveRequests.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 200),
                      Center(child: Text("No leave applications submitted")),
                      SizedBox(height: 20),
                      Center(
                        child: Text(
                          "Pull down to refresh",
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(

                    itemCount: _leaveRequests.length,
                    padding: const EdgeInsets.all(10),

                    itemBuilder: (context, index) {

                      var leaveRequest = _leaveRequests[index];
                      String status = leaveRequest["status"] ?? "pending";

                      DateTime? leavingDate;
                      DateTime? returnDate;
                      bool isExtended = false;
                      String? extensionStatus;

                      try {
                        if (leaveRequest["leavingDate"] is Timestamp) {
                          leavingDate = (leaveRequest["leavingDate"] as Timestamp).toDate();
                        }
                        if (leaveRequest["returnDate"] is Timestamp) {
                          returnDate = (leaveRequest["returnDate"] as Timestamp).toDate();
                        }
                      } catch (e) {
                        debugPrint("Error parsing dates: $e");
                      }

                      try {
                        isExtended = leaveRequest["extended"] == true;
                      } catch (_) {}

                      try {
                        extensionStatus = leaveRequest["extensionStatus"];
                      } catch (_) {}

                      String purpose = leaveRequest["purpose"] ?? "N/A";

                      Color statusColor;
                      String statusText;

                      if (status == "pending") {
                        statusColor = Colors.orange;
                        statusText = "Pending";
                      } else if (status == "approved") {
                        statusColor = Colors.green;
                        statusText = "Approved";
                      } else {
                        statusColor = Colors.red;
                        statusText = "Rejected";
                      }

                      return GestureDetector(
                        onTap: () => showLeaveDetails(context, leaveRequest),
                        child: Card(

                          margin: const EdgeInsets.all(10),

                          child: Padding(
                            padding: const EdgeInsets.all(15),

                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,

                              children: [

                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,

                                  children: [

                                    Text(
                                      "Leave Request",
                                      style: Theme.of(context).textTheme.headlineSmall,
                                    ),

                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.2),
                                        border: Border.all(color: statusColor),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        statusText,
                                        style: TextStyle(
                                          color: statusColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),

                                  ],
                                ),

                                const SizedBox(height: 15),

                                if (leavingDate != null)
                                  Text(
                                    "From: ${DateFormat('yyyy-MM-dd').format(leavingDate)}",
                                    style: const TextStyle(fontSize: 14),
                                  ),

                                if (returnDate != null)
                                  Row(
                                    children: [
                                      Text(
                                        "To: ${DateFormat('yyyy-MM-dd').format(returnDate)}",
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                      if (isExtended)
                                        const Text(
                                          "  EXTENDED",
                                          style: TextStyle(
                                            color: Colors.blue,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
                                  ),

                                Text(
                                  "Purpose: $purpose",
                                  style: const TextStyle(fontSize: 14),
                                ),

                                // Extension status badge
                                if (extensionStatus != null) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: extensionStatus == "approved"
                                          ? Colors.blue.withValues(alpha: 0.1)
                                          : extensionStatus == "rejected"
                                              ? Colors.red.withValues(alpha: 0.1)
                                              : Colors.orange.withValues(alpha: 0.1),
                                      border: Border.all(
                                        color: extensionStatus == "approved"
                                            ? Colors.blue
                                            : extensionStatus == "rejected"
                                                ? Colors.red
                                                : Colors.orange,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      extensionStatus == "approved"
                                          ? "Extension: Approved"
                                          : extensionStatus == "rejected"
                                              ? "Extension: Rejected"
                                              : "Extension: Pending",
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: extensionStatus == "approved"
                                            ? Colors.blue
                                            : extensionStatus == "rejected"
                                                ? Colors.red
                                                : Colors.orange,
                                      ),
                                    ),
                                  ),
                                ],

                                const SizedBox(height: 15),

                                const Center(
                                  child: Text(
                                    "Tap to view full details",
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 20),

                                if (status == "approved")
                                  _ApprovedLeaveWidget(
                                    passId: leaveRequest.id,
                                    leavingDate: leavingDate,
                                    extensionStatus: extensionStatus,
                                  )

                                else if (status == "rejected")
                                  Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: Column(
                                        children: [
                                          const Text(
                                            "Your leave request has been rejected.",
                                            style: TextStyle(
                                              color: Colors.red,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          Builder(
                                            builder: (context) {
                                              String? rejectionReason;
                                              try {
                                                rejectionReason = leaveRequest["rejectionReason"];
                                              } catch (_) {}
                                              if (rejectionReason != null && rejectionReason.isNotEmpty) {
                                                return Padding(
                                                  padding: const EdgeInsets.only(top: 8),
                                                  child: Text(
                                                    "Reason: $rejectionReason",
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      color: Colors.red,
                                                      fontStyle: FontStyle.italic,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                );
                                              }
                                              return const SizedBox.shrink();
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  )

                                else
                                  const Padding(
                                    padding: EdgeInsets.all(20),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: Center(
                                        child: Text(
                                          "Awaiting warden approval...",
                                          style: TextStyle(
                                            color: Colors.orange,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                              ],
                            ),
                          ),

                        ),
                      );

                    },

                  ),
      ),

    );

  }

}

class _ApprovedLeaveWidget extends StatefulWidget {

  final String passId;
  final DateTime? leavingDate;
  final String? extensionStatus;

  const _ApprovedLeaveWidget({
    required this.passId,
    this.leavingDate,
    this.extensionStatus,
  });

  @override
  State<_ApprovedLeaveWidget> createState() => _ApprovedLeaveWidgetState();
}

class _ApprovedLeaveWidgetState extends State<_ApprovedLeaveWidget> {

  StreamSubscription? _passListener;
  bool _isDeleted = false;

  final _reasonController = TextEditingController();
  DateTime? _selectedNewReturnDate;

  @override
  void initState() {
    super.initState();
    _watchPass();
  }

  @override
  void dispose() {
    _passListener?.cancel();
    _reasonController.dispose();
    super.dispose();
  }

  void _watchPass() {
    _passListener = FirebaseFirestore.instance
        .collection("leave_requests")
        .doc(widget.passId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists && mounted) {
        setState(() => _isDeleted = true);
      }
    });
  }

  void _showExtensionForm() {
    _selectedNewReturnDate = null;
    _reasonController.clear();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Apply for Extension"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _selectedNewReturnDate == null
                        ? "Select New Return Date"
                        : DateFormat('yyyy-MM-dd').format(_selectedNewReturnDate!),
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now().add(const Duration(days: 1)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        _selectedNewReturnDate = picked;
                      });
                    }
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _reasonController,
                  decoration: const InputDecoration(
                    labelText: "Reason for Extension",
                    prefixIcon: Icon(Icons.edit_note),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () {
                if (_selectedNewReturnDate == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please select a new return date")),
                  );
                  return;
                }
                if (_reasonController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please enter a reason")),
                  );
                  return;
                }
                Navigator.pop(dialogContext);
                _submitExtension();
              },
              child: const Text("Submit"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitExtension() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null || _selectedNewReturnDate == null) return;

    try {
      // Store extension data directly on the leave request document
      await FirebaseFirestore.instance
          .collection("leave_requests")
          .doc(widget.passId)
          .update({
        "extensionStatus": "pending",
        "extensionNewReturnDate": Timestamp.fromDate(_selectedNewReturnDate!),
        "extensionReason": _reasonController.text.trim(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Extension request submitted")),
        );
      }
    } catch (e) {
      debugPrint("Error submitting extension: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${e.toString()}")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {

    if (_isDeleted) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: Text(
            "Gate pass has been used.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      );
    }

    // Can apply for extension only if no extension has been requested yet
    bool canApplyExtension = widget.extensionStatus == null;

    return Center(

      child: Column(
        children: [

          const Text(
            "Your QR Code:",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 20),

          QrImageView(
            data: widget.passId,
            size: 250,
          ),

          if (canApplyExtension) ...[
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _showExtensionForm,
              icon: const Icon(Icons.date_range),
              label: const Text("Apply for Extension"),
            ),
          ],

        ],
      ),

    );

  }

}
