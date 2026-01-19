import 'package:flutter/material.dart';
import 'package:dropdown_search/dropdown_search.dart';
import '../services/EnelApiService.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import '../providers/user_session.dart';

class MinhasDespesasScreen extends StatefulWidget {
  const MinhasDespesasScreen({super.key});

  @override
  State<MinhasDespesasScreen> createState() => _MinhasDespesasScreenState();
}

class _MinhasDespesasScreenState extends State<MinhasDespesasScreen> {
  final _scrollCtrl = ScrollController();

  // Users
  bool _loadingUsers = false;
  String? _error;
  List<Map<String, dynamic>> _users = [];
  Map<String, dynamic>? _selectedUser;
  bool _isUserFieldLocked = false; // For tivit role users (logic adapted)

  // Despesas
  bool _loading = false;
  List<Map<String, dynamic>> _despesas = [];

  // despesas_id -> lista de arquivos
  final Map<int, List<Map<String, dynamic>>> _arquivosPorDespesa = {};

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _loadingUsers = true;
      _error = null;
    });
    try {
      final data = await EnelApiService.getGlpiUsers().timeout(
        const Duration(seconds: 10),
      );

      if (!mounted) return;
      final session = context.read<UserSession>();
      final glpiUserId = session.userId;

      if (glpiUserId != null) {
        final currentUser = data.firstWhere(
          (u) => u['id'] == glpiUserId,
          orElse: () => {},
        );

        if (currentUser.isNotEmpty) {
          setState(() {
            _users = data;
            _selectedUser = currentUser;
            _isUserFieldLocked = true;
          });

          _loadDespesas();
        } else {
          setState(() => _users = data);
        }
      } else {
        setState(() => _users = data);
      }
    } catch (e) {
      setState(() => _error = 'Falha ao carregar usuários GLPI: $e');
    } finally {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  Future<void> _loadDespesas() async {
    if (_selectedUser == null) {
      setState(() => _despesas = []);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        EnelApiService.getDespesasByUser(
          userId: _selectedUser!['id'] as int,
        ).timeout(const Duration(seconds: 15)),
        EnelApiService.getAllDespesaArquivos(),
      ]);

      final despesas = results[0];
      final arquivos = results[1];

      // monta mapa despesas_id -> lista de arquivos
      _arquivosPorDespesa.clear();
      for (final row in arquivos) {
        final rawId = row['despesas_id'];
        if (rawId == null) continue;
        final id = rawId is int ? rawId : int.tryParse(rawId.toString()) ?? -1;
        if (id <= 0) continue;
        _arquivosPorDespesa.putIfAbsent(id, () => []).add(row);
      }

      setState(() => _despesas = despesas);
    } catch (e) {
      setState(() => _error = 'Falha ao carregar despesas: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  String _formatDate(String? ymd) {
    if (ymd == null || ymd.isEmpty) return '-';
    try {
      final d = DateTime.parse(ymd); // "YYYY-MM-DD"
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return ymd;
    }
  }

  String _formatMoney(dynamic v) {
    if (v == null) return 'R\$ 0,00';
    final num n = (v is num) ? v : num.tryParse(v.toString()) ?? 0;
    return 'R\$ ${n.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Minhas despesas'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Image.asset('assets/images/tivit_logo.png', height: 28),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadDespesas,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                if (_loadingUsers) const LinearProgressIndicator(),
                // User dropdown
                DropdownSearch<Map<String, dynamic>>(
                  items: _users,
                  selectedItem: _selectedUser,
                  itemAsString: (u) =>
                      '${u['name'] ?? ''} (ID: ${u['id'] ?? ''})',
                  enabled: !_isUserFieldLocked,
                  dropdownDecoratorProps: DropDownDecoratorProps(
                    dropdownSearchDecoration: InputDecoration(
                      labelText: _isUserFieldLocked
                          ? 'Usuário (GLPI) - (bloqueado)'
                          : 'Usuário (GLPI)',
                    ),
                  ),
                  onChanged: _isUserFieldLocked
                      ? null
                      : (u) {
                          setState(() => _selectedUser = u);
                          _loadDespesas();
                        },
                  popupProps: const PopupProps.menu(showSearchBox: true),
                ),
                const SizedBox(height: 16),

                if (_loading) const LinearProgressIndicator(),

                if (!_loading && _selectedUser != null && _despesas.isEmpty)
                  Card(
                    color: cs.surface.withValues(alpha: 0.98),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Nenhuma despesa encontrada para este usuário.',
                      ),
                    ),
                  ),

                // Cards list
                ..._despesas.map((d) {
                  final rawId = d['despesa_id'];
                  final despesaId = rawId is int
                      ? rawId
                      : int.tryParse(rawId.toString()) ?? -1;
                  final arquivos = _arquivosPorDespesa[despesaId] ?? const [];

                  return _DespesaCard(
                    data: d,
                    formatMoney: _formatMoney,
                    formatDateBr: _formatDate,
                    onSaved: _loadDespesas,
                    arquivos: arquivos,
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DespesaCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final String Function(dynamic) formatMoney;
  final String Function(String?) formatDateBr;
  final Future<void> Function() onSaved;
  final List<Map<String, dynamic>> arquivos;

  const _DespesaCard({
    required this.data,
    required this.formatMoney,
    required this.formatDateBr,
    required this.onSaved,
    required this.arquivos,
  });

  @override
  State<_DespesaCard> createState() => _DespesaCardState();
}

class _DespesaCardState extends State<_DespesaCard> {
  bool _editing = false;
  bool _saving = false;

  late TextEditingController _tipoCtrl;
  late TextEditingController _valorCtrl;
  late TextEditingController _qtdCtrl;

  late TextEditingController _justCtrl;
  late TextEditingController _denominacaoCtrl;
  late TextEditingController _responsavelCtrl;
  DateTime? _dataConsumo;

  @override
  void initState() {
    super.initState();
    final d = widget.data;

    _tipoCtrl = TextEditingController(
      text: d['tipo_de_despesa']?.toString() ?? '',
    );
    _valorCtrl = TextEditingController(
      text: (d['valor_despesa'] == null)
          ? ''
          : (d['valor_despesa'] is num
                ? (d['valor_despesa'] as num)
                      .toStringAsFixed(2)
                      .replaceAll('.', ',')
                : d['valor_despesa'].toString()),
    );
    _qtdCtrl = TextEditingController(text: d['quantidade']?.toString() ?? '');
    _justCtrl = TextEditingController(
      text: d['justificativa']?.toString() ?? '',
    );
    _denominacaoCtrl = TextEditingController(
      text: d['denominacao']?.toString() ?? '',
    );
    _responsavelCtrl = TextEditingController(
      text: d['responsavel']?.toString() ?? '',
    );

    try {
      _dataConsumo = d['data_consumo'] != null
          ? DateTime.parse(d['data_consumo'])
          : null;
    } catch (_) {
      _dataConsumo = null;
    }
  }

  @override
  void dispose() {
    _tipoCtrl.dispose();
    _valorCtrl.dispose();
    _qtdCtrl.dispose();
    _qtdCtrl.dispose();
    _justCtrl.dispose();
    _denominacaoCtrl.dispose();
    _responsavelCtrl.dispose();
    super.dispose();
  }

  Color _statusColor(String s, ColorScheme cs) {
    switch (s) {
      case 'Aprovado':
        return Colors.green;
      case 'Reprovado':
        return Colors.red;
      case 'Aguardando Aprovação':
        return Colors.amber.shade700;
      default:
        return cs.outline;
    }
  }

  Future<void> _replaceFile() async {
    final despesaId = widget.data['despesa_id'] as int?;
    if (despesaId == null) return;

    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'pdf', 'txt'],
    );
    if (picked == null || picked.files.isEmpty) return;

    final pf = picked.files.first;
    final bytes = pf.bytes;
    if (bytes == null || bytes.isEmpty) {
      _show('Arquivo inválido');
      return;
    }

    setState(() => _saving = true);
    try {
      int? subtaskId = widget.data['glpi_subtask_id'] as int?;
      if (subtaskId == null) {
        const int parentTaskId = 7227;
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
        subtaskId = await EnelApiService.createGlpiSubtask(
          parentTaskId: parentTaskId,
          name: subtaskName,
        );
        if (subtaskId == null) {
          throw Exception('Subtarefa GLPI não criada');
        }
      }

      final currentDocId = widget.data['photo_docid'] as int?;
      if (currentDocId != null) {
        await EnelApiService.deleteDespesaFile(despesaId);
      }

      final user = (widget.data['user_name']?.toString() ?? 'Usuario')
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final tipo = (widget.data['tipo_de_despesa']?.toString() ?? 'Despesa')
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      String ymd;
      try {
        final d = DateTime.parse(widget.data['data_consumo']?.toString() ?? '');
        ymd =
            '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      } catch (_) {
        ymd = DateTime.now().toIso8601String().split('T').first;
      }

      final ext = (pf.extension ?? 'dat').toLowerCase();
      final filename = '$user - $tipo - $ymd.$ext';

      await EnelApiService.uploadPhotoBytesToTask(
        taskId: subtaskId,
        bytes: bytes,
        filename: filename,
        itemtype: 'ProjectTask',
        despesaId: despesaId,
      );

      await widget.onSaved();
      if (!mounted) return;
      _show('Arquivo enviado.');
    } catch (e) {
      _show('Falha ao enviar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _dataConsumo ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _dataConsumo = picked);
    }
  }

  Future<void> _save() async {
    final despesaId = widget.data['despesa_id'] as int?;
    if (despesaId == null) return;

    final tipo = _tipoCtrl.text.trim();
    if (tipo.isEmpty) {
      _show('Tipo de despesa é obrigatório');
      return;
    }
    final rawValor = _valorCtrl.text.trim().replaceAll(',', '.');
    final valor = double.tryParse(rawValor);
    if (valor == null) {
      _show('Valor de despesa inválido');
      return;
    }
    final qtd = int.tryParse(_qtdCtrl.text.trim());
    if (_dataConsumo == null) {
      _show('Data de consumo é obrigatória');
      return;
    }

    setState(() => _saving = true);
    try {
      await EnelApiService.updateDespesa(
        despesaId: despesaId,
        tipoDespesa: tipo,
        valor: valor,
        dataConsumo: _dataConsumo!,
        quantidade: qtd,

        justificativa: _justCtrl.text.trim(),
        denominacao: _denominacaoCtrl.text.trim(),
        responsavel: _responsavelCtrl.text.trim(),
      );
      await widget.onSaved();
      if (!mounted) return;
      setState(() => _editing = false);
      _show('Despesa atualizada com sucesso');
    } catch (e) {
      _show('Falha ao atualizar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _show(String msg) {
    final ctx = context;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _deleteDespesa() async {
    final despesaId = widget.data['despesa_id'] as int?;
    if (despesaId == null) return;

    final ctx = context;
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: const Text('Excluir despesa'),
        content: const Text(
          'Esta ação apagará a despesa e o arquivo no GLPI (se existir). Deseja continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _saving = true);

    try {
      await EnelApiService.deleteDespesa(despesaId);
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(
        ctx,
      ).showSnackBar(const SnackBar(content: Text('Despesa excluída')));
      await widget.onSaved();
    } catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(
        ctx,
      ).showSnackBar(SnackBar(content: Text('Falha ao excluir: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildDocumentoChip(
    Map<String, dynamic> arq,
    int index,
    bool canEdit,
  ) {
    final docIdRaw = arq['photo_docid'];
    final labelBase = docIdRaw != null
        ? 'Doc ${docIdRaw.toString()}'
        : 'Documento ${index + 1}';

    // If no docId, show a "dead" chip
    if (docIdRaw == null) {
      return Chip(label: Text(labelBase));
    }

    final docId = docIdRaw is int
        ? docIdRaw
        : int.tryParse(docIdRaw.toString());

    if (docId == null) {
      return Chip(label: Text(labelBase));
    }

    final proxyUrl = EnelApiService.glpiDocProxyUrl(docId);

    // ActionChip with delete button on top-right
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ActionChip(
          label: Text(labelBase),
          onPressed: () {
            launchUrl(
              Uri.parse(proxyUrl),
              mode: LaunchMode.externalApplication,
            );
          },
          tooltip: proxyUrl,
        ),
        // Delete button on top-right corner
        if (canEdit)
          Positioned(
            right: -4,
            top: -4,
            child: GestureDetector(
              onTap: () => _deleteFile(arq),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _deleteFile(Map<String, dynamic> arquivo) async {
    final arquivoId = arquivo['id'] as int?;
    if (arquivoId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover arquivo?'),
        content: const Text(
          'O arquivo será removido do GLPI e desvinculado desta despesa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _saving = true);
    try {
      final despesaId = widget.data['despesa_id'] as int?;
      if (despesaId != null) {
        await EnelApiService.deleteDespesaFile(despesaId);
      }
      await widget.onSaved();
      if (!mounted) return;
      _show('Arquivo removido.');
    } catch (e) {
      _show('Falha ao remover: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = widget.data;
    final tipo = d['tipo_de_despesa']?.toString() ?? '-';
    final valor = widget.formatMoney(d['valor_despesa']);
    final data = widget.formatDateBr(d['data_consumo']?.toString());
    final qtd = d['quantidade']?.toString() ?? '0';
    final justificativa = d['justificativa']?.toString() ?? '';
    final aprovacao = d['aprovacao']?.toString() ?? '-';
    final motivo = d['aprovacao_motivo']?.toString().trim();
    final canEdit = aprovacao != 'Aprovado';

    return Card(
      color: cs.surface.withValues(alpha: 0.98),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // header row
            Row(
              children: [
                Expanded(
                  child: Text(
                    tipo,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                // Status chip
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(aprovacao, cs).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _statusColor(aprovacao, cs)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.verified,
                        size: 14,
                        color: _statusColor(aprovacao, cs),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        aprovacao,
                        style: TextStyle(
                          color: _statusColor(aprovacao, cs),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (!canEdit)
                  Tooltip(
                    message: 'Registro aprovado não pode ser editado',
                    child: Icon(Icons.lock, color: cs.outline),
                  )
                else
                  TextButton.icon(
                    onPressed: _saving
                        ? null
                        : () => setState(() => _editing = !_editing),
                    icon: Icon(_editing ? Icons.close : Icons.edit),
                    label: Text(_editing ? 'Cancelar' : 'Editar'),
                  ),
              ],
            ),
            const SizedBox(height: 6),

            if (!_editing) ...[
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [_InfoChip(icon: Icons.calendar_today, label: data)],
              ),
              if (justificativa.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Justificativa: $justificativa',
                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.8)),
                ),
              ],
              // DENOMINACAO & RESPONSAVEL DISPLAY
              if (d['denominacao'] != null &&
                  d['denominacao'].toString().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Denominação: ${d['denominacao']}',
                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.8)),
                ),
              ],
              if (d['responsavel'] != null &&
                  d['responsavel'].toString().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Responsável: ${d['responsavel']}',
                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.8)),
                ),
              ],

              const SizedBox(height: 8),
              const Text(
                'Arquivos',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),

              // Display files as chips with delete buttons
              if (widget.arquivos.isEmpty)
                Text(
                  'Nenhum arquivo anexado.',
                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7)),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (var i = 0; i < widget.arquivos.length; i++)
                      _buildDocumentoChip(widget.arquivos[i], i, canEdit),
                  ],
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    valor,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  if (canEdit)
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _deleteDespesa,
                      icon: const Icon(Icons.delete_forever, color: Colors.red),
                      label: const Text('Excluir despesa'),
                    ),
                ],
              ),
              if (canEdit)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _replaceFile,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Adicionar arquivo'),
                  ),
                ),
              if (motivo != null && motivo.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.4),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          motivo,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 6),
            ] else ...[
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 600;
                  return Column(
                    children: [
                      if (isWide)
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _tipoCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Tipo de Despesa',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _valorCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Valor (R\$)',
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        )
                      else ...[
                        TextField(
                          controller: _tipoCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Tipo de Despesa',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _valorCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Valor (R\$)',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: _pickDate,
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Data de Consumo',
                                  border: OutlineInputBorder(),
                                  suffixIcon: Icon(Icons.calendar_today),
                                ),
                                child: Text(
                                  _dataConsumo == null
                                      ? 'Selecione'
                                      : '${_dataConsumo!.day}/${_dataConsumo!.month}/${_dataConsumo!.year}',
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _qtdCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Quantidade',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _justCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Justificativa',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _denominacaoCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Denominação',
                          border: OutlineInputBorder(),
                        ),
                        maxLength: 100,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _responsavelCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Responsável',
                          border: OutlineInputBorder(),
                        ),
                        maxLength: 100,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => setState(() => _editing = false),
                            child: const Text('Cancelar'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: _save,
                            icon: const Icon(Icons.save),
                            label: const Text('Salvar Alterações'),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(0),
    );
  }
}
