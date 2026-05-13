import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';


class LeaveStatus extends StatefulWidget {
  final bool embedded;
  const LeaveStatus({super.key, this.embedded = false});

  @override
  State<LeaveStatus> createState() => _LeaveStatusState();
}

class _LeaveStatusState extends State<LeaveStatus> {

  // Only run rejected-leave cleanup once per app session
  static bool _hasCleanedUpThisSession = false;

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

      // Auto-delete rejected requests older than 2 days (once per session)
      if (!_hasCleanedUpThisSession) {
        DateTime now = DateTime.now();
        List<DocumentSnapshot> toRemove = [];
        for (var doc in docs) {
          if (doc["status"] == "rejected") {
            try {
              Timestamp? rejectedAt = doc["rejectedAt"];
              if (rejectedAt != null) {
                Duration diff = now.difference(rejectedAt.toDate());
                if (diff.inDays >= 2) {
                  await FirebaseFirestore.instance
                      .collection("leave_requests")
                      .doc(doc.id)
                      .delete();
                  toRemove.add(doc);
                }
              }
            } catch (_) {}
          }
        }
        docs.removeWhere((d) => toRemove.contains(d));
        _hasCleanedUpThisSession = true;
      }

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

              // Warden action info
              Builder(
                builder: (context) {
                  String status = leaveRequest["status"] ?? "pending";
                  String? actionBy;
                  try {
                    if (status == "approved") {
                      actionBy = leaveRequest["approvedBy"];
                    } else if (status == "rejected") {
                      actionBy = leaveRequest["rejectedBy"];
                    }
                  } catch (_) {}
                  if (actionBy != null && actionBy.isNotEmpty) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        "${status == 'approved' ? 'Approved' : 'Rejected'} by: $actionBy",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: status == 'approved' ? Colors.green : Colors.red,
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),

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
                // Extension warden name
                Builder(
                  builder: (context) {
                    String? extBy;
                    try {
                      if (extensionStatus == "approved") {
                        extBy = leaveRequest["extensionApprovedBy"];
                      } else if (extensionStatus == "rejected") {
                        extBy = leaveRequest["extensionRejectedBy"];
                      }
                    } catch (_) {}
                    if (extBy != null && extBy.isNotEmpty) {
                      return Text(
                        "Extension ${extensionStatus == 'approved' ? 'approved' : 'rejected'} by: $extBy",
                        style: TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: extensionStatus == 'approved' ? Colors.green : Colors.red,
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
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
      return const Center(child: Text("Not logged in"));
    }

    Widget body = RefreshIndicator(
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

                      // Get warden name
                      String? actionBy;
                      try {
                        if (status == "approved") {
                          actionBy = leaveRequest["approvedBy"];
                        } else if (status == "rejected") {
                          actionBy = leaveRequest["rejectedBy"];
                        }
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

                                // Warden name
                                if (actionBy != null && actionBy.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    "${status == 'approved' ? 'Approved' : 'Rejected'} by: $actionBy",
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontStyle: FontStyle.italic,
                                      color: status == 'approved' ? Colors.green.shade700 : Colors.red.shade700,
                                    ),
                                  ),
                                ],

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
                                    returnDate: returnDate,
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
      );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Leave Application Status"),
      ),
      body: body,
    );

  }

}

class _ApprovedLeaveWidget extends StatefulWidget {

  final String passId;
  final DateTime? leavingDate;
  final DateTime? returnDate;
  final String? extensionStatus;

  const _ApprovedLeaveWidget({
    required this.passId,
    this.leavingDate,
    this.returnDate,
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

    final currentReturnDate = widget.returnDate;
    final navyBlue = const Color(0xFF0D1B2A);

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: navyBlue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.date_range, color: navyBlue, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          "Apply for Extension",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Current return date info card
                  if (currentReturnDate != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(fontSize: 13, color: Colors.black87),
                                children: [
                                  const TextSpan(text: "Current return date: "),
                                  TextSpan(
                                    text: DateFormat('dd MMM yyyy').format(currentReturnDate),
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 20),

                  // New return date picker
                  const Text(
                    "New Return Date",
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      // initialDate = current return date + 1 day (so student sees where they are)
                      final initDate = currentReturnDate != null
                          ? currentReturnDate.add(const Duration(days: 1))
                          : DateTime.now().add(const Duration(days: 1));

                      DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: initDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2030),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.light(
                                primary: navyBlue,
                                onPrimary: Colors.white,
                                surface: Colors.white,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setDialogState(() {
                          _selectedNewReturnDate = picked;
                        });
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _selectedNewReturnDate != null ? navyBlue : Colors.grey.shade300,
                          width: _selectedNewReturnDate != null ? 1.5 : 1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        color: _selectedNewReturnDate != null
                            ? navyBlue.withOpacity(0.04)
                            : Colors.grey.shade50,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 20,
                            color: _selectedNewReturnDate != null ? navyBlue : Colors.grey,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _selectedNewReturnDate == null
                                ? "Tap to select date"
                                : DateFormat('dd MMM yyyy').format(_selectedNewReturnDate!),
                            style: TextStyle(
                              fontSize: 15,
                              color: _selectedNewReturnDate != null ? navyBlue : Colors.grey.shade600,
                              fontWeight: _selectedNewReturnDate != null
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Reason text field
                  const Text(
                    "Reason for Extension",
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _reasonController,
                    decoration: InputDecoration(
                      hintText: "Why do you need an extension?",
                      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: navyBlue, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.all(14),
                    ),
                    maxLines: 3,
                  ),

                  const SizedBox(height: 24),

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                          child: const Text(
                            "Cancel",
                            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
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
                          style: ElevatedButton.styleFrom(
                            backgroundColor: navyBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            "Submit",
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
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

  void _showDeleteConfirmation() {
    final confirmController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.delete_forever, color: Colors.red, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "Delete Leave QR",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Warning card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(0.25)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Delete this QR only if you are NOT going on leave. If you have already left campus using this QR, DO NOT delete it — you will need it to re-enter.",
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Confirmation input
              const Text(
                "Type  delete_qr  to confirm",
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmController,
                decoration: InputDecoration(
                  hintText: "delete_qr",
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.red, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),

              const SizedBox(height: 24),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: const Text(
                        "Cancel",
                        style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        if (confirmController.text.trim() != "delete_qr") {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Please type 'delete_qr' to confirm")),
                          );
                          return;
                        }
                        Navigator.pop(dialogContext);

                        try {
                          await FirebaseFirestore.instance
                              .collection("leave_requests")
                              .doc(widget.passId)
                              .delete();

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Leave QR deleted successfully")),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("Error: ${e.toString()}")),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        "Delete",
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
            embeddedImage: const AssetImage('assets/images/logo.png'),
            embeddedImageStyle: const QrEmbeddedImageStyle(
              size: Size(40, 40),
            ),
          ),

          if (canApplyExtension) ...[
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _showExtensionForm,
              icon: const Icon(Icons.date_range),
              label: const Text("Apply for Extension"),
            ),
          ],

          const SizedBox(height: 15),

          ElevatedButton.icon(
            onPressed: _showDeleteConfirmation,
            icon: const Icon(Icons.delete_forever),
            label: const Text("Delete QR"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
          ),

        ],
      ),

    );

  }

}
