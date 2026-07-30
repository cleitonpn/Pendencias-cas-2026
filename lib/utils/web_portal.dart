/// Qual portal web a pessoa usou por último.
///
/// Um F5 numa URL sem fragmento (`/` puro) não diz de onde a pessoa veio, e o
/// roteador precisa decidir para onde mandar. Antes ele só conhecia a sessão
/// da organizadora, então quem estava no portal da equipe caía lá.
///
/// Fica num arquivo próprio para o roteador e as telas não se importarem
/// mutuamente.
///
/// Dois portais convivem no mesmo navegador: o da organizadora (sessão
/// própria) e o app completo (sessão do SessionService). A marca diz qual
/// deles restaurar quando o fragmento da URL se perde.
const kLastWebPortal = 'web_last_portal';
const kPortalOrganizadora = 'organizadora';
const kPortalApp = 'app';
