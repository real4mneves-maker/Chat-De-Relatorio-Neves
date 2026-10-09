import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NevesApp());
}

const blue = Color(0xFF0D47A1);

class ReportEntry {
  ReportEntry({required this.id, required this.input, required this.report, required this.date});
  final String id;
  final String input;
  final String report;
  final DateTime date;
  Map<String, dynamic> toJson() => {'id': id, 'input': input, 'report': report, 'date': date.toIso8601String()};
  factory ReportEntry.fromJson(Map<String, dynamic> json) => ReportEntry(
    id: json['id'] as String? ?? '',
    input: json['input'] as String? ?? '',
    report: json['report'] as String? ?? '',
    date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
  );
}

class Template {
  Template(this.name, this.fields, {this.custom = false});
  final String name;
  final List<String> fields;
  final bool custom;
  Map<String, dynamic> toJson() => {'name': name, 'fields': fields, 'custom': custom};
  factory Template.fromJson(Map<String, dynamic> json) => Template(
    json['name'] as String? ?? '',
    List<String>.from(json['fields'] as List? ?? []),
    custom: json['custom'] == true,
  );
}

final standardTemplates = <Template>[
  Template('Transporte de Paciente', ['Origem', 'Destino', 'Meio de transporte', 'Profissional acompanhante', 'Situação']),
  Template('Verificação de Cilindros de Oxigênio', ['Setor', 'Quantidade', 'Condições dos cilindros', 'Pendências']),
  Template('Aviso de Setor', ['Setor', 'Assunto', 'Descrição', 'Orientação']),
  Template('Passagem de Plantão', ['Setor', 'Horário', 'Atividades realizadas', 'Pendências', 'Intercorrências']),
  Template('Relatório de Intercorrência', ['Setor', 'Horário', 'Ocorrência', 'Providências', 'Profissionais comunicados']),
  Template('Higienização de Cadeiras', ['Setor', 'Equipamentos higienizados', 'Situação', 'Observações']),
];

class NevesApp extends StatefulWidget {
  const NevesApp({super.key});
  @override
  State<NevesApp> createState() => _NevesAppState();
}

