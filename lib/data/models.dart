import '../core/utils.dart';

/// All models are thin typed views over the raw database row, which keeps
/// optimistic updates trivial: `Model({...old.raw, ...changes})`.
abstract class Entity {
  Entity(this.raw);
  final Map<String, dynamic> raw;

  String get id => raw['id'] as String;
  DateTime get createdAt => parseDateTime(raw['created_at']) ?? DateTime.now();

  String str(String k) => (raw[k] ?? '').toString();
  String? strOrNull(String k) {
    final v = raw[k];
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  int integer(String k, [int d = 0]) {
    final v = raw[k];
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}') ?? d;
  }

  int? intOrNull(String k) {
    final v = raw[k];
    if (v == null) return null;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  double? numOrNull(String k) {
    final v = raw[k];
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }

  bool flag(String k) => raw[k] == true;
  DateTime? dt(String k) => parseDateTime(raw[k]);
  List<String> strings(String k) => (raw[k] as List?)?.map((e) => e.toString()).toList() ?? const [];
  List<Map<String, dynamic>> maps(String k) =>
      (raw[k] as List?)?.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() ?? const [];
}

// ------------------------------------------------------------ direction
class LifeArea extends Entity {
  LifeArea(super.raw);
  String get name => str('name');
  String? get description => strOrNull('description');
  String get icon => strOrNull('icon') ?? 'growth';
  String get color => strOrNull('color') ?? '#4F46E5';
  int get sortOrder => integer('sort_order');
}

class ItemCategory extends Entity {
  ItemCategory(super.raw);
  String get kind => str('kind');
  String get name => str('name');
  String get color => strOrNull('color') ?? '#64748B';
  int get sortOrder => integer('sort_order');
}

class Vision extends Entity {
  Vision(super.raw);
  String get title => str('title');
  String? get description => strOrNull('description');
  String? get areaId => strOrNull('area_id');
}

class Goal extends Entity {
  Goal(super.raw);
  String get title => str('title');
  String? get description => strOrNull('description');
  String? get visionId => strOrNull('vision_id');
  String? get areaId => strOrNull('area_id');
  DateTime? get targetDate => dt('target_date');
  String get status => strOrNull('status') ?? 'active';
  int get manualProgress => integer('manual_progress');
}

// ------------------------------------------------------------ planning
class Project extends Entity {
  Project(super.raw);
  String get name => str('name');
  String? get description => strOrNull('description');
  String get status => strOrNull('status') ?? 'active';
  String? get goalId => strOrNull('goal_id');
  String? get areaId => strOrNull('area_id');
  String? get parentId => strOrNull('parent_id');
  DateTime? get dueDate => dt('due_date');
  String get color => strOrNull('color') ?? '#4F46E5';
  bool get isClosed => status == 'done' || status == 'archived';
}

class Milestone extends Entity {
  Milestone(super.raw);
  String get projectId => str('project_id');
  String get title => str('title');
  String? get description => strOrNull('description');
  DateTime? get dueDate => dt('due_date');
  int get sortOrder => integer('sort_order');
  bool get done => flag('done');
}

class ProjectNote extends Entity {
  ProjectNote(super.raw);
  String get projectId => str('project_id');
  String get content => str('content');
}

class TaskStep {
  const TaskStep(this.title, this.done);
  final String title;
  final bool done;
  Map<String, dynamic> toJson() => {'title': title, 'done': done};
}

class Task extends Entity {
  Task(super.raw);
  String get title => str('title');
  String? get notes => strOrNull('notes');
  DateTime? get dueDate => dt('due_date');
  int get priority => integer('priority');
  String get status => strOrNull('status') ?? 'todo';
  bool get isDone => status == 'done';
  DateTime? get completedAt => dt('completed_at');
  String? get projectId => strOrNull('project_id');
  String? get milestoneId => strOrNull('milestone_id');
  String? get goalId => strOrNull('goal_id');
  String? get categoryId => strOrNull('category_id');
  int? get estimate => intOrNull('estimate_minutes');
  List<String> get links => strings('links');
  List<TaskStep> get steps =>
      maps('steps').map((m) => TaskStep('${m['title'] ?? ''}', m['done'] == true)).toList();

