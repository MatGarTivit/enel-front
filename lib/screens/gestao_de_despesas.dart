import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:provider/provider.dart';
import '../services/EnelApiService.dart';
import '../providers/user_session.dart';
import '../widgets/gradient_scaffold.dart';

final _currencyFormat = NumberFormat.simpleCurrency(locale: 'pt_BR');
final _dateFormat = DateFormat('dd/MM/yyyy');
final _dateFormatTime = DateFormat('dd/MM/yyyy HH:mm');

class GestaoDeDespesasScreen extends StatefulWidget {
  const GestaoDeDespesasScreen({super.key});

  @override
  State<GestaoDeDespesasScreen> createState() => _GestaoDeDespesasScreenState();
}

class _GestaoDeDespesasScreenState extends State<GestaoDeDespesasScreen> {
  bool _loading = false;

  String? _error;
  bool _isAuthenticated = false; // Controls access

  List<Map<String, dynamic>> _allDespesas = [];
  List<Map<String, dynamic>> _filteredDespesas = [];

  // despesas_id -> lista de arquivos
  final Map<int, List<Map<String, dynamic>>> _arquivosPorDespesa = {};

  // Filtros
  String? _selectedTecnico;
  String? _selectedTipoDespesa;
  String? _selectedStatus; // Pendentes, Aprovado, Reprovado
  String? _selectedTcfStatus; // SIM, NAO, todos (null)
  DateTimeRange? _selectedDateRange;

