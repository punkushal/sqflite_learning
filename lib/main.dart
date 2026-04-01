import 'package:flutter/material.dart';
import 'production/db_helper.dart';
import 'production/models/task.dart';
import 'production/repository/task_repo.dart';

/// ============================================================
/// Putting it all together in a Flutter app
/// ============================================================

void main() async {
  // IMPORTANT: Must call this before using any plugins
  // WHY? → Flutter needs to set up the platform channels
  //        that communicate with native code (SQLite is native)
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize database (this also runs migrations if needed)
  await DatabaseHelper.instance.database;

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(title: 'SQFlite Demo', home: TaskListScreen());
  }
}

class TaskListScreen extends StatefulWidget {
  const TaskListScreen({super.key});

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  // Repository instance
  late final TaskRepository _taskRepo;
  List<Task> _tasks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _taskRepo = TaskRepository(DatabaseHelper.instance);
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    setState(() => _isLoading = true);
    try {
      _tasks = await _taskRepo.getByUserId(1); // User ID 1
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading tasks: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addTask() async {
    final now = DateTime.now();
    final task = Task(
      userId: 1,
      title: 'New Task ${_tasks.length + 1}',
      description: 'Created at $now',
      priority: TaskPriority.medium,
      createdAt: now,
      updatedAt: now,
    );

    await _taskRepo.insert(task);
    await _loadTasks(); // Refresh the list
  }

  Future<void> _toggleComplete(Task task) async {
    if (task.id == null) return;

    if (task.isCompleted) {
      // Mark as incomplete
      final now = DateTime.now();
      await _taskRepo.update(
        task.copyWith(isCompleted: false, updatedAt: now),
        task.id!,
      );
    } else {
      // Mark as complete
      await _taskRepo.markCompleted(task.id!);
    }

    await _loadTasks();
  }

  Future<void> _deleteTask(int id) async {
    await _taskRepo.delete(id);
    await _loadTasks();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
      floatingActionButton: FloatingActionButton(
        onPressed: _addTask,
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _tasks.isEmpty
          ? const Center(child: Text('No tasks yet!'))
          : ListView.builder(
              itemCount: _tasks.length,
              itemBuilder: (context, index) {
                final task = _tasks[index];
                return Dismissible(
                  key: Key('task_${task.id}'),
                  onDismissed: (_) => _deleteTask(task.id!),
                  child: ListTile(
                    leading: Checkbox(
                      value: task.isCompleted,
                      onChanged: (_) => _toggleComplete(task),
                    ),
                    title: Text(
                      task.title,
                      style: TextStyle(
                        decoration: task.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    subtitle: Text(
                      'Priority: ${task.priority.name} '
                      '| Created: ${task.createdAt.toString().substring(0, 16)}',
                    ),
                  ),
                );
              },
            ),
    );
  }
}