class _NevesAppState extends State<NevesApp> {
  bool dark = false;
  bool loaded = false;
  String apiKey = '';
  String provider = 'Gemini';
  final List<ReportEntry> reports = [];
  final List<Template> customTemplates = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    try {
      final raw = jsonDecode(p.getString('reports') ?? '[]') as List;
      reports.addAll(raw.map((e) => ReportEntry.fromJson(Map<String, dynamic>.from(e as Map))));
      final rawTemplates = jsonDecode(p.getString('templates') ?? '[]') as List;
      customTemplates.addAll(rawTemplates.map((e) => Template.fromJson(Map<String, dynamic>.from(e as Map))));
    } catch (_) {
      // Preserva uso do app mesmo se um registro local estiver corrompido.
    }
    if (!mounted) return;
    setState(() {
      dark = p.getBool('dark') ?? false;
      apiKey = p.getString('api_key') ?? '';
      provider = p.getString('provider') ?? 'Gemini';
      loaded = true;
    });
  }

  Future<void> persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('reports', jsonEncode(reports.map((e) => e.toJson()).toList()));
    await p.setString('templates', jsonEncode(customTemplates.map((e) => e.toJson()).toList()));
    await p.setBool('dark', dark);
    await p.setString('api_key', apiKey);
    await p.setString('provider', provider);
  }

  void addReport(String input, String report) {
    setState(() => reports.insert(0, ReportEntry(id: DateTime.now().microsecondsSinceEpoch.toString(), input: input, report: report, date: DateTime.now())));
    persist();
  }

  Future<String> generate(String input) async {
    final cleaned = input.trim();
    if (apiKey.isEmpty) return localReport(cleaned);
    const instruction = '''Você é um assistente de relatórios hospitalares para maqueiros. Produza apenas um relatório breve e profissional em português brasileiro, adequado para copiar no WhatsApp. Identifique o tipo de ocorrência e use título em maiúsculas e campos rotulados. Corrija erros de transcrição, mas NUNCA invente nome, setor, horário, condição clínica, profissional ou conclusão. Omita campos não informados ou use "Não informado" quando essencial. Evite diagnósticos e informações médicas sensíveis desnecessárias. Se o usuário disser sem intercorrências, mantenha essa informação. Não acrescente fatos.''';
    try {
      if (provider == 'OpenAI') {
        final response = await http.post(Uri.parse('https://api.openai.com/v1/chat/completions'), headers: {
          'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json',
        }, body: jsonEncode({'model': 'gpt-4o-mini', 'messages': [
          {'role': 'system', 'content': instruction}, {'role': 'user', 'content': cleaned}
        ]})).timeout(const Duration(seconds: 35));
        if (response.statusCode != 200) throw Exception('OpenAI HTTP ${response.statusCode}: ${_shortError(response.body)}');
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        return ((data['choices'] as List).first['message']['content'] as String).trim();
      }
      final response = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent'),
        headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
        body: jsonEncode({'system_instruction': {'parts': [{'text': instruction}]}, 'contents': [{'role': 'user', 'parts': [{'text': cleaned}]}]}),
      ).timeout(const Duration(seconds: 35));
      if (response.statusCode != 200) throw Exception('Gemini HTTP ${response.statusCode}: ${_shortError(response.body)}');
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final candidate = (data['candidates'] as List).first as Map<String, dynamic>;
      final parts = (candidate['content'] as Map<String, dynamic>)['parts'] as List;
      return parts.map((e) => e['text'] ?? '').join('\n').trim();
    } catch (e) {
      throw Exception('Não foi possível consultar a IA: $e');
    }
  }

  String _shortError(String body) => body.length > 180 ? body.substring(0, 180) : body;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: blue, brightness: dark ? Brightness.dark : Brightness.light);
    return MaterialApp(
      title: 'Chat de Relatório Neves', debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: scheme, useMaterial3: true, appBarTheme: const AppBarTheme(centerTitle: false)),
      home: loaded ? HomePage(
        reports: reports,
        templates: [...standardTemplates, ...customTemplates],
        onGenerate: generate,
        onAddReport: addReport,
        onDelete: (item) { setState(() => reports.remove(item)); persist(); },
        onNewTemplate: (item) { setState(() => customTemplates.add(item)); persist(); },
        dark: dark, onDark: (value) { setState(() => dark = value); persist(); },
        provider: provider, onProvider: (value) { setState(() => provider = value); persist(); },
        apiKey: apiKey, onApiKey: (value) { setState(() => apiKey = value); persist(); },
      ) : const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}

