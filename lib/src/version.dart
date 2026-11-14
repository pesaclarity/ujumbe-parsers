/// The version of this engine, matching `version` in pubspec.yaml.
///
/// Packs and the pack index name the oldest engine that can read them; a
/// phone compares that against this value before using a downloaded pack.
const engineVersion = '0.2.0'; // x-release-please-version

final _semver = RegExp(
  r'^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
);

/// Whether [version] is a semantic version such as `1.2.3` or `1.2.3-beta.1`.
bool isSemanticVersion(String version) => _semver.hasMatch(version);

/// Compares two semantic versions by precedence: negative if [a] is older
/// than [b], zero if equal, positive if newer. Build metadata is ignored.
///
/// Throws [FormatException] if either is not a semantic version.
int compareVersions(String a, String b) {
  final ma = _parse(a);
  final mb = _parse(b);
  for (var i = 1; i <= 3; i++) {
    final c = BigInt.parse(ma.group(i)!).compareTo(BigInt.parse(mb.group(i)!));
    if (c != 0) return c;
  }
  final pa = ma.group(4);
  final pb = mb.group(4);
  if (pa == null || pb == null) {
    // A release outranks any pre-release of the same version.
    return pa == pb ? 0 : (pa == null ? 1 : -1);
  }
  final ia = pa.split('.');
  final ib = pb.split('.');
  for (var i = 0; i < ia.length && i < ib.length; i++) {
    final c = _compareIdentifier(ia[i], ib[i]);
    if (c != 0) return c;
  }
  return ia.length.compareTo(ib.length);
}

RegExpMatch _parse(String version) =>
    _semver.firstMatch(version) ??
    (throw FormatException('Not a semantic version', version));

int _compareIdentifier(String a, String b) {
  final na = _numeric.hasMatch(a) ? BigInt.parse(a) : null;
  final nb = _numeric.hasMatch(b) ? BigInt.parse(b) : null;
  if (na != null && nb != null) return na.compareTo(nb);
  if (na != null) return -1;
  if (nb != null) return 1;
  return a.compareTo(b);
}

final _numeric = RegExp(r'^\d+$');
