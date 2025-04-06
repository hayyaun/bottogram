import 'package:bottogram/pages/bot.dart';
import 'package:bottogram/store/bots.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:bottogram/utils/context.dart';
import 'package:bottogram/utils/list.dart';
import 'package:bottogram/utils/string.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class BotCard extends StatelessWidget {
  const BotCard({super.key, required this.bot});

  final VirtBot bot;

  @override
  Widget build(BuildContext context) {
    final acts = bot.events.map((ev) => ev.acts.length).sum();
    final color =
        bot.active ? Colors.greenAccent : context.colors.inversePrimary;
    final borderRadius = BorderRadius.circular(12);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      margin: EdgeInsets.all(0),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => BotPage(bot: bot)),
          );
        },
        child: Column(
          children: [
            Container(color: color, height: 8),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      bot.name.ellipsize(8),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w200,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(bot.active ? 'ACTIVE' : 'INACTIVE'),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('${bot.events.length} events'),
                              Text('$acts actions'),
                            ],
                          ),
                        ),
                        IconButton.filled(
                          style: ButtonStyle(
                            backgroundColor: WidgetStatePropertyAll(
                              bot.active ? Colors.greenAccent : Colors.black,
                            ),
                          ),
                          color: bot.active ? Colors.black : Colors.white,
                          icon: Icon(
                            bot.active ? Icons.pause : Icons.play_arrow,
                          ),
                          onPressed: () async {
                            await bot.toggle();
                            // ignore: use_build_context_synchronously
                            context.read<BotsCubit>().update();
                          },
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
