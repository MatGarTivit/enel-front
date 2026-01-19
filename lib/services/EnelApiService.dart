import 'dart:convert';
import 'dart:typed_data';
import 'package:http_parser/http_parser.dart';

import 'package:dio/dio.dart';

class EnelDownloadedDocument {
  final Uint8List bytes;
  final String filename;
  final String contentType;

  const EnelDownloadedDocument({
    required this.bytes,
    required this.filename,
    required this.contentType,
  });
}
//com
class EnelApiService {
  //static const String baseUrl = 'http://localhost:3000';
  static const String baseUrl = 'https://subsequent-loon-tivit-fe258f78.koyeb.app';
  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  // --- GLPI Users (via DB) ---
  static Future<List<Map<String, dynamic>>> getGlpiUsers() async {
    final res = await _dio.get('/glpi/users');
    if (res.statusCode == 200) {
      final data = res.data;
      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      }
    }
    throw Exception('Failed GLPI users: ${res.statusCode} ${res.data}');
  }

  // --- Tipos de Despesa ---
  static Future<List<Map<String, dynamic>>> getTipoDespesa() async {
    final res = await _dio.get('/tipo-de-despesa');
    if (res.statusCode == 200) {
      final data = res.data;
      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      }
    }
    throw Exception(
      'Failed to load tipos de despesa: ${res.statusCode} ${res.data}',
    );
  }

  // --- Operacoes (Auto-fill) ---
  static Future<List<Map<String, dynamic>>> getOperacoes() async {
    final res = await _dio.get('/operacoes');
    if (res.statusCode == 200) {
      final data = res.data;
      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      }
    }
    throw Exception('Failed to load operacoes: ${res.statusCode} ${res.data}');
  }

  // --- criar despesa (tabela ENEL.despesas) ---
  static Future<int?> createDespesaEnel({
    required String tecnico,
    required int userId,
    required DateTime data,
    required String servicos,
    required String tipoDeDespesa,
    required String tipoDoc2,
    required String centroCusto,
    required String pep,
    required double valor,
    String? dataLancamentoSap,
    required String denominacao,
    required String responsavel,
  }) async {
    // FIXED: Use local date format to avoid timezone conversion (UTC shift)
    // toIso8601String() converts to UTC which can cause -1 day offset
    final String ymd =
        '${data.year}-${data.month.toString().padLeft(2, '0')}-${data.day.toString().padLeft(2, '0')}';

    final body = {
      'tecnico': tecnico,
      'user_id': userId,
      'data': ymd,
      'servicos': servicos,
      'tipo_de_despesa': tipoDeDespesa,
      'tipo_doc2': tipoDoc2,
      'centro_custo': centroCusto,
      'pep': pep,
      'valor': valor,
      'data_lancamento_sap': dataLancamentoSap,
      'denominacao': denominacao,
      'responsavel': responsavel,
    };

    final res = await _dio.post(
      '/despesas',
      data: jsonEncode(body),
      options: Options(headers: {'Content-Type': 'application/json'}),
    );

    if (res.statusCode == 200 || res.statusCode == 201) {
      int? asInt(dynamic v) =>
          v is int ? v : (v is String ? int.tryParse(v) : null);

      final decoded = res.data;
      if (decoded is Map) {
        final id =
            asInt(decoded['id']) ??
            asInt(decoded['despesaId']) ??
            asInt(decoded['insertId']) ??
            asInt((decoded['data'] is Map) ? decoded['data']['id'] : null);
        if (id != null) return id;
      }
      final numOnly = asInt(decoded);
      if (numOnly != null) return numOnly;

      throw Exception(
        'POST /despesas returned 200 but no id in body: ${res.data}',
      );
    }

    throw Exception('POST /despesas failed ${res.statusCode}: ${res.data}');
  }

  // --- criar subtarefa GLPI ---
  static Future<int?> createGlpiSubtask({
    required int parentTaskId,
    required String name,
  }) async {
    final now = DateTime.now();
    // FIXED: Use local date format to avoid timezone conversion
    final startDate =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final tomorrow = now.add(const Duration(days: 1));
    final endDate =
        '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';

    final body = {
      'projecttasks_id': parentTaskId,
      'name': name,
      'plan_start_date': startDate,
      'plan_end_date': endDate,
    };

    final res = await _dio.post(
      '/glpi/subtask',
      data: jsonEncode(body),
      options: Options(headers: {'Content-Type': 'application/json'}),
    );

    if (res.statusCode == 200) {
      final data = res.data;
      final task = data['task'];
      if (task is Map<String, dynamic>) {
        return task['id'] as int?;
      }
    }

    throw Exception('Subtask creation failed: ${res.statusCode} ${res.data}');
  }

  static MediaType _detectMediaType(String ext) {
    switch (ext.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return MediaType('image', 'jpeg');
      case 'png':
        return MediaType('image', 'png');
      case 'gif':
        return MediaType('image', 'gif');
      case 'webp':
        return MediaType('image', 'webp');
      case 'pdf':
        return MediaType('application', 'pdf');
      case 'txt':
        return MediaType('text', 'plain');
      case 'doc':
        return MediaType('application', 'msword');
      case 'docx':
        return MediaType(
          'application',
          'vnd.openxmlformats-officedocument.wordprocessingml.document',
        );
      default:
        return MediaType('application', 'octet-stream');
    }
  }

  static Future<Map<String, dynamic>> uploadPhotoBytesToTask({
    required int taskId,
    required Uint8List bytes,
    required String filename,
    String itemtype = 'ProjectTask',
    int? maxPartBytes,
    int? despesaId,
  }) async {
    // Extract extension
    final ext = filename.split('.').last.toLowerCase();
    final contentType = _detectMediaType(ext);

    final formData = FormData.fromMap({
      'itemtype': itemtype,
      'itemsId': taskId.toString(),
      if (maxPartBytes != null) 'maxPartBytes': maxPartBytes.toString(),
      if (despesaId != null) 'despesaId': despesaId.toString(),
      'files': [
        MultipartFile.fromBytes(
          bytes,
          filename: filename, // keep original filename UNCHANGED
          contentType: contentType, // correct MIME
        ),
      ],
    });

    final res = await _dio.post('/upload-documents', data: formData);
    return Map<String, dynamic>.from(res.data);
  }

  // --- Despesas: Listar por usuário ---
  static Future<List<Map<String, dynamic>>> getDespesasByUser({
    required int userId,
  }) async {
    final res = await _dio.get(
      '/despesas',
      queryParameters: {'user_id': userId},
    );
    if (res.statusCode == 200) {
      final data = res.data;
      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      } else if (data is Map && data['data'] is List) {
        return (data['data'] as List).cast<Map<String, dynamic>>();
      } else {
        // If data is something else, return empty list
        return [];
      }
    }
    throw Exception('Failed to load despesas: ${res.statusCode}');
  }

  // --- Despesas: Excluir ---
  static Future<void> deleteDespesa(int despesaId) async {
    final res = await _dio.delete('/despesas/$despesaId');
    if (res.statusCode != 200) {
      throw Exception(
        'Falha ao excluir despesa: ${res.statusCode} ${res.data}',
      );
    }
  }

  static Future<List<Map<String, dynamic>>> getAllDespesas() async {
    final res = await _dio.get('/despesas');
    if (res.statusCode == 200) {
      final data = res.data;
      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      } else if (data is Map && data['data'] is List) {
        return (data['data'] as List).cast<Map<String, dynamic>>();
      } else {
        return [];
      }
    }
    throw Exception('Failed to load despesas: ${res.statusCode}');
  }

  // --- Despesas: Excluir Arquivo ---
  static Future<void> deleteDespesaFile(int despesaId) async {
    final res = await _dio.delete('/despesas/$despesaId/file');
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception(
        'Falha ao remover arquivo: ${res.statusCode} ${res.data}',
      );
    }
  }

  // --- Despesas: Atualizar ---
  static Future<void> updateDespesa({
    required int despesaId,
    String? tipoDespesa,
    double? valor,
    DateTime? dataConsumo,
    int? quantidade,
    String? justificativa,
    String? denominacao,
    String? responsavel,
    String? tcfData,
    DateTime? dataLancamentoSap,
  }) async {
    final body = <String, dynamic>{};
    if (tipoDespesa != null) body['tipo_de_despesa'] = tipoDespesa;
    if (valor != null) body['valor'] = valor;
    if (dataConsumo != null) {
      body['data'] =
          '${dataConsumo.year}-${dataConsumo.month.toString().padLeft(2, '0')}-${dataConsumo.day.toString().padLeft(2, '0')}';
    }
    if (justificativa != null) body['servicos'] = justificativa;
    // quantidade? If backend supports it. I added it to PUT but noted schema mismatch.
    // I'll send it anyway if the UI sends it.
    if (quantidade != null) body['quantidade'] = quantidade;
    if (denominacao != null) body['denominacao'] = denominacao;
    if (responsavel != null) body['responsavel'] = responsavel;
    if (tcfData != null) body['tcf_data'] = tcfData;
    if (dataLancamentoSap != null) {
      body['data_lancamento_sap'] =
          '${dataLancamentoSap.year}-${dataLancamentoSap.month.toString().padLeft(2, '0')}-${dataLancamentoSap.day.toString().padLeft(2, '0')}';
    }

    final res = await _dio.put('/despesas/$despesaId', data: body);
    if (res.statusCode != 200) {
      throw Exception(
        'Falha ao atualizar despesa: ${res.statusCode} ${res.data}',
      );
    }
  }

  static Future<void> updateDespesaStatus({
    required int despesaId,
    required String aprovacao, // 'Aprovado' ou 'Reprovado'
    String? quemAprovou,
  }) async {
    final body = <String, dynamic>{'aprovacao': aprovacao};
    if (quemAprovou != null) {
      body['quem_aprovou'] = quemAprovou;
    }

    final res = await _dio.put('/despesas/$despesaId', data: body);
    if (res.statusCode != 200) {
      throw Exception(
        'Falha ao atualizar status: ${res.statusCode} ${res.data}',
      );
    }
  }

  // --- Despesas Arquivos: Listar todos (despesas_arquivos) ---
  static Future<List<Map<String, dynamic>>> getAllDespesaArquivos() async {
    final res = await _dio.get('/despesas-arquivos');
    if (res.statusCode == 200) {
      final data = res.data;
      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      } else if (data is Map && data['data'] is List) {
        return (data['data'] as List).cast<Map<String, dynamic>>();
      } else {
        return [];
      }
    }
    throw Exception(
      'Failed to load despesas_arquivos: ${res.statusCode} ${res.data}',
    );
  }

  // --- Baixar documento via proxy (/proxy/document/:id) ---
  static Future<EnelDownloadedDocument> downloadGlpiDocument(int docId) async {
    final res = await _dio.get<List<int>>(
      '/proxy/document/$docId',
      options: Options(
        responseType: ResponseType.bytes,
        // Não deixe Dio jogar exception em 4xx/5xx automaticamente,
        // vamos tratar manualmente.
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    final status = res.statusCode ?? 500;
    if (status != 200) {
      throw Exception(
        'Falha ao baixar documento (status $status): ${res.data}',
      );
    }

    // headers podem vir em minúsculo dependendo do adapter
    final headers = res.headers;
    final contentType =
        headers.value('content-type') ?? 'application/octet-stream';

    // Ex.: attachment; filename="abc.pdf"; filename*=UTF-8''abc.pdf
    final contentDisp = headers.value('content-disposition') ?? '';
    String filename = 'document-$docId';

    // tenta extrair filename entre aspas
    final filenameMatch = RegExp(
      r'filename\*?=([^;]+)',
      caseSensitive: false,
    ).firstMatch(contentDisp);
    if (filenameMatch != null) {
      var raw = filenameMatch.group(1)?.trim() ?? '';
      // remove aspas se existirem
      raw = raw.replaceAll('"', '');
      // trata formato filename*=UTF-8''nome.ext
      if (raw.toLowerCase().startsWith("utf-8''")) {
        raw = Uri.decodeComponent(raw.substring("utf-8''".length));
      }
      if (raw.isNotEmpty) {
        filename = raw;
      }
    }

    final bytes = Uint8List.fromList(res.data ?? const []);

    return EnelDownloadedDocument(
      bytes: bytes,
      filename: filename,
      contentType: contentType,
    );
  }

  // --- Proxy URL helper ---
  static String glpiDocProxyUrl(int docid) => '$baseUrl/proxy/document/$docid';
}
