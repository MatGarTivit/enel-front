import 'package:flutter/material.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:provider/provider.dart';
import '../services/EnelApiService.dart';
import '../providers/user_session.dart';
import '../theme/cemig_colors.dart';
import '../main.dart';

class UserSelectionScreen extends StatefulWidget {
  const UserSelectionScreen({super.key});

  @override
  State<UserSelectionScreen> createState() => _UserSelectionScreenState();
}

class _UserSelectionScreenState extends State<UserSelectionScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final users = await EnelApiService.getGlpiUsers();
      setState(() {
        _users = users;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [kGradientStart, kGradientEnd],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Logo or icon
                      const Icon(
                        Icons.person_outline,
                        size: 80,
                        color: kPrimary,
                      ),
                      const SizedBox(height: 24),

                      // Title
                      const Text(
                        'Bem-vindo!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: kOnSurface,
                        ),
                      ),
                      const SizedBox(height: 8),

                      const Text(
                        'Selecione seu nome para continuar',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: kOnSurface),
                      ),
                      const SizedBox(height: 32),

                      // Error message
                      if (_error != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: kError.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: kError),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: kError),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Erro ao carregar usuários: $_error',
                                  style: const TextStyle(color: kError),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Loading or Dropdown
                      if (_loading)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(color: kPrimary),
                          ),
                        )
                      else if (_users.isEmpty && _error == null)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Nenhum usuário encontrado',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: kOnSurface),
                          ),
                        )
                      else
                        DropdownSearch<Map<String, dynamic>>(
                          items: _users,
                          itemAsString: (user) => user['name'] as String,
                          dropdownDecoratorProps: const DropDownDecoratorProps(
                            dropdownSearchDecoration: InputDecoration(
                              labelText: 'Selecione seu usuário',
                              hintText: 'Buscar usuário...',
                              prefixIcon: Icon(Icons.search, color: kPrimary),
                            ),
                          ),
                          popupProps: PopupProps.menu(
                            showSearchBox: true,
                            searchFieldProps: const TextFieldProps(
                              decoration: InputDecoration(
                                hintText: 'Buscar...',
                                prefixIcon: Icon(Icons.search),
                              ),
                            ),
                            menuProps: const MenuProps(
                              elevation: 8,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(12),
                                ),
                              ),
                            ),
                            itemBuilder: (context, item, isSelected) {
                              return ListTile(
                                title: Text(item['name'] as String),
                                selected: isSelected,
                                selectedTileColor: kPrimary.withOpacity(0.1),
                              );
                            },
                          ),
                          onChanged: (user) {
                            if (user != null) {
                              _selectUser(user);
                            }
                          },
                        ),

                      // Retry button if error
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _loadUsers,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Tentar Novamente'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _selectUser(Map<String, dynamic> user) {
    final id = user['id'] as int;
    final name = user['name'] as String;

    // Store in provider
    context.read<UserSession>().setUser(id: id, name: name);

    // Navigate to main app
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeShell()));
  }
}