  bool get isOverdue => !isDone && dueDate != null && dueDate!.isBefore(today());
}

// ------------------------------------------------------------ execution
class Habit extends Entity {
  Habit(super.raw);
  String get title => str('title');
  String? get description => strOrNull('description');
  String get frequency => strOrNull('frequency') ?? 'daily';
  int get target => frequency == 'daily' ? 1 : integer('target', 1).clamp(1, 31);
  String? get preferredTime => strOrNull('preferred_time');
  int? get preferredMinutes => parseHm(preferredTime);
  int get duration => integer('duration_minutes', 30);
  String? get areaId => strOrNull('area_id');
  String? get categoryId => strOrNull('category_id');
  String get color => strOrNull('color') ?? '#10B981';
  List<String> get steps => maps('steps').map((m) => '${m['title'] ?? ''}').where((s) => s.isNotEmpty).toList();
  bool get archived => flag('archived');
  int get sortOrder => integer('sort_order');
}

class HabitLog extends Entity {
  HabitLog(super.raw);
  String get habitId => str('habit_id');
  DateTime get date => dt('date') ?? today();
}

class PlanItem extends Entity {
  PlanItem(super.raw);
  DateTime get date => dt('date') ?? today();
  int get startMinutes => parseHm(strOrNull('start_time')) ?? 9 * 60;
  int get duration => integer('duration_minutes', 30);
  String? get taskId => strOrNull('task_id');
  String? get habitId => strOrNull('habit_id');
  String? get title => strOrNull('title');
  String? get notes => strOrNull('notes');
  bool get done => flag('done');
  bool get skipped => flag('skipped');
}

// ------------------------------------------------------------ capture
class IdeaStage extends Entity {
  IdeaStage(super.raw);
  String get name => str('name');
  String get color => strOrNull('color') ?? '#64748B';
  int get sortOrder => integer('sort_order');
}

class IdeaUpdate {
  const IdeaUpdate(this.date, this.text);
  final DateTime date;
  final String text;
  Map<String, dynamic> toJson() => {'date': isoUtc(date), 'text': text};
}

class Idea extends Entity {
  Idea(super.raw);
  String? get stageId => strOrNull('stage_id');
  String? get categoryId => strOrNull('category_id');
  String get title => str('title');
  String? get content => strOrNull('content');
  List<IdeaUpdate> get updates => maps('updates')
      .map((m) => IdeaUpdate(parseDateTime(m['date']) ?? DateTime.now(), '${m['text'] ?? ''}'))
      .toList();
  String? get convertedTaskId => strOrNull('converted_task_id');
  String? get convertedProjectId => strOrNull('converted_project_id');
}

class WisdomEntry extends Entity {
  WisdomEntry(super.raw);
  String? get title => strOrNull('title');
  String get content => str('content');
  String get category => strOrNull('category') ?? 'mindset';
  List<String> get tags => strings('tags');
  String? get collection => strOrNull('collection');
  bool get favorite => flag('favorite');
}

class ShoppingItem extends Entity {
  ShoppingItem(super.raw);
  String get name => str('name');
  String? get categoryId => strOrNull('category_id');
  double get quantity => numOrNull('quantity') ?? 1;
  double? get estimatedPrice => numOrNull('estimated_price');
  double? get actualPaid => numOrNull('actual_paid');
  bool get purchased => flag('purchased');
  DateTime? get purchasedAt => dt('purchased_at');
  DateTime? get targetDate => dt('target_date');
  String? get notes => strOrNull('notes');

  /// Only what was really paid counts as spending (qty 3 × 100 est. but 250 paid → 250).
  double get spent => purchased ? (actualPaid ?? 0) : 0;
  double get estimatedTotal => (estimatedPrice ?? 0) * quantity;
  DateTime get spendDate => purchasedAt ?? dateOnly(createdAt);
}

class TimeEntry extends Entity {
  TimeEntry(super.raw);
  String? get description => strOrNull('description');
  DateTime get startedAt => dt('started_at') ?? DateTime.now();
  DateTime? get endedAt => dt('ended_at');
  String? get taskId => strOrNull('task_id');
  String? get projectId => strOrNull('project_id');
  String? get areaId => strOrNull('area_id');
  bool get running => endedAt == null;

  /// Valid = finished, positive and below 16 hours.
  bool get isValid {
    final e = endedAt;
    if (e == null) return false;
    final d = e.difference(startedAt);
    return d.inSeconds > 0 && d.inHours < 16;
  }

  int get minutes => isValid ? endedAt!.difference(startedAt).inMinutes : 0;
}

class JournalEntry extends Entity {
  JournalEntry(super.raw);
  DateTime get date => dt('date') ?? today();
  String get content => str('content');
  int? get mood => intOrNull('mood');
  List<String> get tags => strings('tags');
}

class WeeklyReview extends Entity {
  WeeklyReview(super.raw);
  DateTime get weekStart => dt('week_start') ?? today();
  String get wins => str('wins');
  String get challenges => str('challenges');
  String get lessons => str('lessons');
  String get nextPriorities => str('next_priorities');
  int? get rating => intOrNull('rating');
}
