import 'package:flutter/material.dart';

class FreightRequest {
  final String? id;
  final int number;
  final int fairId;
  final String fairName;
  final List<String> clientIds;
  final List<String> clientNames;
  final String portao;
  final String scheduledFor;
  final String items;
  final List<String> motivos;
  final List<String> equipes;
  final String priority;
  final String status;
  final String requestedBy;
  final String requestedByRole;
  final String requesterTopic;
  final String requestedAt;
  final String handledBy;
  final String statusNote;
  final String? scheduledAt;
  final String? dispatchedAt;
  final String? finalizedAt;
  final String receiptPhotoUrl;

  const FreightRequest({
    this.id,
    required this.number,
    required this.fairId,
    required this.fairName,
    this.clientIds = const [],
    this.clientNames = const [],
    required this.portao,
    required this.scheduledFor,
    required this.items,
    this.motivos = const [],
    this.equipes = const [],
    this.priority = 'normal',
    this.status = 'em_aberto',
    required this.requestedBy,
    required this.requestedByRole,
    required this.requesterTopic,
    required this.requestedAt,
    this.handledBy = '',
    this.statusNote = '',
    this.scheduledAt,
    this.dispatchedAt,
    this.finalizedAt,
    this.receiptPhotoUrl = '',
  });

  factory FreightRequest.fromMap(String id, Map<String, dynamic> map) {
    List<String> castList(dynamic v) {
      if (v == null) return [];
      if (v is List) return v.map((e) => e.toString()).toList();
      return [];
    }

    return FreightRequest(
      id: id,
      number: (map['number'] as num?)?.toInt() ?? 0,
      fairId: (map['fairId'] as num?)?.toInt() ?? 0,
      fairName: map['fairName'] as String? ?? '',
      clientIds: castList(map['clientIds']),
      clientNames: castList(map['clientNames']),
      portao: map['portao'] as String? ?? '',
      scheduledFor: map['scheduledFor'] as String? ?? '',
      items: map['items'] as String? ?? '',
      motivos: castList(map['motivos']),
      equipes: castList(map['equipes']),
      priority: map['priority'] as String? ?? 'normal',
      status: map['status'] as String? ?? 'em_aberto',
      requestedBy: map['requestedBy'] as String? ?? '',
      requestedByRole: map['requestedByRole'] as String? ?? '',
      requesterTopic: map['requesterTopic'] as String? ?? '',
      requestedAt: map['requestedAt'] as String? ?? '',
      handledBy: map['handledBy'] as String? ?? '',
      statusNote: map['statusNote'] as String? ?? '',
      scheduledAt: map['scheduledAt'] as String?,
      dispatchedAt: map['dispatchedAt'] as String?,
      finalizedAt: map['finalizedAt'] as String?,
      receiptPhotoUrl: map['receiptPhotoUrl'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'number': number,
        'fairId': fairId,
        'fairName': fairName,
        'clientIds': clientIds,
        'clientNames': clientNames,
        'portao': portao,
        'scheduledFor': scheduledFor,
        'items': items,
        'motivos': motivos,
        'equipes': equipes,
        'priority': priority,
        'status': status,
        'requestedBy': requestedBy,
        'requestedByRole': requestedByRole,
        'requesterTopic': requesterTopic,
        'requestedAt': requestedAt,
        'handledBy': handledBy,
        'statusNote': statusNote,
        if (scheduledAt != null) 'scheduledAt': scheduledAt,
        if (dispatchedAt != null) 'dispatchedAt': dispatchedAt,
        if (finalizedAt != null) 'finalizedAt': finalizedAt,
        'receiptPhotoUrl': receiptPhotoUrl,
      };

  bool get isUrgent => priority == 'urgente';
  bool get isOpen => status == 'em_aberto';
  bool get isScheduled => status == 'agendado';
  bool get isDispatched => status == 'despachado';
  bool get isFinalized => status == 'finalizado';

  String get statusLabel {
    switch (status) {
      case 'agendado':
        return 'Agendado';
      case 'despachado':
        return 'Despachado';
      case 'finalizado':
        return 'Finalizado';
      default:
        return 'Em aberto';
    }
  }

  Color get statusColor {
    switch (status) {
      case 'agendado':
        return Colors.blue;
      case 'despachado':
        return Colors.orange;
      case 'finalizado':
        return Colors.green;
      default:
        return Colors.red;
    }
  }
}
