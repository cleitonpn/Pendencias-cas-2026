import '../utils/producer_pool.dart';
import 'art_status.dart';

class Client {
  final int fairId;          // which fair this client belongs to
  final String rowId;
  final String firestoreId;  // stable cross-device key: normalizedFairName_rowNum
  final String nome;
  final String montagem;
  final String local;
  final String hangar;
  final String area;
  final String deck;
  final String totalArea;
  final String mezanino;

  /// Dono ATUAL do stand. Continua sendo um nome só, de propósito: todas as
  /// consultas do app filtram por ele, e a transferência troca este valor em
  /// vez de mudar a forma como se pergunta.
  final String produtor;

  /// Todos os produtores habilitados neste stand, na ordem da planilha. O
  /// primeiro é o dono padrão quando não há transferência registrada.
  final List<String> produtores;
  final String atendimento;  // consultor responsável pelo cliente
  final String organizadora; // organizadora do evento (faz o link com o cliente)
  final String pin;          // PIN de acesso do stand (adesivo), lido da planilha
  final String marceneiro;
  final String tapeceiro;
  final String eletricista;
  final String faxineira;
  final String teto50;
  final String projectLink;
  final String linkCv;
  final String linkMemorial;
  final String mobilario;
  final String extras;       // coluna "extras" da planilha

  /// Balcão padrão, balcão personalizado e cores — colunas da planilha que a
  /// equipe usa para montar o stand.
  final String balcaoPadrao;
  final String balcaoPersonalizado;
  final String cores;

  /// Coluna "elétrica" da planilha — o que o stand tem de instalação elétrica.
  ///
  /// Diferente de [eletricista], que é a pessoa responsável. Esta é a
  /// especificação: pontos, tomadas, carga. Quem vai montar precisa das duas
  /// coisas, e só o nome do eletricista estava chegando ao app.
  final String eletrica;

  /// Coluna "tipo" da planilha — o tipo de montagem do stand. Nas feiras
  /// grandes é a informação que diz de cara o que aquele stand é.
  final String tipo;

  // Event-level info columns (same for all clients in a fair)
  final String pavilhao;
  final String dataMontagem;
  final String dataEvento;
  final String dataDesmontagem;
  final String linkPlanta;
  final String linkDrive;

  bool isCompleted;
  DateTime? completedAt;

  /// Status da arte, vindo da ferramenta de aprovação.
  ///
  /// Não persiste no SQLite de propósito: muda o tempo todo — a cada arte que
  /// o cliente manda e a cada prova que o analista aprova — e é lido da nuvem
  /// quando a feira abre. Guardado no banco local, mostraria o estado de
  /// ontem com cara de estado de agora, que é pior do que não mostrar.
  ArtStatus? arte;

  Client({
    this.fairId = 1,
    required this.rowId,
    this.firestoreId = '',
    required this.nome,
    required this.montagem,
    required this.local,
    required this.hangar,
    required this.area,
    required this.deck,
    required this.totalArea,
    required this.mezanino,
    required this.produtor,
    this.produtores = const [],
    this.atendimento = '',
    this.organizadora = '',
    this.pin = '',
    required this.marceneiro,
    required this.tapeceiro,
    required this.eletricista,
    required this.faxineira,
    required this.teto50,
    this.projectLink = '',
    this.linkCv = '',
    this.linkMemorial = '',
    this.mobilario = '',
    this.extras = '',
    this.balcaoPadrao = '',
    this.balcaoPersonalizado = '',
    this.cores = '',
    this.eletrica = '',
    this.tipo = '',
    this.pavilhao = '',
    this.dataMontagem = '',
    this.dataEvento = '',
    this.dataDesmontagem = '',
    this.linkPlanta = '',
    this.linkDrive = '',
    this.isCompleted = false,
    this.completedAt,
  });

  /// Verdadeiro se esta pessoa é responsável por este stand.
  ///
  /// Todos os produtores da coluna respondem pelo stand ao mesmo tempo — não
  /// há um titular. Foi assim que a gente resolveu o caso do produtor
  /// principal ficar sem bateria: antes ninguém mais enxergava as pendências
  /// dele, e não havia como corrigir sem mexer na planilha.
  bool temProdutor(String nome) {
    final alvo = nome.toLowerCase().trim();
    if (alvo.isEmpty) return false;
    if (produtor.toLowerCase().trim() == alvo) return true;
    return produtores.any((n) => n.toLowerCase().trim() == alvo);
  }

  /// Mesma ficha, outro dono. Usado pela transferência de titularidade.
  Client copyWithOwner(String novoProdutor) => reidentify(
        fairId,
        rowId,
        newProdutor: novoProdutor,
      );

  /// Returns a new Client with updated fairId, rowId and firestoreId (used when
  /// assigning derived fair IDs after reading from a master sheet).
  Client reidentify(int newFairId, String newRowId,
          {String newFirestoreId = '', String? newProdutor}) => Client(
        fairId: newFairId,
        rowId: newRowId,
        firestoreId: newFirestoreId.isNotEmpty ? newFirestoreId : firestoreId,
        nome: nome,
        montagem: montagem,
        local: local,
        hangar: hangar,
        area: area,
        deck: deck,
        totalArea: totalArea,
        mezanino: mezanino,
        produtor: newProdutor ?? produtor,
        produtores: produtores,
        atendimento: atendimento,
        organizadora: organizadora,
        pin: pin,
        marceneiro: marceneiro,
        tapeceiro: tapeceiro,
        eletricista: eletricista,
        faxineira: faxineira,
        teto50: teto50,
        projectLink: projectLink,
        linkCv: linkCv,
        linkMemorial: linkMemorial,
        mobilario: mobilario,
        extras: extras,
        balcaoPadrao: balcaoPadrao,
        balcaoPersonalizado: balcaoPersonalizado,
        cores: cores,
        eletrica: eletrica,
        tipo: tipo,
        pavilhao: pavilhao,
        dataMontagem: dataMontagem,
        dataEvento: dataEvento,
        dataDesmontagem: dataDesmontagem,
        linkPlanta: linkPlanta,
        linkDrive: linkDrive,
        isCompleted: isCompleted,
        completedAt: completedAt,
      )..arte = arte;

