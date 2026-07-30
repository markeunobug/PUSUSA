class RealtimeDisplayRange {
  const RealtimeDisplayRange({
    required this.minDbfs,
    required this.referenceDbfs,
    required this.waterfallFloorDbfs,
    required this.waterfallReferenceDbfs,
  });
  final double minDbfs;
  final double referenceDbfs;
  final double waterfallFloorDbfs;
  final double waterfallReferenceDbfs;
}

/// Pure display policy for raw dBFS RT data. No instrument command is implied.
RealtimeDisplayRange realtimeDisplayRange(double requestedReferenceDbfs) {
  final reference = requestedReferenceDbfs.clamp(-140.0, 0.0).toDouble();
  final min = (reference - 130.0).clamp(-160.0, -10.0).toDouble();
  final waterfallFloor =
      (reference - 110.0).clamp(-160.0, reference - 10.0).toDouble();
  return RealtimeDisplayRange(
    minDbfs: min,
    referenceDbfs: reference,
    waterfallFloorDbfs: waterfallFloor,
    waterfallReferenceDbfs: reference,
  );
}
