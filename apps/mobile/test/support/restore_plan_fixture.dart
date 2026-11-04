import 'dart:async';
import 'dart:io';

import 'package:shika/library/models.dart';
import 'package:shika/library/repository.dart';
import 'package:shika/library/server_api.dart';

import '../server_maintenance_tasks_test.dart' show TaskServerFixture;
import 'maintenance_fixture.dart'
    show TasksLibrary, FakeTaskCatalog, taskSummary;
import 'pack_trash_fixture.dart' show TrashLibrary;

typedef PlanJson = Map<String, dynamic>;

PlanJson planJson(
  String id,
  String request,
  int count, {
  int succeeded = 0,
  int failed = 0,
  int stopped = 0,
  bool historical = false,
  bool stopRequested = false,
}) {
  final done = succeeded + failed + stopped == count;
  return {
    'id': id,
    'request_id': request,
    'kind': 'pack_restore_plan',
    'status': done ? 'completed' : 'running',
    'phase': done
        ? stopped > 0
              ? 'stopped'
              : 'completed'
        : 'restoring_batches',
    'historical': historical,
    'stop_requested': stopRequested,
    'batch_size': 1000,
    'error': stopped > 0 ? 'plan_stopped' : null,
    'created_at': 1792890000.0,
    'finished_at': done ? 1792890100.0 : null,
    'result': {
      'operation_id': id,
      'total': count,
      'processed': succeeded + failed,
      'succeeded': succeeded,
      'failed': failed,
      'stopped': stopped,
      'remaining': count - succeeded - failed - stopped,
      'batches': 1,
      'partial': stopped > 0 || failed > 0 && succeeded > 0,
    },
  };
}

PlanJson planSummary(PlanJson raw) {
  final result = raw['result'] as Map;
  return {
    ...taskSummary(
      raw['id'],
      kind: 'pack_restore_plan',
      state: raw['historical']
          ? 'historical'
          : raw['status'] == 'running'
          ? 'processing'
          : result['stopped'] > 0 || result['failed'] > 0
          ? 'partial'
          : 'completed',
    ),
    'phase': raw['phase'],
    'error': raw['error'],
    for (final key in [
      'total',
      'processed',
      'succeeded',
      'failed',
      'stopped',
      'remaining',
    ])
      key: result[key],
  };
}

class RestoreServerFixture extends TaskServerFixture {
  final planBook = <String, PlanJson>{},
      originals = <String, String>{},
      stops = <String, String>{};
  bool losePlan = false,
      loseStop = false,
      missBefore = false,
      corruptPlan = false;
  Completer<void>? postStarted, postRelease;
  final requests = <String>[];
  void complete(String id, {int stopped = 0}) {
    final old = planBook[id]!, total = (old['result'] as Map)['total'] as int;
    planBook[id] = planJson(
      id,
      old['request_id'],
      total,
      succeeded: total - stopped,
      stopped: stopped,
      stopRequested: old['stop_requested'],
    );
    summaries[id] = planSummary(planBook[id]!);
  }

  @override
  Future<({int status, PlanJson body})?> handle(
    HttpRequest r,
    PlanJson body,
  ) async {
    final path = r.uri.path;
    if (path == '/api/v1/info') {
      final response = await super.handle(r, body);
      return (
        status: 200,
        body: {
          ...response!.body,
          'capabilities': [
            ...response.body['capabilities'],
            'pack_restore_plans',
          ],
        },
      );
    }
    if (path.contains('pack-restore')) requests.add('${r.method} $path');
    if (path == '/api/v1/pack-restore-plans' && r.method == 'POST') {
      postStarted?.complete();
      if (postRelease != null) await postRelease!.future;
      if (!missBefore) {
        final id = 'plan-${originals.length}';
        originals[body['request_id']] = id;
        planBook[id] = planJson(
          id,
          body['request_id'],
          (body['trash_ids'] as List).length,
        );
        summaries[id] = planSummary(planBook[id]!);
      }
      if (losePlan || missBefore) {
        return (
          status: 503,
          body: {
            'error': {'code': 'reply_lost', 'message': '结果未知'},
          },
        );
      }
      return (status: 202, body: planBook[originals[body['request_id']]]!);
    }
    if (path.endsWith('/stop') && path.contains('pack-restore-plans')) {
      final id = r.uri.pathSegments[3];
      planBook[id]!['stop_requested'] = true;
      stops[body['request_id']] = id;
      if (loseStop) {
        return (
          status: 503,
          body: {
            'error': {'code': 'reply_lost', 'message': '停止结果未知'},
          },
        );
      }
      return (
        status: 202,
        body: {...planBook[id]!, 'stop_request_id': body['request_id']},
      );
    }
    if (path.contains('/pack-restore-requests/')) {
      final id = originals[r.uri.pathSegments.last];
      if (id == null) return missing();
      return (
        status: 200,
        body: corruptPlan
            ? {...planBook[id]!, 'request_id': 'wrong'}
            : planBook[id]!,
      );
    }
    if (path.contains('/pack-restore-stop-requests/')) {
      final key = r.uri.pathSegments.last, id = stops[key];
      if (id == null) return missing();
      return (status: 200, body: {...planBook[id]!, 'stop_request_id': key});
    }
    if (path.startsWith('/api/v1/pack-restore-plans/')) {
      final id = r.uri.pathSegments.last;
      return planBook.containsKey(id)
          ? (status: 200, body: planBook[id]!)
          : missing();
    }
    return super.handle(r, body);
  }
}