String localReport(String input) {
  // Modo básico offline: organiza fatos escritos, sem inferir detalhes que não foram fornecidos.
  final lower = input.toLowerCase();
  String title = 'RELATÓRIO DE ATIVIDADE';
  if (lower.contains('transport') || lower.contains('paciente')) title = 'TRANSPORTE DE PACIENTE';
  else if (lower.contains('oxigênio') || lower.contains('oxigenio') || lower.contains('cilindro') || lower.contains('bala de ox')) title = 'VERIFICAÇÃO DE OXIGÊNIO';
  else if (lower.contains('higieniz') || lower.contains('cadeira')) title = 'HIGIENIZAÇÃO DE EQUIPAMENTOS';
  else if (lower.contains('plantão') || lower.contains('plantao')) title = 'PASSAGEM DE PLANTÃO';
  else if (lower.contains('intercorrência') || lower.contains('intercorrencia')) title = 'RELATÓRIO DE INTERCORRÊNCIA';
  final normalized = input.isEmpty ? 'Não informado.' : '${input[0].toUpperCase()}${input.substring(1).replaceAll(RegExp(r'[. ]+$'), '')}.';
  return '📋 $title\n\nDescrição: $normalized';
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.reports, required this.templates, required this.onGenerate, required this.onAddReport,
    required this.onDelete, required this.onNewTemplate, required this.dark, required this.onDark,
    required this.provider, required this.onProvider, required this.apiKey, required this.onApiKey});
  final List<ReportEntry> reports;
  final List<Template> templates;
  final Future<String> Function(String) onGenerate;
  final void Function(String, String) onAddReport;
  final void Function(ReportEntry) onDelete;
  final void Function(Template) onNewTemplate;
  final bool dark;
  final ValueChanged<bool> onDark;
  final String provider;
  final ValueChanged<String> onProvider;
  final String apiKey;
  final ValueChanged<String> onApiKey;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  final input = TextEditingController();
  final stt.SpeechToText speech = stt.SpeechToText();
  bool listening = false;
  bool sending = false;
  String? error;

  @override
  void dispose() { input.dispose(); super.dispose(); }

  Future<void> submit() async {
    final text = input.text.trim();
    if (text.isEmpty || sending) return;
    setState(() { sending = true; error = null; });
    try {
      final result = await widget.onGenerate(text);
      if (!mounted) return;
      widget.onAddReport(text, result);
      input.clear();
      setState(() {});
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> toggleSpeech() async {
    if (listening) { await speech.stop(); if (mounted) setState(() => listening = false); return; }
    final available = await speech.initialize(onStatus: (status) {
      if (status == 'done' || status == 'notListening') { if (mounted) setState(() => listening = false); }
    }, onError: (e) { if (mounted) setState(() { listening = false; error = 'Erro no microfone: ${e.errorMsg}'; }); });
    if (!available) { if (mounted) setState(() => error = 'Reconhecimento de voz indisponível neste aparelho.'); return; }
    setState(() => listening = true);
    await speech.listen(localeId: 'pt_BR', onResult: (result) {
      if (mounted) setState(() => input.text = result.recognizedWords);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Row(children: [
        Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.assignment_turned_in_rounded)),
        const SizedBox(width: 12), const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Chat de Relatório Neves', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)), Text('Assistente hospitalar', style: TextStyle(fontSize: 12))]))
      ])),
      body: IndexedStack(index: tab, children: [chatTab(), templatesTab(), historyTab(), settingsTab()]),
      bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (n) => setState(() => tab = n), destinations: const [
        NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Chat'),
        NavigationDestination(icon: Icon(Icons.dashboard_customize_outlined), label: 'Modelos'),
        NavigationDestination(icon: Icon(Icons.history), label: 'Histórico'),
        NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Ajustes'),
      ]),
    );
  }

  Widget chatTab() => Column(children: [
    Expanded(child: widget.reports.isEmpty ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.speaker_notes_rounded, size: 64, color: Theme.of(context).colorScheme.primary),
      const SizedBox(height: 16), const Text('Seu plantão, organizado.', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8), const Text('Descreva uma atividade por texto ou voz. O relatório ficará pronto para copiar ou compartilhar.', textAlign: TextAlign.center),
      const SizedBox(height: 18), FilledButton.tonal(onPressed: () => setState(() => tab = 1), child: const Text('Explorar modelos'))
    ]))) : ListView.builder(reverse: true, padding: const EdgeInsets.all(16), itemCount: widget.reports.length, itemBuilder: (context, index) {
      final r = widget.reports[widget.reports.length - index - 1];
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(alignment: Alignment.centerRight, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 310), child: Card(color: Theme.of(context).colorScheme.primaryContainer, child: Padding(padding: const EdgeInsets.all(14), child: Text(r.input))))),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r.report, style: const TextStyle(height: 1.5)), const SizedBox(height: 10),
          Wrap(spacing: 8, children: [TextButton.icon(onPressed: () { Clipboard.setData(ClipboardData(text: r.report)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Relatório copiado'))); }, icon: const Icon(Icons.copy_outlined, size: 18), label: const Text('Copiar')),
            TextButton.icon(onPressed: () => SharePlus.instance.share(ShareParams(text: r.report)), icon: const Icon(Icons.share_outlined, size: 18), label: const Text('Compartilhar'))])
        ]))), const SizedBox(height: 10)
      ]);
    })),
    if (error != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
    if (sending) const LinearProgressIndicator(),
    SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
      IconButton.filledTonal(onPressed: toggleSpeech, tooltip: listening ? 'Parar gravação' : 'Ditar relatório', iconSize: 28, icon: Icon(listening ? Icons.stop_circle : Icons.mic_rounded)),
      const SizedBox(width: 8), Expanded(child: TextField(controller: input, minLines: 1, maxLines: 4, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(hintText: 'O que aconteceu no plantão?', filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none)))),
      const SizedBox(width: 8), IconButton.filled(onPressed: sending ? null : submit, icon: const Icon(Icons.send_rounded))
    ])))
  ]);

  Widget templatesTab() => ListView(padding: const EdgeInsets.all(16), children: [
    Row(children: [const Expanded(child: Text('Modelos de relatórios', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))), IconButton.filledTonal(onPressed: newTemplateDialog, tooltip: 'Novo modelo', icon: const Icon(Icons.add))]),
    const SizedBox(height: 8), ...widget.templates.map((t) => Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.description_outlined)), title: Text(t.name), subtitle: Text('${t.fields.length} campos${t.custom ? ' • personalizado' : ''}'), trailing: const Icon(Icons.chevron_right), onTap: () => openTemplate(t))))
  ]);

  void openTemplate(Template template) {
    final controllers = {for (final field in template.fields) field: TextEditingController()};
    showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: Text(template.name), content: SizedBox(width: 450, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: template.fields.map((f) => Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(controller: controllers[f], decoration: InputDecoration(labelText: f, border: const OutlineInputBorder())))).toList()))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')), FilledButton(onPressed: () {
        final detail = controllers.entries.where((e) => e.value.text.trim().isNotEmpty).map((e) => '${e.key}: ${e.value.text.trim()}').join('\n');
        if (detail.isEmpty) return;
        final report = '📋 ${template.name.toUpperCase()}\n\n$detail';
        widget.onAddReport(detail, report);
        Navigator.pop(context);
        setState(() => tab = 0);
      }, child: const Text('Criar relatório'))],
    )).then((_) { for (final c in controllers.values) { c.dispose(); } });
  }

  void newTemplateDialog() {
    final title = TextEditingController();
    final fields = TextEditingController();
    showDialog<void>(context: context, builder: (context) => AlertDialog(title: const Text('Novo modelo'), content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: title, decoration: const InputDecoration(labelText: 'Nome do modelo')),
      TextField(controller: fields, maxLines: 3, decoration: const InputDecoration(labelText: 'Campos separados por vírgula', hintText: 'Setor, Horário, Ocorrência')),
    ]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')), FilledButton(onPressed: () {
      final name = title.text.trim(); final list = fields.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      if (name.isEmpty || list.isEmpty) return;
      widget.onNewTemplate(Template(name, list, custom: true)); Navigator.pop(context);
    }, child: const Text('Salvar'))])).then((_) { title.dispose(); fields.dispose(); });
  }

  Widget historyTab() => HistoryPanel(reports: widget.reports, onDelete: (item) { widget.onDelete(item); setState(() {}); });

  Widget settingsTab() => ListView(padding: const EdgeInsets.all(20), children: [
    const Text('Configurações', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
    const SizedBox(height: 20), SwitchListTile(title: const Text('Tema escuro'), secondary: const Icon(Icons.dark_mode_outlined), value: widget.dark, onChanged: widget.onDark),
    const SizedBox(height: 14), DropdownButtonFormField<String>(value: widget.provider, decoration: const InputDecoration(labelText: 'Provedor de IA', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'Gemini', child: Text('Google Gemini')), DropdownMenuItem(value: 'OpenAI', child: Text('OpenAI'))], onChanged: (v) { if (v != null) widget.onProvider(v); }),
    const SizedBox(height: 16), TextFormField(initialValue: widget.apiKey, obscureText: true, autocorrect: false, decoration: const InputDecoration(labelText: 'Chave da API', border: OutlineInputBorder(), helperText: 'Sem chave: modelos e organização básica offline.'), onChanged: widget.onApiKey),
    const SizedBox(height: 20), const Text('Privacidade', style: TextStyle(fontWeight: FontWeight.bold)),
    const Text('O histórico fica salvo neste aparelho. Quando a IA está ativada, o texto digitado é enviado ao provedor escolhido. Evite inserir nome completo, CPF, prontuário ou outros dados que identifiquem pacientes.'),
    const SizedBox(height: 12), const Text('A chave é armazenada nas preferências locais do app. Para uso institucional, recomenda-se autenticação e servidor seguro, sem expor a chave no aparelho.'),
    const SizedBox(height: 20), OutlinedButton.icon(onPressed: () async { await exportPdf(widget.reports); }, icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Exportar relatórios em PDF')),
    OutlinedButton.icon(onPressed: () async { await exportCsv(widget.reports); }, icon: const Icon(Icons.table_chart_outlined), label: const Text('Compartilhar planilha CSV do dia')),
  ]);
}

