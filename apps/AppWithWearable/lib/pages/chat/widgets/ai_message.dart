import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:friend_private/backend/storage/message.dart';

class AIMessage extends StatelessWidget {
  final Message message;
  final Function(String) sendMessage;
  final bool displayOptions;

  const AIMessage({
    super.key,
    required this.message,
    required this.sendMessage,
    required this.displayOptions,
  });

  @override
  Widget build(BuildContext context) {
    // return Column(
    //   crossAxisAlignment: CrossAxisAlignment.start,
    return Row(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage("assets/images/background.png"),
              fit: BoxFit.cover,
            ),
            borderRadius: BorderRadius.all(Radius.circular(16.0)),
          ),
          height: 32,
          width: 32,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Image.asset(
                "assets/images/herologo.png",
                height: 24,
                width: 24,
              ),
            ],
          ),
        ),
        const SizedBox(width: 16.0),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 6),
              SelectionArea(
                  child: AutoSizeText(
                message.text.replaceAll(r'\n', '\n'),
                style: TextStyle(fontSize: 15.0, fontWeight: FontWeight.w500, color: Colors.grey.shade300),
              )),
              if (message.id != '1') _getCopyButton(context),
              if (message.id == '1' && displayOptions) const SizedBox(height: 8),
              if (message.id == '1' && displayOptions) ..._getInitialOptions(context)
            ],
            // ),
            // if (message.memoryIds != null && message.memoryIds!.isNotEmpty)
            //   ElevatedButton(
            //     onPressed: onShowMemoriesPressed,
            //     child: const Text('Show Memories'),
          ),
        ),
      ],
    );
  }

  _getCopyButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(0.0, 6.0, 0.0, 0.0),
      child: InkWell(
        splashColor: Colors.transparent,
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: message.text));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Response copied to clipboard.',
                style: TextStyle(
                  color: Color.fromARGB(255, 255, 255, 255),
                  fontSize: 12.0,
                ),
              ),
              duration: Duration(milliseconds: 2000),
            ),
          );
        },
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(0.0, 0.0, 4.0, 0.0),
              child: Icon(
                Icons.content_copy,
                color: Theme.of(context).textTheme.bodySmall!.color,
                size: 10.0,
              ),
            ),
            Text(
              'Copy response',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  _getInitialOption(BuildContext context, String optionText) {
    return GestureDetector(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
        width: double.maxFinite,
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Text(optionText, style: Theme.of(context).textTheme.bodyMedium),
      ),
      onTap: () {
        sendMessage(optionText);
      },
    );
  }

  _getInitialOptions(BuildContext context) {
    return [
      const SizedBox(height: 8),
      _getInitialOption(context, 'What tasks do I have from yesterday?'),
      const SizedBox(height: 8),
      _getInitialOption(context, 'What conversations did I have with John?'),
      const SizedBox(height: 8),
      _getInitialOption(context, 'What advise have I received about entrepreneurship?'),
    ];
  }
}
