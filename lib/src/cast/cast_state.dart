/// 投屏会话连接状态。
enum CastConnectionState {
  /// 没投屏。
  idle,

  /// 正在发现设备。
  discovering,

  /// 已选设备，正在连接。
  connecting,

  /// 已连接，可发命令。
  connected,

  /// 出错（具体原因见 events 流的 CastError 事件）。
  error,
}

/// 投屏结束原因。
enum CastEndReason {
  /// 用户主动断开。
  userCancelled,

  /// 网络问题（重试 3 次失败）。
  networkError,

  /// 设备主动 byebye / 不可达。
  deviceLost,

  /// 超时（如 connect 30s 不返回）。
  timeout,
}