class HistoryPanel extends StatefulWidget {
  const HistoryPanel({super.key, required this.reports, required this.onDelete});
  final List<ReportEntry> reports;
  final ValueChanged<ReportEntry> onDelete;
  @override
  State<HistoryPanel> createState() => _HistoryPanelState();
}
class _HistoryPanelState extends State<HistoryPanel> {
  String search = '';
  DateTime? day;
  @override
  Widget build(BuildContext context) {
    final filtered = widget.reports.where((r) {
      final matchText = '${r.input}\n${r.report}'.toLowerCase().contains(search.toLowerCase());
      final matchDay = day == null || (r.date.year == day!.year && r.date.month == day!.month && r.date.day == day!.day);
      return matchText && matchDay;
    }).toList();
    return Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        TextField(onChanged: (s) => setState(() => search = s), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por setor, texto ou paciente', border: OutlineInputBorder())),
        const SizedBox(height: 8), Row(children: [TextButton.icon(onPressed: () async { final picked = await showDatePicker(context: context, initialDate: day ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100)); if (picked != null) setState(() => day = picked); }, icon: const Icon(Icons.calendar_month), label: Text(day == null ? 'Filtrar data' : DateFormat('dd/MM/yyyy').format(day!))), if (day != null) TextButton(onPressed: () => setState(() => day = null), child: const Text('Limpar'))])
      ])),
      Expanded(child: filtered.isEmpty ? const Center(child: Text('Nenhum relatório encontrado.')) : ListView.builder(itemCount: filtered.length, itemBuilder: (context, i) {
        final r = filtered[i];
        return Card(margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5), child: ExpansionTile(title: Text(r.report.split('\n').first), subtitle: Text(DateFormat('dd/MM/yyyy HH:mm').format(r.date)), children: [
          Padding(padding: const EdgeInsets.all(16), child: SelectableText(r.report)),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [TextButton.icon(onPressed: () => Clipboard.setData(ClipboardData(text: r.report)), icon: const Icon(Icons.copy), label: const Text('Copiar')), TextButton.icon(onPressed: () => widget.onDelete(r), icon: const Icon(Icons.delete_outline), label: const Text('Excluir'))])
        ]));
      }))
    ]);
  }
}

