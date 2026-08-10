/// One item of مكتبة إدو بلس, as the device holds it.
///
/// There is no separate "remote item" type. Everything the app shows comes out
/// of the local database — a synced row with no download is still a readable
/// item, because the summary and the mind map *are* the `content` field. Two
/// types would mean two code paths for the same screen, one of which only runs
/// when the network happens to be up.
class LibraryItem {
  const LibraryItem({
    required this.name,
    required this.title,
    required this.itemType,
    this.titleAr,
    this.subject,
    this.skill,
    this.gradeLevel,
    this.language,
    this.content,
    this.attachment,
    this.thumbnail,
    this.remoteBytes = 0,
    this.remoteVersion = 0,
    this.localPath,
    this.localBytes = 0,
    this.localVersion = 0,
    this.downloadedAt,
  });

  final String name;
  final String title;
  final String? titleAr;
  final String itemType;
  final String? subject;
  final String? skill;
  final String? gradeLevel;
  final String? language;

  /// The readable body, stored with the row. This is what makes the library
  /// work offline on a school that attaches no files at all.
  final String? content;

  /// Site-relative path of the attached file, if any.
  final String? attachment;
  final String? thumbnail;

  /// What the server says the attachment weighs. Zero means *unknown*, not
  /// empty — an external URL has no `File` row to measure.
  final int remoteBytes;
  final int remoteVersion;

  final String? localPath;
  final int localBytes;
  final int localVersion;
  final String? downloadedAt;

  /// Prefer Arabic, fall back to whatever the school actually typed.
  String get displayTitle {
    final ar = titleAr?.trim();
    return (ar != null && ar.isNotEmpty) ? ar : title;
  }

  bool get hasAttachment => (attachment?.isNotEmpty ?? false);
  bool get isDownloaded => (localPath?.isNotEmpty ?? false);

  /// Readable with no network: either the body travelled with the row, or the
  /// file is on the device.
  bool get isAvailableOffline => isDownloaded || (content?.isNotEmpty ?? false);

  /// The size to show before downloading — null when the server does not know
  /// it, so the UI says nothing rather than saying "0 KB".
  int? get downloadSize => remoteBytes > 0 ? remoteBytes : null;

  static const _typeLabels = {
    'Summary': 'ملخّص',
    'Question Bank': 'بنك أسئلة',
    'Mind Map': 'خريطة ذهنية',
    'Formula Sheet': 'صفحة قوانين',
    'Worksheet': 'ورقة عمل',
    'Reference': 'مرجع',
  };

  static const typeOptions = _typeLabels;

  String get typeLabel => _typeLabels[itemType] ?? itemType;

  factory LibraryItem.fromRow(Map<String, Object?> row) => LibraryItem(
    name: row['name'] as String,
    title: (row['title'] as String?) ?? '',
    titleAr: row['title_ar'] as String?,
    itemType: (row['item_type'] as String?) ?? '',
    subject: row['subject'] as String?,
    skill: row['skill'] as String?,
    gradeLevel: row['grade_level'] as String?,
    language: row['language'] as String?,
    content: row['content'] as String?,
    attachment: row['attachment'] as String?,
    thumbnail: row['thumbnail'] as String?,
    remoteBytes: (row['remote_bytes'] as int?) ?? 0,
    remoteVersion: (row['remote_version'] as int?) ?? 0,
    localPath: row['local_path'] as String?,
    localBytes: (row['local_bytes'] as int?) ?? 0,
    localVersion: (row['local_version'] as int?) ?? 0,
    downloadedAt: row['downloaded_at'] as String?,
  );
}

/// Byte counts a student can read.
///
/// Written per magnitude rather than by a formula: «٠٫٩٨ ميغابايت» is a
/// measurement, «١٠٠٠ كيلوبايت» is an answer.
String humanBytes(int bytes) {
  if (bytes <= 0) return '—';
  if (bytes < 1024) return '$bytes بايت';

  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.round()} كيلوبايت';

  final mb = kb / 1024;
  if (mb < 1024) {
    return mb < 10
        ? '${mb.toStringAsFixed(1)} ميغابايت'
        : '${mb.round()} ميغابايت';
  }

  return '${(mb / 1024).toStringAsFixed(1)} غيغابايت';
}
