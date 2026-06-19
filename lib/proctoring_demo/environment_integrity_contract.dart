class EnvironmentIntegrityContract {
  const EnvironmentIntegrityContract({
    required this.clean,
    required this.hardwareEnvironmentRisk,
    required this.cameraDriverRisk,
    required this.findings,
  });

  final bool clean;
  final bool hardwareEnvironmentRisk;
  final bool cameraDriverRisk;
  final List<String> findings;

  Map<String, Object?> toJson() => <String, Object?>{
        'clean': clean,
        'hardware_environment_risk': hardwareEnvironmentRisk,
        'camera_driver_risk': cameraDriverRisk,
        'findings': findings,
      };
}
