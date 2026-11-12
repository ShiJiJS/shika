import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../library/repository.dart';
import '../../library/models.dart';
import '../../library/server_api.dart';
import '../../ui/paper.dart';
import '../../ui/paper_form.dart';
import '../../ui/preferences.dart';

enum _Step { welcome, server, setup, login }

/// An authentication surface, never a destination inside the media shell.
class ConnectionFlow extends StatefulWidget {
  const ConnectionFlow({
    super.key,
    required this.repository,
    required this.preferences,
    this.onConnected,
    this.onCancel,
    this.autoCheck = false,
    this.initialError,
  });
  final LibraryRepository repository;
  final UiPreferences preferences;
  final VoidCallback? onConnected, onCancel;
  final bool autoCheck;
  final String? initialError;

  @override
  State<ConnectionFlow> createState() => _ConnectionFlowState();
}

class _ConnectionFlowState extends State<ConnectionFlow> {
  final address = TextEditingController(), port = TextEditingController();
  final password = TextEditingController(),
      confirmation = TextEditingController();
  final failureAnchor = GlobalKey();
  late _Step step;
  bool busy = false, showPassword = false;
  late String error = widget.initialError ?? '';
  int operation = 0;
  (String, int)? remembered;
  LibraryRepository get repo => widget.repository;