  @override
  void initState() {
    super.initState();
    // Schedule the PIN dialog after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showPinDialog();
    });
    // We can start loading data in background, but don't show it yet
    _loadData();
  }

  Future<void> _showPinDialog() async {
    bool? success = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        String pin = '';
        return AlertDialog(
          title: const Text('Acesso Restrito'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Digite o PIN de acesso:'),
              const SizedBox(height: 10),
              TextField(
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                onChanged: (value) => pin = value,
                onSubmitted: (value) {
                  if (value == '1234') {
                    Navigator.of(context).pop(true);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('PIN Incorreto')),
                    );
                  }
                },
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                // Return false to indicate failure/cancellation
                Navigator.of(context).pop(false);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (pin == '1234') {
                  Navigator.of(context).pop(true);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('PIN Incorreto')),
                  );
                }
              },
              child: const Text('Entrar'),
            ),
          ],
        );
      },
    );

    if (success == true) {
      setState(() {
        _isAuthenticated = true;
      });
    } else {
      // If cancelled or failed, go back
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        EnelApiService.getAllDespesas(),
        EnelApiService.getAllDespesaArquivos(),
      ]);

      final despesas = results[0] as List<Map<String, dynamic>>;
      final arquivos = results[1] as List<Map<String, dynamic>>;

      _allDespesas = despesas;

      // monta mapa despesas_id -> lista de arquivos
      _arquivosPorDespesa.clear();
      for (final row in arquivos) {
        final rawId = row['despesas_id'];
        if (rawId == null) continue;
        final id = rawId is int ? rawId : int.tryParse(rawId.toString()) ?? -1;
        if (id <= 0) continue;
        _arquivosPorDespesa.putIfAbsent(id, () => []).add(row);
      }

      _applyFilters();
    } catch (e) {
      _error = 'Erro ao carregar dados: $e';
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _applyFilters() {
    List<Map<String, dynamic>> list = List.of(_allDespesas);

    if (_selectedTecnico != null && _selectedTecnico!.isNotEmpty) {
      list = list
          .where(
            (d) =>
                (d['user_name'] ?? '').toString() == _selectedTecnico!.trim(),
          )
          .toList();
    }

    if (_selectedTipoDespesa != null && _selectedTipoDespesa!.isNotEmpty) {
      list = list
          .where(
            (d) =>
                (d['tipo_de_despesa'] ?? '').toString() ==
                _selectedTipoDespesa!.trim(),
          )
          .toList();
    }

    if (_selectedStatus != null && _selectedStatus!.isNotEmpty) {
      final st = _selectedStatus!;
      list = list.where((d) {
        final aprov = (d['aprovacao'] ?? '').toString();
        if (st == 'Pendentes') {
          return aprov.isEmpty ||
              aprov.toLowerCase().startsWith('pend') ||
              aprov.toLowerCase().contains('aguardando');
        }
        return aprov == st;
      }).toList();
    }

    if (_selectedDateRange != null) {
      final from = _selectedDateRange!.start;
      final to = _selectedDateRange!.end;
      list = list.where((d) {
        final raw = d['data_consumo'];
        if (raw == null) return false;
        try {
          final dt = DateTime.parse(raw.toString());
          final day = DateTime(dt.year, dt.month, dt.day);
          final dayFrom = DateTime(from.year, from.month, from.day);
          final dayTo = DateTime(to.year, to.month, to.day);
          return (day.isAtSameMomentAs(dayFrom) || day.isAfter(dayFrom)) &&
              (day.isAtSameMomentAs(dayTo) ||
                  day.isBefore(dayTo.add(const Duration(days: 1))));
        } catch (_) {
          return false;
        }
      }).toList();
    }

    if (_selectedTcfStatus != null && _selectedTcfStatus!.isNotEmpty) {
      final status = _selectedTcfStatus!;
      list = list.where((d) {
        final tcf = (d['tcf_data'] ?? '').toString().trim();
        if (status == 'SIM') {
          return tcf.isNotEmpty;
        } else if (status == 'NAO') {
          return tcf.isEmpty;
        }
        return true;
      }).toList();
    }

    setState(() {
      _filteredDespesas = list;
    });
  }

  double _parseValor(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) {
      return double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
    }
    return 0.0;
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return null;
    }
  }

  // Métricas simples
  double get _totalGeral {
    return _filteredDespesas.fold<double>(
      0.0,
      (sum, d) => sum + _parseValor(d['valor_despesa']),
    );
  }

  int get _totalPendentes {
    return _filteredDespesas.where((d) {
      final aprov = (d['aprovacao'] ?? '').toString();
      return aprov.isEmpty ||
          aprov.toLowerCase().startsWith('pend') ||
          aprov.toLowerCase().contains('aguardando');
    }).length;
  }

  int get _totalAprovados {
    return _filteredDespesas
        .where((d) => (d['aprovacao'] ?? '').toString() == 'Aprovado')
        .length;
  }

  int get _totalReprovados {
    return _filteredDespesas
        .where((d) => (d['aprovacao'] ?? '').toString() == 'Reprovado')
        .length;
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
      initialDateRange:
          _selectedDateRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 30)),
            end: now,
          ),
    );

    if (result != null) {
      setState(() => _selectedDateRange = result);
      _applyFilters();
    }
  }

  void _clearFilters() {
    setState(() {
      _selectedTecnico = null;
      _selectedTipoDespesa = null;
      _selectedStatus = null;
      _selectedTcfStatus = null;
      _selectedDateRange = null;
    });
    _applyFilters();
  }

  Future<void> _changeStatus(
    Map<String, dynamic> despesa,
    String newStatus,
  ) async {
    final id = despesa['despesa_id'];
    if (id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          newStatus == 'Aprovado' ? 'Aprovar despesa' : 'Reprovar despesa',
        ),
        content: Text('Marcar despesa #$id como "$newStatus"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      setState(() => _loading = true);
      final idInt = id is int ? id : int.parse(id.toString());
      final userName = Provider.of<UserSession>(
        context,
        listen: false,
      ).userName;

      await EnelApiService.updateDespesaStatus(
        despesaId: idInt,
        aprovacao: newStatus,
        quemAprovou: userName,
      );

      setState(() {
        final idx = _allDespesas.indexWhere(
          (d) => d['despesa_id'] == despesa['despesa_id'],
        );
        if (idx >= 0) {
          _allDespesas[idx] = {..._allDespesas[idx], 'aprovacao': newStatus};
        }
        final fIdx = _filteredDespesas.indexWhere(
          (d) => d['despesa_id'] == despesa['despesa_id'],
        );
        if (fIdx >= 0) {
          _filteredDespesas[fIdx] = {
            ..._filteredDespesas[fIdx],
            'aprovacao': newStatus,
          };
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Despesa #$id marcada como $newStatus')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao atualizar status: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openDocument(String url) async {
    final uri = Uri.parse(url);

    if (!await canLaunchUrl(uri)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir o documento.')),
        );
      }
      return;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final tecnicos =
        _allDespesas
            .map((d) => (d['user_name'] ?? '').toString())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    final tipos =
        _allDespesas
            .map((d) => (d['tipo_de_despesa'] ?? '').toString())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    const statuses = <String>['Pendentes', 'Aprovado', 'Reprovado'];

    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Gestão de Despesas'),
        actions: [
          IconButton(
            onPressed: _loading || !_isAuthenticated ? null : _loadData,
            icon: const Icon(Icons.refresh),
            tooltip: 'Recarregar',
          ),
        ],
      ),
      body: !_isAuthenticated
          ? const Center(child: CircularProgressIndicator()) // Hide content
          : Padding(
              padding: const EdgeInsets.all(16),
              child: _loading && _allDespesas.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Filtros
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            SizedBox(
                              width: min(
                                220,
                                MediaQuery.of(context).size.width,
                              ),
                              child: DropdownButtonFormField<String>(
                                value: _selectedTecnico,
                                decoration: const InputDecoration(
                                  labelText: 'Técnico',
                                  border: OutlineInputBorder(),
                                ),
                                isExpanded: true,
                                items: [
                                  const DropdownMenuItem(
                                    value: null,
                                    child: Text('Todos'),
                                  ),
                                  ...tecnicos.map(
                                    (t) => DropdownMenuItem(
                                      value: t,
                                      child: Text(t),
                                    ),
                                  ),
                                ],
                                onChanged: (value) {
                                  setState(() => _selectedTecnico = value);
                                  _applyFilters();
                                },
                              ),
                            ),
                            SizedBox(
                              width: min(
                                200,
                                MediaQuery.of(context).size.width,
                              ),
                              child: DropdownButtonFormField<String>(
                                value: _selectedTipoDespesa,
                                decoration: const InputDecoration(
                                  labelText: 'Tipo de despesa',
                                  border: OutlineInputBorder(),
                                ),
                                isExpanded: true,
                                items: [
                                  const DropdownMenuItem(
                                    value: null,
                                    child: Text('Todos'),
                                  ),
                                  ...tipos.map(
                                    (t) => DropdownMenuItem(
                                      value: t,
                                      child: Text(t),
                                    ),
                                  ),
                                ],
                                onChanged: (value) {
                                  setState(() => _selectedTipoDespesa = value);
                                  _applyFilters();
                                },
                              ),
                            ),
                            SizedBox(
                              width: min(
                                180,
                                MediaQuery.of(context).size.width,
                              ),
                              child: DropdownButtonFormField<String>(
                                value: _selectedStatus,
                                decoration: const InputDecoration(
                                  labelText: 'Status',
                                  border: OutlineInputBorder(),
                                ),
                                isExpanded: true,
                                items: [
                                  const DropdownMenuItem(
                                    value: null,
                                    child: Text('Todos'),
                                  ),
                                  ...statuses.map(
                                    (s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(s),
                                    ),
                                  ),
                                ],
                                onChanged: (value) {
                                  setState(() => _selectedStatus = value);
                                  _applyFilters();
                                },
                              ),
                            ),
                            SizedBox(
                              width: min(
                                150,
                                MediaQuery.of(context).size.width,
                              ),
                              child: DropdownButtonFormField<String>(
                                value: _selectedTcfStatus,
                                decoration: const InputDecoration(
                                  labelText: 'TCF/DATA',
                                  border: OutlineInputBorder(),
                                ),
                                isExpanded: true,
                                items: const [
                                  DropdownMenuItem(
                                    value: null,
                                    child: Text('Todos'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'SIM',
                                    child: Text('SIM'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'NAO',
                                    child: Text('NÃO'),
                                  ),
                                ],
                                onChanged: (value) {
                                  setState(() => _selectedTcfStatus = value);
                                  _applyFilters();
                                },
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _pickDateRange,
                              icon: const Icon(Icons.date_range),
                              label: Text(
                                _selectedDateRange == null
                                    ? 'Período'
                                    : '${_dateFormat.format(_selectedDateRange!.start)} - '
                                          '${_dateFormat.format(_selectedDateRange!.end)}',
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _clearFilters,
                              icon: const Icon(Icons.clear_all),
                              label: const Text('Limpar filtros'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Cards de métricas
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _MetricCard(
                                label: 'Total Geral',
                                value: _currencyFormat.format(_totalGeral),
                              ),
                              const SizedBox(width: 8),
                              _MetricCard(
                                label: 'Pendentes',
                                value: '$_totalPendentes',
                                color: Colors.orange.shade600,
                              ),
                              const SizedBox(width: 8),
                              _MetricCard(
                                label: 'Aprovados',
                                value: '$_totalAprovados',
                                color: Colors.green.shade600,
                              ),
                              const SizedBox(width: 8),
                              _MetricCard(
                                label: 'Reprovados',
                                value: '$_totalReprovados',
                                color: Colors.red.shade600,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        Expanded(
                          child: _filteredDespesas.isEmpty
                              ? const Center(
                                  child: Text('Nenhuma despesa encontrada.'),
                                )
                              : ListView.separated(
                                  itemCount: _filteredDespesas.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    final d = _filteredDespesas[index];
                                    return _buildDespesaCard(context, d);
                                  },
                                ),
                        ),
                      ],
                    ),
            ),
    );
  }

  Widget _buildDespesaCard(BuildContext context, Map<String, dynamic> despesa) {
    final theme = Theme.of(context);
    final id = despesa['despesa_id'];
    final tecnico = (despesa['user_name'] ?? '').toString();
    final tipo = (despesa['tipo_de_despesa'] ?? '').toString();
    final dt = _parseDate(despesa['data_consumo']);
    final valor = _parseValor(despesa['valor_despesa']);
    final justificativa = (despesa['justificativa'] ?? '').toString();
    final aprov = (despesa['aprovacao'] ?? '').toString();

    Color chipColor;
    String chipText;
    if (aprov == 'Aprovado') {
      chipColor = Colors.green.shade600;
      chipText = 'Aprovado';
    } else if (aprov == 'Reprovado') {
      chipColor = Colors.red.shade600;
      chipText = 'Reprovado';
    } else {
      chipColor = Colors.orange.shade600;
      chipText = aprov.isEmpty ? 'Pendente' : aprov;
    }

    final quemAprovou = (despesa['quem_aprovou'] ?? '').toString();
    final aprovadoEmRaw = despesa['aprovado_em'];
    DateTime? aprovadoEm;
    if (aprovadoEmRaw != null) {
      try {
        aprovadoEm = DateTime.parse(aprovadoEmRaw.toString());
      } catch (_) {}
    }

    final rawId = despesa['despesa_id'];
    final despesaId = rawId is int
        ? rawId
        : int.tryParse(rawId.toString()) ?? -1;
    final arquivos = _arquivosPorDespesa[despesaId] ?? const [];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1.5,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabeçalho
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Despesa #$id',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(tecnico, style: theme.textTheme.bodyMedium),
                      if (tipo.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          tipo,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: chipColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        chipText,
                        style: TextStyle(
                          color: chipColor,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (quemAprovou.isNotEmpty && aprovadoEm != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Por: $quemAprovou',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        _dateFormatTime.format(aprovadoEm),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Infos principais
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _InfoChip(
                  label: 'Data',
                  value: dt == null ? '-' : _dateFormat.format(dt),
                ),
                _InfoChip(label: 'Valor', value: _currencyFormat.format(valor)),
              ],
            ),
            const SizedBox(height: 12),

            if (justificativa.isNotEmpty) ...[
              Text('Justificativa', style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(justificativa, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 12),
            ],

            // Documentos
            Text('Documentos anexados', style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            if (arquivos.isEmpty)
              Text(
                'Nenhum documento anexado.',
                style: theme.textTheme.bodySmall,
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (var i = 0; i < arquivos.length; i++)
                    _buildDocumentoChip(arquivos[i], i),
                ],
              ),
            const SizedBox(height: 12),

            // Botões de ação
            _TcfDataSection(
              initialValue: (despesa['tcf_data'] ?? '').toString(),
              initialDate: _parseDate(despesa['data_lancamento_sap']),
              onConfirm: (tcfValue, dateValue) async {
                try {
                  setState(() => _loading = true);
                  final idInt = despesaId;

                  await EnelApiService.updateDespesa(
                    despesaId: idInt,
                    tcfData: tcfValue,
                    dataLancamentoSap: dateValue,
                  );

                  setState(() {
                    final idx = _allDespesas.indexWhere(
                      (d) => d['despesa_id'] == despesa['despesa_id'],
                    );
                    if (idx >= 0) {
                      _allDespesas[idx] = {
                        ..._allDespesas[idx],
                        'tcf_data': tcfValue,
                        // Update local date string. _parseDate expects string in ISO or similar,
                        // but here we just store what we have or converting if needed for local state consistency
                        // The backend returns it as string usually.
                        'data_lancamento_sap': dateValue
                            ?.toIso8601String()
                            .substring(0, 10),
                      };
                    }
                    final fIdx = _filteredDespesas.indexWhere(
                      (d) => d['despesa_id'] == despesa['despesa_id'],
                    );
                    if (fIdx >= 0) {
                      _filteredDespesas[fIdx] = {
                        ..._filteredDespesas[fIdx],
                        'tcf_data': tcfValue,
                        'data_lancamento_sap': dateValue
                            ?.toIso8601String()
                            .substring(0, 10),
                      };
                    }
                  });

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Dados atualizados!')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Erro: $e')));
                  }
                } finally {
                  if (mounted) setState(() => _loading = false);
                }
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _loading
                        ? null
                        : () => _changeStatus(despesa, 'Aprovado'),
                    child: const Text('Aprovar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade50,
                    ),
                    onPressed: _loading
                        ? null
                        : () => _changeStatus(despesa, 'Reprovado'),
                    child: Text(
                      'Reprovar',
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentoChip(Map<String, dynamic> arq, int index) {
    final docIdRaw = arq['photo_docid'];
    final labelBase = docIdRaw != null
        ? 'Doc ${docIdRaw.toString()}'
        : 'Documento ${index + 1}';

    // se não tiver docId, só mostra chip "morto"
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

    return ActionChip(
      label: Text(labelBase),
      onPressed: () => _openDocument(proxyUrl),
      tooltip: proxyUrl,
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _MetricCard({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = color ?? theme.colorScheme.primary;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;

  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: theme.textTheme.labelSmall),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TcfDataSection extends StatefulWidget {
  final String initialValue;
  final DateTime? initialDate;
  final void Function(String, DateTime?) onConfirm;

  const _TcfDataSection({
    super.key,
    required this.initialValue,
    this.initialDate,
    required this.onConfirm,
  });

  @override
  State<_TcfDataSection> createState() => _TcfDataSectionState();
}

class _TcfDataSectionState extends State<_TcfDataSection> {
  late TextEditingController _controller;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _selectedDate = widget.initialDate;
  }

  @override
  void didUpdateWidget(covariant _TcfDataSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      if (_controller.text != widget.initialValue) {
        _controller.text = widget.initialValue;
      }
    }
    if (oldWidget.initialDate != widget.initialDate) {
      _selectedDate = widget.initialDate;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final result = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (result != null) {
      setState(() => _selectedDate = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasValue = widget.initialValue.isNotEmpty;
    // Format date if selected
    final dateStr = _selectedDate != null
        ? DateFormat('dd/MM/yyyy').format(_selectedDate!)
        : '';

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Date Picker Field
        SizedBox(
          width: 150,
          child: InkWell(
            onTap: _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Data SAP',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.all(8),
              ),
              child: Text(
                dateStr,
                style: _selectedDate != null
                    ? const TextStyle(color: Colors.grey)
                    : null,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),

        SizedBox(
          width: 120, // Approx 10 chars width
          child: TextField(
            controller: _controller,
            maxLength: 10,
            style: hasValue
                ? const TextStyle(color: Colors.grey)
                : null, // Grey out if exists
            decoration: const InputDecoration(
              labelText: 'TCF',
              border: OutlineInputBorder(),
              counterText: '',
              isDense: true,
              contentPadding: EdgeInsets.all(8),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () {
            widget.onConfirm(_controller.text, _selectedDate);
          },
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Confirmado', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}