Future<void> exportPdf(List<ReportEntry> reports) async {
  final doc = pw.Document();
  final font = pw.Font.helvetica();
  final bold = pw.Font.helveticaBold();
  final items = reports.isEmpty ? ['Nenhum relatório registrado.'] : reports.map((r) => '${DateFormat('dd/MM/yyyy HH:mm').format(r.date)}\n${r.report}').toList();
  doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, theme: pw.ThemeData.withFont(base: font, bold: bold), build: (ctx) => [
    pw.Text('Chat de Relatório Neves', style: pw.TextStyle(font: bold, fontSize: 20)), pw.SizedBox(height: 16),
    ...items.map((item) => pw.Padding(padding: const pw.EdgeInsets.only(bottom: 16), child: pw.Text(item.replaceAll(RegExp(r'[\u{1F300}-\u{1FAFF}]', unicode: true), ''), style: const pw.TextStyle(fontSize: 10))))
  ]));
  await Printing.sharePdf(bytes: await doc.save(), filename: 'relatorios_neves.pdf');
}

Future<void> exportCsv(List<ReportEntry> reports) async {
  final today = DateTime.now();
  final todayEntries = reports.where((r) => r.date.year == today.year && r.date.month == today.month && r.date.day == today.day);
  String esc(String s) => '"${s.replaceAll('"', '""')}"';
  final rows = ['Data;Descrição;Relatório', ...todayEntries.map((r) => '${esc(DateFormat('dd/MM/yyyy HH:mm').format(r.date))};${esc(r.input)};${esc(r.report)}')];
  final bytes = Uint8List.fromList(utf8.encode('\uFEFF${rows.join('\r\n')}'));
  final file = XFile.fromData(bytes, mimeType: 'text/csv', name: 'relatorios_neves_${DateFormat('yyyyMMdd').format(today)}.csv');
  await SharePlus.instance.share(ShareParams(files: [file]));
}
