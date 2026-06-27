// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $CheckpointsTable extends Checkpoints
    with TableInfo<$CheckpointsTable, Checkpoint> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CheckpointsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stepMeta = const VerificationMeta('step');
  @override
  late final GeneratedColumn<int> step = GeneratedColumn<int>(
    'step',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<String> data = GeneratedColumn<String>(
    'data',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, step, status, data];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'checkpoints';
  @override
  VerificationContext validateIntegrity(
    Insertable<Checkpoint> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('step')) {
      context.handle(
        _stepMeta,
        step.isAcceptableOrUnknown(data['step']!, _stepMeta),
      );
    } else if (isInserting) {
      context.missing(_stepMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('data')) {
      context.handle(
        _dataMeta,
        this.data.isAcceptableOrUnknown(data['data']!, _dataMeta),
      );
    } else if (isInserting) {
      context.missing(_dataMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Checkpoint map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Checkpoint(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      step: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}step'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      data: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data'],
      )!,
    );
  }

  @override
  $CheckpointsTable createAlias(String alias) {
    return $CheckpointsTable(attachedDatabase, alias);
  }
}

class Checkpoint extends DataClass implements Insertable<Checkpoint> {
  /// The run id this snapshot belongs to (primary key).
  final String id;

  /// The step index reached.
  final int step;

  /// The serialized [CheckpointStatus] name.
  final String status;

