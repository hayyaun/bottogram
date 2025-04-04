import 'package:bottogram/store/rmus.dart';
import 'package:bottogram/units/virt_rmu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class TemplatesPage extends StatefulWidget {
  const TemplatesPage({super.key, required this.selectMode});

  final bool selectMode;

  @override
  State<TemplatesPage> createState() => _BotPageState();
}

class _BotPageState extends State<TemplatesPage> {
  @override
  void initState() {
    super.initState();
  }

  void _addTemplate() {}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Templates"), centerTitle: true),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          // list of rmus
          BlocBuilder<RMUsCubit, List<VirtRMU>>(
            builder: (context, rmus) {
              if (rmus.isEmpty) {
                return Center(child: Text('List empty! create a template'));
              }
              return Expanded(
                child: ListView.builder(
                  itemCount: rmus.length,
                  itemBuilder: (context, index) {
                    final rmu = rmus[index];
                    return ListTile(
                      onTap: () {
                        Navigator.pop(context, rmu);
                      },
                      title: Text('${rmu.type.name}/${rmu.name}'),
                      trailing: IconButton(
                        icon: Icon(Icons.delete),
                        onPressed: () {
                          context.read<RMUsCubit>().remove(rmu);
                        },
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addTemplate,
        tooltip: 'Add a Template',
        child: const Icon(Icons.add),
      ),
    );
  }
}
