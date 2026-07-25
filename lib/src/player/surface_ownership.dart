import 'dart:async';

import 'package:flutter/widgets.dart';

/// 「独占底层 surface」的所有权仲裁：同一 owner（通常是
/// `NiumaPlayerController`）同一时刻只允许一份渲染 widget 持有 surface。
///
/// 存在的原因：Android platformView 路径下 ExoPlayer 的输出 surface 是
/// 独占的单一资源——平台视图构造时 `setVideoSurfaceView(自己)` 抢绑定、
/// 销毁时只释放自己的 surface 不归还。全屏路由把 inline 那份留在树上时
/// （共享 controller 架构的必然状态），退全屏后 player 就绑在已释放的
/// surface 上，画面停在最后一帧。
///
/// 语义与 1.x 自研 native 路径的 `PlayerSession.surfaceStack` 一致：后
/// push 的抢占，pop 时回退到栈里仍存活的上一个。
class SurfaceOwnership extends ChangeNotifier {
  SurfaceOwnership._(this._owner);

  static final Map<Object, SurfaceOwnership> _instances =
      <Object, SurfaceOwnership>{};

  /// 取（或惰性创建）[owner] 对应的仲裁器。栈空时实例自动销毁并移出表。
  static SurfaceOwnership of(Object owner) =>
      _instances.putIfAbsent(owner, () => SurfaceOwnership._(owner));

  final Object _owner;
  final List<Object> _stack = <Object>[];
  bool _notifyScheduled = false;

  /// 当前持有 surface 的 token；无人持有时为 null。
  Object? get active => _stack.isEmpty ? null : _stack.last;

  /// 抢占所有权（重复 push 同一 token 只是把它挪到栈顶）。
  void push(Object token) {
    _stack
      ..remove(token)
      ..add(token);
    _scheduleNotify();
  }

  /// 交还所有权；若 [token] 是当前持有者，则回退给栈里仍存活的上一个。
  void pop(Object token) {
    if (!_stack.remove(token)) return;
    _scheduleNotify();
  }

  // push / pop 发生在 initState / dispose，即 build 阶段内；同步
  // notifyListeners 会对另一份已构建的 gate 触发 markNeedsBuild，撞
  // 「setState() called during build」断言。故延到微任务。
  void _scheduleNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (_stack.isEmpty) {
        _instances.remove(_owner);
        dispose();
        return;
      }
      notifyListeners();
    });
  }
}

/// 独占 surface 的渲染门：同一 [owner] 下只有最后 mount 的那份调用
/// [builder] 构造真正的渲染 widget，其余渲染 [placeholder]。
///
/// 持有者 unmount 时所有权回退给栈里仍存活的上一个，它随之重建渲染
/// widget——平台视图重新构造，绑定自然恢复。
class ExclusiveSurfaceGate extends StatefulWidget {
  /// 构造一个渲染门。
  const ExclusiveSurfaceGate({
    super.key,
    required this.owner,
    required this.builder,
    required this.placeholder,
  });

  /// 仲裁作用域，同一个 owner 下的 gate 互相抢占。
  final Object owner;

  /// 持有所有权时构造的渲染 widget。
  final WidgetBuilder builder;

  /// 未持有所有权时渲染的占位。
  final Widget placeholder;

  @override
  State<ExclusiveSurfaceGate> createState() => _ExclusiveSurfaceGateState();
}

class _ExclusiveSurfaceGateState extends State<ExclusiveSurfaceGate> {
  late SurfaceOwnership _ownership;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(ExclusiveSurfaceGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.owner, widget.owner)) {
      _detach();
      _attach();
    }
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _attach() {
    _ownership = SurfaceOwnership.of(widget.owner)
      ..addListener(_onOwnershipChanged)
      ..push(this);
  }

  void _detach() {
    _ownership
      ..removeListener(_onOwnershipChanged)
      ..pop(this);
  }

  void _onOwnershipChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return identical(_ownership.active, this)
        ? widget.builder(context)
        : widget.placeholder;
  }
}