  Map<String, dynamic> toMap() => {
        'fair_id': fairId,
        'row_id': rowId,
        'firestore_id': firestoreId,
        'nome': nome,
        'montagem': montagem,
        'local': local,
        'hangar': hangar,
        'area': area,
        'deck': deck,
        'total_area': totalArea,
        'mezanino': mezanino,
        'produtor': produtor,
        'produtores': produtores.join(', '),
        'atendimento': atendimento,
        'organizadora': organizadora,
        'pin': pin,
        'marceneiro': marceneiro,
        'tapeceiro': tapeceiro,
        'eletricista': eletricista,
        'faxineira': faxineira,
        'teto50': teto50,
        'project_link': projectLink,
        'link_cv': linkCv,
        'link_memorial': linkMemorial,
        'mobilario': mobilario,
        'extras': extras,
        'balcao_padrao': balcaoPadrao,
        'balcao_personalizado': balcaoPersonalizado,
        'cores': cores,
        'eletrica': eletrica,
        'tipo': tipo,
        'produtores_key': produtoresKeyFrom(produtores),
        'pavilhao': pavilhao,
        'data_montagem': dataMontagem,
        'data_evento': dataEvento,
        'data_desmontagem': dataDesmontagem,
        'link_planta': linkPlanta,
        'link_drive': linkDrive,
        'is_completed': isCompleted ? 1 : 0,
        'completed_at': completedAt?.toIso8601String(),
      };

  factory Client.fromMap(Map<String, dynamic> map) => Client(
        fairId: map['fair_id'] as int? ?? 1,
        rowId: map['row_id'] as String,
        firestoreId: (map['firestore_id'] as String?)?.isNotEmpty == true
            ? map['firestore_id'] as String
            : map['row_id'] as String,
        nome: map['nome'] ?? '',
        montagem: map['montagem'] ?? '',
        local: map['local'] ?? '',
        hangar: map['hangar'] ?? '',
        area: map['area'] ?? '',
        deck: map['deck'] ?? '',
        totalArea: map['total_area'] ?? '',
        mezanino: map['mezanino'] ?? '',
        produtor: map['produtor'] ?? '',
        produtores: produtoresFrom((map['produtores'] as String?) ?? ''),
        atendimento: map['atendimento'] ?? '',
        organizadora: map['organizadora'] ?? '',
        pin: map['pin'] ?? '',
        marceneiro: map['marceneiro'] ?? '',
        tapeceiro: map['tapeceiro'] ?? '',
        eletricista: map['eletricista'] ?? '',
        faxineira: map['faxineira'] ?? '',
        teto50: map['teto50'] ?? '',
        projectLink: map['project_link'] ?? '',
        linkCv: map['link_cv'] ?? '',
        linkMemorial: map['link_memorial'] ?? '',
        mobilario: map['mobilario'] ?? '',
        extras: map['extras'] ?? '',
        balcaoPadrao: map['balcao_padrao'] ?? '',
        balcaoPersonalizado: map['balcao_personalizado'] ?? '',
        cores: map['cores'] ?? '',
        eletrica: map['eletrica'] ?? '',
        tipo: map['tipo'] ?? '',
        pavilhao: map['pavilhao'] ?? '',
        dataMontagem: map['data_montagem'] ?? '',
        dataEvento: map['data_evento'] ?? '',
        dataDesmontagem: map['data_desmontagem'] ?? '',
        linkPlanta: map['link_planta'] ?? '',
        linkDrive: map['link_drive'] ?? '',
        isCompleted: (map['is_completed'] as int? ?? 0) == 1,
        completedAt: map['completed_at'] != null
            ? DateTime.tryParse(map['completed_at'] as String)
            : null,
      );

  /// O print da comunicação visual que vale.
  ///
  /// A ferramenta de aprovação tem prioridade sobre a planilha, e a razão é
  /// que são o mesmo documento com idades diferentes: o link da planilha é
  /// colado à mão e envelhece na primeira arte corrigida, enquanto o da
  /// ferramenta é sempre a prova mais recente daquele stand.
  ///
  /// A planilha continua valendo como reserva — para o stand que ainda não foi
  /// importado para a ferramenta, e para o período de transição em que uma
  /// feira está nos dois lugares. Trocar um pelo outro, e não somar, evita a
  /// pergunta "qual desses dois eu abro?" no meio da montagem.
  String get linkCvEfetivo {
    final daFerramenta = arte?.linkProva ?? '';
    return daFerramenta.isNotEmpty ? daFerramenta : linkCv;
  }

  /// A prova veio da ferramenta (e não da planilha)?
  bool get provaDaFerramenta => (arte?.linkProva ?? '').isNotEmpty;

  String get displayName => nome.isNotEmpty ? nome : 'Stand $local';

  String get standLabel => local.isNotEmpty ? local : rowId;
}
