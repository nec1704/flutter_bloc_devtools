part of flutter_bloc_devtools;

/// The connection state of the middleware
enum RemoteDevToolsStatus {
  /// No socket connection to the remote host
  notConnected,

  /// Attempting to open socket
  connecting,

  /// Connected to remote, but not started
  connected,

  /// Awating start response
  starting,

  /// Sending and receiving actions
  started
}

class RemoteDevToolsObserver extends BlocObserver {
  ///
  /// The remote-devtools server to connect to. Should include
  /// protocol and port if necessary. For example:
  ///
  /// example.lan:8000
  ///
  final String _host;
  late SocketClusterWrapper socket;
  late String _channel;
  RemoteDevToolsStatus _status = RemoteDevToolsStatus.notConnected;

  RemoteDevToolsStatus get status => _status;

  final Map<String, Map<int, String>> _blocs = {};
  final Map<String, dynamic> _appState = {};

  /// The name that will appear in Instance Name in Dev Tools. If not specified,
  /// default to 'flutter'.
  late String instanceName;

  RemoteDevToolsObserver(
    this._host, {
    SocketClusterWrapper? socket,
    String? instanceName,
  }) {
    this.socket = socket ?? SocketClusterWrapper('ws://$_host/socketcluster/');
    this.instanceName = instanceName ?? 'flutter';
  }

  Future<void> connect() async {
    _status = RemoteDevToolsStatus.connecting;
    print('trying to connect to socket at $_host');
    await socket.connect();
    _status = RemoteDevToolsStatus.connected;
    print('connected to socket at $_host');
    _channel = await _login();
    _status = RemoteDevToolsStatus.starting;
    _relayStart();
    // _relay('START');
    await _waitForStart();
  }

  Future<String> _login() {
    final c = Completer<String>();
    socket.emit('login', 'master', (String name, dynamic error, dynamic data) {
      c.complete(data as String);
    });
    return c.future;
  }

  Future<dynamic> _waitForStart() {
    final c = Completer();
    socket.on(_channel, (String? name, dynamic data) {
      if (data['type'] == 'START') {
        _status = RemoteDevToolsStatus.started;
        c.complete();
      } else {
        c.completeError(data);
      }
    });
    return c.future;
  }

  String _getBlocName(BlocBase bloc) {
    final blocName = bloc.runtimeType.toString();
    final blocHash = bloc.hashCode;
    if (_blocs.containsKey(blocName)) {
      if (!_blocs[blocName]!.containsKey(blocHash)) {
        _blocs[blocName]![blocHash] =
            '$blocName-${_blocs[blocName]!.keys.length}';
      }
    } else {
      _blocs[blocName] = {blocHash: blocName};
    }
    return _blocs[blocName]![blocHash]!;
  }

  void _removeBlocName(BlocBase bloc) {
    final blocName = bloc.runtimeType.toString();
    final blocHash = bloc.hashCode;
    if (_blocs.containsKey(blocName) &&
        _blocs[blocName]!.containsKey(blocHash)) {
      _blocs[blocName]!.remove(blocHash);
    }
  }

  void _relayStart() {
    final message = {'type': 'START', 'id': socket.id, 'name': instanceName};
    socket.emit(socket.id != null ? 'log' : 'log-noid', message);
  }

  void _relay(String type,
      BlocBase bloc, Object? state, dynamic action, String? nextActionId) {
    final message = {'type': type, 'id': socket.id, 'name': instanceName};
    final blocName = _getBlocName(bloc);

    if (state == null) {
      /// Remove Bloc state
      if (_appState.containsKey(blocName)) {
        _removeBlocName(bloc);
        _appState.remove(blocName);
        message['payload'] = jsonEncode(_appState);
      }
    } else {
      _appState[blocName] = _maybeToJson(state) ?? state.toString();
    }

    message['payload'] = jsonEncode(_appState);
    message['action'] = _actionEncode(action);

    if (type == 'ACTION') {
      message['nextActionId'] = nextActionId;
    }
    socket.emit(socket.id != null ? 'log' : 'log-noid', message);
  }

  @override
  void onTransition(Bloc bloc, Transition transition) {
    super.onTransition(bloc, transition);
    if (status == RemoteDevToolsStatus.started) {
      _relay('ACTION', bloc, transition.nextState, transition.event, null);
    }
  }

  @override
  void onCreate(BlocBase bloc) {
    super.onCreate(bloc);
    if (status == RemoteDevToolsStatus.started) {
      _relay('ACTION', bloc, bloc.state, 'OnCreate', null);
    }
  }

  @override
  void onClose(BlocBase bloc) {
    super.onClose(bloc);
    if (status == RemoteDevToolsStatus.started) {
      _relay('ACTION', bloc, null, 'OnClose', null);
    }
  }

  Object? _maybeToJson(dynamic object) {
    try {
      return object.toJson();
    } on NoSuchMethodError {
      return null;
    }
  }

  String? _actionEncode(Object? action) {
    if (action == null) {
      return null;
    }
    final jsonOrNull = _maybeToJson(action);

    var actionName = action.toString();
    if (actionName.contains('Instance of')) {
      actionName = action.runtimeType.toString();
    }

    return jsonEncode({
      'type': actionName,
      if (jsonOrNull != null &&
          (jsonOrNull is Map ? jsonOrNull.isNotEmpty : true))
        'payload': jsonOrNull,
    });

  }
}
