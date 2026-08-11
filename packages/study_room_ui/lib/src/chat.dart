import 'package:flutter/material.dart';
import 'package:study_room_sdk/study_room_sdk.dart';

import 'localizations.dart';
import 'room_style.dart';

class ChatPanel extends StatefulWidget {
  const ChatPanel({
    required this.messages,
    required this.onSend,
    this.copy = const StudyRoomCopy(),
    super.key,
  });

  final List<ChatMessage> messages;
  final Future<void> Function(String text) onSend;
  final StudyRoomCopy copy;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _controller = TextEditingController();
  var _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    return Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          Expanded(
            child: widget.messages.isEmpty
                ? Center(
                    child: Text(
                      widget.copy.emptyMessages ?? localizations.emptyMessages,
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: widget.messages.length,
                    itemBuilder: (context, index) {
                      final message = widget.messages[index];
                      return ListTile(
                        dense: true,
                        title: Text(message.senderName),
                        subtitle: Text(message.text),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: localizations.messageHint,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: localizations.send,
                  icon: _sending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  onPressed: _sending ? null : _send,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.onSend(text);
      _controller.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}
