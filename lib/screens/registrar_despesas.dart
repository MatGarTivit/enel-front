import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_compression_flutter/image_compression_flutter.dart';
import '../widgets/gradient_scaffold.dart';
import '../providers/user_session.dart';
import '../services/EnelApiService.dart';

class RegistrarDespesasScreen extends StatefulWidget {
  const RegistrarDespesasScreen({super.key});

  @override
  State<RegistrarDespesasScreen> createState() =>
      _RegistrarDespesasScreenState();
}

class _RegistrarDespesasScreenState extends State<RegistrarDespesasScreen> {
  final _formKey = GlobalKey<FormState>();

  // Form controllers
  final TextEditingController _dataCtrl = TextEditingController();
  DateTime? _data;
  final TextEditingController _servicosCtrl = TextEditingController();
  final TextEditingController _tipoDespesaCtrl = TextEditingController();
  final TextEditingController _tipoDoc2Ctrl = TextEditingController();
  final TextEditingController _centroCustoCtrl = TextEditingController();
  final TextEditingController _pepCtrl = TextEditingController();
  final TextEditingController _valorCtrl = TextEditingController();

  final TextEditingController _denominacaoCtrl = TextEditingController();
  final TextEditingController _responsavelCtrl = TextEditingController();

  // Files
  final List<PlatformFile> _files = [];
  bool _submitting = false;

  // Operacoes for auto-fill
  List<Map<String, dynamic>> _operacoes = [];
  bool _loadingOperacoes = false;

  // Expense types dropdown
  List<String> _tiposDespesa = [];
  bool _loadingTipos = false;
  bool _tiposLoadError = false;
  String? _selectedTipoDespesa;

  @override
  void initState() {
    super.initState();
    _fetchTiposDespesa();
    _fetchOperacoes();
  }

  Future<void> _fetchOperacoes() async {
    setState(() => _loadingOperacoes = true);
    try {
      final ops = await EnelApiService.getOperacoes();
      if (mounted) {
        setState(() {
          _operacoes = ops;
          _loadingOperacoes = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar operacoes: $e');
      if (mounted) setState(() => _loadingOperacoes = false);
    }
  }

  Future<void> _fetchTiposDespesa() async {
    setState(() {
      _loadingTipos = true;
      _tiposLoadError = false;
    });

    try {
      final tipos = await EnelApiService.getTipoDespesa();
      setState(() {
        _tiposDespesa = tipos
            .map((t) => t['tipo']?.toString() ?? '')
            .where((t) => t.isNotEmpty)
            .toList();
        _loadingTipos = false;
      });
    } catch (e) {
      debugPrint('Error loading tipos de despesa: $e');
      setState(() {
        _loadingTipos = false;
        _tiposLoadError = true;
      });
    }
  }

  @override
  void dispose() {
    _dataCtrl.dispose();
    _servicosCtrl.dispose();
    _tipoDespesaCtrl.dispose();
    _tipoDoc2Ctrl.dispose();
    _centroCustoCtrl.dispose();
    _pepCtrl.dispose();
    _valorCtrl.dispose();
    _denominacaoCtrl.dispose();
    _responsavelCtrl.dispose();
    super.dispose();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Campo obrigatório' : null;

  Future<void> _pickData() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _data ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _data = picked;
        _dataCtrl.text =
            '${picked.day.toString().padLeft(2, '0')}/'
            '${picked.month.toString().padLeft(2, '0')}/'
            '${picked.year}';
      });
    }
  }

