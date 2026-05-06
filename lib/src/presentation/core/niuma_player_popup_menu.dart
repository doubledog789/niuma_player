// 自定义 PopupMenuRoute——绕开 Flutter `showMenu` 的 safe-area clamp，
// 让 more 菜单能精确锚到 ⋮ 按钮 RenderBox 真实坐标。详见 [NiumaPlayer]
// 内 `_showMoreMenu` 调用方注释。
//
// 这 3 个类（`_NiumaPopupMenuRoute` / `_NiumaPopupMenu` /
// `_NiumaPopupMenuRouteLayout`）原本都内嵌在 niuma_player.dart 里，
// 把这部分独立成 part 让 niuma_player.dart 主体专注 [NiumaPlayer] widget
// 自身职责。仍是 underscore 私有——`part of` 共享同一 library，跨 part
// 互访不需公开化、不污染 SDK API surface。
part of 'niuma_player.dart';

const double _kNiumaPopupMenuMinWidth = 112.0;
const double _kNiumaPopupMenuMaxWidth = 280.0;
const double _kNiumaPopupMenuWidthStep = 56.0;
const double _kNiumaPopupMenuScreenPadding = 8.0;

class _NiumaPopupMenuRoute<T> extends PopupRoute<T> {
  _NiumaPopupMenuRoute({
    required this.position,
    required this.items,
    required this.barrierLabel,
    required this.semanticLabel,
    required this.capturedThemes,
  }) : super(traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop);

  final RelativeRect position;
  final List<PopupMenuEntry<T>> items;
  final String? semanticLabel;
  final CapturedThemes capturedThemes;

  @override
  final String? barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 120);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final mediaQuery = MediaQuery.of(context);
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      removeLeft: true,
      removeRight: true,
      child: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: FocusScope(
          autofocus: true,
          child: CustomSingleChildLayout(
            delegate: _NiumaPopupMenuRouteLayout(
              position,
              DisplayFeatureSubScreen.avoidBounds(mediaQuery).toSet(),
            ),
            child: capturedThemes.wrap(
              _NiumaPopupMenu<T>(
                items: items,
                semanticLabel: semanticLabel,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    );
  }
}

class _NiumaPopupMenu<T> extends StatelessWidget {
  const _NiumaPopupMenu({
    required this.items,
    required this.semanticLabel,
  });

  final List<PopupMenuEntry<T>> items;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final popupTheme = PopupMenuTheme.of(context);
    final defaultElevation = theme.useMaterial3 ? 3.0 : 8.0;
    final defaultShape = theme.useMaterial3
        ? const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(4)),
          )
        : null;
    final defaultColor = theme.useMaterial3 ? theme.colorScheme.surface : null;
    final defaultSurfaceTintColor =
        theme.useMaterial3 ? Colors.transparent : null;

    return Material(
      type: MaterialType.card,
      elevation: popupTheme.elevation ?? defaultElevation,
      shadowColor: popupTheme.shadowColor,
      surfaceTintColor: popupTheme.surfaceTintColor ?? defaultSurfaceTintColor,
      color: popupTheme.color ?? defaultColor,
      shape: popupTheme.shape ?? defaultShape,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: _kNiumaPopupMenuMinWidth,
          maxWidth: _kNiumaPopupMenuMaxWidth,
        ),
        child: IntrinsicWidth(
          stepWidth: _kNiumaPopupMenuWidthStep,
          child: Semantics(
            scopesRoute: true,
            namesRoute: true,
            explicitChildNodes: true,
            label: semanticLabel,
            child: SingleChildScrollView(
              padding: popupTheme.menuPadding ??
                  const EdgeInsets.symmetric(vertical: 8),
              child: ListBody(children: items),
            ),
          ),
        ),
      ),
    );
  }
}

class _NiumaPopupMenuRouteLayout extends SingleChildLayoutDelegate {
  _NiumaPopupMenuRouteLayout(this.position, this.avoidBounds);

  final RelativeRect position;
  final Set<Rect> avoidBounds;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(constraints.biggest).deflate(
      const EdgeInsets.all(_kNiumaPopupMenuScreenPadding),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double x;
    if (position.left > position.right) {
      x = size.width - position.right - childSize.width;
    } else {
      x = position.left;
    }

    final wantedPosition = Offset(x, position.top);
    final originCenter = position.toRect(Offset.zero & size).center;
    final subScreens = DisplayFeatureSubScreen.subScreensInBounds(
      Offset.zero & size,
      avoidBounds,
    );
    final subScreen = _closestScreen(subScreens, originCenter);
    return _fitInsideScreen(subScreen, childSize, wantedPosition);
  }

  Rect _closestScreen(Iterable<Rect> screens, Offset point) {
    var closest = screens.first;
    for (final screen in screens) {
      if ((screen.center - point).distance <
          (closest.center - point).distance) {
        closest = screen;
      }
    }
    return closest;
  }

  Offset _fitInsideScreen(Rect screen, Size childSize, Offset wantedPosition) {
    var x = wantedPosition.dx;
    var y = wantedPosition.dy;
    final minX = screen.left + _kNiumaPopupMenuScreenPadding;
    final maxX = screen.right - childSize.width - _kNiumaPopupMenuScreenPadding;
    if (maxX < minX) {
      x = minX;
    } else if (x < minX) {
      x = minX;
    } else if (x > maxX) {
      x = maxX;
    }

    final minY = screen.top + _kNiumaPopupMenuScreenPadding;
    final maxY =
        screen.bottom - childSize.height - _kNiumaPopupMenuScreenPadding;
    if (maxY < minY) {
      y = minY;
    } else if (y < minY) {
      y = minY;
    } else if (y > maxY) {
      y = maxY;
    }

    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_NiumaPopupMenuRouteLayout oldDelegate) {
    if (position != oldDelegate.position) return true;
    if (avoidBounds.length != oldDelegate.avoidBounds.length) return true;
    return avoidBounds.any((bound) => !oldDelegate.avoidBounds.contains(bound));
  }
}
