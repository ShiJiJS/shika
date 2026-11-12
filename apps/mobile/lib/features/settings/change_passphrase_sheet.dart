import 'package:flutter/material.dart';

import '../../library/repository.dart';
import '../../ui/paper.dart';
import '../../ui/paper_form.dart';

class ChangePassphraseSheet extends StatefulWidget {
  const ChangePassphraseSheet({super.key, required this.repository});
  final LibraryRepository repository;
  @override
  State<ChangePassphraseSheet> createState() => _ChangePassphraseSheetState();
}

class _ChangePassphraseSheetState extends State<ChangePassphraseSheet> {
  final current = TextEditingController();
  final replacement = TextEditingController();
  final confirmation = TextEditingController();
  bool busy = false;
  String error = '';

  @override
  void dispose() {
    current.dispose();
    replacement.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (current.text.isEmpty ||
        replacement.text.length < 8 ||
        replacement.text.length > 1024) {
      setState(() => error = '请填写当前口令，新口令需要8–1024个字符');
      return;
    }
    if (replacement.text != confirmation.text) {
      setState(() => error = '两次输入的新口令不一致');
      return;
    }
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await widget.repository.changePassphrase(current.text, replacement.text);
      if (mounted) Navigator.pop(context, true);
    } catch (failure) {
      if (mounted) setState(() => error = failure.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(String label, String key, TextEditingController controller) =>
      Padding(
        padding: const EdgeInsets.only(top: 18),
        child: PaperField(
          label: label,
          child: TextField(
            key: Key(key),
            controller: controller,
            enabled: !busy,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: SheetFrame(
      title: '修改个人口令',
      closeEnabled: !busy,
      footer: FilledButton(
        key: const Key('change-passphrase-save'),
        onPressed: busy ? null : save,
        child: Text(busy ? '正在保存…' : '保存新口令'),
      ),
      children: [
        Text(
          '修改后本机继续连接，其他设备需用新口令重新登录。',
          style: TextStyle(color: Paper.of(context).muted, height: 1.7),
        ),
        field('当前口令', 'change-current-passphrase', current),
        field('新口令', 'change-new-passphrase', replacement),
        field('再次输入新口令', 'change-confirm-passphrase', confirmation),
        if (error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              error,
              style: TextStyle(color: Paper.of(context).danger),
            ),
          ),
      ],
    ),
  );
}
