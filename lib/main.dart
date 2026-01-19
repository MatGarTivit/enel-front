import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/cemig_theme.dart';
import 'screens/gestao_de_despesas.dart';
import 'screens/minhas_despesas.dart';
import 'screens/registrar_despesas.dart';
import 'screens/user_selection_screen.dart';
import 'providers/user_session.dart';

void main() {
  runApp(const EnelDespesasApp());
}

class EnelDespesasApp extends StatelessWidget {
  const EnelDespesasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => UserSession(),
      child: MaterialApp(
        title: 'Gestão de Despesas',
        debugShowCheckedModeBanner: false,
        theme: cemigTheme(),
        home: const UserSelectionScreen(),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends State<HomeShell> {
  // Default to index 2 (RegistrarDespesasScreen) to avoid PIN prompt on startup
  int _index = 2;

  final _screens = const [
    GestaoDeDespesasScreen(),
    MinhasDespesasScreen(),
    RegistrarDespesasScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            label: 'Gestão',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Minhas Despesas',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline),
            label: 'Registrar',
          ),
        ],
      ),
    );
  }
}