class RestoreLibrary extends TasksLibrary {
  RestoreLibrary({int count = 27}) {
    records.clear();
    records.addAll(TrashLibrary(count: count).records);
    rows = [];
    memberCount = count;
  }
  final planBook = <String, PlanJson>{},
      originalPlans = <String, String>{},
      stopKeys = <String, String>{};
  final planCalls = <String>[], planBodies = <PlanJson>[];
  bool losePlan = false, loseStop = false;
  Completer<void>? planStarted, planRelease;
  @override
  ServiceCapabilities get capabilities =>
      ServiceCapabilities([...super.capabilities.values, 'pack_restore_plans']);
  @override
  MaintenanceTaskCatalog createMaintenanceTasks() => RestoreTaskCatalog(this);
  @override
  PackRestorePlans createPackRestorePlans() {
    final identity = owner;
    return PackRestorePlans(
      journal: journal,
      scope: 'trash-fixture',
      isCurrent: () => identical(owner, identity),
      call: (method, path, {body}) async {
        planCalls.add('$method $path');
        if (method == 'POST' && path == '/api/v1/pack-restore-plans') {
          planBodies.add(body!);
          planStarted?.complete();
          if (planRelease != null) await planRelease!.future;
          final id = 'plan-${originalPlans.length}';
          originalPlans[body['request_id']] = id;
          planBook[id] = planJson(
            id,
            body['request_id'],
            (body['trash_ids'] as List).length,
          );
          rows = [MaintenanceTask(planSummary(planBook[id]!))];
          if (losePlan) {
            throw const ApiFailure(
              '恢复或停止结果待确认，请查询原请求',
              code: 'reply_lost',
              status: 503,
            );
          }
          return planBook[id]!;
        }
        if (method == 'POST') {
          planBodies.add(body!);
          final id = Uri.parse(path).pathSegments[3];
          planBook[id]!['stop_requested'] = true;
          stopKeys[body['request_id']] = id;
          if (loseStop) {
            throw const ApiFailure('停止未知', code: 'reply_lost', status: 503);
          }
          return {...planBook[id]!, 'stop_request_id': body['request_id']};
        }
        final key = Uri.parse(path).pathSegments.last;
        if (path.contains('pack-restore-stop-requests')) {
          final id = stopKeys[key];
          if (id != null) return {...planBook[id]!, 'stop_request_id': key};
        } else {
          final id = path.contains('pack-restore-requests')
              ? originalPlans[key]
              : key;
          if (planBook[id] != null) return planBook[id]!;
        }
        throw const ApiFailure('Unknown', code: 'not_found', status: 404);
      },
    );
  }
}

class RestoreTaskCatalog extends FakeTaskCatalog {
  RestoreTaskCatalog(this.library) : super(library);
  final RestoreLibrary library;
  @override
  Future<CatalogPage<MaintenanceItem>> items(
    String identity, {
    int offset = 0,
    int limit = 24,
    bool unfinished = true,
  }) async {
    final raw = library.planBook[identity];
    if (raw == null) {
      return super.items(
        identity,
        offset: offset,
        limit: limit,
        unfinished: unfinished,
      );
    }
    final result = raw['result'] as Map;
    final items = <MaintenanceItem>[];
    for (var i = 0; i < (result['total'] as int); i++) {
      final outcome = i < (result['succeeded'] as int)
          ? 'succeeded'
          : i < result['processed']
          ? 'failed'
          : result['stopped'] > 0
          ? 'stopped'
          : 'pending';
      if (unfinished && outcome == 'succeeded') continue;
      items.add(
        MaintenanceItem({
          'id': 'member-$i',
          'name': '图包$i',
          'path': '/packs/图包$i',
          'outcome': outcome,
          'phase': outcome,
          'error': outcome == 'stopped' ? 'plan_stopped' : null,
        }),
      );
    }
    return CatalogPage(
      items: items.skip(offset).take(limit).toList(),
      total: items.length,
      offset: offset,
      limit: limit,
    );
  }
}