  /// The serialized checkpoint (`jsonEncode(checkpointToJson(...))`).
  final String data;
  const Checkpoint({
    required this.id,
    required this.step,
    required this.status,
    required this.data,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['step'] = Variable<int>(step);
    map['status'] = Variable<String>(status);
    map['data'] = Variable<String>(data);
    return map;
  }

  CheckpointsCompanion toCompanion(bool nullToAbsent) {
    return CheckpointsCompanion(
      id: Value(id),
      step: Value(step),
      status: Value(status),
      data: Value(data),
    );
  }

  factory Checkpoint.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Checkpoint(
      id: serializer.fromJson<String>(json['id']),
      step: serializer.fromJson<int>(json['step']),
      status: serializer.fromJson<String>(json['status']),
      data: serializer.fromJson<String>(json['data']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'step': serializer.toJson<int>(step),
      'status': serializer.toJson<String>(status),
      'data': serializer.toJson<String>(data),
    };
  }

  Checkpoint copyWith({String? id, int? step, String? status, String? data}) =>
      Checkpoint(
        id: id ?? this.id,
        step: step ?? this.step,
        status: status ?? this.status,
        data: data ?? this.data,
      );
  Checkpoint copyWithCompanion(CheckpointsCompanion data) {
    return Checkpoint(
      id: data.id.present ? data.id.value : this.id,
      step: data.step.present ? data.step.value : this.step,
      status: data.status.present ? data.status.value : this.status,
      data: data.data.present ? data.data.value : this.data,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Checkpoint(')
          ..write('id: $id, ')
          ..write('step: $step, ')
          ..write('status: $status, ')
          ..write('data: $data')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, step, status, data);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Checkpoint &&
          other.id == this.id &&
          other.step == this.step &&
          other.status == this.status &&
          other.data == this.data);
}

class CheckpointsCompanion extends UpdateCompanion<Checkpoint> {
  final Value<String> id;
  final Value<int> step;
  final Value<String> status;
  final Value<String> data;
  final Value<int> rowid;
  const CheckpointsCompanion({
    this.id = const Value.absent(),
    this.step = const Value.absent(),
    this.status = const Value.absent(),
    this.data = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CheckpointsCompanion.insert({
    required String id,
    required int step,
    required String status,
    required String data,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       step = Value(step),
       status = Value(status),
       data = Value(data);
  static Insertable<Checkpoint> custom({
    Expression<String>? id,
    Expression<int>? step,
    Expression<String>? status,
    Expression<String>? data,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (step != null) 'step': step,
      if (status != null) 'status': status,
      if (data != null) 'data': data,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CheckpointsCompanion copyWith({
    Value<String>? id,
    Value<int>? step,
    Value<String>? status,
    Value<String>? data,
    Value<int>? rowid,
  }) {
    return CheckpointsCompanion(
      id: id ?? this.id,
      step: step ?? this.step,
      status: status ?? this.status,
      data: data ?? this.data,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (step.present) {
      map['step'] = Variable<int>(step.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CheckpointsCompanion(')
          ..write('id: $id, ')
          ..write('step: $step, ')
          ..write('status: $status, ')
          ..write('data: $data, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$CheckpointDatabase extends GeneratedDatabase {
  _$CheckpointDatabase(QueryExecutor e) : super(e);
  $CheckpointDatabaseManager get managers => $CheckpointDatabaseManager(this);
  late final $CheckpointsTable checkpoints = $CheckpointsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [checkpoints];
}

typedef $$CheckpointsTableCreateCompanionBuilder =
    CheckpointsCompanion Function({
      required String id,
      required int step,
      required String status,
      required String data,
      Value<int> rowid,
    });
typedef $$CheckpointsTableUpdateCompanionBuilder =
    CheckpointsCompanion Function({
      Value<String> id,
      Value<int> step,
      Value<String> status,
      Value<String> data,
      Value<int> rowid,
    });

class $$CheckpointsTableFilterComposer
    extends Composer<_$CheckpointDatabase, $CheckpointsTable> {
  $$CheckpointsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get step => $composableBuilder(
    column: $table.step,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CheckpointsTableOrderingComposer
    extends Composer<_$CheckpointDatabase, $CheckpointsTable> {
  $$CheckpointsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get step => $composableBuilder(
    column: $table.step,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CheckpointsTableAnnotationComposer
    extends Composer<_$CheckpointDatabase, $CheckpointsTable> {
  $$CheckpointsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get step =>
      $composableBuilder(column: $table.step, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);
}

class $$CheckpointsTableTableManager
    extends
        RootTableManager<
          _$CheckpointDatabase,
          $CheckpointsTable,
          Checkpoint,
          $$CheckpointsTableFilterComposer,
          $$CheckpointsTableOrderingComposer,
          $$CheckpointsTableAnnotationComposer,
          $$CheckpointsTableCreateCompanionBuilder,
          $$CheckpointsTableUpdateCompanionBuilder,
          (
            Checkpoint,
            BaseReferences<_$CheckpointDatabase, $CheckpointsTable, Checkpoint>,
          ),
          Checkpoint,
          PrefetchHooks Function()
        > {
  $$CheckpointsTableTableManager(
    _$CheckpointDatabase db,
    $CheckpointsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CheckpointsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CheckpointsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CheckpointsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> step = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> data = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CheckpointsCompanion(
                id: id,
                step: step,
                status: status,
                data: data,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required int step,
                required String status,
                required String data,
                Value<int> rowid = const Value.absent(),
              }) => CheckpointsCompanion.insert(
                id: id,
                step: step,
                status: status,
                data: data,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CheckpointsTableProcessedTableManager =
    ProcessedTableManager<
      _$CheckpointDatabase,
      $CheckpointsTable,
      Checkpoint,
      $$CheckpointsTableFilterComposer,
      $$CheckpointsTableOrderingComposer,
      $$CheckpointsTableAnnotationComposer,
      $$CheckpointsTableCreateCompanionBuilder,
      $$CheckpointsTableUpdateCompanionBuilder,
      (
        Checkpoint,
        BaseReferences<_$CheckpointDatabase, $CheckpointsTable, Checkpoint>,
      ),
      Checkpoint,
      PrefetchHooks Function()
    >;

class $CheckpointDatabaseManager {
  final _$CheckpointDatabase _db;
  $CheckpointDatabaseManager(this._db);
  $$CheckpointsTableTableManager get checkpoints =>
      $$CheckpointsTableTableManager(_db, _db.checkpoints);
}