  Future<void> _pickFiles() async {
    if (_files.length >= 15) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Máximo de 15 arquivos atingido')),
      );
      return;
    }

    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
      withData: true,
    );
    if (res == null) return;

    final remaining = 15 - _files.length;
    final toAdd = res.files.take(remaining).toList();

    setState(() => _files.addAll(toAdd));

    if (res.files.length > remaining) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Apenas $remaining arquivo(s) adicionado(s). Limite de 15 atingido.',
          ),
        ),
      );
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha todos os campos obrigatórios')),
      );
      return;
    }

    // Validate tipo de despesa
    if (_selectedTipoDespesa == null || _selectedTipoDespesa!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione o Tipo de Despesa')),
      );
      return;
    }

    final userSession = context.read<UserSession>();
    if (!userSession.hasUser) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Usuário não selecionado')));
      return;
    }

    setState(() => _submitting = true);

    try {
      // Parse valor
      final rawValor = _valorCtrl.text.trim().replaceAll(',', '.');
      final valor = double.tryParse(rawValor);
      if (valor == null) {
        throw Exception('Valor inválido');
      }

      // 1) Create despesa
      final despesaId = await EnelApiService.createDespesaEnel(
        tecnico: userSession.userName!,
        userId: userSession.userId!,
        data: _data!,
        servicos: _servicosCtrl.text.trim(),
        tipoDeDespesa: _selectedTipoDespesa!.trim(),
        tipoDoc2: _tipoDoc2Ctrl.text.trim(),
        centroCusto: _centroCustoCtrl.text.trim(),
        pep: _pepCtrl.text.trim(),
        valor: valor,
        denominacao: _denominacaoCtrl.text.trim(),
        responsavel: _responsavelCtrl.text.trim(),
      );

      if (despesaId == null) {
        throw Exception('Falha ao criar despesa');
      }

      // 2) Upload files if any
      int uploaded = 0;
      final failures = <String>[];

      if (_files.isNotEmpty) {
        // Create GLPI subtask
        const int parentTaskId = 12153;
        final now = DateTime.now();
        const monthNames = [
          'Janeiro',
          'Fevereiro',
          'Março',
          'Abril',
          'Maio',
          'Junho',
          'Julho',
          'Agosto',
          'Setembro',
          'Outubro',
          'Novembro',
          'Dezembro',
        ];
        final subtaskName = '${monthNames[now.month - 1]} despesas_registro';

        int? subtaskId;
        try {
          subtaskId = await EnelApiService.createGlpiSubtask(
            parentTaskId: parentTaskId,
            name: subtaskName,
          );
        } catch (e) {
          throw Exception('Erro ao criar subtarefa GLPI: $e');
        }

        if (subtaskId == null) {
          throw Exception('Subtarefa GLPI não foi criada');
        }

        // Upload each file
        final tecnico = _sanitizeName(userSession.userName!);
        final tipo = _sanitizeName(_selectedTipoDespesa!.trim());
        final ymd = _toYmd(_data!);
        final base = '$tecnico - $tipo - $ymd';

        for (int i = 0; i < _files.length; i++) {
          final pf = _files[i];
          final ext = (pf.extension ?? 'file').toLowerCase();
          final seq = _files.length > 1 ? ' - ${_two(i + 1)}' : '';
          final filename = '$base$seq.$ext';

          final fileBytes = pf.bytes;
          if (fileBytes == null || fileBytes.isEmpty) {
            failures.add('${pf.name}: sem bytes');
            continue;
          }

          // from here on, `bytes` is guaranteed non-null
          Uint8List bytes = fileBytes;

          // Compress images
          if (_isImage(ext)) {
            try {
              final compressed = await compressor.compress(
                ImageFileConfiguration(
                  input: ImageFile(rawBytes: bytes, filePath: pf.name),
                  config: Configuration(
                    outputType: ImageOutputType.jpg, // or webpThenJpg
                    quality: 80,
                  ),
                ),
              );
              bytes = compressed.rawBytes;
            } catch (e) {
              debugPrint('Compression failed for ${pf.name}: $e');
            }
          }

          try {
            await EnelApiService.uploadPhotoBytesToTask(
              taskId: subtaskId,
              bytes: bytes, // non-null here
              filename: filename,
              itemtype: 'ProjectTask',
              despesaId: despesaId,
            );
            uploaded++;
          } catch (e) {
            failures.add('${pf.name}: $e');
          }
        }
      }

      // 3) Show result
      if (mounted) {
        if (_files.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Despesa registrada com sucesso!')),
          );
          _resetForm();
        } else if (uploaded > 0 && failures.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Despesa registrada e $uploaded arquivo(s) enviado(s)!',
              ),
            ),
          );
          _resetForm();
        } else if (uploaded > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Despesa registrada. $uploaded enviado(s), ${failures.length} falha(s)',
              ),
            ),
          );
          _resetForm();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Despesa registrada, mas arquivos falharam: ${failures.join(", ")}',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    setState(() {
      _data = null;
      _dataCtrl.clear();
      _servicosCtrl.clear();
      _selectedTipoDespesa = null;
      _tipoDoc2Ctrl.clear();
      _centroCustoCtrl.clear();
      _pepCtrl.clear();
      _valorCtrl.clear();
      _denominacaoCtrl.clear();
      _responsavelCtrl.clear();
      _files.clear();
    });
  }

  String _sanitizeName(String s) => s
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String _toYmd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final da = d.day.toString().padLeft(2, '0');
    return '$y-$m-$da';
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  bool _isImage(String ext) {
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
  }

  Widget _buildDropdown({
    required TextEditingController controller,
    required String label,
    required String fieldKey, // 'denominacao', 'responsavel', etc.
    String? Function(String?)? validator,
  }) {
    // 1. Get unique values for this field from _operacoes
    final uniqueValues = _operacoes
        .map((op) => op[fieldKey]?.toString())
        .where((val) => val != null && val.isNotEmpty)
        .toSet()
        .toList();

    // 2. Build entries
    final entries = uniqueValues.map((val) {
      return DropdownMenuEntry<String>(value: val!, label: val);
    }).toList();

    return DropdownMenu<String>(
      controller: controller, // Use the same controller for text input/display
      label: Text(label),
      dropdownMenuEntries: entries,
      enableFilter: true, // Allow typing to filter
      enableSearch: true,
      expandedInsets: EdgeInsets.zero, // Full width match parent
      onSelected: (String? value) {
        if (value != null) {
          // Find the operation that matches this value
          // Note: If multiple operations have the same value for this field,
          // we might just pick the first one. This is a known constraint for "unique columns".
          final op = _operacoes.firstWhere(
            (o) => o[fieldKey].toString() == value,
            orElse: () => {},
          );
          if (op.isNotEmpty) {
            _fillFieldsFromOperacao(op);
          }
        }
      },
      errorText:
          validator != null &&
              (controller.text.isEmpty) // simplistic validation for dropdown
          ? 'Campo obrigatório'
          : null,
    );
  }

  void _fillFieldsFromOperacao(Map<String, dynamic> op) {
    setState(() {
      if (op['denominacao'] != null) {
        _denominacaoCtrl.text = op['denominacao'].toString();
      }
      if (op['responsavel'] != null) {
        _responsavelCtrl.text = op['responsavel'].toString();
      }
      if (op['tipo_documento'] != null) {
        _tipoDoc2Ctrl.text = op['tipo_documento'].toString();
      }
      if (op['centro_custo'] != null) {
        _centroCustoCtrl.text = op['centro_custo'].toString();
      }
      if (op['pep'] != null) {
        _pepCtrl.text = op['pep'].toString();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(title: const Text('Registrar Despesa')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // TECNICO field - locked with selected user
              Consumer<UserSession>(
                builder: (context, userSession, _) {
                  return TextFormField(
                    decoration: const InputDecoration(
                      labelText: 'Técnico',
                      enabled: false,
                      prefixIcon: Icon(Icons.person),
                    ),
                    initialValue: userSession.userName ?? '',
                    enabled: false,
                  );
                },
              ),
              const SizedBox(height: 12),

              // DATA
              TextFormField(
                controller: _dataCtrl,
                decoration: const InputDecoration(
                  labelText: 'Data *',
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                readOnly: true,
                onTap: _pickData,
                validator: _required,
              ),
              const SizedBox(height: 12),

              // SERVICOS
              TextFormField(
                controller: _servicosCtrl,
                decoration: const InputDecoration(labelText: 'Serviços *'),
                maxLines: 3,
                validator: _required,
              ),
              const SizedBox(height: 12),

              // tipo_de_despesa - Searchable Dropdown
              if (_loadingTipos)
                const LinearProgressIndicator()
              else if (_tiposLoadError || _tiposDespesa.isEmpty)
                // Fallback to text field if loading failed
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _tipoDespesaCtrl,
                      decoration: InputDecoration(
                        labelText: 'Tipo de Despesa *',
                        errorText: _tiposLoadError
                            ? 'Erro ao carregar tipos'
                            : null,
                        suffixIcon: _tiposLoadError
                            ? IconButton(
                                icon: const Icon(Icons.refresh),
                                onPressed: _fetchTiposDespesa,
                                tooltip: 'Tentar novamente',
                              )
                            : null,
                      ),
                      validator: _required,
                      onChanged: (value) {
                        setState(() {
                          _selectedTipoDespesa = value;
                        });
                      },
                    ),
                    if (_tiposLoadError)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, left: 12),
                        child: Text(
                          'Usando entrada manual',
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: Colors.orange),
                        ),
                      ),
                  ],
                )
              else
                DropdownMenu<String>(
                  initialSelection: _selectedTipoDespesa,
                  controller: _tipoDespesaCtrl,
                  requestFocusOnTap: true,
                  label: const Text('Tipo de Despesa *'),
                  expandedInsets: EdgeInsets.zero,
                  onSelected: (String? value) {
                    setState(() {
                      _selectedTipoDespesa = value;
                    });
                  },
                  dropdownMenuEntries: _tiposDespesa
                      .map<DropdownMenuEntry<String>>((String tipo) {
                        return DropdownMenuEntry<String>(
                          value: tipo,
                          label: tipo,
                        );
                      })
                      .toList(),
                  enableFilter: true,
                  enableSearch: true,
                  errorText:
                      _selectedTipoDespesa == null ||
                          _selectedTipoDespesa!.isEmpty
                      ? 'Campo obrigatório'
                      : null,
                ),
              const SizedBox(height: 12),

              // DENOMINACAO (Dropdown)
              _buildDropdown(
                controller: _denominacaoCtrl,
                label: 'Denominação *',
                fieldKey: 'denominacao',
                validator: _required,
              ),
              const SizedBox(height: 12),

              // RESPONSAVEL (Dropdown)
              _buildDropdown(
                controller: _responsavelCtrl,
                label: 'Responsável *',
                fieldKey: 'responsavel',
                validator: _required,
              ),
              const SizedBox(height: 12),

              // TIPO DE DOC2 (Dropdown)
              _buildDropdown(
                controller: _tipoDoc2Ctrl,
                label: 'Tipo de Documento *',
                fieldKey: 'tipo_documento',
                validator: _required,
              ),
              const SizedBox(height: 12),

              // CENTRO DE CUSTO (Dropdown)
              _buildDropdown(
                controller: _centroCustoCtrl,
                label: 'Centro de Custo *',
                fieldKey: 'centro_custo',
                validator: _required,
              ),
              const SizedBox(height: 12),

              // PEP (Dropdown)
              _buildDropdown(
                controller: _pepCtrl,
                label: 'PEP *',
                fieldKey: 'pep',
                validator: _required,
              ),
              const SizedBox(height: 12),

              // VALOR
              TextFormField(
                controller: _valorCtrl,
                decoration: const InputDecoration(
                  labelText: 'Valor Gasto *',
                  prefixText: 'R\$ ',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d+([.,]\d{0,2})?$'),
                  ),
                ],
                validator: _required,
              ),
              const SizedBox(height: 12),
              // Files section
              Text(
                'Documentos (até 15 arquivos)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _submitting ? null : _pickFiles,
                    icon: const Icon(Icons.attach_file),
                    label: const Text('Adicionar Arquivos'),
                  ),
                  const SizedBox(width: 12),
                  if (_files.isNotEmpty)
                    TextButton.icon(
                      onPressed: _submitting
                          ? null
                          : () => setState(() => _files.clear()),
                      icon: const Icon(Icons.clear),
                      label: const Text('Limpar Todos'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (_files.isEmpty)
                const Text('Nenhum arquivo selecionado')
              else
                Card(
                  child: Column(
                    children: [
                      for (int i = 0; i < _files.length; i++)
                        ListTile(
                          dense: true,
                          leading: Icon(
                            _isImage(_files[i].extension ?? '')
                                ? Icons.image
                                : Icons.insert_drive_file,
                          ),
                          title: Text(_files[i].name),
                          subtitle: Text(
                            '${(_files[i].size / 1024).toStringAsFixed(1)} KB',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: _submitting
                                ? null
                                : () => setState(() => _files.removeAt(i)),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),

              // Submit button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Enviar Despesa'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
