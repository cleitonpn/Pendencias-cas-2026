// `databaseFactory` (o setter global) vem do sqflite; o pacote web só fornece
// a fábrica. Sem este import o analyze falha em TODAS as plataformas, porque
// ele analisa os arquivos de import condicional independentemente do alvo.
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// No navegador o SQLite roda em WebAssembly, com persistência em IndexedDB.
///
/// É isto que permite o app web ter as MESMAS telas do Android: o
/// DatabaseService e as 26 telas que dependem dele não mudam — só a
/// implementação por baixo. Sem isso `package:sqflite` não funciona na web, e
/// a árvore inteira do app fica fora da compilação.
///
/// O banco local é cache: os clientes vêm da planilha e as pendências do
/// Firestore. Se o navegador descartar o armazenamento (o Safari do iOS faz
/// isso após dias sem uso), a próxima abertura sincroniza de novo.
void initDesktopDatabase() {
  databaseFactory = databaseFactoryFfiWeb;
}