  @override
  void initState() {
    super.initState();
    syncAddress();
    step = !widget.preferences.onboardingComplete && address.text.isEmpty
        ? _Step.welcome
        : _Step.server;
    repo.addListener(syncAddress);
    if (widget.autoCheck && address.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(checkServer(restoring: true));
      });
    }
  }

  void syncAddress() {
    final saved = (repo.snapshot.address, repo.snapshot.port);
    if (remembered == saved) return;
    remembered = saved;
    address.text = saved.$1;
    port.text = '${saved.$2}';
  }

  void clearSecret() {
    password.clear();
    confirmation.clear();
    showPassword = false;
  }

  void back() {
    final wasServer = step == _Step.server;
    operation++;
    if (busy) repo.cancelConnection();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      busy = false;
      error = '';
      clearSecret();
      if (step == _Step.server && widget.onCancel == null) {
        step = _Step.welcome;
      } else if (step != _Step.server) {
        step = _Step.server;
      }
    });
    if (wasServer && widget.onCancel != null) widget.onCancel!();
  }

  void showFailure(String text) {
    setState(() => error = text);
    revealFormError(failureAnchor);
  }

  Future<void> begin() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.preferences.completeOnboarding();
      if (mounted) setState(() => step = _Step.server);
    } catch (_) {
      if (mounted) showFailure('未能保存引导状态，请重试。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> checkServer({bool restoring = false}) async {
    if (busy) return;
    if (address.text.trim().isEmpty ||
        (int.tryParse(port.text) ?? 0) < 1 ||
        (int.tryParse(port.text) ?? 0) > 65535) {
      showFailure('请填写地址和 1–65535 之间的端口');
      return;
    }
    final serial = ++operation;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final setup = await repo.connectionNeedsSetup(
        address.text.trim(),
        int.parse(port.text),
      );
      if (!mounted || serial != operation) return;
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() {
        clearSecret();
        step = setup ? _Step.setup : _Step.login;
        if (restoring) error = widget.initialError ?? '';
      });
    } catch (failure) {
      if (mounted && serial == operation) {
        showFailure(connectionFailure(failure));
      }
    } finally {
      if (mounted && serial == operation) setState(() => busy = false);
    }
  }

  Future<void> submit() async {
    if (busy) return;
    final setup = step == _Step.setup;
    if (password.text.trim().isEmpty ||
        password.text.length > 1024 ||
        setup && password.text.length < 8) {
      showFailure(setup ? '个人口令需要8–1024个字符' : '请填写个人口令');
      return;
    }
    if (setup && password.text != confirmation.text) {
      showFailure('两次输入的口令不一致');
      return;
    }
    final serial = ++operation;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      if (setup) {
        await repo.setupConnection(
          address.text.trim(),
          int.parse(port.text),
          password.text,
        );
      } else {
        await repo.connect(
          address.text.trim(),
          int.parse(port.text),
          password.text,
        );
      }
      if (!mounted || serial != operation) return;
      clearSecret();
      FocusManager.instance.primaryFocus?.unfocus();
      widget.onConnected?.call();
    } catch (failure) {
      if (!mounted || serial != operation) return;
      if (failure is ApiFailure && failure.code == 'setup_completed') {
        setState(() {
          step = _Step.login;
          confirmation.clear();
        });
      }
      showFailure(connectionFailure(failure));
    } finally {
      if (mounted && serial == operation) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    repo.removeListener(syncAddress);
    operation++;
    if (busy) repo.cancelConnection();
    address.dispose();
    port.dispose();
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> help({bool forgotten = false}) => paperSheet<void>(
    context,
    SheetFrame(
      title: forgotten ? '找回个人口令' : '连接前的准备',
      children: forgotten
          ? const [
              Text('请联系 NAS 管理者重置服务端口令，再用新口令连接。'),
              SizedBox(height: 16),
              Text('重新安装 App 不会重置 NAS 上的口令或媒体数据。'),
            ]
          : const [
              Text(
                '先在 NAS 部署拾刻服务端',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              Text('App 用来浏览和整理内容，媒体和管理数据由 NAS 保存。'),
              SizedBox(height: 20),
              Text('查看服务的访问地址', style: TextStyle(fontWeight: FontWeight.w600)),
              Text('填写 NAS 的 IP 或域名，端口使用部署时设置的值，默认是 8760。'),
              SizedBox(height: 20),
              Text('连接后设置个人口令', style: TextStyle(fontWeight: FontWeight.w600)),
              Text('新服务会让你设置口令；已经使用过的服务，输入原口令即可。'),
            ],
    ),
  );

  Widget failure() => Padding(
    key: failureAnchor,
    padding: EdgeInsets.only(bottom: error.isEmpty ? 0 : 16),
    child: error.isEmpty
        ? const SizedBox.shrink()
        : Text(
            error,
            key: const Key('connection-error'),
            style: TextStyle(
              color: Paper.of(context).danger,
              fontSize: 14,
              height: 1.7,
            ),
          ),
  );

  Widget action(String label, VoidCallback callback) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      key: const Key('connection-save'),
      onPressed: busy ? null : callback,
      style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy) ...[
            SizedBox(
              width: 16,
              height: 16,
              child: PaperCircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
            const SizedBox(width: 9),
          ],
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ],
      ),
    ),
  );

  Widget welcome() => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
          child: IntrinsicHeight(
            child: Column(
              children: [
                SizedBox(height: math.max(20, constraints.maxHeight * .08)),
                const ConnectionBrand(size: 112),
                const SizedBox(height: 20),
                Text(
                  '拾刻',
                  style: Paper.of(context).title
                      .copyWith(fontSize: 40, letterSpacing: 4),
                ),
                const SizedBox(height: 6),
                Text(
                  '边看边整理的私人媒体库',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Paper.of(context).muted,
                  ),
                ),
                const SizedBox(height: 44),
                for (final item in [
                  (Icons.smart_display_outlined, '视频与图包，各自好好收藏'),
                  (Icons.sell_outlined, '标签、阅读进度，留在自己的 NAS'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 17),
                    child: Row(
                      children: [
                        Icon(item.$1, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            item.$2,
                            style: const TextStyle(fontSize: 14, height: 1.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                const Spacer(),
                const SizedBox(height: 40),
                failure(),
                action('连接我的媒体库', begin),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => help(),
                  child: const Text('还没有部署服务端？'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget passwordField({bool confirm = false}) => PaperField(
    label: confirm ? '再次输入口令' : '个人口令',
    child: TextField(
      key: Key(
        confirm ? 'connection-confirm-passphrase' : 'connection-passphrase',
      ),
      controller: confirm ? confirmation : password,
      enabled: !busy,
      obscureText: !showPassword,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: [
        step == _Step.setup
            ? AutofillHints.newPassword
            : AutofillHints.password,
      ],
      textInputAction: confirm || step == _Step.login
          ? TextInputAction.done
          : TextInputAction.next,
      onSubmitted: confirm || step == _Step.login ? (_) => submit() : null,
      decoration: InputDecoration(
        hintText: step == _Step.setup && !confirm ? '至少 8 个字符' : null,
        suffixIcon: confirm
            ? null
            : IconButton(
                tooltip: showPassword ? '隐藏口令' : '显示口令',
                onPressed: () => setState(() => showPassword = !showPassword),
                icon: Icon(
                  showPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 21,
                ),
              ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = Paper.of(context);
    final server = step == _Step.server, setup = step == _Step.setup;
    return PopScope<void>(
      canPop: step == _Step.welcome && widget.onCancel == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) back();
      },
      child: Scaffold(
        key: const Key('authentication-screen'),
        body: SafeArea(
          child: TweenAnimationBuilder<double>(
            key: ValueKey(step),
            tween: Tween(begin: 0, end: 1),
            duration:
                MediaQuery.disableAnimationsOf(context) || step == _Step.welcome
                ? Duration.zero
                : PaperMotion.transition,
            curve: PaperMotion.response,
            builder: (context, value, child) =>
                Opacity(opacity: value, child: child),
            child: step == _Step.welcome
                ? welcome()
                : Column(
                    children: [
                      SizedBox(
                        height: 50,
                        child: Row(
                          children: [
                            const SizedBox(width: 16),
                            IconButton(
                              key: const Key('connection-back'),
                              tooltip: '返回',
                              onPressed: back,
                              icon: const Icon(Icons.chevron_left),
                            ),
                            Text('拾刻', style: p.title.copyWith(fontSize: 19)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                          child: AutofillGroup(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  server
                                      ? '连接媒体库'
                                      : setup
                                      ? '设置个人口令'
                                      : '连接已有媒体库',
                                  style: p.title.copyWith(
                                    fontSize: 28,
                                    height: 1.45,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  server
                                      ? '填写 NAS 上拾刻服务的地址。'
                                      : setup
                                      ? '这是新部署的媒体库。设置后，其他设备也使用这个口令连接。'
                                      : '这个服务已设置口令，输入后即可进入。',
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.75,
                                    color: p.muted,
                                  ),
                                ),
                                const SizedBox(height: 26),
                                if (server) ...[
                                  PaperField(
                                    label: '服务器地址',
                                    child: TextField(
                                      key: const Key('connection-address'),
                                      controller: address,
                                      enabled: !busy,
                                      keyboardType: TextInputType.url,
                                      textInputAction: TextInputAction.next,
                                      autocorrect: false,
                                      decoration: const InputDecoration(
                                        hintText: 'NAS 的 IP 或域名',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  PaperField(
                                    label: '端口',
                                    child: TextField(
                                      key: const Key('connection-port'),
                                      controller: port,
                                      enabled: !busy,
                                      keyboardType: TextInputType.number,
                                      textInputAction: TextInputAction.done,
                                      onSubmitted: (_) => checkServer(),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    '手机需能访问该地址，通常连接同一 Wi-Fi。',
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.75,
                                      color: p.muted,
                                    ),
                                  ),
                                  const SizedBox(height: 22),
                                  failure(),
                                  action(busy ? '正在连接…' : '连接服务器', checkServer),
                                  if (busy)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: Text(
                                        '正在确认服务器是否已设置口令',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: p.muted,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 15),
                                  TextButton(
                                    onPressed: () => help(),
                                    child: const Text('地址和端口在哪里找？'),
                                  ),
                                ] else ...[
                                  Container(
                                    padding: const EdgeInsets.only(bottom: 13),
                                    margin: const EdgeInsets.only(bottom: 25),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(color: p.line),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.circle,
                                          size: 6,
                                          color: p.olive,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '${address.text}:${port.text}',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: p.muted,
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: back,
                                          child: const Text('更换'),
                                        ),
                                      ],
                                    ),
                                  ),
                                  passwordField(),
                                  if (setup) ...[
                                    const SizedBox(height: 20),
                                    passwordField(confirm: true),
                                  ],
                                  const SizedBox(height: 16),
                                  if (setup) ...[
                                    Text(
                                      '请妥善保存，可在连接后到设置中修改。',
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.75,
                                        color: p.muted,
                                      ),
                                    ),
                                    const SizedBox(height: 22),
                                  ],
                                  failure(),
                                  action(
                                    busy
                                        ? (setup ? '正在设置…' : '正在验证…')
                                        : setup
                                        ? '设置口令并进入'
                                        : '连接并进入',
                                    submit,
                                  ),
                                  if (!setup) ...[
                                    const SizedBox(height: 15),
                                    TextButton(
                                      onPressed: () => help(forgotten: true),
                                      child: const Text('忘记口令？'),
                                    ),
                                  ],
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

String connectionFailure(Object failure) =>
    failure is LibraryFailure ? failure.message : '暂时无法连接服务，请检查地址和网络后重试。';

class ConnectionBrand extends StatelessWidget {
  const ConnectionBrand({super.key, this.size = 76});
  final double size;
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/branding/icon.png',
    width: size,
    height: size,
    semanticLabel: '拾刻图标',
  );
}

/// No cached library is visible while a stored credential is being verified.
class ConnectionRestoration extends StatelessWidget {
  const ConnectionRestoration({
    super.key,
    required this.endpoint,
    this.error,
    required this.onRetry,
    required this.onChange,
  });
  final String endpoint;
  final String? error;
  final VoidCallback onRetry, onChange;
  @override
  Widget build(BuildContext context) {
    final p = Paper.of(context), failed = error != null;
    return Scaffold(
      key: const Key('connection-restoration'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(28, 110, 28, 28),
          children: [
            const Center(child: ConnectionBrand()),
            const SizedBox(height: 26),
            Text(
              failed ? '暂时无法连接' : '正在连接媒体库',
              textAlign: TextAlign.center,
              style: p.title.copyWith(fontSize: 26),
            ),
            const SizedBox(height: 12),
            Text(
              endpoint,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: p.muted),
            ),
            const SizedBox(height: 30),
            if (!failed)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: PaperCircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  const Flexible(child: Text('正在验证登录状态')),
                ],
              )
            else ...[
              Text(
                error!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1.7, color: p.danger),
              ),
              const SizedBox(height: 12),
              Text(
                '保存的连接信息还在，检查网络后可以重试。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1.7, color: p.muted),
              ),
              const SizedBox(height: 25),
              FilledButton(
                key: const Key('connection-retry'),
                onPressed: onRetry,
                child: const Text('重新连接'),
              ),
              TextButton(
                key: const Key('connection-change-server'),
                onPressed: onChange,
                child: const Text('更换服务器'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
